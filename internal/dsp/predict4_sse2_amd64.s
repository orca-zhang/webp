#include "textflag.h"

// VP8 4x4 intra prediction modes - AMD64 SSE2 assembly.
//
// All functions have signature: func xxx4asmSSE2(dst []byte, off int)
// Arguments on stack (Plan9 ABI):
//   dst_base+0(FP)   = pointer to dst data
//   dst_len+8(FP)    = length (unused)
//   dst_cap+16(FP)   = capacity (unused)
//   off+24(FP)       = byte offset into dst
//
// BPS = 32 (stride between rows).
//
// Port of the NEON kernels in predict_arm64.s, using the libwebp SSE2
// technique (dec_sse2.c: VE4_SSE2, RD4_SSE2, ...) for the averages:
//   - avg2(a,b) = (a + b + 1) >> 1 = PAVGB(a, b) (rounds up, like URHADD).
//   - avg3(a,b,c) = (a + 2b + c + 2) >> 2 is computed branch-free as
//     PAVGB(PAVGB(a,c) - ((a XOR c) AND 1), b). The subtraction turns the
//     rounding PAVGB into a truncating average (UHADD equivalent); this is
//     bit-exact for the same reason as the NEON URHADD(UHADD(a,c), b) trick.
//   - MOVQ loads/moves zero the upper 8 XMM bytes, so PSRLDQ shifts bring in
//     zeros; lanes past the ones consumed are never read, except where a
//     PINSRW patches the needed byte (LD4/RD4), mirroring libwebp.
//   - Rows are 4 bytes wide: results are moved to a GPR and written with
//     32-bit stores (one per row).
//   - Top-row loads may read up to dst[off-BPS+6]; callers guarantee 8 bytes
//     of top(-right) context (the scalar LD4/VL4 already read off-BPS+7).

#define BPS 32

// AVG3_X0X1X2 computes per-byte avg3(X0, X1, X2) into X0.
// Requires X6 = 0x01 in each (low 8) byte(s); clobbers X7.
#define AVG3_X0X1X2 \
	MOVO  X0, X7; \
	PXOR  X2, X7; \
	PAND  X6, X7; \
	PAVGB X2, X0; \
	PSUBB X7, X0; \
	PAVGB X1, X0

// LOAD_ONE_X6 sets the low 8 bytes of X6 to 0x01 (clobbers BX).
#define LOAD_ONE_X6 \
	MOVQ $0x0101010101010101, BX; \
	MOVQ BX, X6

// func dc4asmSSE2(dst []byte, off int)
// DC 4x4: average of 4 top + 4 left pixels. Scalar sum + dword fills.
TEXT ·dc4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	MOVBQZX -BPS(SI), AX     // top row
	MOVBQZX -BPS+1(SI), DX
	ADDQ DX, AX
	MOVBQZX -BPS+2(SI), DX
	ADDQ DX, AX
	MOVBQZX -BPS+3(SI), DX
	ADDQ DX, AX
	MOVBQZX -1(SI), DX       // left column
	ADDQ DX, AX
	MOVBQZX BPS-1(SI), DX
	ADDQ DX, AX
	MOVBQZX 2*BPS-1(SI), DX
	ADDQ DX, AX
	MOVBQZX 3*BPS-1(SI), DX
	ADDQ DX, AX

	ADDQ $4, AX
	SHRQ $3, AX              // dc = (sum + 4) >> 3
	MOVQ $0x01010101, DX
	IMULQ DX, AX             // replicate dc into 4 bytes
	MOVL AX, (SI)
	MOVL AX, BPS(SI)
	MOVL AX, 2*BPS(SI)
	MOVL AX, 3*BPS(SI)
	RET

