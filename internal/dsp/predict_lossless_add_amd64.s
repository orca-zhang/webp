#include "textflag.h"

// VP8L inverse spatial predictors, SSE2 (see predict_lossless_add.go for the
// slice conventions). Modeled on VP8LPredictorsAdd_SSE2 from libwebp
// (src/dsp/lossless_sse2.c), adapted to this package's upper[] convention
// (upper[i] = TL, upper[i+1] = T, upper[i+2] = TR).
//
// All functions share the func(in, upper, out []uint32, n int) signature:
//   in_base+0(FP), upper_base+24(FP), out_base+48(FP), n+72(FP)
//
// Register roles: SI = &in[0], DX = &upper[0] (TL of current pixel),
// DI = &out[1] (result cursor; out[0] is the initial left neighbor),
// CX = remaining count, BX = quad-loop counter.
//
// Modes without a left dependency (0, 1, 2, 3, 4, 8, 9) process 4 pixels per
// iteration (mode 1 uses the byte prefix-sum trick: mod-256 addition is
// associative per channel; modes 8/9 compute the floor average in byte lanes
// as PAVGB minus the carry bit (a^b)&1). Modes that depend on the
// just-decoded left pixel (5, 6, 7, 10, 12, 13) run pixel-at-a-time in
// widened 16-bit lanes (PUNPCKLBW zero, PADDW/PSUBW/PSRLW, PACKUSWB clamp),
// which matches the scalar per-channel arithmetic exactly. Mode 11 stays in
// byte lanes and uses PSADBW for the sums of absolute differences.
//
// Single pixels are loaded and stored with MOVSS: exactly 4 bytes, and a
// load zeroes bits 32..127 of the XMM register (the Go assembler's MOVD
// moves 8 bytes for XMM operands, which would corrupt the in-place decode).
// Where PACKUSWB duplication pollutes bytes 4..7 of an intermediate, only
// dword 0 is ever stored and only word lanes 0..3 feed later lane-wise math,
// so the pollution never reaches a result. Mode 11 relies on clean upper
// lanes and keeps them zero throughout (its inputs are MOVSS loads and its
// selects only mix such values).

// func predictorAdd0SSE2(in, upper, out []uint32, n int)
// Predictor 0: pred = ARGB black (0xff000000).
TEXT ·predictorAdd0SSE2(SB), NOSPLIT, $0-80
	MOVQ   in_base+0(FP), SI
	MOVQ   out_base+48(FP), DI
	MOVQ   n+72(FP), CX
	ADDQ   $4, DI               // results start at out[1]
	MOVL   $0xff000000, AX
	MOVD   AX, X4
	PSHUFD $0x00, X4, X4
	MOVQ   CX, BX
	SHRQ   $2, BX
	JZ     pa0_tail

pa0_loop4:
	MOVOU (SI), X0
	PADDB X4, X0
	MOVOU X0, (DI)
	ADDQ  $16, SI
	ADDQ  $16, DI
	DECQ  BX
	JNZ   pa0_loop4

pa0_tail:
	ANDQ $3, CX
	JZ   pa0_done

pa0_tail1:
	MOVSS (SI), X0
	PADDB X4, X0
	MOVSS X0, (DI)
	ADDQ  $4, SI
	ADDQ  $4, DI
	DECQ  CX
	JNZ   pa0_tail1

pa0_done:
	RET

// func predictorAdd1SSE2(in, upper, out []uint32, n int)
// Predictor 1: pred = left. out[i] = out[i-1] + in[i] per channel mod 256,
// vectorized with a byte prefix sum: E = prefix(in[0..3]), out = E + L.
TEXT ·predictorAdd1SSE2(SB), NOSPLIT, $0-80
	MOVQ   in_base+0(FP), SI
	MOVQ   out_base+48(FP), DI
	MOVQ   n+72(FP), CX
	MOVSS  (DI), X5             // L = out[0]
	PSHUFD $0x00, X5, X5
	ADDQ   $4, DI
	MOVQ   CX, BX
	SHRQ   $2, BX
	JZ     pa1_tail

