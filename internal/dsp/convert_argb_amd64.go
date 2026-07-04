//go:build amd64

package dsp

func init() {
	ConvertARGBToRGBABatch = convertARGBToRGBASSE2
}

//go:noescape
func convertARGBToRGBASSE2(src []uint32, dst []byte, n int)