// func tm4asmSSE2(dst []byte, off int)
// TrueMotion 4x4: dst[i,j] = clip(left[j] + top[i] - tl).
TEXT ·tm4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	PXOR X7, X7              // zero register

	MOVBQZX -1-BPS(SI), AX   // tl
	MOVL -BPS(SI), DX        // 4 top pixels
	MOVD DX, X4
	PUNPCKLBW X7, X4         // X4 = top[0..3] as int16 (low 4 words)

	// Broadcast tl as int16, compute diff = top - tl
	MOVD AX, X6
	PUNPCKLWL X6, X6
	PSHUFD $0x00, X6, X6     // X6 = tl (8 x int16)
	PSUBW X6, X4             // X4 = top - tl (int16)

	MOVBQZX -1(SI), AX       // row 0
	MOVD AX, X0
	PUNPCKLWL X0, X0
	PSHUFD $0x00, X0, X0
	PADDW X4, X0
	PACKUSWB X7, X0          // clips to [0,255]
	MOVQ X0, AX
	MOVL AX, (SI)

	MOVBQZX BPS-1(SI), AX    // row 1
	MOVD AX, X0
	PUNPCKLWL X0, X0
	PSHUFD $0x00, X0, X0
	PADDW X4, X0
	PACKUSWB X7, X0
	MOVQ X0, AX
	MOVL AX, BPS(SI)

	MOVBQZX 2*BPS-1(SI), AX  // row 2
	MOVD AX, X0
	PUNPCKLWL X0, X0
	PSHUFD $0x00, X0, X0
	PADDW X4, X0
	PACKUSWB X7, X0
	MOVQ X0, AX
	MOVL AX, 2*BPS(SI)

	MOVBQZX 3*BPS-1(SI), AX  // row 3
	MOVD AX, X0
	PUNPCKLWL X0, X0
	PSHUFD $0x00, X0, X0
	PADDW X4, X0
	PACKUSWB X7, X0
	MOVQ X0, AX
	MOVL AX, 3*BPS(SI)
	RET

// func ve4asmSSE2(dst []byte, off int)
// Vertical 4x4: one row of avg3 over top[-1..4], replicated 4 times.
TEXT ·ve4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVQ -1-BPS(SI), X0      // [tl t0 t1 t2 t3 t4 x x]
	MOVO X0, X1
	PSRLDQ $1, X1
	MOVO X0, X2
	PSRLDQ $2, X2
	AVG3_X0X1X2              // X0 = avg3 lanes; lanes 0..3 used
	MOVQ X0, AX
	MOVL AX, (SI)
	MOVL AX, BPS(SI)
	MOVL AX, 2*BPS(SI)
	MOVL AX, 3*BPS(SI)
	RET

// func he4asmSSE2(dst []byte, off int)
// Horizontal 4x4: per-row avg3 over left column, broadcast across the row.
TEXT ·he4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	MOVBQZX -1-BPS(SI), R8   // tl
	MOVBQZX -1(SI), R9       // l0
	MOVBQZX BPS-1(SI), R10   // l1
	MOVBQZX 2*BPS-1(SI), R11 // l2
	MOVBQZX 3*BPS-1(SI), R12 // l3
	MOVQ $0x01010101, DI

	LEAQ 2(R8)(R10*1), AX    // avg3(tl, l0, l1)
	LEAQ (AX)(R9*2), AX
	SHRQ $2, AX
	IMULQ DI, AX
	MOVL AX, (SI)

	LEAQ 2(R9)(R11*1), AX    // avg3(l0, l1, l2)
	LEAQ (AX)(R10*2), AX
	SHRQ $2, AX
	IMULQ DI, AX
	MOVL AX, BPS(SI)

	LEAQ 2(R10)(R12*1), AX   // avg3(l1, l2, l3)
	LEAQ (AX)(R11*2), AX
	SHRQ $2, AX
	IMULQ DI, AX
	MOVL AX, 2*BPS(SI)

	LEAQ 2(R11)(R12*1), AX   // avg3(l2, l3, l3)
	LEAQ (AX)(R12*2), AX
	SHRQ $2, AX
	IMULQ DI, AX
	MOVL AX, 3*BPS(SI)
	RET

// func ld4asmSSE2(dst []byte, off int)
// Down-Left 4x4: avg3 over the 8 top pixels; row j = lanes j..j+3.
TEXT ·ld4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVQ -BPS(SI), X0        // A..H
	MOVO X0, X1
	PSRLDQ $1, X1            // B..H 0
	MOVO X0, X2
	PSRLDQ $2, X2            // C..H 0 0
	MOVBQZX -BPS+7(SI), AX   // H
	PINSRW $3, AX, X2        // bytes 6,7 = H,0: lane 6 becomes avg3(G, H, H)
	AVG3_X0X1X2
	MOVQ X0, AX
	MOVL AX, (SI)            // row 0 = lanes 0..3
	SHRQ $8, AX
	MOVL AX, BPS(SI)         // row 1 = lanes 1..4
	SHRQ $8, AX
	MOVL AX, 2*BPS(SI)       // row 2 = lanes 2..5
	SHRQ $8, AX
	MOVL AX, 3*BPS(SI)       // row 3 = lanes 3..6
	RET

