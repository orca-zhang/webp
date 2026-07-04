package dsp

import (
	"math/rand"
	"testing"
)

// ---------- Complex (normal) loop filter conformance ----------
//
// These tests compare the dispatched VFilter16/VFilter16i/VFilter8/VFilter8i
// (NEON on arm64, pure Go elsewhere) against the pure Go reference across
// random inputs, sweeping thresh/ithresh/hevT combinations including
// clipping edge cases.

// fillFilterData fills buf with data in one of several modes so that the
// needs-filter, interior-smoothness and HEV branches are all exercised:
//
//	mode 0: uniform random bytes (mostly no-filter for small thresholds)
//	mode 1: smooth data with small noise (filter path, low variance)
//	mode 2: smooth data with occasional large spikes (HEV path)
//	mode 3: extreme values only (saturation/clipping edges)
func fillFilterData(rng *rand.Rand, buf []byte, mode int) {
	switch mode {
	case 1:
		center := rng.Intn(256)
		amp := rng.Intn(16) + 1
		for i := range buf {
			v := center + rng.Intn(2*amp+1) - amp
			if v < 0 {
				v = 0
			} else if v > 255 {
				v = 255
			}
			buf[i] = byte(v)
		}
	case 2:
		center := rng.Intn(256)
		amp := rng.Intn(8) + 1
		for i := range buf {
			v := center + rng.Intn(2*amp+1) - amp
			if rng.Intn(8) == 0 {
				v = rng.Intn(256) // spike
			}
			if v < 0 {
				v = 0
			} else if v > 255 {
				v = 255
			}
			buf[i] = byte(v)
		}
	case 3:
		extremes := []byte{0, 1, 127, 128, 254, 255}
		for i := range buf {
			buf[i] = extremes[rng.Intn(len(extremes))]
		}
	default:
		for i := range buf {
			buf[i] = byte(rng.Intn(256))
		}
	}
}

// makeComplexFilterBuf creates a buffer with room for p3..q3 rows around the
// base offset (base-4*stride .. base+3*stride+15).
func makeComplexFilterBuf(rng *rand.Rand, stride, mode int) ([]byte, int) {
	base := 4 * stride
	size := base + 3*stride + 16
	buf := make([]byte, size)
	fillFilterData(rng, buf, mode)
	return buf, base
}

// filterTestParams returns thresh/ithresh/hevT for a test iteration,
// alternating between decoder-realistic values and full-range sweeps.
func filterTestParams(rng *rand.Rand, iter int) (int, int, int) {
	switch iter % 3 {
	case 0:
		// Decoder-realistic: thresh = limit(+4) <= 193, ithresh <= 63, hevT <= 3.
		return rng.Intn(194), rng.Intn(64), rng.Intn(4)
	case 1:
		// Full byte range.
		return rng.Intn(256), rng.Intn(256), rng.Intn(256)
	default:
		// Boundary-heavy values.
		picks := []int{0, 1, 2, 3, 63, 64, 127, 128, 254, 255}
		return picks[rng.Intn(len(picks))], picks[rng.Intn(len(picks))], picks[rng.Intn(len(picks))]
	}
}

func TestVFilter16Conformance(t *testing.T) {
	rng := rand.New(rand.NewSource(500))
	for iter := 0; iter < 4000; iter++ {
		stride := 16 + rng.Intn(48)
		thresh, ithresh, hevT := filterTestParams(rng, iter)
		buf1, base := makeComplexFilterBuf(rng, stride, iter%4)
		buf2 := copyBuf(buf1)

		vFilter16Go(buf1, base, stride, thresh, ithresh, hevT)
		VFilter16(buf2, base, stride, thresh, ithresh, hevT)

		for i := range buf1 {
			if buf1[i] != buf2[i] {
				t.Fatalf("iter %d (stride=%d thresh=%d ithresh=%d hevT=%d mode=%d): byte[%d] Go=%d dispatch=%d",
					iter, stride, thresh, ithresh, hevT, iter%4, i, buf1[i], buf2[i])
			}
		}
	}
}

func TestVFilter16iConformance(t *testing.T) {
	rng := rand.New(rand.NewSource(501))
	for iter := 0; iter < 4000; iter++ {
		stride := 16 + rng.Intn(48)
		thresh, ithresh, hevT := filterTestParams(rng, iter)
		// VFilter16i spans base+4*stride .. base+12*stride(+context).
		base := 4 * stride
		size := base + 16*stride + 16
		buf1 := make([]byte, size)
		fillFilterData(rng, buf1, iter%4)
		buf2 := copyBuf(buf1)

		vFilter16iGo(buf1, base, stride, thresh, ithresh, hevT)
		VFilter16i(buf2, base, stride, thresh, ithresh, hevT)

		for i := range buf1 {
			if buf1[i] != buf2[i] {
				t.Fatalf("iter %d (stride=%d thresh=%d ithresh=%d hevT=%d mode=%d): byte[%d] Go=%d dispatch=%d",
					iter, stride, thresh, ithresh, hevT, iter%4, i, buf1[i], buf2[i])
			}
		}
	}
}

