#include "textflag.h"

// VP8 loop filters — ARM64 NEON assembly (vertical variants only).
//
// Implements the "simple" and "complex" (normal) vertical loop filters used
// by the VP8 decoder, following the algorithms of libwebp dec_neon.c
// (NeedsFilter2, NeedsHev, DoFilter2/4/6) while remaining bit-exact with the
// pure Go reference implementations in filter.go:
//
//   - The needs-filter edge test (4*|p0-q0| + |p1-q1| <= 2*thresh+1) is
//     computed exactly in 16-bit lanes (UABDL + shift + CMHS), so thresh2
//     values above 255 are handled exactly like the Go code.
//   - The interior smoothness test (|p3-p2|<=ithresh, ...) and the HEV test
//     are computed in 8-bit lanes (UABD/UMAX/CMHS/CMHI); both are exact for
//     ithresh/hevT in [0, 255].
//   - The filter arithmetic uses the classic sign-flip (pixel ^ 0x80) plus
//     saturating int8 operations. The saturating chain
//     sat(sat(sat(p1-q1)+(q0-p0))+(q0-p0))+(q0-p0)) is exactly equivalent to
//     Ksclip1(3*(q0-p0) + Ksclip1(p1-q1)), and (sat(a+4))>>3 / (sat(a+3))>>3
//     are exactly equivalent to Ksclip2((a+4)>>3) / Ksclip2((a+3)>>3);
//     final saturating adds in the flipped domain match Kclip1. This is the
//     same normative equivalence libwebp relies on.
//
// Horizontal variants (HFilter*) are NOT implemented: they require 16x8
// transposes whose shuffle overhead erodes most of the SIMD benefit; the Go
// fallback is kept for those.
//
// Many instructions are WORD-encoded because the Go assembler lacks the
// mnemonics (UABD, UABDL, CMHS, CMHI, SQADD, SQSUB, SSHR, SRSHR, SSHLL,
// MUL.8H, XTN, LD1/ST1 single-lane).
//
// Register conventions shared by all functions:
//   R0 = luma/U edge pointer (&p[base]), R1 = V edge pointer (chroma only)
//   R2 = stride, R4/R5 = row cursors
//   V0..V7   = p3, p2, p1, p0, q0, q1, q2, q3 rows
//   V8..V15  = temporaries
//   V16 = needs-filter mask, V17 = HEV mask
//   V18 = base delta, V19/V20/V23 = filter temporaries
//   V21 = simple-filter mask (mask & hev), V22 = complex mask (mask & ^hev)
//   V24 = 4 (int8), V25 = 3 (int8), V26 = 9 (.8H), V27 = thresh2 (.8H)
//   V28 = ithresh (.16B), V29 = hevT (.16B), V30 = 0x80, V31 = 63 (.8H)

// Broadcast the shared filter constants. Expects:
//   thresh at off+0(FP), ithresh at off+8(FP), hevT at off+16(FP)
// handled by callers (offsets differ); this macro only materializes the
// immediate-value vectors.
#define FILTER_CONSTS \
	VMOVI $128, V30.B16; \
	VMOVI $4, V24.B16; \
	VMOVI $3, V25.B16

// NEEDS_FILTER_EDGE: exact 16-bit test 4*|p0-q0| + |p1-q1| <= thresh2.
// Inputs: V2=p1, V3=p0, V4=q0, V5=q1, V27=thresh2 (.8H).
// Output: V9 = 0xFF where the edge test passes.
// Clobbers: V9, V14, V15, V17.
#define NEEDS_FILTER_EDGE \
	WORD $0x2e247069; \ // UABDL  V9.8H,  V3.8B,  V4.8B    |p0-q0| lo
	WORD $0x6e24706e; \ // UABDL2 V14.8H, V3.16B, V4.16B   |p0-q0| hi
	WORD $0x2e25704f; \ // UABDL  V15.8H, V2.8B,  V5.8B    |p1-q1| lo
	WORD $0x6e257051; \ // UABDL2 V17.8H, V2.16B, V5.16B   |p1-q1| hi
	VSHL $2, V9.H8, V9.H8; \
	VSHL $2, V14.H8, V14.H8; \
	VADD V15.H8, V9.H8, V9.H8; \
	VADD V17.H8, V14.H8, V14.H8; \
	WORD $0x6e693f69; \ // CMHS V9.8H,  V27.8H, V9.8H
	WORD $0x6e6e3f6e; \ // CMHS V14.8H, V27.8H, V14.8H
	WORD $0x0e212929; \ // XTN  V9.8B,  V9.8H
	WORD $0x4e2129c9    // XTN2 V9.16B, V14.8H

