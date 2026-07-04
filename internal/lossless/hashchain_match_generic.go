//go:build !amd64 && !arm64

package lossless

// findMatchLength returns the length of the match between array1 and array2,
// up to maxLimit. If array1[bestLenMatch] != array2[bestLenMatch], returns 0
// immediately as an optimization (the match can't be better than current best).
//
// Portable version: 4-way unrolled word comparison with bounds checks
// eliminated by reslicing. 32-bit platforms use this (unaligned 64-bit
// loads are not safe there).
func findMatchLength(array1, array2 []uint32, bestLenMatch, maxLimit int) int {
	if bestLenMatch < maxLimit && array1[bestLenMatch] != array2[bestLenMatch] {
		return 0
	}
	a1 := array1[:maxLimit]
	a2 := array2[:maxLimit]
	matchLen := 0
	for matchLen+4 <= maxLimit {
		if a1[matchLen] != a2[matchLen] {
			return matchLen
		}
		if a1[matchLen+1] != a2[matchLen+1] {
			return matchLen + 1
		}
		if a1[matchLen+2] != a2[matchLen+2] {
			return matchLen + 2
		}
		if a1[matchLen+3] != a2[matchLen+3] {
			return matchLen + 3
		}
		matchLen += 4
	}
	for matchLen < maxLimit && a1[matchLen] == a2[matchLen] {
		matchLen++
	}
	return matchLen
}