// func rd4asmSSE2(dst []byte, off int)
// Down-Right 4x4: avg3 over X = [l3 l2 l1 l0 tl t0 t1 t2] (+t3 in lane 6).
TEXT ·rd4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVBQZX 3*BPS-1(SI), AX  // l3
	MOVBQZX 2*BPS-1(SI), DX  // l2
	SHLQ $8, DX
	ORQ DX, AX
	MOVBQZX BPS-1(SI), DX    // l1
	SHLQ $16, DX
	ORQ DX, AX
	MOVBQZX -1(SI), DX       // l0
	SHLQ $24, DX
	ORQ DX, AX
	MOVL -1-BPS(SI), DX      // [tl t0 t1 t2]
	SHLQ $32, DX
	ORQ DX, AX
	MOVQ AX, X0              // X0 = [l3 l2 l1 l0 tl t0 t1 t2]
	MOVO X0, X1
	PSRLDQ $1, X1
	MOVO X0, X2
	PSRLDQ $2, X2
	MOVBQZX 3-BPS(SI), AX    // t3
	PINSRW $3, AX, X2        // lane 6 becomes avg3(t1, t2, t3)
	AVG3_X0X1X2
	MOVQ X0, AX
	MOVL AX, 3*BPS(SI)       // row 3 = lanes 0..3
	SHRQ $8, AX
	MOVL AX, 2*BPS(SI)       // row 2 = lanes 1..4
	SHRQ $8, AX
	MOVL AX, BPS(SI)         // row 1 = lanes 2..5
	SHRQ $8, AX
	MOVL AX, (SI)            // row 0 = lanes 3..6
	RET

// func vr4asmSSE2(dst []byte, off int)
// Vertical-Right 4x4 over X = [l2 l1 l0 tl t0 t1 t2 t3].
TEXT ·vr4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVBQZX 2*BPS-1(SI), AX  // l2
	MOVBQZX BPS-1(SI), DX    // l1
	SHLQ $8, DX
	ORQ DX, AX
	MOVBQZX -1(SI), DX       // l0
	SHLQ $16, DX
	ORQ DX, AX
	MOVBQZX -1-BPS(SI), DX   // tl
	SHLQ $24, DX
	ORQ DX, AX
	MOVL -BPS(SI), DX        // [t0 t1 t2 t3]
	SHLQ $32, DX
	ORQ DX, AX
	MOVQ AX, X0              // X0 = [l2 l1 l0 tl t0 t1 t2 t3]
	MOVO X0, X1
	PSRLDQ $1, X1
	MOVO X0, X2
	PSRLDQ $2, X2
	MOVO X0, X5
	PAVGB X1, X5             // X5 = avg2 lanes
	AVG3_X0X1X2              // X0 = avg3 lanes
	MOVQ X5, AX              // avg2
	MOVQ X0, DX              // avg3

	MOVQ AX, CX
	SHRQ $24, CX
	MOVL CX, (SI)            // row 0 = avg2 lanes 3..6

	MOVQ DX, CX
	SHRQ $16, CX
	MOVL CX, BPS(SI)         // row 1 = avg3 lanes 2..5

	MOVQ DX, CX              // row 2 = [avg3 lane 1, avg2 lanes 3..5]
	SHRQ $8, CX
	ANDL $0xff, CX
	MOVQ AX, BX
	SHRQ $16, BX
	ANDL $0xffffff00, BX
	ORL BX, CX
	MOVL CX, 2*BPS(SI)

	MOVQ DX, CX              // row 3 = [avg3 lane 0, avg3 lanes 2..4]
	ANDL $0xff, CX
	MOVQ DX, BX
	SHRQ $8, BX
	ANDL $0xffffff00, BX
	ORL BX, CX
	MOVL CX, 3*BPS(SI)
	RET

// func vl4asmSSE2(dst []byte, off int)
// Vertical-Left 4x4: avg2/avg3 over the 8 top pixels A..H.
TEXT ·vl4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVQ -BPS(SI), X0        // A..H
	MOVO X0, X1
	PSRLDQ $1, X1
	MOVO X0, X2
	PSRLDQ $2, X2
	MOVO X0, X5
	PAVGB X1, X5             // X5 = avg2 lanes
	AVG3_X0X1X2              // X0 = avg3 lanes (lane 5 = avg3(F,G,H) valid)
	MOVQ X5, AX              // avg2
	MOVQ X0, DX              // avg3

	MOVL AX, (SI)            // row 0 = avg2 lanes 0..3
	MOVL DX, BPS(SI)         // row 1 = avg3 lanes 0..3

	MOVQ AX, CX              // row 2 = [avg2 lanes 1..3, avg3 lane 4]
	SHRQ $8, CX
	ANDL $0x00ffffff, CX
	MOVQ DX, BX
	SHRQ $8, BX
	ANDL $0xff000000, BX
	ORL BX, CX
	MOVL CX, 2*BPS(SI)

	MOVQ DX, CX              // row 3 = [avg3 lanes 1..3, avg3 lane 5]
	SHRQ $8, CX
	ANDL $0x00ffffff, CX
	MOVQ DX, BX
	SHRQ $16, BX
	ANDL $0xff000000, BX
	ORL BX, CX
	MOVL CX, 3*BPS(SI)
	RET

