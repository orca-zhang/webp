package lossless

import (
	"math/rand"
	"testing"
)

// findMatchLengthRef is the straightforward reference implementation.
func findMatchLengthRef(array1, array2 []uint32, bestLenMatch, maxLimit int) int {
	if bestLenMatch < maxLimit && array1[bestLenMatch] != array2[bestLenMatch] {
		return 0
	}
	matchLen := 0
	for matchLen < maxLimit && array1[matchLen] == array2[matchLen] {
		matchLen++
	}
	return matchLen
}

func TestFindMatchLengthMatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(42))
	const maxN = 300
	for trial := 0; trial < 5000; trial++ {
		n := 1 + rng.Intn(maxN)
		a1 := make([]uint32, n)
		a2 := make([]uint32, n)
		for i := range a1 {
			// Small value range so random prefixes often match.
			a1[i] = uint32(rng.Intn(3))
			a2[i] = uint32(rng.Intn(3))
		}
		// Half the trials: force a long common prefix with a controlled
		// mismatch position to exercise every word-offset case.
		if trial%2 == 0 {
			copy(a2, a1)
			if mismatch := rng.Intn(n + 1); mismatch < n {
				a2[mismatch] ^= 1 + uint32(rng.Intn(0xffff))
			}
		}
		maxLimit := 1 + rng.Intn(n)
		bestLenMatch := rng.Intn(maxLimit + 1)

		want := findMatchLengthRef(a1, a2, bestLenMatch, maxLimit)
		got := findMatchLength(a1, a2, bestLenMatch, maxLimit)
		if got != want {
			t.Fatalf("trial %d: findMatchLength=%d, want %d (n=%d maxLimit=%d bestLenMatch=%d)",
				trial, got, want, n, maxLimit, bestLenMatch)
		}
	}
}
