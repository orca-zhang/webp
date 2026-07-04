package lossless

import "testing"

// benchPaletteImage builds a 640x480 ARGB image with nColors distinct colors
// arranged in flat regions, like typical icons/graphics.
func benchPaletteImage(nColors int) []uint32 {
	argb := make([]uint32, 640*480)
	for y := 0; y < 480; y++ {
		for x := 0; x < 640; x++ {
			c := uint32((x/40 + y/60*16) % nColors)
			argb[y*640+x] = 0xff000000 | c<<16 | (255-c)<<8 | c*3
		}
	}
	return argb
}

func BenchmarkColorIndexBuild(b *testing.B) {
	argb := benchPaletteImage(200)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, ok := ColorIndexBuild(argb, 640, 480)
		if !ok {
			b.Fatal("expected palette")
		}
	}
}

func BenchmarkApplyPaletteTransform(b *testing.B) {
	argb := benchPaletteImage(200)
	palette, _, ok := ColorIndexBuild(argb, 640, 480)
	if !ok {
		b.Fatal("expected palette")
	}
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ApplyPaletteTransform(argb, 640, 480, palette)
	}
}
