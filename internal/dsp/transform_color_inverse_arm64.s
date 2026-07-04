#include "textflag.h"

// NEON inverse cross-color transform (see transform_color_inverse.go).
// Modeled on TransformColorInverse_NEON/_SSE2 from libwebp.
//
// Pixels are ARGB words, little-endian bytes [B, G, R, A], i.e. 16-bit
// lanes [G:B, A:R]. The per-channel delta (m * int8(v)) >> 5 is computed
// with SQDMULH on 16-bit lanes: with v pre-positioned as v<<8 (= int8(v)*256)
// and the multiplier pre-scaled to int8(m)*4 by the Go wrapper,
//   SQDMULH = (2 * v*256 * m*4) >> 16 = floor(int8(v)*int8(m) / 32)
// which matches the scalar arithmetic shift exactly (no saturation is
// possible since |m*4| <= 512). Only the low byte of each delta is
// meaningful (the scalar code masks with 0xff); byte-wise adds put it on
// the right channel and the polluted alpha/green bytes are restored from
// the source at the end.
//
// The Go assembler lacks SQDMULH; WORD encoding (verified against clang):
//   SQDMULH Vd.8H, Vn.8H, Vm.8H = 0x4E60B400 | m<<16 | n<<5 | d
//
// Register roles: V6 = multsRB (lanes [g2b*4, g2r*4] per pixel),
// V7 = multsB2 (lanes [0, r2b*4]), V16 = 0xff00ff00, V17 = 0x00ff00ff.

// func transformColorInverseNEON(multsRB, multsB2 uint32, src, dst []uint32, n int)
TEXT ·transformColorInverseNEON(SB), NOSPLIT, $0-64
	MOVWU multsRB+0(FP), R4
	MOVWU multsB2+4(FP), R5
	MOVD  src_base+8(FP), R0
	MOVD  dst_base+32(FP), R1
	MOVD  n+56(FP), R3
	VDUP  R4, V6.S4
	VDUP  R5, V7.S4
	MOVD  $0xff00ff00, R6
	VDUP  R6, V16.S4
	MOVD  $0x00ff00ff, R6
	VDUP  R6, V17.S4
	LSR   $2, R3, R7
	CBZ   R7, tci_tail

tci_loop4:
	VLD1.P 16(R0), [V0.B16]
	VAND   V16.B16, V0.B16, V1.B16 // A = in & ff00ff00: lanes [G<<8, A<<8]
	VTRN1  V1.H8, V1.H8, V2.H8     // C = [G<<8, G<<8] per pixel
	WORD   $0x4E66B442             // SQDMULH V2.8H, V2.8H, V6.8H  [dB, dR]
	VADD   V2.B16, V0.B16, V2.B16  // E: B += dB, R += dR (G/A polluted)
	VSHL   $8, V2.H8, V3.H8        // F = [B'<<8, R'<<8]
	WORD   $0x4E67B463             // SQDMULH V3.8H, V3.8H, V7.8H  [0, dB2]
	VUSHR  $16, V3.S4, V3.S4       // dB2 moved to the blue lane
	VADD   V3.B16, V2.B16, V2.B16  // B'' = B' + dB2
	VAND   V17.B16, V2.B16, V2.B16 // keep computed R, B
	VORR   V1.B16, V2.B16, V2.B16  // restore original A, G
	VST1.P [V2.B16], 16(R1)
	SUBS   $1, R7
	BNE    tci_loop4

tci_tail:
	ANDS $3, R3, R7
	BEQ  tci_done

tci_tail1:
	FMOVS (R0), F0
	ADD   $4, R0
	VAND  V16.B16, V0.B16, V1.B16
	VTRN1 V1.H8, V1.H8, V2.H8
	WORD  $0x4E66B442              // SQDMULH V2.8H, V2.8H, V6.8H
	VADD  V2.B16, V0.B16, V2.B16
	VSHL  $8, V2.H8, V3.H8
	WORD  $0x4E67B463              // SQDMULH V3.8H, V3.8H, V7.8H
	VUSHR $16, V3.S4, V3.S4
	VADD  V3.B16, V2.B16, V2.B16
	VAND  V17.B16, V2.B16, V2.B16
	VORR  V1.B16, V2.B16, V2.B16
	FMOVS F2, (R1)
	ADD   $4, R1
	SUBS  $1, R7
	BNE   tci_tail1

tci_done:
	RET