pa1_loop4:
	MOVOU  (SI), X0             // A = [i0 i1 i2 i3]
	MOVO   X0, X1
	PSLLDQ $4, X1               // B = A << 1 pixel = [0 i0 i1 i2]
	PADDB  X1, X0               // C = A + B
	MOVO   X0, X1
	PSLLDQ $8, X1               // D = C << 2 pixels
	PADDB  X1, X0               // E = C + D = prefix sums
	PADDB  X5, X0               // + L in every lane
	MOVOU  X0, (DI)
	PSHUFD $0xff, X0, X5        // L = last decoded pixel
	ADDQ   $16, SI
	ADDQ   $16, DI
	DECQ   BX
	JNZ    pa1_loop4

pa1_tail:
	ANDQ $3, CX
	JZ   pa1_done

pa1_tail1:
	MOVSS  (SI), X0
	PADDB  X5, X0
	MOVSS  X0, (DI)
	PSHUFD $0x00, X0, X5
	ADDQ   $4, SI
	ADDQ   $4, DI
	DECQ   CX
	JNZ    pa1_tail1

pa1_done:
	RET

// func predictorAdd2SSE2(in, upper, out []uint32, n int)
// Predictor 2: pred = T (upper[i+1]).
TEXT ·predictorAdd2SSE2(SB), NOSPLIT, $0-80
	MOVQ in_base+0(FP), SI
	MOVQ upper_base+24(FP), DX
	MOVQ out_base+48(FP), DI
	MOVQ n+72(FP), CX
	ADDQ $4, DX                 // DX = &T of pixel 0
	ADDQ $4, DI
	MOVQ CX, BX
	SHRQ $2, BX
	JZ   pa2_tail

pa2_loop4:
	MOVOU (SI), X0
	MOVOU (DX), X1
	PADDB X1, X0
	MOVOU X0, (DI)
	ADDQ  $16, SI
	ADDQ  $16, DX
	ADDQ  $16, DI
	DECQ  BX
	JNZ   pa2_loop4

pa2_tail:
	ANDQ $3, CX
	JZ   pa2_done

pa2_tail1:
	MOVSS (SI), X0
	MOVSS (DX), X1
	PADDB X1, X0
	MOVSS X0, (DI)
	ADDQ  $4, SI
	ADDQ  $4, DX
	ADDQ  $4, DI
	DECQ  CX
	JNZ   pa2_tail1

pa2_done:
	RET

// func predictorAdd3SSE2(in, upper, out []uint32, n int)
// Predictor 3: pred = TR (upper[i+2]). Callers exclude the last pixel of the
// row (its TR wraps to out[0]) and size upper accordingly.
TEXT ·predictorAdd3SSE2(SB), NOSPLIT, $0-80
	MOVQ in_base+0(FP), SI
	MOVQ upper_base+24(FP), DX
	MOVQ out_base+48(FP), DI
	MOVQ n+72(FP), CX
	ADDQ $8, DX                 // DX = &TR of pixel 0
	ADDQ $4, DI
	MOVQ CX, BX
	SHRQ $2, BX
	JZ   pa3_tail

pa3_loop4:
	MOVOU (SI), X0
	MOVOU (DX), X1
	PADDB X1, X0
	MOVOU X0, (DI)
	ADDQ  $16, SI
	ADDQ  $16, DX
	ADDQ  $16, DI
	DECQ  BX
	JNZ   pa3_loop4

pa3_tail:
	ANDQ $3, CX
	JZ   pa3_done

pa3_tail1:
	MOVSS (SI), X0
	MOVSS (DX), X1
	PADDB X1, X0
	MOVSS X0, (DI)
	ADDQ  $4, SI
	ADDQ  $4, DX
	ADDQ  $4, DI
	DECQ  CX
	JNZ   pa3_tail1

pa3_done:
	RET

