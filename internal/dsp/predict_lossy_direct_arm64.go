//go:build arm64

package dsp

// PredLuma16Direct calls the 16x16 prediction function for the given mode.
// On ARM64, modes 0-3 dispatch to NEON assembly for ~2-4x speedup over scalar Go.
// Modes 4-6 (boundary cases) remain pure Go since they are rarely called.
func PredLuma16Direct(mode int, dst []byte, off int) {
	switch mode {
	case 0:
		dc16asmNEON(dst, off)
	case 1:
		tm16asmNEON(dst, off)
	case 2:
		ve16asmNEON(dst, off)
	case 3:
		he16asmNEON(dst, off)
	case 4:
		dc16NoTop(dst, off)
	case 5:
		dc16NoLeft(dst, off)
	case 6:
		dc16NoTopLeft(dst, off)
	}
}

// PredChroma8Direct calls the 8x8 chroma prediction function for the given mode.
// On ARM64, modes 0-3 dispatch to NEON assembly.
func PredChroma8Direct(mode int, dst []byte, off int) {
	switch mode {
	case 0:
		dc8uvasmNEON(dst, off)
	case 1:
		tm8uvasmNEON(dst, off)
	case 2:
		ve8uvasmNEON(dst, off)
	case 3:
		he8uvasmNEON(dst, off)
	case 4:
		dc8uvNoTop(dst, off)
	case 5:
		dc8uvNoLeft(dst, off)
	case 6:
		dc8uvNoTopLeft(dst, off)
	}
}

// PredLuma4Direct calls the 4x4 prediction function for the given mode.
// On ARM64 all 10 modes dispatch to NEON assembly. Unlike FTransform (where
// NEON lost to scalar Go due to strided byte-packing overhead), the 4x4
// predictors win across the board because inputs are small (one contiguous
// 8-byte top row and/or 4 left bytes) and each output row is a single 32-bit
// store. Measured on Apple M5 Max (2026-07-04), scalar Go vs NEON:
//   DC4 7.4->2.2ns, TM4 12.8->2.5ns, VE4 6.9->1.9ns, HE4 7.3->2.0ns,
//   RD4 3.5->2.5ns, VR4 3.7->2.3ns, LD4 3.5->1.9ns, VL4 3.6->1.9ns,
//   HD4 3.7->2.4ns, HU4 3.0->2.2ns.
//
// A libwebp-style Intra4Preds_NEON ("all 10 modes in one call", enc_neon.c)
// was considered for the encoder RD pre-screen loop but not wired: it needs a
// separate strided scratch layout plus changes to every pick-I4-mode call
// site in internal/lossy, while the remaining per-block prediction cost with
// per-mode NEON is already ~22ns for all 10 modes (vs ~55ns scalar) and is
// dwarfed by the SSE/FTransform/quantize work in the same loop.
func PredLuma4Direct(mode int, dst []byte, off int) {
	switch mode {
	case 0:
		dc4asmNEON(dst, off)
	case 1:
		tm4asmNEON(dst, off)
	case 2:
		ve4asmNEON(dst, off)
	case 3:
		he4asmNEON(dst, off)
	case 4:
		rd4asmNEON(dst, off)
	case 5:
		vr4asmNEON(dst, off)
	case 6:
		ld4asmNEON(dst, off)
	case 7:
		vl4asmNEON(dst, off)
	case 8:
		hd4asmNEON(dst, off)
	case 9:
		hu4asmNEON(dst, off)
	}
}
