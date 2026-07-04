//go:build amd64

package dsp

// SSE2 assembly stubs (filter_sse2_amd64.s). All are vertical filters:
// pixels across the edge are strided rows, pixels along the edge are
// contiguous, which maps directly onto 16-byte vector lanes.

//go:noescape
func vFilter16EdgeSSE2(p []byte, base, stride, thresh, ithresh, hevT int)

//go:noescape
func vFilter16InnerSSE2(p []byte, base, stride, thresh, ithresh, hevT int)

//go:noescape
func vFilter8EdgeSSE2(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)

//go:noescape
func vFilter8InnerSSE2(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)

// filterParamsInRange reports whether the SSE2 filters are bit-exact for
// the given thresholds. The SSE2 code broadcasts ithresh/hevT to unsigned
// bytes and 2*thresh+1 to unsigned 16-bit lanes, so out-of-range values
// (never produced by the decoder, which uses thresh <= level+ilevel+4 <= 193,
// ithresh <= 63 and hevT <= 3) fall back to the Go implementation.
func filterParamsInRange(thresh, ithresh, hevT int) bool {
	return thresh >= 0 && thresh <= 30000 &&
		ithresh >= 0 && ithresh <= 255 &&
		hevT >= 0 && hevT <= 255
}

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
func VFilter16(p []byte, base, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter16Go(p, base, stride, thresh, ithresh, hevT)
		return
	}
	vFilter16EdgeSSE2(p, base, stride, thresh, ithresh, hevT)
}

// VFilter8 applies the complex vertical filter to an 8-wide chroma edge.
// Both planes are filtered in a single SSE2 pass (U in lanes 0-7, V in
// lanes 8-15).
func VFilter8(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter8Go(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
		return
	}
	vFilter8EdgeSSE2(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
}

// VFilter16i applies complex vertical filtering at internal block boundaries.
func VFilter16i(p []byte, base, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter16iGo(p, base, stride, thresh, ithresh, hevT)
		return
	}
	for k := 1; k <= 3; k++ {
		vFilter16InnerSSE2(p, base+k*4*stride, stride, thresh, ithresh, hevT)
	}
}

// VFilter8i applies complex vertical filtering at internal 4-row boundaries
// for 8x8 chroma blocks.
func VFilter8i(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter8iGo(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
		return
	}
	vFilter8InnerSSE2(u, v, uBase+4*stride, vBase+4*stride, stride, thresh, ithresh, hevT)
}
