//go:build amd64

package dsp

func init() {
	TransformColorInverseBatch = transformColorInverseSSE2Batch
}

// transformColorInverseSSE2Batch packs the tile multipliers into the vector
// constants the assembly expects: each multiplier is sign-extended to 16
// bits and pre-scaled by 8 so PMULHW ((a*b)>>16) against v<<8 yields
// floor(int8(v)*int8(m)/32), the scalar (m*v)>>5.
func transformColorInverseSSE2Batch(g2r, g2b, r2b int8, src, dst []uint32, n int) {
	cstG2R := uint32(uint16(int16(g2r) << 3))
	cstG2B := uint32(uint16(int16(g2b) << 3))
	cstR2B := uint32(uint16(int16(r2b) << 3))
	transformColorInverseSSE2(cstG2R<<16|cstG2B, cstR2B<<16, src, dst, n)
}

//go:noescape
func transformColorInverseSSE2(multsRB, multsB2 uint32, src, dst []uint32, n int)
