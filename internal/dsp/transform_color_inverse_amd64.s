#include "textflag.h"

// SSE2 inverse cross-color transform (see transform_color_inverse.go).
// Modeled on TransformColorInverse_SSE2 from libwebp (src/dsp/lossless_sse2.c).
//
// Pixels are ARGB words, little-endian bytes [B, G, R, A], i.e. 16-bit
// lanes [G:B, A:R]. The per-channel delta (m * int8(v)) >> 5 is computed
// with PMULHW on 16-bit lanes: with v pre-positioned as v<<8 (= int8(v)*256)
// and the multiplier pre-scaled to int8(m)*8 by the Go wrapper,
//   PMULHW = (v*256 * m*8) >> 16 = floor(int8(v)*int8(m) / 32)
// which matches the scalar arithmetic shift exactly. Only the low byte of
// each delta is meaningful (the scalar code masks with 0xff); the byte-wise
// add puts it on the right channel and the polluted alpha/green bytes are
// discarded by the final shift/mask sequence:
//   E = in + D (bytes)            B', R' in bytes 0 and 2
//   F = E << 8 per word           [0, B', 0, R']
//   G = PMULHW(F, multsB2)        [0, dB2] words
//   H = G >> 8 per dword          dB2 in bytes 1..2
//   I = F + H (bytes)             byte 1 = B' + dB2 = B''
//   J = I >> 8 per word           [B'', 0, R', 0]
//   out = J | (in & 0xff00ff00)   restore original A, G
//
// Register roles: X6 = multsRB (lanes [g2b*8, g2r*8] per pixel),
// X7 = multsB2 (lanes [0, r2b*8]), X5 = 0xff00ff00 mask.

// func transformColorInverseSSE2(multsRB, multsB2 uint32, src, dst []uint32, n int)
TEXT ·transformColorInverseSSE2(SB), NOSPLIT, $0-64
	MOVL   multsRB+0(FP), AX
	MOVL   multsB2+4(FP), BX
	MOVQ   src_base+8(FP), SI
	MOVQ   dst_base+32(FP), DI
	MOVQ   n+56(FP), CX
	MOVD   AX, X6
	PSHUFD $0x00, X6, X6
	MOVD   BX, X7
	PSHUFD $0x00, X7, X7
	MOVL   $0xff00ff00, AX
	MOVD   AX, X5
	PSHUFD $0x00, X5, X5
	MOVQ   CX, BX
	SHRQ   $2, BX
	JZ     tci_tail

tci_loop4:
	MOVOU   (SI), X0
	MOVO    X0, X1
	PAND    X5, X1              // A = in & ff00ff00: lanes [G<<8, A<<8]
	PSHUFLW $0xa0, X1, X2
	PSHUFHW $0xa0, X2, X2       // C = [G<<8, G<<8] per pixel
	PMULHW  X6, X2              // D = [dB, dR]
	PADDB   X0, X2              // E: B += dB, R += dR (G/A polluted)
	MOVO    X2, X3
	PSLLW   $8, X3              // F = [B'<<8, R'<<8]
	MOVO    X3, X4
	PMULHW  X7, X4              // G = [0, dB2]
	PSRLL   $8, X4              // H: dB2 moved to bytes 1..2
	PADDB   X4, X3              // I: byte 1 = B'' = B' + dB2
	PSRLW   $8, X3              // J = [B'', 0, R', 0]
	POR     X1, X3              // restore original A, G
	MOVOU   X3, (DI)
	ADDQ    $16, SI
	ADDQ    $16, DI
	DECQ    BX
	JNZ     tci_loop4

tci_tail:
	ANDQ $3, CX
	JZ   tci_done

tci_tail1:
	MOVSS   (SI), X0
	ADDQ    $4, SI
	MOVO    X0, X1
	PAND    X5, X1
	PSHUFLW $0xa0, X1, X2
	PMULHW  X6, X2
	PADDB   X0, X2
	MOVO    X2, X3
	PSLLW   $8, X3
	MOVO    X3, X4
	PMULHW  X7, X4
	PSRLL   $8, X4
	PADDB   X4, X3
	PSRLW   $8, X3
	POR     X1, X3
	MOVSS   X3, (DI)
	ADDQ    $4, DI
	DECQ    CX
	JNZ     tci_tail1

tci_done:
	RET
