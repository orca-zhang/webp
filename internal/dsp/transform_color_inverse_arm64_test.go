//go:build arm64

package dsp

import (
	"math/rand"
	"testing"
)

// TestTransformColorInverseNEONConformance verifies the NEON inverse
// cross-color transform is bit-exact against the scalar reference for all
// multiplier extremes, run lengths covering quad loops and sub-quad tails,
// and pixel values biased toward channel extremes.
func TestTransformColorInverseNEONConformance(t *testing.T) {
	rng := rand.New(rand.NewSource(4321))
	const guard = 0xdeadbeef
	multValues := []int8{-128, -127, -1, 0, 1, 127}
	pickMult := func() int8 {
		if rng.Intn(2) == 0 {
			return multValues[rng.Intn(len(multValues))]
		}
		return int8(rng.Intn(256) - 128)
	}
	for iter := 0; iter < 20000; iter++ {
		n := 1 + rng.Intn(67)
		g2r, g2b, r2b := pickMult(), pickMult(), pickMult()

		src := make([]uint32, n)
		fillPredRand(rng, src)
		dstGo := make([]uint32, n+1)
		dstNeon := make([]uint32, n+1)
		dstGo[n], dstNeon[n] = guard, guard

		transformColorInverseGo(g2r, g2b, r2b, src, dstGo[:n], n)
		transformColorInverseNEONBatch(g2r, g2b, r2b, src, dstNeon[:n], n)

		for i := range dstGo {
			if dstGo[i] != dstNeon[i] {
				t.Fatalf("iter %d n=%d mults=(%d,%d,%d): mismatch at dst[%d]: src=%08x go=%08x neon=%08x",
					iter, n, g2r, g2b, r2b, i, src[i%n], dstGo[i], dstNeon[i])
			}
		}
	}
}

// TestTransformColorInverseNEONInPlace mirrors the decoder's in-place call
// (src and dst are the same slice).
func TestTransformColorInverseNEONInPlace(t *testing.T) {
	rng := rand.New(rand.NewSource(77))
	for iter := 0; iter < 2000; iter++ {
		n := 1 + rng.Intn(67)
		g2r := int8(rng.Intn(256) - 128)
		g2b := int8(rng.Intn(256) - 128)
		r2b := int8(rng.Intn(256) - 128)

		buf := make([]uint32, n)
		fillPredRand(rng, buf)
		want := make([]uint32, n)
		transformColorInverseGo(g2r, g2b, r2b, buf, want, n)

		transformColorInverseNEONBatch(g2r, g2b, r2b, buf, buf, n)

		for i := range want {
			if want[i] != buf[i] {
				t.Fatalf("iter %d n=%d: in-place mismatch at [%d]: go=%08x neon=%08x",
					iter, n, i, want[i], buf[i])
			}
		}
	}
}

func BenchmarkTransformColorInverse(b *testing.B) {
	rng := rand.New(rand.NewSource(5))
	for _, n := range []int{16, 32, 1024} {
		src := make([]uint32, n)
		dst := make([]uint32, n)
		fillPredRand(rng, src)
		b.Run("go/n"+itoa(n), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				transformColorInverseGo(-52, 37, -110, src, dst, n)
			}
		})
		b.Run("neon/n"+itoa(n), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				transformColorInverseNEONBatch(-52, 37, -110, src, dst, n)
			}
		})
	}
}

// itoa avoids importing strconv in this small test file's hot loops.
func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var buf [8]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	return string(buf[i:])
}
