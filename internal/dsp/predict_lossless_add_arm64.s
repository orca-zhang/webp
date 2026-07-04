#include "textflag.h"

// VP8L inverse spatial predictors, NEON (see predict_lossless_add.go for the
// slice conventions). Modeled on VP8LPredictorsAdd_NEON from libwebp
// (src/dsp/lossless_neon.c).
//
// All functions share the func(in, upper, out []uint32, n int) signature:
//   in_base+0(FP), upper_base+24(FP), out_base+48(FP), n+72(FP)
//
// Register roles: R0 = &in[0], R1 = &upper[0] (TL of current pixel),
// R2 = &out[1] (result cursor; out[0] is the initial left neighbor),
// R3 = remaining count, R5 = loop counter.
//
// Modes without a left dependency (0, 1, 2, 3, 4, 8, 9) process 4 pixels per
// iteration (mode 1 uses the byte prefix-sum trick: mod-256 addition is
// associative per channel). Modes that depend on the just-decoded left pixel
// (5, 6, 7, 10, 11, 12, 13) run pixel-at-a-time but keep all channel math in
// NEON registers, branch-free.
//
// Single pixels are loaded with FMOVS, which zeroes the upper 96 bits of the
// vector register; 64-bit vector ops zero the upper half. Every intermediate
// therefore has zeroes above byte 3, which mode 11 relies on (UADDLV sums all
// 8 bytes of the low half).
//
// The Go assembler lacks several byte-wise mnemonics; WORD encodings are used
// (verified against clang -arch arm64):
//   UHADD  Vd.8B,  Vn.8B,  Vm.8B  = 0x2E200400 | m<<16 | n<<5 | d
//   UHADD  Vd.16B, Vn.16B, Vm.16B = 0x6E200400 | m<<16 | n<<5 | d
//   UHSUB  Vd.8B,  Vn.8B,  Vm.8B  = 0x2E202400 | m<<16 | n<<5 | d
//   UQADD  Vd.8B,  Vn.8B,  Vm.8B  = 0x2E200C00 | m<<16 | n<<5 | d
//   UQSUB  Vd.8B,  Vn.8B,  Vm.8B  = 0x2E202C00 | m<<16 | n<<5 | d
//   UABD   Vd.8B,  Vn.8B,  Vm.8B  = 0x2E207400 | m<<16 | n<<5 | d
//   CMHI   Vd.8B,  Vn.8B,  Vm.8B  = 0x2E203400 | m<<16 | n<<5 | d
//   CMHS   Dd, Dn, Dm             = 0x7EE03C00 | m<<16 | n<<5 | d
//   SQXTUN Vd.8B,  Vn.8H          = 0x2E212800 | n<<5 | d
//   SXTL   Vd.8H,  Vn.8B          = 0x0F08A400 | n<<5 | d (SSHLL #0)

// func predictorAdd0NEON(in, upper, out []uint32, n int)
// Predictor 0: pred = ARGB black (0xff000000).
TEXT ·predictorAdd0NEON(SB), NOSPLIT, $0-80
	MOVD in_base+0(FP), R0
	MOVD out_base+48(FP), R2
	MOVD n+72(FP), R3
	ADD  $4, R2                 // results start at out[1]
	MOVD $0xff000000, R4
	VDUP R4, V4.S4
	LSR  $2, R3, R5
	CBZ  R5, pa0_tail

pa0_loop4:
	VLD1.P 16(R0), [V0.B16]
	VADD   V4.B16, V0.B16, V0.B16
	VST1.P [V0.B16], 16(R2)
	SUBS   $1, R5
	BNE    pa0_loop4

pa0_tail:
	ANDS $3, R3, R5
	BEQ  pa0_done

pa0_tail1:
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V4.B8, V0.B8, V0.B8
	FMOVS F0, (R2)
	ADD   $4, R2
	SUBS  $1, R5
	BNE   pa0_tail1

pa0_done:
	RET

// func predictorAdd1NEON(in, upper, out []uint32, n int)
// Predictor 1: pred = left. out[i] = out[i-1] + in[i] per channel mod 256,
// vectorized with a byte prefix sum: E = prefix(in[0..3]), out = E + L.
TEXT ·predictorAdd1NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L (left neighbor)
	ADD   $4, R2
	VDUP  V5.S[0], V5.S4
	VEOR  V6.B16, V6.B16, V6.B16
	LSR   $2, R3, R5
	CBZ   R5, pa1_tail

