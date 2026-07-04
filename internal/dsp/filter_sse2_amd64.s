#include "textflag.h"

// VP8 complex (normal) loop filters — AMD64 SSE2 assembly (vertical only).
//
// Implements the complex vertical loop filters used by the VP8 decoder,
// following the algorithms of libwebp dec_sse2.c (NeedsFilter2, NeedsHev,
// DoFilter2/4/6) while remaining bit-exact with the pure Go reference
// implementations in filter.go, mirroring the NEON port (filter_arm64.s):
//
//   - The needs-filter edge test (4*|p0-q0| + |p1-q1| <= 2*thresh+1) is
//     computed exactly in 16-bit lanes: byte absolute differences are
//     widened with PUNPCKLBW/PUNPCKHBW, summed as words, and compared via
//     PSUBUSW+PCMPEQW (sum -us thresh2 == 0  <=>  sum <= thresh2), so
//     thresh2 values above 255 are handled exactly like the Go code.
//     This is the SSE2 equivalent of the NEON UABDL+CMHS sequence.
//   - The interior smoothness test (|p3-p2|<=ithresh, ...) and the HEV test
//     are computed in 8-bit lanes (PSUBUSB abs-diff, PMAXUB, PCMPEQB); both
//     are exact for ithresh/hevT in [0, 255].
//   - The filter arithmetic uses the classic sign-flip (pixel ^ 0x80) plus
//     saturating int8 operations (PADDSB/PSUBSB). The saturating chain
//     sat(sat(sat(p1-q1)+(q0-p0))+(q0-p0))+(q0-p0)) is exactly equivalent to
//     Ksclip1(3*(q0-p0) + Ksclip1(p1-q1)), and the per-byte signed shift
//     (sat(a+4))>>3 / (sat(a+3))>>3 — done by widening into the high byte of
//     each word and PSRAW $11 — is exactly equivalent to Ksclip2((a+4)>>3) /
//     Ksclip2((a+3)>>3); final saturating adds in the flipped domain match
//     Kclip1. This is the same normative equivalence libwebp relies on.
//   - doFilter4's a3 = (a1+1)>>1 uses the libwebp PAVGB trick:
//     avg_epu8(a1+128, 0) - 64 == (a1+1)>>1 for all signed a1.
//
// Horizontal variants (HFilter*) are NOT implemented: they require 16x8
// transposes whose shuffle overhead erodes most of the SIMD benefit; the Go
// fallback is kept for those.
//
// Register conventions shared by all functions:
//   SI  = slice base pointer      DX  = stride
//   R8  = luma/U edge pointer     R9  = V edge pointer (chroma only)
//   R10/R11 = row cursors         CX  = thresh2, R12 = ithresh, R13 = hevT
//   X0..X7  = p3, p2, p1, p0, q0, q1, q2, q3 rows
//   X8..X15 = temporaries / masks:
//     after NEEDS_FILTER2_COMBINE: X10 = complex mask (needs & !hev),
//                                  X11 = simple mask (needs & hev)
//     after BASE_DELTA:            X14 = base filter delta

// ---- Constants ----

DATA kSign_b<>+0x00(SB)/8, $0x8080808080808080
DATA kSign_b<>+0x08(SB)/8, $0x8080808080808080
GLOBL kSign_b<>(SB), RODATA|NOPTR, $16

DATA kFour_b<>+0x00(SB)/8, $0x0404040404040404
DATA kFour_b<>+0x08(SB)/8, $0x0404040404040404
GLOBL kFour_b<>(SB), RODATA|NOPTR, $16

DATA kThree_b<>+0x00(SB)/8, $0x0303030303030303
DATA kThree_b<>+0x08(SB)/8, $0x0303030303030303
GLOBL kThree_b<>(SB), RODATA|NOPTR, $16