// func predictorAdd4SSE2(in, upper, out []uint32, n int)
// Predictor 4: pred = TL (upper[i]).
TEXT ·predictorAdd4SSE2(SB), NOSPLIT, $0-80
	MOVQ in_base+0(FP), SI
	MOVQ upper_base+24(FP), DX  // DX = &TL of pixel 0
	MOVQ out_base+48(FP), DI
	MOVQ n+72(FP), CX
	ADDQ $4, DI
	MOVQ CX, BX
	SHRQ $2, BX
	JZ   pa4_tail

pa4_loop4:
	MOVOU (SI), X0
	MOVOU (DX), X1
	PADDB X1, X0
	MOVOU X0, (DI)
	ADDQ  $16, SI
	ADDQ  $16, DX
	ADDQ  $16, DI
	DECQ  BX
	JNZ   pa4_loop4

pa4_tail:
	ANDQ $3, CX
	JZ   pa4_done

pa4_tail1:
	MOVSS (SI), X0
	MOVSS (DX), X1
	PADDB X1, X0
	MOVSS X0, (DI)
	ADDQ  $4, SI
	ADDQ  $4, DX
	ADDQ  $4, DI
	DECQ  CX
	JNZ   pa4_tail1

pa4_done:
	RET

// func predictorAdd5SSE2(in, upper, out []uint32, n int)
// Predictor 5: pred = Average2(Average2(L, TR), T). Sequential in L,
// computed in 16-bit lanes ((a+b)>>1 is the exact per-channel floor).
TEXT ·predictorAdd5SSE2(SB), NOSPLIT, $0-80
	MOVQ      in_base+0(FP), SI
	MOVQ      upper_base+24(FP), DX
	MOVQ      out_base+48(FP), DI
	MOVQ      n+72(FP), CX
	PXOR      X6, X6
	MOVSS     (DI), X5          // L
	PUNPCKLBW X6, X5            // L as 16-bit lanes
	ADDQ      $4, DI
	TESTQ     CX, CX
	JZ        pa5_done

pa5_loop:
	MOVSS     8(DX), X1         // TR
	PUNPCKLBW X6, X1
	MOVSS     4(DX), X2         // T
	PUNPCKLBW X6, X2
	ADDQ      $4, DX
	MOVO      X5, X3
	PADDW     X1, X3
	PSRLW     $1, X3            // avg2(L, TR)
	PADDW     X2, X3
	PSRLW     $1, X3            // avg2(., T)
	PACKUSWB  X3, X3            // pred bytes
	MOVSS     (SI), X0
	ADDQ      $4, SI
	PADDB     X3, X0            // out = in + pred
	MOVSS     X0, (DI)
	ADDQ      $4, DI
	PUNPCKLBW X6, X0            // next L (words 4..7 polluted, unused)
	MOVO      X0, X5
	DECQ      CX
	JNZ       pa5_loop

pa5_done:
	RET

// func predictorAdd6SSE2(in, upper, out []uint32, n int)
// Predictor 6: pred = Average2(L, TL). Sequential in L.
TEXT ·predictorAdd6SSE2(SB), NOSPLIT, $0-80
	MOVQ      in_base+0(FP), SI
	MOVQ      upper_base+24(FP), DX
	MOVQ      out_base+48(FP), DI
	MOVQ      n+72(FP), CX
	PXOR      X6, X6
	MOVSS     (DI), X5          // L
	PUNPCKLBW X6, X5
	ADDQ      $4, DI
	TESTQ     CX, CX
	JZ        pa6_done

pa6_loop:
	MOVSS     (DX), X1          // TL
	PUNPCKLBW X6, X1
	ADDQ      $4, DX
	MOVO      X5, X3
	PADDW     X1, X3
	PSRLW     $1, X3            // avg2(L, TL)
	PACKUSWB  X3, X3
	MOVSS     (SI), X0
	ADDQ      $4, SI
	PADDB     X3, X0            // out = in + pred
	MOVSS     X0, (DI)
	ADDQ      $4, DI
	PUNPCKLBW X6, X0
	MOVO      X0, X5
	DECQ      CX
	JNZ       pa6_loop

pa6_done:
	RET