pa1_loop4:
	VLD1.P 16(R0), [V0.B16]           // A = [i0 i1 i2 i3]
	VEXT   $12, V0.B16, V6.B16, V1.B16 // B = A << 1 pixel = [0 i0 i1 i2]
	VADD   V1.B16, V0.B16, V0.B16     // C = A + B
	VEXT   $8, V0.B16, V6.B16, V1.B16 // D = C << 2 pixels
	VADD   V1.B16, V0.B16, V0.B16     // E = C + D = prefix sums
	VADD   V5.B16, V0.B16, V0.B16     // + L in every lane
	VST1.P [V0.B16], 16(R2)
	VDUP   V0.S[3], V5.S4             // L = last decoded pixel
	SUBS   $1, R5
	BNE    pa1_loop4

pa1_tail:
	ANDS $3, R3, R5
	BEQ  pa1_done

pa1_tail1:
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V5.B8, V0.B8, V0.B8
	FMOVS F0, (R2)
	ADD   $4, R2
	VDUP  V0.S[0], V5.S4
	SUBS  $1, R5
	BNE   pa1_tail1

pa1_done:
	RET

// func predictorAdd2NEON(in, upper, out []uint32, n int)
// Predictor 2: pred = T (upper[i+1]).
TEXT ·predictorAdd2NEON(SB), NOSPLIT, $0-80
	MOVD in_base+0(FP), R0
	MOVD upper_base+24(FP), R1
	MOVD out_base+48(FP), R2
	MOVD n+72(FP), R3
	ADD  $4, R1                 // R1 = &T of pixel 0
	ADD  $4, R2
	LSR  $2, R3, R5
	CBZ  R5, pa2_tail

pa2_loop4:
	VLD1.P 16(R0), [V0.B16]
	VLD1.P 16(R1), [V1.B16]
	VADD   V1.B16, V0.B16, V0.B16
	VST1.P [V0.B16], 16(R2)
	SUBS   $1, R5
	BNE    pa2_loop4

pa2_tail:
	ANDS $3, R3, R5
	BEQ  pa2_done

pa2_tail1:
	FMOVS (R0), F0
	FMOVS (R1), F1
	ADD   $4, R0
	ADD   $4, R1
	VADD  V1.B8, V0.B8, V0.B8
	FMOVS F0, (R2)
	ADD   $4, R2
	SUBS  $1, R5
	BNE   pa2_tail1

pa2_done:
	RET

// func predictorAdd3NEON(in, upper, out []uint32, n int)
// Predictor 3: pred = TR (upper[i+2]). Callers exclude the last pixel of the
// row (its TR wraps to out[0]) and size upper accordingly.
TEXT ·predictorAdd3NEON(SB), NOSPLIT, $0-80
	MOVD in_base+0(FP), R0
	MOVD upper_base+24(FP), R1
	MOVD out_base+48(FP), R2
	MOVD n+72(FP), R3
	ADD  $8, R1                 // R1 = &TR of pixel 0
	ADD  $4, R2
	LSR  $2, R3, R5
	CBZ  R5, pa3_tail

pa3_loop4:
	VLD1.P 16(R0), [V0.B16]
	VLD1.P 16(R1), [V1.B16]
	VADD   V1.B16, V0.B16, V0.B16
	VST1.P [V0.B16], 16(R2)
	SUBS   $1, R5
	BNE    pa3_loop4

pa3_tail:
	ANDS $3, R3, R5
	BEQ  pa3_done

pa3_tail1:
	FMOVS (R0), F0
	FMOVS (R1), F1
	ADD   $4, R0
	ADD   $4, R1
	VADD  V1.B8, V0.B8, V0.B8
	FMOVS F0, (R2)
	ADD   $4, R2
	SUBS  $1, R5
	BNE   pa3_tail1

pa3_done:
	RET