DATA k64_b<>+0x00(SB)/8, $0x4040404040404040
DATA k64_b<>+0x08(SB)/8, $0x4040404040404040
GLOBL k64_b<>(SB), RODATA|NOPTR, $16

DATA kNine_w<>+0x00(SB)/8, $0x0009000900090009
DATA kNine_w<>+0x08(SB)/8, $0x0009000900090009
GLOBL kNine_w<>(SB), RODATA|NOPTR, $16

DATA k63_w<>+0x00(SB)/8, $0x003F003F003F003F
DATA k63_w<>+0x08(SB)/8, $0x003F003F003F003F
GLOBL k63_w<>(SB), RODATA|NOPTR, $16

// ---- Helper macros ----

// ABSDIFF: dst = |a - b| per byte (PSUBUSB both ways + POR).
#define ABSDIFF(a, b, dst, tmp) \
	MOVO a, dst; \
	PSUBUSB b, dst; \
	MOVO b, tmp; \
	PSUBUSB a, tmp; \
	POR tmp, dst

// BCAST_BYTE: broadcast the low byte of GP register gp to all 16 bytes of x.
#define BCAST_BYTE(gp, x) \
	MOVD gp, x; \
	PUNPCKLBW x, x; \
	PSHUFLW $0, x, x; \
	PSHUFD $0, x, x

// BCAST_WORD: broadcast the low word of GP register gp to all 8 words of x.
#define BCAST_WORD(gp, x) \
	MOVD gp, x; \
	PSHUFLW $0, x, x; \
	PSHUFD $0, x, x

// SIGNEDSHIFT8B: per-byte arithmetic shift right by 3 of x (values must be
// the result of a saturating int8 add, i.e. in [-128, 127]; outputs are in
// [-16, 15] so the final PACKSSWB never saturates). Clobbers t1, t2.
#define SIGNEDSHIFT8B(x, t1, t2) \
	PXOR t1, t1; \
	MOVO t1, t2; \
	PUNPCKLBW x, t1; \
	PUNPCKHBW x, t2; \
	PSRAW $11, t1; \
	PSRAW $11, t2; \
	PACKSSWB t2, t1; \
	MOVO t1, x

// NEEDS_FILTER2_COMBINE: computes the combined needs-filter mask and splits
// it by HEV. Inputs: rows X0..X7 (p3..q3), CX = thresh2, R12 = ithresh,
// R13 = hevT. Outputs: X10 = complex mask (needs & !hev), X11 = simple mask
// (needs & hev). Clobbers X8, X9, X12, X13, X15 (rows X0..X7 preserved).
//
// Interior test: max of six |Δ| byte diffs <= ithresh via PSUBUSB+PCMPEQB.
// HEV test:      max(|p1-p0|, |q1-q0|) <= hevT gives the NOT-HEV mask.
// Edge test:     exact 16-bit 4*|p0-q0| + |p1-q1| <= thresh2 (see header).
#define NEEDS_FILTER2_COMBINE \
	ABSDIFF(X0, X1, X8, X15); \
	ABSDIFF(X1, X2, X9, X15); \
	ABSDIFF(X2, X3, X10, X15); \
	ABSDIFF(X7, X6, X11, X15); \
	ABSDIFF(X6, X5, X12, X15); \
	ABSDIFF(X5, X4, X13, X15); \
	PMAXUB X9, X8; \
	PMAXUB X12, X11; \
	PMAXUB X10, X8; \
	PMAXUB X13, X11; \
	PMAXUB X11, X8; \
	BCAST_BYTE(R12, X9); \
	PSUBUSB X9, X8; \
	PXOR X9, X9; \
	PCMPEQB X9, X8; \
	PMAXUB X13, X10; \
	BCAST_BYTE(R13, X9); \
	PSUBUSB X9, X10; \
	PXOR X9, X9; \
	PCMPEQB X9, X10; \
	ABSDIFF(X3, X4, X9, X15); \
	ABSDIFF(X2, X5, X11, X15); \
	PXOR X15, X15; \
	MOVO X9, X12; \
	PUNPCKLBW X15, X9; \
	PUNPCKHBW X15, X12; \
	MOVO X11, X13; \
	PUNPCKLBW X15, X11; \
	PUNPCKHBW X15, X13; \
	PSLLW $2, X9; \
	PSLLW $2, X12; \
	PADDW X11, X9; \
	PADDW X13, X12; \
	BCAST_WORD(CX, X11); \
	PSUBUSW X11, X9; \
	PSUBUSW X11, X12; \
	PCMPEQW X15, X9; \
	PCMPEQW X15, X12; \
	PACKSSWB X12, X9; \
	PAND X9, X8; \
	MOVO X10, X11; \
	PANDN X8, X11; \
	PAND X8, X10

