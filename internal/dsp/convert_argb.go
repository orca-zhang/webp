package dsp

// ConvertARGBToRGBABatch converts n ARGB uint32 pixels to interleaved RGBA
// bytes (same layout as ConvertBGRAToRGBA, which is the scalar reference).
// nil when no accelerated implementation exists for this platform.
var ConvertARGBToRGBABatch func(src []uint32, dst []byte, n int)