// NEEDS_FILTER2: combined mask for the complex filter.
// Inputs: V0..V7 rows, V27=thresh2 (.8H), V28=ithresh (.16B), V29=hevT (.16B).
// Outputs: V16 = needs-filter mask, V17 = HEV mask.
// Clobbers: V8..V15.
#define NEEDS_FILTER2 \
	WORD $0x6e217408; \ // UABD V8.16B,  V0.16B, V1.16B   |p3-p2|
	WORD $0x6e227429; \ // UABD V9.16B,  V1.16B, V2.16B   |p2-p1|
	WORD $0x6e23744a; \ // UABD V10.16B, V2.16B, V3.16B   |p1-p0| (kept for HEV)
	WORD $0x6e2674eb; \ // UABD V11.16B, V7.16B, V6.16B   |q3-q2|
	WORD $0x6e2574cc; \ // UABD V12.16B, V6.16B, V5.16B   |q2-q1|
	WORD $0x6e2474ad; \ // UABD V13.16B, V5.16B, V4.16B   |q1-q0| (kept for HEV)
	VUMAX V9.B16, V8.B16, V8.B16; \
	VUMAX V12.B16, V11.B16, V11.B16; \
	VUMAX V10.B16, V8.B16, V8.B16; \
	VUMAX V13.B16, V11.B16, V11.B16; \
	VUMAX V11.B16, V8.B16, V8.B16; \
	WORD $0x6e283f90; \ // CMHS V16.16B, V28.16B, V8.16B  (ithresh >= max)
	NEEDS_FILTER_EDGE; \
	VAND V9.B16, V16.B16, V16.B16; \
	VUMAX V13.B16, V10.B16, V10.B16; \
	WORD $0x6e3d3551    // CMHI V17.16B, V10.16B, V29.16B (HEV: max > hevT)

// FLIP_SIGN4 / FLIP_SIGN6: convert pixels to the signed domain (x ^ 0x80).
#define FLIP_SIGN4 \
	VEOR V30.B16, V2.B16, V2.B16; \
	VEOR V30.B16, V3.B16, V3.B16; \
	VEOR V30.B16, V4.B16, V4.B16; \
	VEOR V30.B16, V5.B16, V5.B16

#define FLIP_SIGN6 \
	VEOR V30.B16, V1.B16, V1.B16; \
	FLIP_SIGN4; \
	VEOR V30.B16, V6.B16, V6.B16

// BASE_DELTA: V18 = sclip1(3*(q0-p0) + sclip1(p1-q1)) via saturating chain.
// Inputs: V2=p1s, V3=p0s, V4=q0s, V5=q1s (signed domain).
// Clobbers: V19, V20.
#define BASE_DELTA \
	WORD $0x4e232c93; \ // SQSUB V19.16B, V4.16B, V3.16B   q0s - p0s
	WORD $0x4e252c54; \ // SQSUB V20.16B, V2.16B, V5.16B   p1s - q1s
	WORD $0x4e330e92; \ // SQADD V18.16B, V20.16B, V19.16B
	WORD $0x4e320e72; \ // SQADD V18.16B, V19.16B, V18.16B
	WORD $0x4e320e72    // SQADD V18.16B, V19.16B, V18.16B

// COMBINE_MASKS: V21 = mask & hev (simple), V22 = mask & ^hev (complex).
#define COMBINE_MASKS \
	VAND V17.B16, V16.B16, V21.B16; \
	VEOR V16.B16, V21.B16, V22.B16

// DO_FILTER2: apply the 2-tap filter on lanes selected by V21.
// Uses V18 (base delta); updates V3 (p0s) and V4 (q0s) in place.
// Clobbers: V19, V20.
#define DO_FILTER2 \
	VAND V21.B16, V18.B16, V19.B16; \
	WORD $0x4e380e74; \ // SQADD V20.16B, V19.16B, V24.16B  delta+4
	WORD $0x4e390e73; \ // SQADD V19.16B, V19.16B, V25.16B  delta+3
	WORD $0x4f0d0694; \ // SSHR V20.16B, V20.16B, #3        a1
	WORD $0x4f0d0673; \ // SSHR V19.16B, V19.16B, #3        a2
	WORD $0x4e330c63; \ // SQADD V3.16B, V3.16B, V19.16B    p0 += a2
	WORD $0x4e342c84    // SQSUB V4.16B, V4.16B, V20.16B    q0 -= a1

