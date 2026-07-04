//go:build amd64

package dsp

import (
	"math/rand"
	"testing"
)

// TestConvertARGBToRGBASSE2Conformance verifies the SSE2 ARGB->RGBA byte
// conversion is bit-exact against the scalar ConvertBGRAToRGBA reference for
// lengths covering the 8-pixel loop, the 4-pixel step and 1-3 pixel tails.
// Guard bytes after the output catch out-of-range writes.
func TestConvertARGBToRGBASSE2Conformance(t *testing.T) {
	rng := rand.New(rand.NewSource(2024))
	for iter := 0; iter < 5000; iter++ {
		n := 1 + rng.Intn(67)
		src := make([]uint32, n)
		fillPredRand(rng, src)

		dstGo := make([]byte, n*4+4)
		dstSSE2 := make([]byte, n*4+4)
		for i := n * 4; i < n*4+4; i++ {
			dstGo[i], dstSSE2[i] = 0xAB, 0xAB
		}

		ConvertBGRAToRGBA(src, n, dstGo[:n*4])
		convertARGBToRGBASSE2(src, dstSSE2[:n*4], n)

		for i := range dstGo {
			if dstGo[i] != dstSSE2[i] {
				t.Fatalf("iter %d n=%d: mismatch at dst[%d]: go=%02x sse2=%02x",
					iter, n, i, dstGo[i], dstSSE2[i])
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
		b.Run("sse2/n"+itoa(n), func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				convertARGBToRGBASSE2(src, dst, n)
			}
		})
	}
}
