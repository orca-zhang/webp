//go:build !amd64 && !arm64

package dsp

// SimpleVFilter16 applies the simple loop filter vertically across a 16-wide edge.
// On platforms without an assembly implementation, uses the pure Go implementation.
func SimpleVFilter16(p []byte, base, stride, thresh int) {
	simpleVFilter16Go(p, base, stride, thresh)
}

// VFilter16 applies the complex vertical loop filter across a 16-wide edge.
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