// DO_FILTER6: apply the 6-tap filter on lanes selected by V22.
// Uses V18 (base delta, zeroed on non-selected lanes); a1=(27a+63)>>7,
// a2=(18a+63)>>7, a3=(9a+63)>>7 computed exactly in 16-bit lanes.
// Updates V1..V6 in place. Clobbers V8..V13, V18.
#define DO_FILTER6 \
	VAND V22.B16, V18.B16, V18.B16; \
	WORD $0x0f08a648; \ // SSHLL  V8.8H, V18.8B, #0   sign-extend a lo
	WORD $0x4f08a649; \ // SSHLL2 V9.8H, V18.16B, #0  sign-extend a hi
	WORD $0x4e7a9d08; \ // MUL V8.8H, V8.8H, V26.8H   9a lo
	WORD $0x4e7a9d29; \ // MUL V9.8H, V9.8H, V26.8H   9a hi
	VSHL $1, V8.H8, V10.H8; \
	VSHL $1, V9.H8, V11.H8; \
	VADD V8.H8, V10.H8, V12.H8; \
	VADD V9.H8, V11.H8, V13.H8; \
	VADD V31.H8, V8.H8, V8.H8; \
	VADD V31.H8, V9.H8, V9.H8; \
	VADD V31.H8, V10.H8, V10.H8; \
	VADD V31.H8, V11.H8, V11.H8; \
	VADD V31.H8, V12.H8, V12.H8; \
	VADD V31.H8, V13.H8, V13.H8; \
	WORD $0x4f190508; \ // SSHR V8.8H,  V8.8H,  #7    a3 lo
	WORD $0x4f190529; \ // SSHR V9.8H,  V9.8H,  #7    a3 hi
	WORD $0x4f19054a; \ // SSHR V10.8H, V10.8H, #7    a2 lo
	WORD $0x4f19056b; \ // SSHR V11.8H, V11.8H, #7    a2 hi
	WORD $0x4f19058c; \ // SSHR V12.8H, V12.8H, #7    a1 lo
	WORD $0x4f1905ad; \ // SSHR V13.8H, V13.8H, #7    a1 hi
	WORD $0x0e212908; \ // XTN  V8.8B,  V8.8H
	WORD $0x4e212928; \ // XTN2 V8.16B, V9.8H         a3
	WORD $0x0e21294a; \ // XTN  V10.8B, V10.8H
	WORD $0x4e21296a; \ // XTN2 V10.16B, V11.8H       a2
	WORD $0x0e21298c; \ // XTN  V12.8B, V12.8H
	WORD $0x4e2129ac; \ // XTN2 V12.16B, V13.8H       a1
	WORD $0x4e2c0c63; \ // SQADD V3.16B, V3.16B, V12.16B   p0 += a1
	WORD $0x4e2c2c84; \ // SQSUB V4.16B, V4.16B, V12.16B   q0 -= a1
	WORD $0x4e2a0c42; \ // SQADD V2.16B, V2.16B, V10.16B   p1 += a2
	WORD $0x4e2a2ca5; \ // SQSUB V5.16B, V5.16B, V10.16B   q1 -= a2
	WORD $0x4e280c21; \ // SQADD V1.16B, V1.16B, V8.16B    p2 += a3
	WORD $0x4e282cc6    // SQSUB V6.16B, V6.16B, V8.16B    q2 -= a3

