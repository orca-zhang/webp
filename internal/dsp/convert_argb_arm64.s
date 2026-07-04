#include "textflag.h"

// NEON ARGB -> RGBA byte conversion (decoder output path).
//
// VP8L pixels are ARGB uint32 words, i.e. little-endian bytes [B, G, R, A].
// The NRGBA output wants [R, G, B, A]: a byte 0<->2 swap within each 32-bit
// word, done with a single TBL shuffle per 16 bytes (4 pixels).

// Shuffle indices: per pixel [2, 1, 0, 3].
DATA shufARGB2RGBA<>+0(SB)/8, $0x0704050603000102
DATA shufARGB2RGBA<>+8(SB)/8, $0x0F0C0D0E0B08090A
GLOBL shufARGB2RGBA<>(SB), RODATA|NOPTR, $16

// func convertARGBToRGBANEON(src []uint32, dst []byte, n int)
TEXT ·convertARGBToRGBANEON(SB), NOSPLIT, $0-56
	MOVD src_base+0(FP), R0
	MOVD dst_base+24(FP), R1
	MOVD n+48(FP), R3
	MOVD $shufARGB2RGBA<>(SB), R4
	VLD1 (R4), [V4.B16]
	LSR  $3, R3, R5             // 8 pixels per iteration
	CBZ  R5, ca_quad

ca_loop8:
	VLD1.P 32(R0), [V0.B16, V1.B16]
	VTBL   V4.B16, [V0.B16], V2.B16
	VTBL   V4.B16, [V1.B16], V3.B16
	VST1.P [V2.B16, V3.B16], 32(R1)
	SUBS   $1, R5
	BNE    ca_loop8

ca_quad:
	TSTW $4, R3
	BEQ  ca_tail
	VLD1.P 16(R0), [V0.B16]
	VTBL   V4.B16, [V0.B16], V2.B16
	VST1.P [V2.B16], 16(R1)

ca_tail:
	ANDS $3, R3, R5
	BEQ  ca_done

ca_tail1:
	FMOVS (R0), F0
	ADD   $4, R0
	VTBL  V4.B16, [V0.B16], V2.B16
	FMOVS F2, (R1)
	ADD   $4, R1
	SUBS  $1, R5
	BNE   ca_tail1

ca_done:
	RET
