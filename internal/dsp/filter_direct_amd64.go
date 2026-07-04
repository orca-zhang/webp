//go:build amd64

package dsp

// SimpleVFilter16 applies the simple loop filter vertically across a 16-wide edge.
// Uses AVX2 when available, falls back to SSE2.
func SimpleVFilter16(p []byte, base, stride, thresh int) {
	if hasAVX2 {
		simpleVFilter16AVX2(p, base, stride, thresh)
		return
	}
	simpleVFilter16SSE2(p, base, stride, thresh)
}

// VFilter16 applies the complex vertical loop filter across a 16-wide edge.
// No SIMD implementation on amd64 yet; uses the pure Go implementation.
func VFilter16(p []byte, base, stride, thresh, ithresh, hevT int) {
	vFilter16Go(p, base, stride, thresh, ithresh, hevT)
}

// VFilter8 applies the complex vertical filter to an 8-wide chroma edge.
func VFilter8(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int) {
	vFilter8Go(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
}

// VFilter16i applies complex vertical filtering at internal block boundaries.
func VFilter16i(p []byte, base, stride, thresh, ithresh, hevT int) {
	vFilter16iGo(p, base, stride, thresh, ithresh, hevT)
}

// VFilter8i applies complex vertical filtering at internal 4-row boundaries
// for 8x8 chroma blocks.
func VFilter8i(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int) {
	vFilter8iGo(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
}