// DO_FILTER4: apply the 4-tap filter on lanes selected by V22.
// Recomputes 3*(q0-p0) from the (possibly filter2-updated) V3/V4 — the
// complex-mask lanes were untouched by DO_FILTER2 so this matches the Go
// code exactly. Updates V2..V5 in place. Clobbers V18, V19, V20, V23.
#define DO_FILTER4 \
	WORD $0x4e232c93; \ // SQSUB V19.16B, V4.16B, V3.16B   q0s - p0s
	WORD $0x4e330e72; \ // SQADD V18.16B, V19.16B, V19.16B
	WORD $0x4e320e72; \ // SQADD V18.16B, V19.16B, V18.16B 3*(q0-p0)
	VAND V22.B16, V18.B16, V18.B16; \
	WORD $0x4e380e54; \ // SQADD V20.16B, V18.16B, V24.16B a+4
	WORD $0x4e390e53; \ // SQADD V19.16B, V18.16B, V25.16B a+3
	WORD $0x4f0d0694; \ // SSHR V20.16B, V20.16B, #3       a1
	WORD $0x4f0d0673; \ // SSHR V19.16B, V19.16B, #3       a2
	WORD $0x4f0f2697; \ // SRSHR V23.16B, V20.16B, #1      a3 = (a1+1)>>1
	WORD $0x4e330c63; \ // SQADD V3.16B, V3.16B, V19.16B   p0 += a2
	WORD $0x4e342c84; \ // SQSUB V4.16B, V4.16B, V20.16B   q0 -= a1
	WORD $0x4e370c42; \ // SQADD V2.16B, V2.16B, V23.16B   p1 += a3
	WORD $0x4e372ca5    // SQSUB V5.16B, V5.16B, V23.16B   q1 -= a3

// LOAD_LUMA_8ROWS: load p3..q3 (V0..V7), 16 bytes per row, from R0-4*stride.
#define LOAD_LUMA_8ROWS \
	LSL $2, R2, R6; \
	SUB R6, R0, R4; \
	VLD1.P (R4)(R2), [V0.B16]; \
	VLD1.P (R4)(R2), [V1.B16]; \
	VLD1.P (R4)(R2), [V2.B16]; \
	VLD1.P (R4)(R2), [V3.B16]; \
	VLD1.P (R4)(R2), [V4.B16]; \
	VLD1.P (R4)(R2), [V5.B16]; \
	VLD1.P (R4)(R2), [V6.B16]; \
	VLD1.P (R4)(R2), [V7.B16]

// LOAD_UV_8ROWS: load p3..q3 with the U rows (from R4, 8 bytes) in the low
// half and the V rows (from R5) in the high half of each vector.
// The U-plane VLD1 into .B8 zeroes the upper half, then a single-lane LD1
// fills it from the V plane.
#define LOAD_UV_8ROWS \
	LSL $2, R2, R6; \
	SUB R6, R0, R4; \
	SUB R6, R1, R5; \
	VLD1.P (R4)(R2), [V0.B8]; \
	WORD $0x4dc284a0; \ // LD1 {V0.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V1.B8]; \
	WORD $0x4dc284a1; \ // LD1 {V1.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V2.B8]; \
	WORD $0x4dc284a2; \ // LD1 {V2.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V3.B8]; \
	WORD $0x4dc284a3; \ // LD1 {V3.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V4.B8]; \
	WORD $0x4dc284a4; \ // LD1 {V4.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V5.B8]; \
	WORD $0x4dc284a5; \ // LD1 {V5.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V6.B8]; \
	WORD $0x4dc284a6; \ // LD1 {V6.D}[1], [R5], R2
	VLD1.P (R4)(R2), [V7.B8]; \
	WORD $0x4dc284a7    // LD1 {V7.D}[1], [R5], R2

// func simpleVFilter16NEON(p []byte, base, stride, thresh int)
// Simple 2-tap vertical filter across a 16-wide edge (bit-exact with
// simpleVFilter16Go). thresh must be in [0, 30000].
TEXT ·simpleVFilter16NEON(SB), NOSPLIT, $0-48
	MOVD p_base+0(FP), R0
	MOVD base+24(FP), R1
	ADD  R1, R0, R0            // R0 = &p[base] (q0 row)
	MOVD stride+32(FP), R2
	MOVD thresh+40(FP), R3
	LSL  $1, R3, R3
	ADD  $1, R3, R3            // thresh2 = 2*thresh + 1
	VDUP R3, V27.H8
	FILTER_CONSTS

	// Load p1, p0, q0, q1.
	LSL  $1, R2, R6
	SUB  R6, R0, R4            // base - 2*stride
	VLD1.P (R4)(R2), [V2.B16]  // p1
	VLD1.P (R4)(R2), [V3.B16]  // p0
	VLD1.P (R4)(R2), [V4.B16]  // q0
	VLD1.P (R4)(R2), [V5.B16]  // q1

	NEEDS_FILTER_EDGE          // V9 = mask
	VORR V9.B16, V9.B16, V21.B16

	FLIP_SIGN4
	BASE_DELTA
	DO_FILTER2

	// Flip back and store p0, q0.
	VEOR V30.B16, V3.B16, V3.B16
	VEOR V30.B16, V4.B16, V4.B16
	SUB  R2, R0, R4
	VST1.P [V3.B16], (R4)(R2)
	VST1   [V4.B16], (R4)

	RET