// func predictorAdd4NEON(in, upper, out []uint32, n int)
// Predictor 4: pred = TL (upper[i]).
TEXT ·predictorAdd4NEON(SB), NOSPLIT, $0-80
	MOVD in_base+0(FP), R0
	MOVD upper_base+24(FP), R1  // R1 = &TL of pixel 0
	MOVD out_base+48(FP), R2
	MOVD n+72(FP), R3
	ADD  $4, R2
	LSR  $2, R3, R5
	CBZ  R5, pa4_tail

pa4_loop4:
	VLD1.P 16(R0), [V0.B16]
	VLD1.P 16(R1), [V1.B16]
	VADD   V1.B16, V0.B16, V0.B16
	VST1.P [V0.B16], 16(R2)
	SUBS   $1, R5
	BNE    pa4_loop4

pa4_tail:
	ANDS $3, R3, R5
	BEQ  pa4_done

pa4_tail1:
	FMOVS (R0), F0
	FMOVS (R1), F1
	ADD   $4, R0
	ADD   $4, R1
	VADD  V1.B8, V0.B8, V0.B8
	FMOVS F0, (R2)
	ADD   $4, R2
	SUBS  $1, R5
	BNE   pa4_tail1

pa4_done:
	RET

// func predictorAdd5NEON(in, upper, out []uint32, n int)
// Predictor 5: pred = Average2(Average2(L, TR), T). Sequential in L.
TEXT ·predictorAdd5NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa5_done

pa5_loop:
	FMOVS 8(R1), F1             // TR
	FMOVS 4(R1), F2             // T
	ADD   $4, R1
	WORD  $0x2E2104A3           // UHADD V3.8B, V5.8B, V1.8B   avg2(L, TR)
	WORD  $0x2E220463           // UHADD V3.8B, V3.8B, V2.8B   avg2(., T)
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V3.B8, V0.B8, V5.B8   // out = in + pred; V5 is also the next L
	FMOVS F5, (R2)
	ADD   $4, R2
	SUBS  $1, R3
	BNE   pa5_loop

pa5_done:
	RET

// func predictorAdd6NEON(in, upper, out []uint32, n int)
// Predictor 6: pred = Average2(L, TL). Sequential in L.
TEXT ·predictorAdd6NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa6_done

pa6_loop:
	FMOVS (R1), F1              // TL
	ADD   $4, R1
	WORD  $0x2E2104A3           // UHADD V3.8B, V5.8B, V1.8B   avg2(L, TL)
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V3.B8, V0.B8, V5.B8   // out = in + pred; V5 is also the next L
	FMOVS F5, (R2)
	ADD   $4, R2
	SUBS  $1, R3
	BNE   pa6_loop

pa6_done:
	RET

// func predictorAdd7NEON(in, upper, out []uint32, n int)
// Predictor 7: pred = Average2(L, T). Sequential in L.
TEXT ·predictorAdd7NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa7_done

pa7_loop:
	FMOVS 4(R1), F1             // T
	ADD   $4, R1
	WORD  $0x2E2104A3           // UHADD V3.8B, V5.8B, V1.8B   avg2(L, T)
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V3.B8, V0.B8, V5.B8   // out = in + pred; V5 is also the next L
	FMOVS F5, (R2)
	ADD   $4, R2
	SUBS  $1, R3
	BNE   pa7_loop

pa7_done:
	RET

// func predictorAdd8NEON(in, upper, out []uint32, n int)
// Predictor 8: pred = Average2(TL, T). No left dependency: 4 pixels/iter.
TEXT ·predictorAdd8NEON(SB), NOSPLIT, $0-80
	MOVD in_base+0(FP), R0
	MOVD upper_base+24(FP), R1  // TL cursor
	MOVD out_base+48(FP), R2
	MOVD n+72(FP), R3
	ADD  $4, R1, R4             // T cursor
	ADD  $4, R2
	LSR  $2, R3, R5
	CBZ  R5, pa8_tail

pa8_loop4:
	VLD1.P 16(R1), [V0.B16]     // TL
	VLD1.P 16(R4), [V1.B16]     // T
	WORD   $0x6E210402          // UHADD V2.16B, V0.16B, V1.16B
	VLD1.P 16(R0), [V3.B16]     // in
	VADD   V3.B16, V2.B16, V2.B16
	VST1.P [V2.B16], 16(R2)
	SUBS   $1, R5
	BNE    pa8_loop4