// func hd4asmSSE2(dst []byte, off int)
// Horizontal-Down 4x4 over X = [l3 l2 l1 l0 tl t0 t1 t2], zip(avg2, avg3).
TEXT ·hd4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVBQZX 3*BPS-1(SI), AX  // l3
	MOVBQZX 2*BPS-1(SI), DX  // l2
	SHLQ $8, DX
	ORQ DX, AX
	MOVBQZX BPS-1(SI), DX    // l1
	SHLQ $16, DX
	ORQ DX, AX
	MOVBQZX -1(SI), DX       // l0
	SHLQ $24, DX
	ORQ DX, AX
	MOVL -1-BPS(SI), DX      // [tl t0 t1 t2]
	SHLQ $32, DX
	ORQ DX, AX
	MOVQ AX, X0              // X0 = [l3 l2 l1 l0 tl t0 t1 t2]
	MOVO X0, X1
	PSRLDQ $1, X1
	MOVO X0, X2
	PSRLDQ $2, X2
	MOVO X0, X5
	PAVGB X1, X5             // X5 = avg2 lanes
	AVG3_X0X1X2              // X0 = avg3 lanes
	PUNPCKLBW X0, X5         // X5 = [a2_0 a3_0 a2_1 a3_1 a2_2 a3_2 a2_3 a3_3 ...]
	MOVQ X5, AX              // zip
	MOVQ X0, DX              // avg3

	MOVL AX, 3*BPS(SI)       // row 3 = zip lanes 0..3
	MOVQ AX, CX
	SHRQ $16, CX
	MOVL CX, 2*BPS(SI)       // row 2 = zip lanes 2..5
	MOVQ AX, CX
	SHRQ $32, CX
	MOVL CX, BPS(SI)         // row 1 = zip lanes 4..7
	MOVQ AX, CX              // row 0 = [zip lanes 6..7, avg3 lanes 4..5]
	SHRQ $48, CX
	MOVQ DX, BX
	SHRQ $16, BX
	ANDL $0xffff0000, BX
	ORL BX, CX
	MOVL CX, (SI)
	RET

// func hu4asmSSE2(dst []byte, off int)
// Horizontal-Up 4x4 over X = [l0 l1 l2 l3 l3 l3 l3 l3], zip(avg2, avg3).
TEXT ·hu4asmSSE2(SB), NOSPLIT, $0-32
	MOVQ dst_base+0(FP), SI
	MOVQ off+24(FP), AX
	ADDQ AX, SI              // SI = &dst[off]

	LOAD_ONE_X6
	MOVBQZX 3*BPS-1(SI), AX  // l3
	MOVQ $0x0101010101010101, DX
	IMULQ DX, AX             // AX = l3 replicated in all 8 bytes
	MOVQ AX, R8              // keep for row 3
	SHRQ $24, AX
	SHLQ $24, AX             // clear low 3 bytes
	MOVBQZX -1(SI), DX       // l0
	ORQ DX, AX
	MOVBQZX BPS-1(SI), DX    // l1
	SHLQ $8, DX
	ORQ DX, AX
	MOVBQZX 2*BPS-1(SI), DX  // l2
	SHLQ $16, DX
	ORQ DX, AX
	MOVQ AX, X0              // X0 = [l0 l1 l2 l3 l3 l3 l3 l3]
	MOVO X0, X1
	PSRLDQ $1, X1
	MOVO X0, X2
	PSRLDQ $2, X2
	MOVO X0, X5
	PAVGB X1, X5             // X5 = avg2 lanes
	AVG3_X0X1X2              // X0 = avg3 lanes
	PUNPCKLBW X0, X5         // X5 = [a2_0 a3_0 a2_1 a3_1 a2_2 a3_2 l3 l3 ...]
	MOVQ X5, AX

	MOVL AX, (SI)            // row 0 = zip lanes 0..3
	MOVQ AX, CX
	SHRQ $16, CX
	MOVL CX, BPS(SI)         // row 1 = zip lanes 2..5
	SHRQ $16, CX
	MOVL CX, 2*BPS(SI)       // row 2 = zip lanes 4..7
	MOVL R8, 3*BPS(SI)       // row 3 = [l3 l3 l3 l3]
	RET
