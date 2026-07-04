//go:build !amd64 && !arm64

package dsp

// PredLuma16Direct calls the 16x16 prediction function for the given mode directly.
func PredLuma16Direct(mode int, dst []byte, off int) {
	switch mode {
	case 0:
		dc16(dst, off)
	case 1:
		tm16(dst, off)
	case 2:
		ve16(dst, off)
	case 3:
		he16(dst, off)
	case 4:
		dc16NoTop(dst, off)
	case 5:
		dc16NoLeft(dst, off)
	case 6:
		dc16NoTopLeft(dst, off)
	}
}

// PredChroma8Direct calls the 8x8 chroma prediction function for the given mode directly.
func PredChroma8Direct(mode int, dst []byte, off int) {
	switch mode {
	case 0:
		dc8uv(dst, off)
	case 1:
		tm8uv(dst, off)
	case 2:
		ve8uv(dst, off)
	case 3:
		he8uv(dst, off)
	case 4:
		dc8uvNoTop(dst, off)
	case 5:
		dc8uvNoLeft(dst, off)
	case 6:
		dc8uvNoTopLeft(dst, off)
	}
}

// PredLuma4Direct calls the 4x4 prediction function for the given mode directly
// via a switch statement, avoiding indirect function call overhead.
func PredLuma4Direct(mode int, dst []byte, off int) {
	switch mode {
	case 0:
		dc4(dst, off)
	case 1:
		tm4(dst, off)
	case 2:
		ve4(dst, off)
	case 3:
		he4(dst, off)
	case 4:
		rd4(dst, off)
	case 5:
		vr4(dst, off)
	case 6:
		ld4(dst, off)
	case 7:
		vl4(dst, off)
	case 8:
		hd4(dst, off)
	case 9:
		hu4(dst, off)
	}
}