func TestVFilter8Conformance(t *testing.T) {
	rng := rand.New(rand.NewSource(502))
	for iter := 0; iter < 4000; iter++ {
		stride := 8 + rng.Intn(48)
		thresh, ithresh, hevT := filterTestParams(rng, iter)
		u1, uBase := makeComplexFilterBuf(rng, stride, iter%4)
		v1, vBase := makeComplexFilterBuf(rng, stride, (iter+1)%4)
		u2 := copyBuf(u1)
		v2 := copyBuf(v1)

		vFilter8Go(u1, v1, uBase, vBase, stride, thresh, ithresh, hevT)
		VFilter8(u2, v2, uBase, vBase, stride, thresh, ithresh, hevT)

		for i := range u1 {
			if u1[i] != u2[i] {
				t.Fatalf("iter %d (stride=%d thresh=%d ithresh=%d hevT=%d): U byte[%d] Go=%d dispatch=%d",
					iter, stride, thresh, ithresh, hevT, i, u1[i], u2[i])
			}
		}
		for i := range v1 {
			if v1[i] != v2[i] {
				t.Fatalf("iter %d (stride=%d thresh=%d ithresh=%d hevT=%d): V byte[%d] Go=%d dispatch=%d",
					iter, stride, thresh, ithresh, hevT, i, v1[i], v2[i])
			}
		}
	}
}

func TestVFilter8iConformance(t *testing.T) {
	rng := rand.New(rand.NewSource(503))
	for iter := 0; iter < 4000; iter++ {
		stride := 8 + rng.Intn(48)
		thresh, ithresh, hevT := filterTestParams(rng, iter)
		// VFilter8i filters at base+4*stride; needs context up to base+7*stride+8.
		base := 4 * stride
		size := base + 8*stride + 16
		u1 := make([]byte, size)
		v1 := make([]byte, size)
		fillFilterData(rng, u1, iter%4)
		fillFilterData(rng, v1, (iter+2)%4)
		u2 := copyBuf(u1)
		v2 := copyBuf(v1)

		vFilter8iGo(u1, v1, base, base, stride, thresh, ithresh, hevT)
		VFilter8i(u2, v2, base, base, stride, thresh, ithresh, hevT)

		for i := range u1 {
			if u1[i] != u2[i] {
				t.Fatalf("iter %d (stride=%d thresh=%d ithresh=%d hevT=%d): U byte[%d] Go=%d dispatch=%d",
					iter, stride, thresh, ithresh, hevT, i, u1[i], u2[i])
			}
		}
		for i := range v1 {
			if v1[i] != v2[i] {
				t.Fatalf("iter %d (stride=%d thresh=%d ithresh=%d hevT=%d): V byte[%d] Go=%d dispatch=%d",
					iter, stride, thresh, ithresh, hevT, i, v1[i], v2[i])
			}
		}
	}
}

// TestVFilterConformanceOutOfRange verifies the dispatch falls back to Go
// for parameter values outside the NEON-exact range.
func TestVFilterConformanceOutOfRange(t *testing.T) {
	rng := rand.New(rand.NewSource(504))
	params := [][3]int{
		{-1, 20, 2}, {40, -1, 2}, {40, 20, -1},
		{40, 300, 2}, {40, 20, 300}, {50000, 20, 2},
	}
	for iter, p := range params {
		stride := 32
		buf1, base := makeComplexFilterBuf(rng, stride, 1)
		buf2 := copyBuf(buf1)
		vFilter16Go(buf1, base, stride, p[0], p[1], p[2])
		VFilter16(buf2, base, stride, p[0], p[1], p[2])
		for i := range buf1 {
			if buf1[i] != buf2[i] {
				t.Fatalf("case %d (%v): byte[%d] Go=%d dispatch=%d", iter, p, i, buf1[i], buf2[i])
			}
		}
	}
}

// ---------- Benchmarks ----------

// benchFilterBuf returns a smooth buffer so the filter branch is actually
// taken (worst case for performance).
func benchFilterBuf(stride int) ([]byte, int) {
	rng := rand.New(rand.NewSource(510))
	base := 4 * stride
	size := base + 16*stride + 16
	buf := make([]byte, size)
	fillFilterData(rng, buf, 1)
	return buf, base
}

func BenchmarkVFilter16Go(b *testing.B) {
	buf, base := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		vFilter16Go(buf, base, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter16Dispatch(b *testing.B) {
	buf, base := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		VFilter16(buf, base, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter16iGo(b *testing.B) {
	buf, base := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		vFilter16iGo(buf, base, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter16iDispatch(b *testing.B) {
	buf, base := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		VFilter16i(buf, base, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter8Go(b *testing.B) {
	u, uBase := benchFilterBuf(32)
	v, vBase := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		vFilter8Go(u, v, uBase, vBase, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter8Dispatch(b *testing.B) {
	u, uBase := benchFilterBuf(32)
	v, vBase := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		VFilter8(u, v, uBase, vBase, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter8iGo(b *testing.B) {
	u, uBase := benchFilterBuf(32)
	v, vBase := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		vFilter8iGo(u, v, uBase, vBase, 32, 35, 20, 2)
	}
}

func BenchmarkVFilter8iDispatch(b *testing.B) {
	u, uBase := benchFilterBuf(32)
	v, vBase := benchFilterBuf(32)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		VFilter8i(u, v, uBase, vBase, 32, 35, 20, 2)
	}
}