// func vFilter16EdgeNEON(p []byte, base, stride, thresh, ithresh, hevT int)
// Complex vertical macroblock-edge filter (FilterLoop26, 16 wide).
// Bit-exact with filterLoop26(p, base, stride, 1, 16, ...) for
// thresh in [0, 30000], ithresh/hevT in [0, 255].
TEXT ·vFilter16EdgeNEON(SB), NOSPLIT, $0-64
	MOVD p_base+0(FP), R0
	MOVD base+24(FP), R1
	ADD  R1, R0, R0
	MOVD stride+32(FP), R2
	MOVD thresh+40(FP), R3
	LSL  $1, R3, R3
	ADD  $1, R3, R3
	VDUP R3, V27.H8            // thresh2
	MOVD ithresh+48(FP), R3
	VDUP R3, V28.B16
	MOVD hevT+56(FP), R3
	VDUP R3, V29.B16
	FILTER_CONSTS
	MOVD $9, R3
	VDUP R3, V26.H8
	MOVD $63, R3
	VDUP R3, V31.H8

	LOAD_LUMA_8ROWS

	NEEDS_FILTER2
	COMBINE_MASKS
	FLIP_SIGN6
	BASE_DELTA
	DO_FILTER2
	DO_FILTER6

	// Flip back and store p2..q2 (6 rows starting at base-3*stride).
	VEOR V30.B16, V1.B16, V1.B16
	VEOR V30.B16, V2.B16, V2.B16
	VEOR V30.B16, V3.B16, V3.B16
	VEOR V30.B16, V4.B16, V4.B16
	VEOR V30.B16, V5.B16, V5.B16
	VEOR V30.B16, V6.B16, V6.B16
	LSL  $1, R2, R6
	ADD  R2, R6, R6            // 3*stride
	SUB  R6, R0, R4
	VST1.P [V1.B16], (R4)(R2)
	VST1.P [V2.B16], (R4)(R2)
	VST1.P [V3.B16], (R4)(R2)
	VST1.P [V4.B16], (R4)(R2)
	VST1.P [V5.B16], (R4)(R2)
	VST1   [V6.B16], (R4)

	RET

// func vFilter16InnerNEON(p []byte, base, stride, thresh, ithresh, hevT int)
// Complex vertical inner-edge filter (one FilterLoop24 span, 16 wide).
// Bit-exact with filterLoop24(p, base, stride, 1, 16, ...) for
// thresh in [0, 30000], ithresh/hevT in [0, 255].
TEXT ·vFilter16InnerNEON(SB), NOSPLIT, $0-64
	MOVD p_base+0(FP), R0
	MOVD base+24(FP), R1
	ADD  R1, R0, R0
	MOVD stride+32(FP), R2
	MOVD thresh+40(FP), R3
	LSL  $1, R3, R3
	ADD  $1, R3, R3
	VDUP R3, V27.H8
	MOVD ithresh+48(FP), R3
	VDUP R3, V28.B16
	MOVD hevT+56(FP), R3
	VDUP R3, V29.B16
	FILTER_CONSTS

	LOAD_LUMA_8ROWS

	NEEDS_FILTER2
	COMBINE_MASKS
	FLIP_SIGN4
	BASE_DELTA
	DO_FILTER2
	DO_FILTER4

	// Flip back and store p1..q1 (4 rows starting at base-2*stride).
	VEOR V30.B16, V2.B16, V2.B16
	VEOR V30.B16, V3.B16, V3.B16
	VEOR V30.B16, V4.B16, V4.B16
	VEOR V30.B16, V5.B16, V5.B16
	LSL  $1, R2, R6
	SUB  R6, R0, R4
	VST1.P [V2.B16], (R4)(R2)
	VST1.P [V3.B16], (R4)(R2)
	VST1.P [V4.B16], (R4)(R2)
	VST1   [V5.B16], (R4)

	RET