// FLIP_SIGN4 / FLIP_SIGN6: convert pixels to the signed domain (x ^ 0x80).
#define FLIP_SIGN4 \
	PXOR kSign_b<>(SB), X2; \
	PXOR kSign_b<>(SB), X3; \
	PXOR kSign_b<>(SB), X4; \
	PXOR kSign_b<>(SB), X5

#define FLIP_SIGN6 \
	PXOR kSign_b<>(SB), X1; \
	FLIP_SIGN4; \
	PXOR kSign_b<>(SB), X6

// BASE_DELTA: X14 = sclip1(3*(q0-p0) + sclip1(p1-q1)) via saturating chain
// sat(sat(sat((p1-q1) + t) + t) + t) with t = sat(q0s - p0s).
// Inputs: X2=p1s, X3=p0s, X4=q0s, X5=q1s (signed domain). Clobbers X13.
#define BASE_DELTA \
	MOVO X4, X13; \
	PSUBSB X3, X13; \
	MOVO X2, X14; \
	PSUBSB X5, X14; \
	PADDSB X13, X14; \
	PADDSB X13, X14; \
	PADDSB X13, X14

// DO_FILTER2: apply the 2-tap filter on lanes selected by X11 (simple mask).
// Uses X14 (base delta, preserved); updates X3 (p0s) and X4 (q0s) in place.
// On non-selected lanes the masked delta is 0, so a1 = a2 = 0 (no change).
// Clobbers X8, X9, X12, X13.
#define DO_FILTER2 \
	MOVO X14, X9; \
	PAND X11, X9; \
	MOVO X9, X8; \
	PADDSB kFour_b<>(SB), X8; \
	PADDSB kThree_b<>(SB), X9; \
	SIGNEDSHIFT8B(X8, X12, X13); \
	SIGNEDSHIFT8B(X9, X12, X13); \
	PADDSB X9, X3; \
	PSUBSB X8, X4

// DO_FILTER6: apply the 6-tap filter on lanes selected by X10 (complex mask).
// Uses X14 (base delta, consumed). a1=(27a+63)>>7, a2=(18a+63)>>7,
// a3=(9a+63)>>7 computed exactly in 16-bit lanes (PMULLW by 9 on the
// sign-extended delta). Results are in [-27, 27] so PACKSSWB never
// saturates. Updates X1..X6 in place. Clobbers X8..X15.
#define DO_FILTER6 \
	PAND X10, X14; \
	PXOR X15, X15; \
	MOVO X15, X8; \
	MOVO X15, X9; \
	PUNPCKLBW X14, X8; \
	PUNPCKHBW X14, X9; \
	PSRAW $8, X8; \
	PSRAW $8, X9; \
	PMULLW kNine_w<>(SB), X8; \
	PMULLW kNine_w<>(SB), X9; \
	MOVO X8, X10; \
	PADDW k63_w<>(SB), X10; \
	MOVO X9, X11; \
	PADDW k63_w<>(SB), X11; \
	MOVO X10, X12; \
	PADDW X8, X12; \
	MOVO X11, X13; \
	PADDW X9, X13; \
	PADDW X12, X8; \
	PADDW X13, X9; \
	PSRAW $7, X10; \
	PSRAW $7, X11; \
	PSRAW $7, X12; \
	PSRAW $7, X13; \
	PSRAW $7, X8; \
	PSRAW $7, X9; \
	PACKSSWB X11, X10; \
	PACKSSWB X13, X12; \
	PACKSSWB X9, X8; \
	PADDSB X8, X3; \
	PSUBSB X8, X4; \
	PADDSB X12, X2; \
	PSUBSB X12, X5; \
	PADDSB X10, X1; \
	PSUBSB X10, X6