// func predictorAdd7SSE2(in, upper, out []uint32, n int)
// Predictor 7: pred = Average2(L, T). Sequential in L.
TEXT ·predictorAdd7SSE2(SB), NOSPLIT, $0-80
	MOVQ      in_base+0(FP), SI
	MOVQ      upper_base+24(FP), DX
	MOVQ      out_base+48(FP), DI
	MOVQ      n+72(FP), CX
	PXOR      X6, X6
	MOVSS     (DI), X5          // L
	PUNPCKLBW X6, X5
	ADDQ      $4, DI
	TESTQ     CX, CX
	JZ        pa7_done

pa7_loop:
	MOVSS     4(DX), X1         // T
	PUNPCKLBW X6, X1
	ADDQ      $4, DX
	MOVO      X5, X3
	PADDW     X1, X3
	PSRLW     $1, X3            // avg2(L, T)
	PACKUSWB  X3, X3
	MOVSS     (SI), X0
	ADDQ      $4, SI
	PADDB     X3, X0            // out = in + pred
	MOVSS     X0, (DI)
	ADDQ      $4, DI
	PUNPCKLBW X6, X0
	MOVO      X0, X5
	DECQ      CX
	JNZ       pa7_loop

pa7_done:
	RET

// func predictorAdd8SSE2(in, upper, out []uint32, n int)
// Predictor 8: pred = Average2(TL, T). No left dependency: 4 pixels/iter.
// Floor average in byte lanes: PAVGB rounds up, so subtract (a^b)&1.
TEXT ·predictorAdd8SSE2(SB), NOSPLIT, $0-80
	MOVQ   in_base+0(FP), SI
	MOVQ   upper_base+24(FP), DX // TL cursor; T is at 4(DX)
	MOVQ   out_base+48(FP), DI
	MOVQ   n+72(FP), CX
	ADDQ   $4, DI
	MOVL   $0x01010101, AX
	MOVD   AX, X7
	PSHUFD $0x00, X7, X7        // 0x01 in every byte
	MOVQ   CX, BX
	SHRQ   $2, BX
	JZ     pa8_tail

pa8_loop4:
	MOVOU (DX), X0              // TL
	MOVOU 4(DX), X1             // T
	MOVO  X0, X2
	PXOR  X1, X2
	PAND  X7, X2                // (TL^T) & 1
	PAVGB X1, X0                // (TL+T+1)>>1
	PSUBB X2, X0                // floor avg2(TL, T)
	MOVOU (SI), X3
	PADDB X3, X0
	MOVOU X0, (DI)
	ADDQ  $16, SI
	ADDQ  $16, DX
	ADDQ  $16, DI
	DECQ  BX
	JNZ   pa8_loop4

pa8_tail:
	ANDQ $3, CX
	JZ   pa8_done

pa8_tail1:
	MOVSS (DX), X0              // TL
	MOVSS 4(DX), X1             // T
	MOVO  X0, X2
	PXOR  X1, X2
	PAND  X7, X2
	PAVGB X1, X0
	PSUBB X2, X0
	MOVSS (SI), X3
	PADDB X3, X0
	MOVSS X0, (DI)
	ADDQ  $4, SI
	ADDQ  $4, DX
	ADDQ  $4, DI
	DECQ  CX
	JNZ   pa8_tail1

pa8_done:
	RET

// func predictorAdd9SSE2(in, upper, out []uint32, n int)
// Predictor 9: pred = Average2(T, TR). No left dependency: 4 pixels/iter.
// Callers exclude the last pixel of the row and size upper accordingly.
TEXT ·predictorAdd9SSE2(SB), NOSPLIT, $0-80
	MOVQ   in_base+0(FP), SI
	MOVQ   upper_base+24(FP), DX // T is at 4(DX), TR at 8(DX)
	MOVQ   out_base+48(FP), DI
	MOVQ   n+72(FP), CX
	ADDQ   $4, DI
	MOVL   $0x01010101, AX
	MOVD   AX, X7
	PSHUFD $0x00, X7, X7        // 0x01 in every byte
	MOVQ   CX, BX
	SHRQ   $2, BX
	JZ     pa9_tail

