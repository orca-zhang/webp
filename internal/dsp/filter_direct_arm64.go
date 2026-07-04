//go:build arm64

package dsp

// NEON assembly stubs (filter_arm64.s). All are vertical filters: pixels
// across the edge are strided rows, pixels along the edge are contiguous,
// which maps directly onto 16-byte vector lanes.

//go:noescape
func simpleVFilter16NEON(p []byte, base, stride, thresh int)

//go:noescape
func vFilter16EdgeNEON(p []byte, base, stride, thresh, ithresh, hevT int)

//go:noescape
func vFilter16InnerNEON(p []byte, base, stride, thresh, ithresh, hevT int)

//go:noescape
func vFilter8EdgeNEON(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)

//go:noescape
func vFilter8InnerNEON(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int)

// filterParamsInRange reports whether the NEON filters are bit-exact for
// the given thresholds. The NEON code broadcasts ithresh/hevT to unsigned
// bytes and 2*thresh+1 to unsigned 16-bit lanes, so out-of-range values
// (never produced by the decoder, which uses thresh <= level+ilevel+4 <= 193,
// ithresh <= 63 and hevT <= 3) fall back to the Go implementation.
func filterParamsInRange(thresh, ithresh, hevT int) bool {
	return thresh >= 0 && thresh <= 30000 &&
		ithresh >= 0 && ithresh <= 255 &&
		hevT >= 0 && hevT <= 255
}

// SimpleVFilter16 applies the simple loop filter vertically across a 16-wide
// edge using NEON.
func SimpleVFilter16(p []byte, base, stride, thresh int) {
	if thresh < 0 || thresh > 30000 {
		simpleVFilter16Go(p, base, stride, thresh)
		return
	}
	simpleVFilter16NEON(p, base, stride, thresh)
}

// VFilter16 applies the complex vertical loop filter across a 16-wide edge.
func VFilter16(p []byte, base, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter16Go(p, base, stride, thresh, ithresh, hevT)
		return
	}
	vFilter16EdgeNEON(p, base, stride, thresh, ithresh, hevT)
}

// VFilter8 applies the complex vertical filter to an 8-wide chroma edge.
// Both planes are filtered in a single NEON pass (U in lanes 0-7, V in
// lanes 8-15).
func VFilter8(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter8Go(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
		return
	}
	vFilter8EdgeNEON(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
}

// VFilter16i applies complex vertical filtering at internal block boundaries.
func VFilter16i(p []byte, base, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter16iGo(p, base, stride, thresh, ithresh, hevT)
		return
	}
	for k := 1; k <= 3; k++ {
		vFilter16InnerNEON(p, base+k*4*stride, stride, thresh, ithresh, hevT)
	}
}

// VFilter8i applies complex vertical filtering at internal 4-row boundaries
// for 8x8 chroma blocks.
func VFilter8i(u, v []byte, uBase, vBase, stride, thresh, ithresh, hevT int) {
	if !filterParamsInRange(thresh, ithresh, hevT) {
		vFilter8iGo(u, v, uBase, vBase, stride, thresh, ithresh, hevT)
		return
	}
	vFilter8InnerNEON(u, v, uBase+4*stride, vBase+4*stride, stride, thresh, ithresh, hevT)
}