// DO_FILTER4: apply the 4-tap filter on lanes selected by X10 (complex mask).
// Recomputes 3*(q0-p0) from the (possibly filter2-updated) X3/X4 — the
// complex-mask lanes were untouched by DO_FILTER2 so this matches the Go
// code exactly. a3 = (a1+1)>>1 uses the PAVGB trick (see header).
// Updates X2..X5 in place. Clobbers X8, X9, X12, X13, X14.
#define DO_FILTER4 \
	MOVO X4, X13; \
	PSUBSB X3, X13; \
	MOVO X13, X14; \
	PADDSB X13, X14; \
	PADDSB X13, X14; \
	PAND X10, X14; \
	MOVO X14, X8; \
	PADDSB kFour_b<>(SB), X8; \
	MOVO X14, X9; \
	PADDSB kThree_b<>(SB), X9; \
	SIGNEDSHIFT8B(X8, X12, X13); \
	SIGNEDSHIFT8B(X9, X12, X13); \
	MOVO X8, X12; \
	PADDB kSign_b<>(SB), X12; \
	PXOR X13, X13; \
	PAVGB X13, X12; \
	PSUBB k64_b<>(SB), X12; \
	PADDSB X9, X3; \
	PSUBSB X8, X4; \
	PADDSB X12, X2; \
	PSUBSB X12, X5

// LOAD_LUMA_8ROWS: load p3..q3 (X0..X7), 16 bytes per row, from R8-4*stride.
// Clobbers AX, R10.
#define LOAD_LUMA_8ROWS \
	MOVQ DX, AX; \
	SHLQ $2, AX; \
	MOVQ R8, R10; \
	SUBQ AX, R10; \
	MOVOU (R10), X0; \
	ADDQ DX, R10; \
	MOVOU (R10), X1; \
	ADDQ DX, R10; \
	MOVOU (R10), X2; \
	ADDQ DX, R10; \
	MOVOU (R10), X3; \
	ADDQ DX, R10; \
	MOVOU (R10), X4; \
	ADDQ DX, R10; \
	MOVOU (R10), X5; \
	ADDQ DX, R10; \
	MOVOU (R10), X6; \
	ADDQ DX, R10; \
	MOVOU (R10), X7

// LOAD_UV_ROW: load one 8-byte U row (from R10) into the low half and the
// matching V row (from R11) into the high half of x, then advance cursors.
#define LOAD_UV_ROW(x, tmp) \
	MOVQ (R10), x; \
	MOVQ (R11), tmp; \
	PUNPCKLQDQ tmp, x; \
	ADDQ DX, R10; \
	ADDQ DX, R11

// LOAD_UV_8ROWS: load p3..q3 with the U rows in lanes 0-7 and the V rows in
// lanes 8-15 of each vector, starting at R8-4*stride / R9-4*stride.
// Clobbers AX, R10, R11, X8.
#define LOAD_UV_8ROWS \
	MOVQ DX, AX; \
	SHLQ $2, AX; \
	MOVQ R8, R10; \
	SUBQ AX, R10; \
	MOVQ R9, R11; \
	SUBQ AX, R11; \
	LOAD_UV_ROW(X0, X8); \
	LOAD_UV_ROW(X1, X8); \
	LOAD_UV_ROW(X2, X8); \
	LOAD_UV_ROW(X3, X8); \
	LOAD_UV_ROW(X4, X8); \
	LOAD_UV_ROW(X5, X8); \
	LOAD_UV_ROW(X6, X8); \
	LOAD_UV_ROW(X7, X8)