pa9_loop4:
	MOVOU 4(DX), X0             // T
	MOVOU 8(DX), X1             // TR
	MOVO  X0, X2
	PXOR  X1, X2
	PAND  X7, X2                // (T^TR) & 1
	PAVGB X1, X0                // (T+TR+1)>>1
	PSUBB X2, X0                // floor avg2(T, TR)
	MOVOU (SI), X3
	PADDB X3, X0
	MOVOU X0, (DI)
	ADDQ  $16, SI
	ADDQ  $16, DX
	ADDQ  $16, DI
	DECQ  BX
	JNZ   pa9_loop4

pa9_tail:
	ANDQ $3, CX
	JZ   pa9_done

pa9_tail1:
	MOVSS 4(DX), X0             // T
	MOVSS 8(DX), X1             // TR
	MOVO  X0, X2
	PXOR  X1, X2
	PAND  X7, X2
	PAVGB X1, X0
	PSUBB X2, X0
	MOVSS (SI), X3
	PADDB X3, X0
	MOVSS X0, (DI)
	ADDQ  $4, SI
	ADDQ  $4, DX
	ADDQ  $4, DI
	DECQ  CX
	JNZ   pa9_tail1

pa9_done:
	RET

// func predictorAdd10SSE2(in, upper, out []uint32, n int)
// Predictor 10: pred = Average2(Average2(L, TL), Average2(T, TR)).
// Sequential in L. Callers exclude the last pixel of the row.
TEXT ·predictorAdd10SSE2(SB), NOSPLIT, $0-80
	MOVQ      in_base+0(FP), SI
	MOVQ      upper_base+24(FP), DX
	MOVQ      out_base+48(FP), DI
	MOVQ      n+72(FP), CX
	PXOR      X6, X6
	MOVSS     (DI), X5          // L
	PUNPCKLBW X6, X5
	ADDQ      $4, DI
	TESTQ     CX, CX
	JZ        pa10_done

pa10_loop:
	MOVSS     (DX), X1          // TL
	PUNPCKLBW X6, X1
	MOVSS     4(DX), X2         // T
	PUNPCKLBW X6, X2
	MOVSS     8(DX), X4         // TR
	PUNPCKLBW X6, X4
	ADDQ      $4, DX
	MOVO      X5, X3
	PADDW     X1, X3
	PSRLW     $1, X3            // avg2(L, TL)
	PADDW     X4, X2
	PSRLW     $1, X2            // avg2(T, TR)
	PADDW     X2, X3
	PSRLW     $1, X3            // avg2 of the two averages
	PACKUSWB  X3, X3
	MOVSS     (SI), X0
	ADDQ      $4, SI
	PADDB     X3, X0            // out = in + pred
	MOVSS     X0, (DI)
	ADDQ      $4, DI
	PUNPCKLBW X6, X0
	MOVO      X0, X5
	DECQ      CX
	JNZ       pa10_loop

pa10_done:
	RET

// func predictorAdd11SSE2(in, upper, out []uint32, n int)
// Predictor 11 (Select): pred = L if sum|L-TL| > sum|T-TL| else T (matching
// the scalar paMinusPb <= 0 test). PSADBW against the MOVD-loaded pixels
// sums four real byte differences plus four zero lanes; both sums land in
// dword 0, where PCMPGTL builds the select mask. All values keep bits
// 32..127 zero, so the blended pred and the new L stay clean.
TEXT ·predictorAdd11SSE2(SB), NOSPLIT, $0-80
	MOVQ  in_base+0(FP), SI
	MOVQ  upper_base+24(FP), DX
	MOVQ  out_base+48(FP), DI
	MOVQ  n+72(FP), CX
	MOVSS (DI), X5              // L
	ADDQ  $4, DI
	TESTQ CX, CX
	JZ    pa11_done

