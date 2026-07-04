//go:build arm64

package dsp

func init() {
	ConvertARGBToRGBABatch = convertARGBToRGBANEON
}

//go:noescape
func convertARGBToRGBANEON(src []uint32, dst []byte, n int)
