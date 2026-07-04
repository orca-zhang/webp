//go:build arm64

package dsp

import (
	"math/rand"
	"testing"
)

// TestConvertARGBToRGBANEONConformance verifies the NEON ARGB->RGBA byte
// conversion is bit-exact against the scalar ConvertBGRAToRGBA reference for
// lengths covering the 8-pixel loop, the 4-pixel step and 1-3 pixel tails.
// Guard bytes after the output catch out-of-range writes.
func TestConvertARGBToRGBANEONConformance(t *testing.T) {
	rng := rand.New(rand.NewSource(2024))
	for iter := 0; iter < 5000; iter++ {
		n := 1 + rng.Intn(67)
		src := make([]uint32, n)
		fillPredRand(rng, src)

		dstGo := make([]byte, n*4+4)
		dstNeon := make([]byte, n*4+4)
		for i := n * 4; i < n*4+4; i++ {
			dstGo[i], dstNeon[i] = 0xAB, 0xAB
		}

		ConvertBGRAToRGBA(src, n, dstGo[:n*4])
		convertARGBToRGBANEON(src, dstNeon[:n*4], n)

		for i := range dstGo {
			if dstGo[i] != dstNeon[i] {
				t.Fatalf("iter %d n=%d: mismatch at dst[%d]: go=%02x neon=%02x",
					iter, n, i, dstGo[i], dstNeon[i])
			}
		}
	}
}

func BenchmarkConvertARGBToRGBA(b *testing.B) {
	rng := rand.New(rand.NewSource(6))
	for _, n := range []int{16, 1536} {
		src := make([]uint32, n)
		dst := make([]byte, n*4)
		fillPredRand(rng, src)
		b.Run("go/n"+itoa(n), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				ConvertBGRAToRGBA(src, n, dst)
			}
		})
		b.Run("neon/n"+itoa(n), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				convertARGBToRGBANEON(src, dst, n)
			}
		})
	}
}
