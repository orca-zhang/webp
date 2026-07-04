package lossless

import (
	"math"
	"math/rand"
	"testing"
)

// estimateEntropyRef is the former per-mode implementation, kept as a
// reference to prove bestPredictorForTile selects identical modes.
func estimateEntropyRef(argb []uint32, width, height, tx, ty, bits, mode int) float64 {
	tileSize := 1 << bits
	xStart := tx * tileSize
	yStart := ty * tileSize
	xEnd := xStart + tileSize
	if xEnd > width {
		xEnd = width
	}
	yEnd := yStart + tileSize
	if yEnd > height {
		yEnd = height
	}
	yStep := 1
	if yEnd-yStart > 16 {
		yStep = 2
	}
	var histogram [4 * 256]uint32
	count := uint32(0)
	for y := yStart; y < yEnd; y += yStep {
		for x := xStart; x < xEnd; x++ {
			px := argb[y*width+x]
			var left, top, topRight, topLeft uint32
			if x > 0 {
				left = argb[y*width+x-1]
			}
			if y > 0 {
				top = argb[(y-1)*width+x]
				if x > 0 {
					topLeft = argb[(y-1)*width+x-1]
				}
				if x < width-1 {
					topRight = argb[(y-1)*width+x+1]
				} else {
					topRight = top
				}
			}
			residual := subPixels(px, predictPixel(mode, left, top, topRight, topLeft))
			histogram[0*256+int((residual>>24)&0xff)]++
			histogram[1*256+int((residual>>16)&0xff)]++
			histogram[2*256+int((residual>>8)&0xff)]++
			histogram[3*256+int(residual&0xff)]++
			count++
		}
	}
	if count == 0 {
		return 0
	}
	entropy := 0.0
	for ch := 0; ch < 4; ch++ {
		channelEntropy := fastSLog2(count)
		base := ch * 256
		for i := 0; i < 256; i++ {
			if histogram[base+i] > 0 {
				channelEntropy -= fastSLog2(histogram[base+i])
			}
		}
		entropy += channelEntropy
	}
	return entropy
}

func TestBestPredictorForTileMatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(7))
	for trial := 0; trial < 200; trial++ {
		width := 1 + rng.Intn(70)
		height := 1 + rng.Intn(70)
		argb := make([]uint32, width*height)
		for i := range argb {
			// Correlated pixels so predictor modes actually differ in cost.
			if i > 0 && rng.Intn(3) > 0 {
				argb[i] = argb[i-1] + uint32(rng.Intn(5))
			} else {
				argb[i] = rng.Uint32()
			}
		}
		bits := 2 + rng.Intn(4) // tile sizes 4..32
		maxMode := []int{4, 8, numPredictors}[rng.Intn(3)]
		tileXSize := VP8LSubSampleSize(width, bits)
		tileYSize := VP8LSubSampleSize(height, bits)
		histos := make([]uint32, maxMode*1024)

		for ty := 0; ty < tileYSize; ty++ {
			for tx := 0; tx < tileXSize; tx++ {
				wantMode := 0
				wantCost := math.MaxFloat64
				for mode := 0; mode < maxMode; mode++ {
					cost := estimateEntropyRef(argb, width, height, tx, ty, bits, mode)
					if cost < wantCost {
						wantCost = cost
						wantMode = mode
					}
				}
				got := bestPredictorForTile(argb, width, height, tx, ty, bits, maxMode, histos)
				if got != wantMode {
					t.Fatalf("trial %d tile(%d,%d): got mode %d, want %d (w=%d h=%d bits=%d maxMode=%d)",
						trial, tx, ty, got, wantMode, width, height, bits, maxMode)
				}
			}
		}
	}
}

func benchTileImage(width, height int) []uint32 {
	rng := rand.New(rand.NewSource(99))
	argb := make([]uint32, width*height)
	for i := range argb {
		if i > 0 && rng.Intn(3) > 0 {
			argb[i] = argb[i-1] + uint32(rng.Intn(5))
		} else {
			argb[i] = rng.Uint32()
		}
	}
	return argb
}

func BenchmarkBestPredictorForTile(b *testing.B) {
	const width, height, bits = 256, 256, 4
	argb := benchTileImage(width, height)
	histos := make([]uint32, numPredictors*1024)
	tileXSize := VP8LSubSampleSize(width, bits)
	tileYSize := VP8LSubSampleSize(height, bits)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for ty := 0; ty < tileYSize; ty++ {
			for tx := 0; tx < tileXSize; tx++ {
				bestPredictorForTile(argb, width, height, tx, ty, bits, numPredictors, histos)
			}
		}
	}
}

func BenchmarkBestPredictorForTileRef(b *testing.B) {
	const width, height, bits = 256, 256, 4
	argb := benchTileImage(width, height)
	tileXSize := VP8LSubSampleSize(width, bits)
	tileYSize := VP8LSubSampleSize(height, bits)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		for ty := 0; ty < tileYSize; ty++ {
			for tx := 0; tx < tileXSize; tx++ {
				best := 0
				bestCost := math.MaxFloat64
				for mode := 0; mode < numPredictors; mode++ {
					cost := estimateEntropyRef(argb, width, height, tx, ty, bits, mode)
					if cost < bestCost {
						bestCost = cost
						best = mode
					}
				}
				_ = best
			}
		}
	}
}
