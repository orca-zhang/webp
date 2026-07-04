package dsp

// VP8L inverse spatial prediction, batch form (decoder hot path).
//
// A PredictorAddFunc reconstructs a run of n pixels for a single predictor
// mode: out[1+i] = AddPixels(in[i], pred(L, T, TL, TR)) with per-channel
// modular addition, mirroring VP8LPredictorsAdd from libwebp
// (src/dsp/lossless_neon.c).
//
// Slice conventions (all indices relative to the run):
//   - in[0..n-1]  residuals for the n pixels.
//   - upper[i]    top-left neighbor (TL) of pixel i, so upper[i+1] is the
//     top (T) and upper[i+2] the top-right (TR) neighbor. Callers must size
//     upper as n+1 elements (n+2 for modes that use TR: 3, 5, 9, 10).
//     Modes 0 and 1 ignore upper (it may be nil).
//   - out[0]      left neighbor (L) of pixel 0; results are written to
//     out[1..n]. For sequential modes, out[i] is the left neighbor of
//     pixel i as it is produced.
//
// in and out may overlap with out one element behind in (the decoder applies
// the transform in place): implementations must read in[i] before writing
// out[1+i], and never re-read earlier in elements.

// PredictorAddFunc applies one VP8L inverse predictor to a run of n pixels.
type PredictorAddFunc func(in, upper, out []uint32, n int)

// PredictorsAdd holds accelerated implementations of the 14 VP8L predictor
// modes (indices 14 and 15 are unused sentinels). A nil entry means no
// accelerated version exists and callers must use their scalar loop.
var PredictorsAdd [16]PredictorAddFunc

// lAddPixels adds two ARGB pixels per component, mod 256.
func lAddPixels(a, b uint32) uint32 {
	alphaAndGreen := (a & 0xff00ff00) + (b & 0xff00ff00)
	redAndBlue := (a & 0x00ff00ff) + (b & 0x00ff00ff)
	return (alphaAndGreen & 0xff00ff00) | (redAndBlue & 0x00ff00ff)
}

// predictorAddGo returns the scalar reference implementation for a predictor
// mode. It is the conformance and benchmark baseline for the assembly
// versions; it is not wired into PredictorsAdd (scalar callers keep their
// specialized inline loops).
func predictorAddGo(mode int) PredictorAddFunc {
	pred := LosslessPredictors[mode]
	return func(in, upper, out []uint32, n int) {
		for i := 0; i < n; i++ {
			var p uint32
			if mode >= 2 {
				p = pred(&out[i], upper[i:])
			} else {
				p = pred(&out[i], nil)
			}
			out[i+1] = lAddPixels(in[i], p)
		}
	}
}
