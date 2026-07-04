#include "textflag.h"

// SSE2 ARGB -> RGBA byte conversion (decoder output path). Modeled on
// ConvertBGRAToRGBA_SSE2 from libwebp (src/dsp/lossless_sse2.c), which
// stays in pure SSE2 (no PSHUFB) by swapping R and B via masks and word
// shuffles.
//
// VP8L pixels are ARGB uint32 words, i.e. little-endian bytes [B, G, R, A].
// The NRGBA output wants [R, G, B, A]: a byte 0<->2 swap within each 32-bit
// word. With mask = 0x00ff00ff:
//   rb = in & mask                 [B, 0, R, 0]
//   rb = swap 16-bit words/dword   [R, 0, B, 0]   (PSHUFLW/PSHUFHW 0xb1)
//   ga = in &^ mask                [0, G, 0, A]
//   out = rb | ga                  [R, G, B, A]
//
// Register roles: X4 = 0x00ff00ff mask.

// func convertARGBToRGBASSE2(src []uint32, dst []byte, n int)
TEXT ·convertARGBToRGBASSE2(SB), NOSPLIT, $0-56
	MOVQ   src_base+0(FP), SI
	MOVQ   dst_base+24(FP), DI
	MOVQ   n+48(FP), CX
	MOVL   $0x00ff00ff, AX
	MOVD   AX, X4
	PSHUFD $0x00, X4, X4
	MOVQ   CX, BX
	SHRQ   $3, BX               // 8 pixels per iteration
	JZ     ca_quad

ca_loop8:
	MOVOU   (SI), X0
	MOVOU   16(SI), X1
	MOVO    X4, X2
	PANDN   X0, X2              // [0, G, 0, A]
	PAND    X4, X0              // [B, 0, R, 0]
	PSHUFLW $0xb1, X0, X0
	PSHUFHW $0xb1, X0, X0       // [R, 0, B, 0]
	POR     X2, X0
	MOVO    X4, X3
	PANDN   X1, X3
	PAND    X4, X1
	PSHUFLW $0xb1, X1, X1
	PSHUFHW $0xb1, X1, X1
	POR     X3, X1
	MOVOU   X0, (DI)
	MOVOU   X1, 16(DI)
	ADDQ    $32, SI
	ADDQ    $32, DI
	DECQ    BX
	JNZ     ca_loop8

ca_quad:
	TESTQ   $4, CX
	JZ      ca_tail
	MOVOU   (SI), X0
	MOVO    X4, X2
	PANDN   X0, X2
	PAND    X4, X0
	PSHUFLW $0xb1, X0, X0
	PSHUFHW $0xb1, X0, X0
	POR     X2, X0
	MOVOU   X0, (DI)
	ADDQ    $16, SI
	ADDQ    $16, DI

ca_tail:
	ANDQ $3, CX
	JZ   ca_done

ca_tail1:
	MOVSS   (SI), X0
	MOVO    X4, X2
	PANDN   X0, X2
	PAND    X4, X0
	PSHUFLW $0xb1, X0, X0
	POR     X2, X0
	MOVSS   X0, (DI)
	ADDQ    $4, SI
	ADDQ    $4, DI
	DECQ    CX
	JNZ     ca_tail1

ca_done:
	RET