// func vFilter8EdgeNEON(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)
// Complex vertical macroblock-edge filter for both 8-wide chroma planes.
// U rows occupy lanes 0-7, V rows lanes 8-15 of each vector.
// Bit-exact with filterLoop26 on each plane.
TEXT ·vFilter8EdgeNEON(SB), NOSPLIT, $0-96
	MOVD u_base+0(FP), R0
	MOVD v_base+24(FP), R1
	MOVD uBase+48(FP), R3
	ADD  R3, R0, R0
	MOVD vBase+56(FP), R3
	ADD  R3, R1, R1
	MOVD stride+64(FP), R2
	MOVD thresh+72(FP), R3
	LSL  $1, R3, R3
	ADD  $1, R3, R3
	VDUP R3, V27.H8
	MOVD ithresh+80(FP), R3
	VDUP R3, V28.B16
	MOVD hevT+88(FP), R3
	VDUP R3, V29.B16
	FILTER_CONSTS
	MOVD $9, R3
	VDUP R3, V26.H8
	MOVD $63, R3
	VDUP R3, V31.H8

	LOAD_UV_8ROWS

	NEEDS_FILTER2
	COMBINE_MASKS
	FLIP_SIGN6
	BASE_DELTA
	DO_FILTER2
	DO_FILTER6

	// Flip back and store p2..q2 to both planes.
	VEOR V30.B16, V1.B16, V1.B16
	VEOR V30.B16, V2.B16, V2.B16
	VEOR V30.B16, V3.B16, V3.B16
	VEOR V30.B16, V4.B16, V4.B16
	VEOR V30.B16, V5.B16, V5.B16
	VEOR V30.B16, V6.B16, V6.B16
	LSL  $1, R2, R6
	ADD  R2, R6, R6            // 3*stride
	SUB  R6, R0, R4
	SUB  R6, R1, R5
	VST1.P [V1.B8], (R4)(R2)
	WORD $0x4d8284a1           // ST1 {V1.D}[1], [R5], R2
	VST1.P [V2.B8], (R4)(R2)
	WORD $0x4d8284a2           // ST1 {V2.D}[1], [R5], R2
	VST1.P [V3.B8], (R4)(R2)
	WORD $0x4d8284a3           // ST1 {V3.D}[1], [R5], R2
	VST1.P [V4.B8], (R4)(R2)
	WORD $0x4d8284a4           // ST1 {V4.D}[1], [R5], R2
	VST1.P [V5.B8], (R4)(R2)
	WORD $0x4d8284a5           // ST1 {V5.D}[1], [R5], R2
	VST1.P [V6.B8], (R4)(R2)
	WORD $0x4d8284a6           // ST1 {V6.D}[1], [R5], R2

	RET

// func vFilter8InnerNEON(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)
// Complex vertical inner-edge filter for both 8-wide chroma planes
// (one FilterLoop24 span; the caller passes bases already offset by
// 4*stride). Bit-exact with filterLoop24 on each plane.
TEXT ·vFilter8InnerNEON(SB), NOSPLIT, $0-96
	MOVD u_base+0(FP), R0
	MOVD v_base+24(FP), R1
	MOVD uBase+48(FP), R3
	ADD  R3, R0, R0
	MOVD vBase+56(FP), R3
	ADD  R3, R1, R1
	MOVD stride+64(FP), R2
	MOVD thresh+72(FP), R3
	LSL  $1, R3, R3
	ADD  $1, R3, R3
	VDUP R3, V27.H8
	MOVD ithresh+80(FP), R3
	VDUP R3, V28.B16
	MOVD hevT+88(FP), R3
	VDUP R3, V29.B16
	FILTER_CONSTS

	LOAD_UV_8ROWS

	NEEDS_FILTER2
	COMBINE_MASKS
	FLIP_SIGN4
	BASE_DELTA
	DO_FILTER2
	DO_FILTER4

	// Flip back and store p1..q1 to both planes.
	VEOR V30.B16, V2.B16, V2.B16
	VEOR V30.B16, V3.B16, V3.B16
	VEOR V30.B16, V4.B16, V4.B16
	VEOR V30.B16, V5.B16, V5.B16
	LSL  $1, R2, R6
	SUB  R6, R0, R4
	SUB  R6, R1, R5
	VST1.P [V2.B8], (R4)(R2)
	WORD $0x4d8284a2           // ST1 {V2.D}[1], [R5], R2
	VST1.P [V3.B8], (R4)(R2)
	WORD $0x4d8284a3           // ST1 {V3.D}[1], [R5], R2
	VST1.P [V4.B8], (R4)(R2)
	WORD $0x4d8284a4           // ST1 {V4.D}[1], [R5], R2
	VST1.P [V5.B8], (R4)(R2)
	WORD $0x4d8284a5           // ST1 {V5.D}[1], [R5], R2

	RET
