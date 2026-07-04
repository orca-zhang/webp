#include "textflag.h"

#define BPS 32

// func ve16asmNEON(dst []byte, off int)
// Vertical 16x16: copy top row to all 16 rows.
TEXT ·ve16asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0                  // R0 = &dst[off]
	SUB $BPS, R0, R2            // R2 = &dst[off-BPS] (top row)
	VLD1 (R2), [V0.B16]        // load 16 top bytes

	VST1 [V0.B16], (R0)
	ADD $BPS, R0, R2
	VST1 [V0.B16], (R2)
	ADD $(2*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(3*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(4*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(5*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(6*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(7*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(8*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(9*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(10*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(11*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(12*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(13*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(14*BPS), R0, R2
	VST1 [V0.B16], (R2)
	ADD $(15*BPS), R0, R2
	VST1 [V0.B16], (R2)
	RET

// func he16asmNEON(dst []byte, off int)
// Horizontal 16x16: broadcast left pixel per row.
TEXT ·he16asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVD $16, R3

he16_loop:
	SUB $1, R0, R2
	MOVBU (R2), R4
	VDUP R4, V0.B16
	VST1 [V0.B16], (R0)
	ADD $BPS, R0
	SUBS $1, R3
	BNE he16_loop
	RET

// func dc16asmNEON(dst []byte, off int)
// DC 16x16: average top+left, fill block. Scalar sum + NEON fill.
TEXT ·dc16asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0                  // R0 = &dst[off]

	// Sum 16 top pixels (scalar)
	SUB $BPS, R0, R2
	MOVD $0, R3
	MOVBU (R2), R4
	ADD R4, R3
	MOVBU 1(R2), R4
	ADD R4, R3
	MOVBU 2(R2), R4
	ADD R4, R3
	MOVBU 3(R2), R4
	ADD R4, R3
	MOVBU 4(R2), R4
	ADD R4, R3
	MOVBU 5(R2), R4
	ADD R4, R3
	MOVBU 6(R2), R4
	ADD R4, R3
	MOVBU 7(R2), R4
	ADD R4, R3
	MOVBU 8(R2), R4
	ADD R4, R3
	MOVBU 9(R2), R4
	ADD R4, R3
	MOVBU 10(R2), R4
	ADD R4, R3
	MOVBU 11(R2), R4
	ADD R4, R3
	MOVBU 12(R2), R4
	ADD R4, R3
	MOVBU 13(R2), R4
	ADD R4, R3
	MOVBU 14(R2), R4
	ADD R4, R3
	MOVBU 15(R2), R4
	ADD R4, R3

	// Sum 16 left pixels (scalar)
	SUB $1, R0, R2
	MOVBU (R2), R4
	ADD R4, R3
	MOVBU BPS(R2), R4
	ADD R4, R3
	MOVBU (2*BPS)(R2), R4
	ADD R4, R3
	MOVBU (3*BPS)(R2), R4
	ADD R4, R3
	MOVBU (4*BPS)(R2), R4
	ADD R4, R3
	MOVBU (5*BPS)(R2), R4
	ADD R4, R3
	MOVBU (6*BPS)(R2), R4
	ADD R4, R3
	MOVBU (7*BPS)(R2), R4
	ADD R4, R3
	MOVBU (8*BPS)(R2), R4
	ADD R4, R3
	MOVBU (9*BPS)(R2), R4
	ADD R4, R3
	MOVBU (10*BPS)(R2), R4
	ADD R4, R3
	MOVBU (11*BPS)(R2), R4
	ADD R4, R3
	MOVBU (12*BPS)(R2), R4
	ADD R4, R3
	MOVBU (13*BPS)(R2), R4
	ADD R4, R3
	MOVBU (14*BPS)(R2), R4
	ADD R4, R3
	MOVBU (15*BPS)(R2), R4
	ADD R4, R3

	// DC = (sum + 16) >> 5
	ADD $16, R3
	LSR $5, R3
	VDUP R3, V0.B16             // broadcast to 16 bytes

	// Fill 16 rows
	MOVD $16, R3
dc16_store:
	VST1 [V0.B16], (R0)
	ADD $BPS, R0
	SUBS $1, R3
	BNE dc16_store
	RET

// func tm16asmNEON(dst []byte, off int)
// TrueMotion 16x16: dst[i,j] = clip(left[j] + top[i] - tl).
// NEON vectorized: widen to uint16, add, saturating narrow.
// ~10 instructions per row vs ~68 scalar.
TEXT ·tm16asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0                  // R0 = &dst[off]

	// Load top-left pixel
	SUB $(BPS+1), R0, R2
	MOVBU (R2), R3              // tl

	// Load 16 top pixels
	SUB $BPS, R0, R2            // &top
	VLD1 (R2), [V0.B16]        // V0 = 16 top pixels (uint8)

	// Widen top pixels: uint8 → uint16 (two 8-element vectors)
	WORD $0x2F08A401            // UXTL  V1.8H, V0.8B   (low 8 pixels)
	WORD $0x6F08A402            // UXTL2 V2.8H, V0.16B  (high 8 pixels)

	// Broadcast tl as uint16, compute diff = top - tl
	VDUP R3, V3.H8              // V3 = [tl, tl, ...] × 8 as uint16
	VSUB V3.H8, V1.H8, V4.H8   // V4 = top_lo - tl (int16)
	VSUB V3.H8, V2.H8, V5.H8   // V5 = top_hi - tl (int16)

	MOVD $16, R5                // row counter
tm16_neon_row:
	SUB $1, R0, R6
	MOVBU (R6), R7              // left pixel for this row

	// Broadcast left as uint16, compute result = left + diff
	VDUP R7, V6.H8              // V6 = [left, ...] × 8 as uint16
	VADD V4.H8, V6.H8, V1.H8   // V1 = left + (top_lo - tl)
	VADD V5.H8, V6.H8, V2.H8   // V2 = left + (top_hi - tl)

	// Saturating narrow int16 → uint8 (clips to [0,255])
	WORD $0x2E212820            // SQXTUN  V0.8B,  V1.8H  (low 8 bytes)
	WORD $0x6E212840            // SQXTUN2 V0.16B, V2.8H  (high 8 bytes)

	// Store 16 result bytes
	VST1 [V0.B16], (R0)

	ADD $BPS, R0
	SUBS $1, R5
	BNE tm16_neon_row
	RET

// func ve8uvasmNEON(dst []byte, off int)
// Vertical 8x8.
TEXT ·ve8uvasmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	SUB $BPS, R0, R2
	VLD1 (R2), [V0.B8]

	VST1 [V0.B8], (R0)
	ADD $BPS, R0, R2
	VST1 [V0.B8], (R2)
	ADD $(2*BPS), R0, R2
	VST1 [V0.B8], (R2)
	ADD $(3*BPS), R0, R2
	VST1 [V0.B8], (R2)
	ADD $(4*BPS), R0, R2
	VST1 [V0.B8], (R2)
	ADD $(5*BPS), R0, R2
	VST1 [V0.B8], (R2)
	ADD $(6*BPS), R0, R2
	VST1 [V0.B8], (R2)
	ADD $(7*BPS), R0, R2
	VST1 [V0.B8], (R2)
	RET

// func he8uvasmNEON(dst []byte, off int)
// Horizontal 8x8.
TEXT ·he8uvasmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVD $8, R3

he8_loop:
	SUB $1, R0, R2
	MOVBU (R2), R4
	VDUP R4, V0.B8
	VST1 [V0.B8], (R0)
	ADD $BPS, R0
	SUBS $1, R3
	BNE he8_loop
	RET

// func dc8uvasmNEON(dst []byte, off int)
// DC 8x8.
TEXT ·dc8uvasmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0

	// Sum 8 top pixels (scalar)
	SUB $BPS, R0, R2
	MOVD $0, R3
	MOVBU (R2), R4
	ADD R4, R3
	MOVBU 1(R2), R4
	ADD R4, R3
	MOVBU 2(R2), R4
	ADD R4, R3
	MOVBU 3(R2), R4
	ADD R4, R3
	MOVBU 4(R2), R4
	ADD R4, R3
	MOVBU 5(R2), R4
	ADD R4, R3
	MOVBU 6(R2), R4
	ADD R4, R3
	MOVBU 7(R2), R4
	ADD R4, R3

	// Sum 8 left pixels (scalar)
	SUB $1, R0, R2
	MOVBU (R2), R4
	ADD R4, R3
	MOVBU BPS(R2), R4
	ADD R4, R3
	MOVBU (2*BPS)(R2), R4
	ADD R4, R3
	MOVBU (3*BPS)(R2), R4
	ADD R4, R3
	MOVBU (4*BPS)(R2), R4
	ADD R4, R3
	MOVBU (5*BPS)(R2), R4
	ADD R4, R3
	MOVBU (6*BPS)(R2), R4
	ADD R4, R3
	MOVBU (7*BPS)(R2), R4
	ADD R4, R3

	// DC = (sum + 8) >> 4
	ADD $8, R3
	LSR $4, R3
	VDUP R3, V0.B8

	MOVD $8, R3
dc8_store:
	VST1 [V0.B8], (R0)
	ADD $BPS, R0
	SUBS $1, R3
	BNE dc8_store
	RET

// func tm8uvasmNEON(dst []byte, off int)
// TrueMotion 8x8. NEON vectorized.
TEXT ·tm8uvasmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0

	SUB $(BPS+1), R0, R2
	MOVBU (R2), R3              // tl

	SUB $BPS, R0, R2            // &top
	VLD1 (R2), [V0.B8]         // V0 = 8 top pixels (uint8)

	// Widen top pixels: uint8 → uint16
	WORD $0x2F08A401            // UXTL V1.8H, V0.8B

	// Broadcast tl as uint16, compute diff = top - tl
	VDUP R3, V3.H8
	VSUB V3.H8, V1.H8, V4.H8   // V4 = top - tl (int16)

	MOVD $8, R5
tm8_neon_row:
	SUB $1, R0, R6
	MOVBU (R6), R7              // left

	VDUP R7, V6.H8
	VADD V4.H8, V6.H8, V1.H8   // V1 = left + (top - tl)

	// Saturating narrow int16 → uint8
	WORD $0x2E212820            // SQXTUN V0.8B, V1.8H

	VST1 [V0.B8], (R0)

	ADD $BPS, R0
	SUBS $1, R5
	BNE tm8_neon_row
	RET

// ---------------------------------------------------------------------------
// 4x4 intra prediction modes (encoder RD loop + decoder).
//
// Common tricks:
//   - avg3(a,b,c) = (a + 2b + c + 2) >> 2 is computed branch-free as
//     URHADD(UHADD(a, c), b). This is bit-exact: UHADD truncates (a+c)>>1,
//     losing 1 only when a+c is odd, in which case the true numerator
//     a+c+2b+2 is odd too, so the floor by 4 is unaffected.
//   - avg2(a,b) = (a + b + 1) >> 1 = URHADD(a, b).
//   - Rows are 4 bytes wide: results are moved to a GPR and written with
//     32-bit stores (one per row), avoiding 16 single-byte stores.
//   - Top-row loads may read up to dst[off-BPS+6]; callers guarantee 8 bytes
//     of top(-right) context (the scalar LD4/VL4 already read off-BPS+7).
//
// UHADD/URHADD are not supported by the Go assembler, hence WORD encodings:
//   UHADD  Vd.8B, Vn.8B, Vm.8B = 0x2E200400 | m<<16 | n<<5 | d
//   URHADD Vd.8B, Vn.8B, Vm.8B = 0x2E201400 | m<<16 | n<<5 | d
// ---------------------------------------------------------------------------

// func dc4asmNEON(dst []byte, off int)
// DC 4x4: average of 4 top + 4 left pixels. Scalar sum + word fills.
TEXT ·dc4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0                  // R0 = &dst[off]
	SUB $BPS, R0, R2            // R2 = &top
	MOVBU (R2), R3
	MOVBU 1(R2), R4
	ADD R4, R3
	MOVBU 2(R2), R4
	ADD R4, R3
	MOVBU 3(R2), R4
	ADD R4, R3
	MOVBU -1(R0), R4            // left column
	ADD R4, R3
	MOVBU (BPS-1)(R0), R4
	ADD R4, R3
	MOVBU (2*BPS-1)(R0), R4
	ADD R4, R3
	MOVBU (3*BPS-1)(R0), R4
	ADD R4, R3
	ADD $4, R3
	LSR $3, R3                  // dc = (sum + 4) >> 3
	MOVD $0x01010101, R5
	MULW R5, R3, R6             // replicate dc into 4 bytes
	MOVW R6, (R0)
	MOVW R6, BPS(R0)
	MOVW R6, (2*BPS)(R0)
	MOVW R6, (3*BPS)(R0)
	RET

// func tm4asmNEON(dst []byte, off int)
// TrueMotion 4x4: dst[i,j] = clip(left[j] + top[i] - tl).
TEXT ·tm4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVBU -(BPS+1)(R0), R3      // tl
	SUB $BPS, R0, R2
	MOVWU (R2), R4              // 4 top pixels
	VMOV R4, V0.S[0]
	WORD $0x2F08A401            // UXTL V1.8H, V0.8B
	VDUP R3, V3.H8
	VSUB V3.H8, V1.H8, V4.H8    // V4 = top - tl (int16)

	MOVBU -1(R0), R5            // row 0
	VDUP R5, V6.H8
	VADD V4.H8, V6.H8, V1.H8
	WORD $0x2E212820            // SQXTUN V0.8B, V1.8H (clips to [0,255])
	VMOV V0.S[0], R6
	MOVW R6, (R0)

	MOVBU (BPS-1)(R0), R5       // row 1
	VDUP R5, V6.H8
	VADD V4.H8, V6.H8, V1.H8
	WORD $0x2E212820
	VMOV V0.S[0], R6
	MOVW R6, BPS(R0)

	MOVBU (2*BPS-1)(R0), R5     // row 2
	VDUP R5, V6.H8
	VADD V4.H8, V6.H8, V1.H8
	WORD $0x2E212820
	VMOV V0.S[0], R6
	MOVW R6, (2*BPS)(R0)

	MOVBU (3*BPS-1)(R0), R5     // row 3
	VDUP R5, V6.H8
	VADD V4.H8, V6.H8, V1.H8
	WORD $0x2E212820
	VMOV V0.S[0], R6
	MOVW R6, (3*BPS)(R0)
	RET

// func ve4asmNEON(dst []byte, off int)
// Vertical 4x4: one row of avg3 over top[-1..4], replicated 4 times.
TEXT ·ve4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	SUB $(BPS+1), R0, R2
	VLD1 (R2), [V0.B8]          // [tl t0 t1 t2 t3 t4 x x]
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B
	VMOV V4.S[0], R3
	MOVW R3, (R0)
	MOVW R3, BPS(R0)
	MOVW R3, (2*BPS)(R0)
	MOVW R3, (3*BPS)(R0)
	RET

// func he4asmNEON(dst []byte, off int)
// Horizontal 4x4: per-row avg3 over left column, broadcast across the row.
TEXT ·he4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVBU -(BPS+1)(R0), R2      // tl
	MOVBU -1(R0), R3            // l0
	MOVBU (BPS-1)(R0), R4       // l1
	MOVBU (2*BPS-1)(R0), R5     // l2
	MOVBU (3*BPS-1)(R0), R6     // l3
	MOVD $0x01010101, R7

	ADD R4, R2, R8              // avg3(tl, l0, l1)
	ADD R3<<1, R8
	ADD $2, R8
	LSR $2, R8
	MULW R7, R8, R9
	MOVW R9, (R0)

	ADD R5, R3, R8              // avg3(l0, l1, l2)
	ADD R4<<1, R8
	ADD $2, R8
	LSR $2, R8
	MULW R7, R8, R9
	MOVW R9, BPS(R0)

	ADD R6, R4, R8              // avg3(l1, l2, l3)
	ADD R5<<1, R8
	ADD $2, R8
	LSR $2, R8
	MULW R7, R8, R9
	MOVW R9, (2*BPS)(R0)

	ADD R6, R5, R8              // avg3(l2, l3, l3)
	ADD R6<<1, R8
	ADD $2, R8
	LSR $2, R8
	MULW R7, R8, R9
	MOVW R9, (3*BPS)(R0)
	RET

// func ld4asmNEON(dst []byte, off int)
// Down-Left 4x4: avg3 over the 8 top pixels; row j = lanes j..j+3.
TEXT ·ld4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	SUB $BPS, R0, R2
	VLD1 (R2), [V0.B8]          // A..H
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	MOVBU 7(R2), R3             // H
	VMOV R3, V2.B[6]            // lane 6 becomes avg3(G, H, H)
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B
	VMOV V4.D[0], R3
	MOVW R3, (R0)               // row 0 = lanes 0..3
	LSR $8, R3, R4
	MOVW R4, BPS(R0)            // row 1 = lanes 1..4
	LSR $16, R3, R4
	MOVW R4, (2*BPS)(R0)        // row 2 = lanes 2..5
	LSR $24, R3, R4
	MOVW R4, (3*BPS)(R0)        // row 3 = lanes 3..6
	RET

// func rd4asmNEON(dst []byte, off int)
// Down-Right 4x4: avg3 over X = [l3 l2 l1 l0 tl t0 t1 t2] (+t3 in lane 6).
TEXT ·rd4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVBU (3*BPS-1)(R0), R3     // l3
	VMOV R3, V0.B[0]
	MOVBU (2*BPS-1)(R0), R3     // l2
	VMOV R3, V0.B[1]
	MOVBU (BPS-1)(R0), R3       // l1
	VMOV R3, V0.B[2]
	MOVBU -1(R0), R3            // l0
	VMOV R3, V0.B[3]
	MOVWU -(BPS+1)(R0), R3      // [tl t0 t1 t2]
	VMOV R3, V0.S[1]
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	MOVBU (3-BPS)(R0), R3       // t3
	VMOV R3, V2.B[6]            // lane 6 becomes avg3(t1, t2, t3)
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B
	VMOV V4.D[0], R3
	MOVW R3, (3*BPS)(R0)        // row 3 = lanes 0..3
	LSR $8, R3, R4
	MOVW R4, (2*BPS)(R0)        // row 2 = lanes 1..4
	LSR $16, R3, R4
	MOVW R4, BPS(R0)            // row 1 = lanes 2..5
	LSR $24, R3, R4
	MOVW R4, (R0)               // row 0 = lanes 3..6
	RET

// func vr4asmNEON(dst []byte, off int)
// Vertical-Right 4x4 over X = [l2 l1 l0 tl t0 t1 t2 t3].
TEXT ·vr4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVBU (2*BPS-1)(R0), R3     // l2
	VMOV R3, V0.B[0]
	MOVBU (BPS-1)(R0), R3       // l1
	VMOV R3, V0.B[1]
	MOVBU -1(R0), R3            // l0
	VMOV R3, V0.B[2]
	MOVBU -(BPS+1)(R0), R3      // tl
	VMOV R3, V0.B[3]
	MOVWU -BPS(R0), R3          // [t0 t1 t2 t3]
	VMOV R3, V0.S[1]
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	WORD $0x2E211405            // URHADD V5.8B, V0.8B, V1.8B (avg2)
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B (avg3)
	VMOV V5.D[0], R3            // avg2 lanes
	VMOV V4.D[0], R4            // avg3 lanes
	LSR $24, R3, R5
	MOVW R5, (R0)               // row 0 = avg2 lanes 3..6
	LSR $16, R4, R5
	MOVW R5, BPS(R0)            // row 1 = avg3 lanes 2..5
	LSR $8, R4, R5              // row 2 = [avg3 lane1, avg2 lanes 3..5]
	AND $0xff, R5
	LSR $16, R3, R6
	AND $0xffffff00, R6
	ORR R6, R5
	MOVW R5, (2*BPS)(R0)
	AND $0xff, R4, R5           // row 3 = [avg3 lane0, avg3 lanes 2..4]
	LSR $8, R4, R6
	AND $0xffffff00, R6
	ORR R6, R5
	MOVW R5, (3*BPS)(R0)
	RET

// func vl4asmNEON(dst []byte, off int)
// Vertical-Left 4x4: avg2/avg3 over the 8 top pixels A..H.
TEXT ·vl4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	SUB $BPS, R0, R2
	VLD1 (R2), [V0.B8]          // A..H
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	WORD $0x2E211405            // URHADD V5.8B, V0.8B, V1.8B (avg2)
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B (avg3)
	VMOV V5.D[0], R3
	VMOV V4.D[0], R4
	MOVW R3, (R0)               // row 0 = avg2 lanes 0..3
	MOVW R4, BPS(R0)            // row 1 = avg3 lanes 0..3
	LSR $8, R3, R5              // row 2 = [avg2 lanes 1..3, avg3 lane 4]
	AND $0xffffff, R5
	LSR $8, R4, R6
	AND $0xff000000, R6
	ORR R6, R5
	MOVW R5, (2*BPS)(R0)
	LSR $8, R4, R5              // row 3 = [avg3 lanes 1..3, avg3 lane 5]
	AND $0xffffff, R5
	LSR $16, R4, R6
	AND $0xff000000, R6
	ORR R6, R5
	MOVW R5, (3*BPS)(R0)
	RET

// func hd4asmNEON(dst []byte, off int)
// Horizontal-Down 4x4 over X = [l3 l2 l1 l0 tl t0 t1 t2], zip(avg2, avg3).
TEXT ·hd4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVBU (3*BPS-1)(R0), R3     // l3
	VMOV R3, V0.B[0]
	MOVBU (2*BPS-1)(R0), R3     // l2
	VMOV R3, V0.B[1]
	MOVBU (BPS-1)(R0), R3       // l1
	VMOV R3, V0.B[2]
	MOVBU -1(R0), R3            // l0
	VMOV R3, V0.B[3]
	MOVWU -(BPS+1)(R0), R3      // [tl t0 t1 t2]
	VMOV R3, V0.S[1]
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	WORD $0x2E211405            // URHADD V5.8B, V0.8B, V1.8B (avg2)
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B (avg3)
	VZIP1 V4.B8, V5.B8, V6.B8   // [a2_0 a3_0 a2_1 a3_1 a2_2 a3_2 a2_3 a3_3]
	VMOV V6.D[0], R3
	VMOV V4.D[0], R4
	MOVW R3, (3*BPS)(R0)        // row 3 = zip lanes 0..3
	LSR $16, R3, R5
	MOVW R5, (2*BPS)(R0)        // row 2 = zip lanes 2..5
	LSR $32, R3, R5
	MOVW R5, BPS(R0)            // row 1 = zip lanes 4..7
	LSR $48, R3, R5             // row 0 = [zip lanes 6..7, avg3 lanes 4..5]
	LSR $16, R4, R6
	AND $0xffff0000, R6
	ORR R6, R5
	MOVW R5, (R0)
	RET

// func hu4asmNEON(dst []byte, off int)
// Horizontal-Up 4x4 over X = [l0 l1 l2 l3 l3 l3 l3 l3], zip(avg2, avg3).
TEXT ·hu4asmNEON(SB), NOSPLIT, $0-32
	MOVD dst_base+0(FP), R0
	MOVD off+24(FP), R1
	ADD R1, R0
	MOVBU (3*BPS-1)(R0), R3     // l3
	VDUP R3, V0.B8
	MOVBU -1(R0), R4            // l0
	VMOV R4, V0.B[0]
	MOVBU (BPS-1)(R0), R4       // l1
	VMOV R4, V0.B[1]
	MOVBU (2*BPS-1)(R0), R4     // l2
	VMOV R4, V0.B[2]
	VEXT $1, V0.B8, V0.B8, V1.B8
	VEXT $2, V0.B8, V0.B8, V2.B8
	WORD $0x2E211405            // URHADD V5.8B, V0.8B, V1.8B (avg2)
	WORD $0x2E220403            // UHADD  V3.8B, V0.8B, V2.8B
	WORD $0x2E211464            // URHADD V4.8B, V3.8B, V1.8B (avg3)
	VZIP1 V4.B8, V5.B8, V6.B8   // [a2_0 a3_0 a2_1 a3_1 a2_2 a3_2 l3 l3]
	VMOV V6.D[0], R4
	MOVW R4, (R0)               // row 0 = zip lanes 0..3
	LSR $16, R4, R5
	MOVW R5, BPS(R0)            // row 1 = zip lanes 2..5
	LSR $32, R4, R5
	MOVW R5, (2*BPS)(R0)        // row 2 = zip lanes 4..7
	MOVD $0x01010101, R5
	MULW R5, R3, R6
	MOVW R6, (3*BPS)(R0)        // row 3 = [l3 l3 l3 l3]
	RET
