#include "textflag.h"

// VP8 YUV→NRGBA batch converter — ARM64 NEON assembly.
//
// Converts N pixels from a Y byte array + packed UV uint32 array into
// interleaved NRGBA output (R, G, B, 255 per pixel). Processes 8 pixels
// per iteration using 32-bit lane arithmetic for exact fixed-point math.
//
// The packedUV input uses the loadUV format: u in bits [7:0], v in bits
// [23:16] of each uint32.
//
// Conversion formulas (matching yuv.go constants, bit-exact):
//   multHi(v, c) = (v * c) >> 8
//   R = clip((multHi(y,19077) + multHi(v,26149) - 14234) >> 6, 0, 255)
//   G = clip((multHi(y,19077) - multHi(u,6419) - multHi(v,13320) + 8708) >> 6, 0, 255)
//   B = clip((multHi(y,19077) + multHi(u,33050) - 17685) >> 6, 0, 255)
//
// The final ">> 6 then clip to [0,255]" is implemented with an arithmetic
// shift followed by saturating narrowing (SQXTN int32→int16, then SQXTUN
// int16→uint8), which is exactly equivalent to the Go vp8kClip table path.
//
// Several instructions are WORD-encoded because the Go assembler has no
// mnemonic for them (MUL.4S, SSHR, SQXTN, SQXTUN).

// func yuvPackedToNRGBABatchNEON(y []byte, packedUV []uint32, dst []byte, width int)
// width must be a multiple of 8.
//
// Register allocation:
//   R0 = Y pointer, R1 = packed UV pointer, R2 = dst pointer, R3 = loop count
//   V24 = kYScale, V25 = kRCr, V26 = kGCb, V27 = kGCr, V28 = kBCb (dup .4S)
//   V29 = kRBias, V30 = kGBias, V31 = kBBias (dup .4S)
//   V23 = 0xFF dword mask, V22 = alpha bytes (0xFF)
//   V0 = Y bytes, V1/V2 = yScaled lo/hi, V4/V5 = packed UV lo/hi
//   V6/V16 = U lo/hi, V7/V17 = V lo/hi
//   V8..V15 = R/G/B accumulators, V18..V21 = narrowed bytes / interleave temps
TEXT ·yuvPackedToNRGBABatchNEON(SB), NOSPLIT, $0-80
	MOVD y_base+0(FP), R0
	MOVD packedUV_base+24(FP), R1
	MOVD dst_base+48(FP), R2
	MOVD width+72(FP), R3

	LSR  $3, R3, R3        // iterations = width / 8
	CBZ  R3, done

	// Broadcast fixed-point coefficients and biases.
	MOVD $19077, R4
	VDUP R4, V24.S4
	MOVD $26149, R4
	VDUP R4, V25.S4
	MOVD $6419, R4
	VDUP R4, V26.S4
	MOVD $13320, R4
	VDUP R4, V27.S4
	MOVD $33050, R4
	VDUP R4, V28.S4
	MOVD $14234, R4
	VDUP R4, V29.S4
	MOVD $8708, R4
	VDUP R4, V30.S4
	MOVD $17685, R4
	VDUP R4, V31.S4
	MOVD $255, R4
	VDUP R4, V23.S4        // 0x000000FF dword mask
	VMOVI $255, V22.B16    // alpha = 255

