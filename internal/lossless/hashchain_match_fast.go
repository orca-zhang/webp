//go:build amd64 || arm64

package lossless

import (
	"math/bits"
	"unsafe"
)

// findMatchLength returns the length of the match between array1 and array2,
// up to maxLimit. If array1[bestLenMatch] != array2[bestLenMatch], returns 0
// immediately as an optimization (the match can't be better than current best).
//
// Fast path for 64-bit little-endian architectures with cheap unaligned
// loads: compares two ARGB pixels (8 bytes) per iteration, like libwebp's
// VP8LVectorMismatch. The XOR of the first differing word locates the
// mismatching pixel without re-comparing.
func findMatchLength(array1, array2 []uint32, bestLenMatch, maxLimit int) int {
	if bestLenMatch < maxLimit && array1[bestLenMatch] != array2[bestLenMatch] {
		return 0
	}
	a1 := array1[:maxLimit]
	a2 := array2[:maxLimit]
	matchLen := 0
	for matchLen+2 <= maxLimit {
		x := *(*uint64)(unsafe.Pointer(&a1[matchLen]))
		y := *(*uint64)(unsafe.Pointer(&a2[matchLen]))
		if x != y {
			// Low 32 bits hold pixel matchLen (little-endian), high 32
			// bits pixel matchLen+1.
			return matchLen + bits.TrailingZeros64(x^y)/32
		}
		matchLen += 2
	}
	if matchLen < maxLimit && a1[matchLen] == a2[matchLen] {
		matchLen++
	}
	return matchLen
}