pa11_loop:
	MOVSS   (DX), X1            // TL
	MOVSS   4(DX), X2           // T
	ADDQ    $4, DX
	MOVO    X2, X3
	PSADBW  X1, X3              // pa = sum|T-TL|
	MOVO    X5, X4
	PSADBW  X1, X4              // pb = sum|L-TL|
	PCMPGTL X3, X4              // mask = pb > pa (dword 0; others 0)
	MOVO    X4, X0
	PAND    X5, X4              // mask & L
	PANDN   X2, X0              // ^mask & T
	POR     X4, X0              // pred = pb > pa ? L : T
	MOVSS   (SI), X1
	ADDQ    $4, SI
	PADDB   X1, X0              // out = in + pred
	MOVSS   X0, (DI)
	ADDQ    $4, DI
	MOVO    X0, X5              // next L (clean upper lanes)
	DECQ    CX
	JNZ     pa11_loop

pa11_done:
	RET

// func predictorAdd12SSE2(in, upper, out []uint32, n int)
// Predictor 12 (ClampedAddSubtractFull): pred = clamp(L + T - TL) per
// channel, computed in signed 16-bit lanes; PACKUSWB is the exact
// clamp-to-[0,255].
TEXT ·predictorAdd12SSE2(SB), NOSPLIT, $0-80
	MOVQ      in_base+0(FP), SI
	MOVQ      upper_base+24(FP), DX
	MOVQ      out_base+48(FP), DI
	MOVQ      n+72(FP), CX
	PXOR      X6, X6
	MOVSS     (DI), X5          // L
	PUNPCKLBW X6, X5
	ADDQ      $4, DI
	TESTQ     CX, CX
	JZ        pa12_done

pa12_loop:
	MOVSS     (DX), X1          // TL
	PUNPCKLBW X6, X1
	MOVSS     4(DX), X2         // T
	PUNPCKLBW X6, X2
	ADDQ      $4, DX
	MOVO      X5, X3
	PADDW     X2, X3
	PSUBW     X1, X3            // L + T - TL (signed words)
	PACKUSWB  X3, X3            // clamp to [0, 255]
	MOVSS     (SI), X0
	ADDQ      $4, SI
	PADDB     X3, X0            // out = in + pred
	MOVSS     X0, (DI)
	ADDQ      $4, DI
	PUNPCKLBW X6, X0
	MOVO      X0, X5
	DECQ      CX
	JNZ       pa12_loop

pa12_done:
	RET

// func predictorAdd13SSE2(in, upper, out []uint32, n int)
// Predictor 13 (ClampedAddSubtractHalf): with avg = Average2(L, T),
// pred = clamp(avg + trunc((avg - TL)/2)). The truncate-toward-zero
// division is (d - (d >> 15)) >> 1 in signed 16-bit lanes (add 1 before
// the arithmetic shift when d is negative).
TEXT ·predictorAdd13SSE2(SB), NOSPLIT, $0-80
	MOVQ      in_base+0(FP), SI
	MOVQ      upper_base+24(FP), DX
	MOVQ      out_base+48(FP), DI
	MOVQ      n+72(FP), CX
	PXOR      X6, X6
	MOVSS     (DI), X5          // L
	PUNPCKLBW X6, X5
	ADDQ      $4, DI
	TESTQ     CX, CX
	JZ        pa13_done

pa13_loop:
	MOVSS     (DX), X1          // TL
	PUNPCKLBW X6, X1
	MOVSS     4(DX), X2         // T
	PUNPCKLBW X6, X2
	ADDQ      $4, DX
	MOVO      X5, X3
	PADDW     X2, X3
	PSRLW     $1, X3            // avg = avg2(L, T)
	MOVO      X3, X4
	PSUBW     X1, X4            // d = avg - TL
	MOVO      X4, X7
	PSRAW     $15, X7           // sign(d) = 0 or -1
	PSUBW     X7, X4            // d += 1 where d < 0
	PSRAW     $1, X4            // trunc(d/2)
	PADDW     X4, X3            // pred16 = avg + trunc(d/2)
	PACKUSWB  X3, X3            // clamp to [0, 255]
	MOVSS     (SI), X0
	ADDQ      $4, SI
	PADDB     X3, X0            // out = in + pred
	MOVSS     X0, (DI)
	ADDQ      $4, DI
	PUNPCKLBW X6, X0
	MOVO      X0, X5
	DECQ      CX
	JNZ       pa13_loop

pa13_done:
	RET
