package dsp

// Batch inverse cross-color transform (VP8L decoder hot path).
//
// For each pixel, with tile multipliers g2r, g2b, r2b (signed 8-bit):
//   red  += (g2r * int8(green)) >> 5              (mod 256)
//   blue += (g2b * int8(green)) >> 5
//   blue += (r2b * int8(new red)) >> 5            (mod 256)
// Alpha and green are unchanged. Mirrors TransformColorInverse from
// libwebp (src/dsp/lossless_neon.c / lossless_sse2.c).

// TransformColorInverseBatchFunc applies the inverse cross-color transform
// to n pixels. src and dst may be the same slice (the decoder transforms in
// place); implementations must read src[i] before writing dst[i].
type TransformColorInverseBatchFunc func(g2r, g2b, r2b int8, src, dst []uint32, n int)

// TransformColorInverseBatch is the accelerated implementation, or nil when
// none exists for this platform (callers fall back to their scalar loop).
var TransformColorInverseBatch TransformColorInverseBatchFunc

// transformColorInverseGo is the scalar reference used by conformance tests
// and benchmarks. It matches the inline loop in
// internal/lossless.colorSpaceInverseTransform bit for bit.
func transformColorInverseGo(g2r, g2b, r2b int8, src, dst []uint32, n int) {
	for i := 0; i < n; i++ {
		argb := src[i]
		green := int32(int8(argb >> 8))
		red := int32((argb >> 16) & 0xff)
		blue := int32(argb & 0xff)

		red += (int32(g2r) * green) >> 5
		red &= 0xff
		blue += (int32(g2b) * green) >> 5
		blue += (int32(r2b) * int32(int8(red))) >> 5
		blue &= 0xff

		dst[i] = (argb & 0xff00ff00) | (uint32(red) << 16) | uint32(blue)
	}
}