// STORE_UV_ROW: store the low half of x to the U row (R10) and the high half
// to the V row (R11), then advance cursors.
#define STORE_UV_ROW(x, tmp) \
	MOVQ x, (R10); \
	PSHUFD $0xEE, x, tmp; \
	MOVQ tmp, (R11); \
	ADDQ DX, R10; \
	ADDQ DX, R11

// func vFilter16EdgeSSE2(p []byte, base, stride, thresh, ithresh, hevT int)
// Complex vertical macroblock-edge filter (FilterLoop26, 16 wide).
// Bit-exact with filterLoop26(p, base, stride, 1, 16, ...) for
// thresh in [0, 30000], ithresh/hevT in [0, 255].
TEXT ·vFilter16EdgeSSE2(SB), NOSPLIT, $0-64
	MOVQ p_base+0(FP), SI
	MOVQ base+24(FP), AX
	LEAQ (SI)(AX*1), R8        // R8 = &p[base] (q0 row)
	MOVQ stride+32(FP), DX
	MOVQ thresh+40(FP), CX
	LEAQ 1(CX)(CX*1), CX       // thresh2 = 2*thresh + 1
	MOVQ ithresh+48(FP), R12
	MOVQ hevT+56(FP), R13

	LOAD_LUMA_8ROWS

	NEEDS_FILTER2_COMBINE
	FLIP_SIGN6
	BASE_DELTA
	DO_FILTER2
	DO_FILTER6

	// Flip back and store p2..q2 (6 rows starting at base-3*stride).
	PXOR kSign_b<>(SB), X1
	PXOR kSign_b<>(SB), X2
	PXOR kSign_b<>(SB), X3
	PXOR kSign_b<>(SB), X4
	PXOR kSign_b<>(SB), X5
	PXOR kSign_b<>(SB), X6
	LEAQ (DX)(DX*2), AX        // 3*stride
	MOVQ R8, R10
	SUBQ AX, R10
	MOVOU X1, (R10)
	ADDQ DX, R10
	MOVOU X2, (R10)
	ADDQ DX, R10
	MOVOU X3, (R10)
	ADDQ DX, R10
	MOVOU X4, (R10)
	ADDQ DX, R10
	MOVOU X5, (R10)
	ADDQ DX, R10
	MOVOU X6, (R10)

	RET

// func vFilter16InnerSSE2(p []byte, base, stride, thresh, ithresh, hevT int)
// Complex vertical inner-edge filter (one FilterLoop24 span, 16 wide).
// Bit-exact with filterLoop24(p, base, stride, 1, 16, ...) for
// thresh in [0, 30000], ithresh/hevT in [0, 255].
TEXT ·vFilter16InnerSSE2(SB), NOSPLIT, $0-64
	MOVQ p_base+0(FP), SI
	MOVQ base+24(FP), AX
	LEAQ (SI)(AX*1), R8
	MOVQ stride+32(FP), DX
	MOVQ thresh+40(FP), CX
	LEAQ 1(CX)(CX*1), CX
	MOVQ ithresh+48(FP), R12
	MOVQ hevT+56(FP), R13

	LOAD_LUMA_8ROWS

	NEEDS_FILTER2_COMBINE
	FLIP_SIGN4
	BASE_DELTA
	DO_FILTER2
	DO_FILTER4

	// Flip back and store p1..q1 (4 rows starting at base-2*stride).
	PXOR kSign_b<>(SB), X2
	PXOR kSign_b<>(SB), X3
	PXOR kSign_b<>(SB), X4
	PXOR kSign_b<>(SB), X5
	MOVQ R8, R10
	SUBQ DX, R10
	SUBQ DX, R10
	MOVOU X2, (R10)
	ADDQ DX, R10
	MOVOU X3, (R10)
	ADDQ DX, R10
	MOVOU X4, (R10)
	ADDQ DX, R10
	MOVOU X5, (R10)

	RET