loop8:
	// Load 8 Y bytes and widen to 2 x 4 uint32 lanes.
	VLD1.P 8(R0), [V0.B8]
	VUSHLL $0, V0.B8, V0.H8   // uxtl: bytes → uint16
	VUSHLL $0, V0.H4, V1.S4   // y lo 4 → uint32
	VUSHLL2 $0, V0.H8, V2.S4  // y hi 4 → uint32

	// yScaled = (y * kYScale) >> 8
	WORD $0x4eb89c21          // MUL V1.4S, V1.4S, V24.4S
	WORD $0x4eb89c42          // MUL V2.4S, V2.4S, V24.4S
	VUSHR $8, V1.S4, V1.S4
	VUSHR $8, V2.S4, V2.S4

	// Load 8 packed UV dwords; extract U (bits 7:0) and V (bits 23:16).
	VLD1.P 32(R1), [V4.B16, V5.B16]
	VAND  V23.B16, V4.B16, V6.B16   // U lo
	VUSHR $16, V4.S4, V7.S4
	VAND  V23.B16, V7.B16, V7.B16   // V lo
	VAND  V23.B16, V5.B16, V16.B16  // U hi
	VUSHR $16, V5.S4, V17.S4
	VAND  V23.B16, V17.B16, V17.B16 // V hi

	// === R = (yScaled + (v*kRCr)>>8 - kRBias) >> 6 ===
	WORD $0x4eb99ce8          // MUL V8.4S, V7.4S, V25.4S
	WORD $0x4eb99e29          // MUL V9.4S, V17.4S, V25.4S
	VUSHR $8, V8.S4, V8.S4
	VUSHR $8, V9.S4, V9.S4
	VADD  V1.S4, V8.S4, V8.S4
	VADD  V2.S4, V9.S4, V9.S4
	VSUB  V29.S4, V8.S4, V8.S4
	VSUB  V29.S4, V9.S4, V9.S4
	WORD $0x4f3a0508          // SSHR V8.4S, V8.4S, #6
	WORD $0x4f3a0529          // SSHR V9.4S, V9.4S, #6

	// === G = (yScaled - (u*kGCb)>>8 - (v*kGCr)>>8 + kGBias) >> 6 ===
	WORD $0x4eba9cca          // MUL V10.4S, V6.4S, V26.4S
	WORD $0x4ebb9ceb          // MUL V11.4S, V7.4S, V27.4S
	WORD $0x4eba9e0c          // MUL V12.4S, V16.4S, V26.4S
	WORD $0x4ebb9e2d          // MUL V13.4S, V17.4S, V27.4S
	VUSHR $8, V10.S4, V10.S4
	VUSHR $8, V11.S4, V11.S4
	VUSHR $8, V12.S4, V12.S4
	VUSHR $8, V13.S4, V13.S4
	VSUB  V10.S4, V1.S4, V10.S4     // yScaled - (u*kGCb)>>8
	VSUB  V11.S4, V10.S4, V10.S4    // - (v*kGCr)>>8
	VADD  V30.S4, V10.S4, V10.S4    // + kGBias
	VSUB  V12.S4, V2.S4, V12.S4
	VSUB  V13.S4, V12.S4, V12.S4
	VADD  V30.S4, V12.S4, V12.S4
	WORD $0x4f3a054a          // SSHR V10.4S, V10.4S, #6
	WORD $0x4f3a058c          // SSHR V12.4S, V12.4S, #6

	// === B = (yScaled + (u*kBCb)>>8 - kBBias) >> 6 ===
	WORD $0x4ebc9cce          // MUL V14.4S, V6.4S, V28.4S
	WORD $0x4ebc9e0f          // MUL V15.4S, V16.4S, V28.4S
	VUSHR $8, V14.S4, V14.S4
	VUSHR $8, V15.S4, V15.S4
	VADD  V1.S4, V14.S4, V14.S4
	VADD  V2.S4, V15.S4, V15.S4
	VSUB  V31.S4, V14.S4, V14.S4
	VSUB  V31.S4, V15.S4, V15.S4
	WORD $0x4f3a05ce          // SSHR V14.4S, V14.4S, #6
	WORD $0x4f3a05ef          // SSHR V15.4S, V15.4S, #6

	// Narrow int32 → int16 (signed sat) → uint8 (unsigned sat).
	WORD $0x0e614912          // SQXTN  V18.4H, V8.4S   (R lo)
	WORD $0x4e614932          // SQXTN2 V18.8H, V9.4S   (R hi)
	WORD $0x0e614953          // SQXTN  V19.4H, V10.4S  (G lo)
	WORD $0x4e614993          // SQXTN2 V19.8H, V12.4S  (G hi)
	WORD $0x0e6149d4          // SQXTN  V20.4H, V14.4S  (B lo)
	WORD $0x4e6149f4          // SQXTN2 V20.8H, V15.4S  (B hi)
	WORD $0x2e212a52          // SQXTUN V18.8B, V18.8H  (R bytes)
	WORD $0x2e212a73          // SQXTUN V19.8B, V19.8H  (G bytes)
	WORD $0x2e212a94          // SQXTUN V20.8B, V20.8H  (B bytes)

	// Interleave R,G,B,A → NRGBA. rg = [r0,g0,...], ba = [b0,255,...],
	// then zip 16-bit pairs into two 16-byte pixel groups.
	VZIP1 V19.B16, V18.B16, V21.B16 // V21 = zip1(R, G)
	VZIP1 V22.B16, V20.B16, V0.B16  // V0 = zip1(B, A)
	VZIP1 V0.H8, V21.H8, V16.H8     // pixels 0-3
	VZIP2 V0.H8, V21.H8, V17.H8     // pixels 4-7
	VST1.P [V16.B16, V17.B16], 32(R2)

	SUBS $1, R3, R3
	BNE  loop8

done:
	RET
