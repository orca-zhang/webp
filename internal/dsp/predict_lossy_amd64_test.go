//go:build amd64

package dsp

import (
	"math/rand"
	"testing"
)

// pred4Impls pairs each scalar 4x4 predictor with its SSE2 counterpart.
var pred4Impls = []struct {
	name string
	gofn PredFunc
	sse2 PredFunc
}{
	{"DC4", dc4, dc4asmSSE2},
	{"TM4", tm4, tm4asmSSE2},
	{"VE4", ve4, ve4asmSSE2},
	{"HE4", he4, he4asmSSE2},
	{"RD4", rd4, rd4asmSSE2},
	{"VR4", vr4, vr4asmSSE2},
	{"LD4", ld4, ld4asmSSE2},
	{"VL4", vl4, vl4asmSSE2},
	{"HD4", hd4, hd4asmSSE2},
	{"HU4", hu4, hu4asmSSE2},
}

// TestPred4SSE2Conformance verifies each SSE2 4x4 predictor is bit-exact
// against the scalar Go reference on random contexts (random top row,
// top-right, top-left corner and left column), at every x offset a real
// caller can produce. Whole buffers are compared, so any out-of-block
// write by the assembly is caught too.
func TestPred4SSE2Conformance(t *testing.T) {
	rng := rand.New(rand.NewSource(1234))
	const bufSize = 8 * BPS
	for _, impl := range pred4Impls {
		t.Run(impl.name, func(t *testing.T) {
			for iter := 0; iter < 2000; iter++ {
				// x in [1,24]: keeps off-BPS-1 >= 0 and the 8 top(-right)
				// bytes inside the row, like the real YOff=BPS+8 layout
				// (x ranges over 8..20 there).
				x := 1 + rng.Intn(24)
				off := 2*BPS + x
				ref := makeRandBuf(rng, bufSize)
				bufGo := make([]byte, bufSize)
				bufSSE2 := make([]byte, bufSize)
				copy(bufGo, ref)
				copy(bufSSE2, ref)

				impl.gofn(bufGo, off)
				impl.sse2(bufSSE2, off)

				for i := range bufGo {
					if bufGo[i] != bufSSE2[i] {
						y := i/BPS - (off / BPS)
						xx := i%BPS - x
						t.Fatalf("iter %d off %d: mismatch at index %d (block y=%d x=%d): go=%d sse2=%d",
							iter, off, i, y, xx, bufGo[i], bufSSE2[i])
					}
				}
			}
		})
	}
}

func BenchmarkPred4(b *testing.B) {
	rng := rand.New(rand.NewSource(99))
	buf := makeRandBuf(rng, 8*BPS)
	off := 2*BPS + 8
	for _, impl := range pred4Impls {
		b.Run(impl.name+"/go", func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				impl.gofn(buf, off)
			}
		})
		b.Run(impl.name+"/sse2", func(b *testing.B) {
			for i := 0; i < b.N; i++ {
				impl.sse2(buf, off)
			}
		})
	}
}

// BenchmarkPred4AllModes mimics the encoder RD pre-screen loop: all 10 modes
// generated back-to-back for one block, through the dispatch function.
func BenchmarkPred4AllModes(b *testing.B) {
	rng := rand.New(rand.NewSource(7))
	buf := makeRandBuf(rng, 8*BPS)
	off := 2*BPS + 8
	b.Run("direct", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			for mode := 0; mode < 10; mode++ {
				PredLuma4Direct(mode, buf, off)
			}
		}
	})
}