pa8_tail:
	ANDS $3, R3, R5
	BEQ  pa8_done

pa8_tail1:
	FMOVS (R1), F0              // TL
	FMOVS (R4), F1              // T
	ADD   $4, R1
	ADD   $4, R4
	WORD  $0x2E210402           // UHADD V2.8B, V0.8B, V1.8B
	FMOVS (R0), F3
	ADD   $4, R0
	VADD  V3.B8, V2.B8, V2.B8
	FMOVS F2, (R2)
	ADD   $4, R2
	SUBS  $1, R5
	BNE   pa8_tail1

pa8_done:
	RET

// func predictorAdd9NEON(in, upper, out []uint32, n int)
// Predictor 9: pred = Average2(T, TR). No left dependency: 4 pixels/iter.
// Callers exclude the last pixel of the row and size upper accordingly.
TEXT ·predictorAdd9NEON(SB), NOSPLIT, $0-80
	MOVD in_base+0(FP), R0
	MOVD upper_base+24(FP), R1
	MOVD out_base+48(FP), R2
	MOVD n+72(FP), R3
	ADD  $8, R1, R4             // TR cursor
	ADD  $4, R1                 // T cursor
	ADD  $4, R2
	LSR  $2, R3, R5
	CBZ  R5, pa9_tail

pa9_loop4:
	VLD1.P 16(R1), [V0.B16]     // T
	VLD1.P 16(R4), [V1.B16]     // TR
	WORD   $0x6E210402          // UHADD V2.16B, V0.16B, V1.16B
	VLD1.P 16(R0), [V3.B16]     // in
	VADD   V3.B16, V2.B16, V2.B16
	VST1.P [V2.B16], 16(R2)
	SUBS   $1, R5
	BNE    pa9_loop4

pa9_tail:
	ANDS $3, R3, R5
	BEQ  pa9_done

pa9_tail1:
	FMOVS (R1), F0              // T
	FMOVS (R4), F1              // TR
	ADD   $4, R1
	ADD   $4, R4
	WORD  $0x2E210402           // UHADD V2.8B, V0.8B, V1.8B
	FMOVS (R0), F3
	ADD   $4, R0
	VADD  V3.B8, V2.B8, V2.B8
	FMOVS F2, (R2)
	ADD   $4, R2
	SUBS  $1, R5
	BNE   pa9_tail1

pa9_done:
	RET

// func predictorAdd10NEON(in, upper, out []uint32, n int)
// Predictor 10: pred = Average2(Average2(L, TL), Average2(T, TR)).
// Sequential in L. Callers exclude the last pixel of the row.
TEXT ·predictorAdd10NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa10_done

pa10_loop:
	FMOVS (R1), F1              // TL
	FMOVS 4(R1), F2             // T
	FMOVS 8(R1), F6             // TR
	ADD   $4, R1
	WORD  $0x2E2104A3           // UHADD V3.8B, V5.8B, V1.8B   avg2(L, TL)
	WORD  $0x2E260444           // UHADD V4.8B, V2.8B, V6.8B   avg2(T, TR)
	WORD  $0x2E240463           // UHADD V3.8B, V3.8B, V4.8B
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V3.B8, V0.B8, V5.B8   // out = in + pred; V5 is also the next L
	FMOVS F5, (R2)
	ADD   $4, R2
	SUBS  $1, R3
	BNE   pa10_loop

pa10_done:
	RET

// func predictorAdd11NEON(in, upper, out []uint32, n int)
// Predictor 11 (Select): pred = T if sum|T-TL| >= sum|L-TL| else L
// (i.e. sum(|L-TL| - |T-TL|) <= 0 selects T, matching the scalar code).
// UADDLV sums all 8 low bytes, so upper halves must stay zero (they do:
// FMOVS loads and 64-bit vector ops zero them).
TEXT ·predictorAdd11NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa11_done

