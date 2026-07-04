//go:build arm64

package dsp

import (
	"fmt"
	"math/rand"
	"testing"
)

// predAddImpls pairs each VP8L predictor mode with its NEON implementation.
var predAddImpls = []struct {
	mode int
	neon PredictorAddFunc
}{
	{0, predictorAdd0NEON},
	{1, predictorAdd1NEON},
	{2, predictorAdd2NEON},
	{3, predictorAdd3NEON},
	{4, predictorAdd4NEON},
	{5, predictorAdd5NEON},
	{6, predictorAdd6NEON},
	{7, predictorAdd7NEON},
	{8, predictorAdd8NEON},
	{9, predictorAdd9NEON},
	{10, predictorAdd10NEON},
	{11, predictorAdd11NEON},
	{12, predictorAdd12NEON},
	{13, predictorAdd13NEON},
}

// fillPredRand fills s with random pixels, biased toward the channel
// extremes 0x00 and 0xff that exercise clamping and carry paths.
func fillPredRand(rng *rand.Rand, s []uint32) {
	for i := range s {
		switch rng.Intn(5) {
		case 0:
			s[i] = 0
		case 1:
			s[i] = 0xffffffff
		case 2:
			// Mixed extreme channels.
			var v uint32
			for c := 0; c < 4; c++ {
				b := uint32(0)
				switch rng.Intn(3) {
				case 0:
					b = 0xff
				case 1:
					b = uint32(rng.Intn(256))
				}
				v = v<<8 | b
			}
			s[i] = v
		default:
			s[i] = rng.Uint32()
		}
	}
}

// TestPredictorAddNEONConformance verifies each NEON predictor is bit-exact
// against the scalar Go reference on random data, for run lengths covering
// sub-quad tails and quad loops, including n < 4 and extreme channel values.
// Guard elements around out catch out-of-range writes.
func TestPredictorAddNEONConformance(t *testing.T) {
	rng := rand.New(rand.NewSource(1234))
	const guard = 0xdeadbeef
	for _, impl := range predAddImpls {
		t.Run(fmt.Sprintf("mode%d", impl.mode), func(t *testing.T) {
			ref := predictorAddGo(impl.mode)
			for iter := 0; iter < 3000; iter++ {
				n := 1 + rng.Intn(67)
				in := make([]uint32, n)
				upper := make([]uint32, n+2)
				fillPredRand(rng, in)
				fillPredRand(rng, upper)

				// out with one guard slot after the results.
				outGo := make([]uint32, n+2)
				outNeon := make([]uint32, n+2)
				left := rng.Uint32()
				if iter%7 == 0 {
					left = 0xffffffff
				}
				outGo[0], outNeon[0] = left, left
				outGo[n+1], outNeon[n+1] = guard, guard

				ref(in, upper, outGo[:n+1], n)
				impl.neon(in, upper, outNeon[:n+1], n)

				for i := range outGo {
					if outGo[i] != outNeon[i] {
						t.Fatalf("iter %d n=%d: mismatch at out[%d]: go=%08x neon=%08x",
							iter, n, i, outGo[i], outNeon[i])
					}
				}
			}
		})
	}
}

// TestPredictorAddNEONAliased mirrors the decoder's in-place use: the residual
// row and the output row are the same buffer, with out starting one element
// before in.
func TestPredictorAddNEONAliased(t *testing.T) {
	rng := rand.New(rand.NewSource(99))
	for _, impl := range predAddImpls {
		t.Run(fmt.Sprintf("mode%d", impl.mode), func(t *testing.T) {
			ref := predictorAddGo(impl.mode)
			for iter := 0; iter < 300; iter++ {
				n := 1 + rng.Intn(67)
				buf := make([]uint32, n+1)
				upper := make([]uint32, n+2)
				fillPredRand(rng, buf)
				fillPredRand(rng, upper)

				want := make([]uint32, n+1)
				copy(want, buf)
				ref(append([]uint32(nil), buf[1:]...), upper, want, n)

				impl.neon(buf[1:], upper, buf, n)

				for i := range want {
					if want[i] != buf[i] {
						t.Fatalf("iter %d n=%d: aliased mismatch at out[%d]: go=%08x neon=%08x",
							iter, n, i, want[i], buf[i])
					}
				}
			}
		})
	}
}

// BenchmarkPredictorAdd compares the scalar reference and NEON versions per
// mode, both on a typical predictor tile span (16 pixels) and a long run.
func BenchmarkPredictorAdd(b *testing.B) {
	rng := rand.New(rand.NewSource(7))
	for _, size := range []int{16, 1024} {
		n := size
		in := make([]uint32, n)
		upper := make([]uint32, n+2)
		out := make([]uint32, n+1)
		fillPredRand(rng, in)
		fillPredRand(rng, upper)
		out[0] = rng.Uint32()
		for _, impl := range predAddImpls {
			ref := predictorAddGo(impl.mode)
			b.Run(fmt.Sprintf("mode%d/n%d/go", impl.mode, n), func(b *testing.B) {
				for i := 0; i < b.N; i++ {
					ref(in, upper, out, n)
				}
			})
			b.Run(fmt.Sprintf("mode%d/n%d/neon", impl.mode, n), func(b *testing.B) {
				for i := 0; i < b.N; i++ {
					impl.neon(in, upper, out, n)
				}
			})
		}
	}
}