// func vFilter8EdgeSSE2(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)
// Complex vertical macroblock-edge filter for both 8-wide chroma planes.
// U rows occupy lanes 0-7, V rows lanes 8-15 of each vector.
// Bit-exact with filterLoop26 on each plane.
TEXT ·vFilter8EdgeSSE2(SB), NOSPLIT, $0-96
	MOVQ u_base+0(FP), SI
	MOVQ uBase+48(FP), AX
	LEAQ (SI)(AX*1), R8        // R8 = &u[uBase]
	MOVQ v_base+24(FP), SI
	MOVQ vBase+56(FP), AX
	LEAQ (SI)(AX*1), R9        // R9 = &v[vBase]
	MOVQ stride+64(FP), DX
	MOVQ thresh+72(FP), CX
	LEAQ 1(CX)(CX*1), CX
	MOVQ ithresh+80(FP), R12
	MOVQ hevT+88(FP), R13

	LOAD_UV_8ROWS

	NEEDS_FILTER2_COMBINE
	FLIP_SIGN6
	BASE_DELTA
	DO_FILTER2
	DO_FILTER6

	// Flip back and store p2..q2 to both planes.
	PXOR kSign_b<>(SB), X1
	PXOR kSign_b<>(SB), X2
	PXOR kSign_b<>(SB), X3
	PXOR kSign_b<>(SB), X4
	PXOR kSign_b<>(SB), X5
	PXOR kSign_b<>(SB), X6
	LEAQ (DX)(DX*2), AX        // 3*stride
	MOVQ R8, R10
	SUBQ AX, R10
	MOVQ R9, R11
	SUBQ AX, R11
	STORE_UV_ROW(X1, X8)
	STORE_UV_ROW(X2, X8)
	STORE_UV_ROW(X3, X8)
	STORE_UV_ROW(X4, X8)
	STORE_UV_ROW(X5, X8)
	STORE_UV_ROW(X6, X8)

	RET

// func vFilter8InnerSSE2(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)
// Complex vertical inner-edge filter for both 8-wide chroma planes
// (one FilterLoop24 span; the caller passes bases already offset by
// 4*stride). Bit-exact with filterLoop24 on each plane.
TEXT ·vFilter8InnerSSE2(SB), NOSPLIT, $0-96
	MOVQ u_base+0(FP), SI
	MOVQ uBase+48(FP), AX
	LEAQ (SI)(AX*1), R8
	MOVQ v_base+24(FP), SI
	MOVQ vBase+56(FP), AX
	LEAQ (SI)(AX*1), R9
	MOVQ stride+64(FP), DX
	MOVQ thresh+72(FP), CX
	LEAQ 1(CX)(CX*1), CX
	MOVQ ithresh+80(FP), R12
	MOVQ hevT+88(FP), R13

	LOAD_UV_8ROWS

	NEEDS_FILTER2_COMBINE
	FLIP_SIGN4
	BASE_DELTA
	DO_FILTER2
	DO_FILTER4

	// Flip back and store p1..q1 to both planes.
	PXOR kSign_b<>(SB), X2
	PXOR kSign_b<>(SB), X3
	PXOR kSign_b<>(SB), X4
	PXOR kSign_b<>(SB), X5
	MOVQ R8, R10
	SUBQ DX, R10
	SUBQ DX, R10
	MOVQ R9, R11
	SUBQ DX, R11
	SUBQ DX, R11
	STORE_UV_ROW(X2, X8)
	STORE_UV_ROW(X3, X8)
	STORE_UV_ROW(X4, X8)
	STORE_UV_ROW(X5, X8)

	RET