pa11_loop:
	FMOVS   (R1), F1            // TL
	FMOVS   4(R1), F2           // T
	ADD     $4, R1
	WORD    $0x2E217446         // UABD V6.8B, V2.8B, V1.8B    |T - TL|
	WORD    $0x2E2174A7         // UABD V7.8B, V5.8B, V1.8B    |L - TL|
	VUADDLV V6.B8, V6           // sum_a = sum|T-TL| (16-bit, rest zeroed)
	VUADDLV V7.B8, V7           // sum_b = sum|L-TL|
	WORD    $0x7EE73CC4         // CMHS D4, D6, D7   mask = sum_a >= sum_b
	VBSL    V5.B8, V2.B8, V4.B8 // V4 = mask ? T : L
	FMOVS   (R0), F0
	ADD     $4, R0
	VADD    V4.B8, V0.B8, V5.B8 // out = in + pred; V5 is also the next L
	FMOVS   F5, (R2)
	ADD     $4, R2
	SUBS    $1, R3
	BNE     pa11_loop

pa11_done:
	RET

// func predictorAdd12NEON(in, upper, out []uint32, n int)
// Predictor 12 (ClampedAddSubtractFull): pred = clamp(L + T - TL) per
// channel, computed entirely in saturating u8 arithmetic: with
// d+ = max(T-TL, 0) and d- = max(TL-T, 0) (UQSUB, at most one nonzero),
// clamp(L + T - TL) = UQSUB(UQADD(L, d+), d-). This keeps the sequential
// dependency chain through L at three instructions.
TEXT ·predictorAdd12NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa12_done

pa12_loop:
	FMOVS (R1), F1              // TL
	FMOVS 4(R1), F2             // T
	ADD   $4, R1
	WORD  $0x2E212C46           // UQSUB V6.8B, V2.8B, V1.8B   d+ = max(T-TL, 0)
	WORD  $0x2E222C27           // UQSUB V7.8B, V1.8B, V2.8B   d- = max(TL-T, 0)
	WORD  $0x2E260CA4           // UQADD V4.8B, V5.8B, V6.8B   min(L + d+, 255)
	WORD  $0x2E272C84           // UQSUB V4.8B, V4.8B, V7.8B   max(. - d-, 0)
	FMOVS (R0), F0
	ADD   $4, R0
	VADD  V4.B8, V0.B8, V5.B8   // out = in + pred; V5 is also the next L
	FMOVS F5, (R2)
	ADD   $4, R2
	SUBS  $1, R3
	BNE   pa12_loop

pa12_done:
	RET

// func predictorAdd13NEON(in, upper, out []uint32, n int)
// Predictor 13 (ClampedAddSubtractHalf): with avg = Average2(L, T),
// pred = clamp(avg + trunc((avg - TL)/2)). UHSUB computes floor((a-b)/2);
// subtracting 1 from TL where TL > avg turns the floor into the
// truncate-toward-zero the scalar code uses (libwebp's trick).
TEXT ·predictorAdd13NEON(SB), NOSPLIT, $0-80
	MOVD  in_base+0(FP), R0
	MOVD  upper_base+24(FP), R1
	MOVD  out_base+48(FP), R2
	MOVD  n+72(FP), R3
	FMOVS (R2), F5              // V5 = L
	ADD   $4, R2
	CBZ   R3, pa13_done

pa13_loop:
	FMOVS  (R1), F1             // TL
	FMOVS  4(R1), F2            // T
	ADD    $4, R1
	WORD   $0x2E2204A3          // UHADD V3.8B, V5.8B, V2.8B   avg = avg2(L, T)
	WORD   $0x2E233424          // CMHI  V4.8B, V1.8B, V3.8B   mask = TL > avg
	VADD   V4.B8, V1.B8, V4.B8  // TL' = TL - 1 where TL > avg (mask = 0xff)
	WORD   $0x2E242466          // UHSUB V6.8B, V3.8B, V4.8B   trunc((avg-TL)/2), int8
	WORD   $0x0F08A4C6          // SXTL  V6.8H, V6.8B          sign-extend
	VUADDW V3.B8, V6.H8, V6.H8  // pred16 = halfdiff + avg (int16)
	WORD   $0x2E2128C4          // SQXTUN V4.8B, V6.8H         clamp to [0,255]
	FMOVS  (R0), F0
	ADD    $4, R0
	VADD   V4.B8, V0.B8, V5.B8  // out = in + pred; V5 is also the next L
	FMOVS  F5, (R2)
	ADD    $4, R2
	SUBS   $1, R3
	BNE    pa13_loop

pa13_done:
	RET
