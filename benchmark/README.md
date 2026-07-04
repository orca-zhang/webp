# WebP Go Libraries Benchmark

Comparative benchmark of Go WebP libraries on a 1536x1024 RGB image (Apple M5 Max, arm64, Go 1.24.2).

Last updated: 2026-07-04 (10-run benchmark)

## Libraries Compared

| Library | Type | Lossy Encode | Lossless Encode | Decode |
|---------|------|:---:|:---:|:---:|
| [deepteams/webp](https://github.com/deepteams/webp) | Pure Go | Yes | Yes | Yes |
| [golang.org/x/image/webp](https://pkg.go.dev/golang.org/x/image/webp) | Pure Go | - | - | Yes |
| [gen2brain/webp](https://github.com/gen2brain/webp) | WASM (wazero) | Yes | Yes | Yes |
| [HugoSmits86/nativewebp](https://github.com/HugoSmits86/nativewebp) | Pure Go | - | Lossless | Yes |
| [chai2010/webp](https://github.com/chai2010/webp) | CGo (libwebp 1.0.2) | Yes | Yes | Yes |

## Results

All values are **medians of 10 runs** (`-count=10`). Provides more reliable statistics and captures variance.

### Encode Lossy (Quality 75, 1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| **deepteams/webp** (Pure Go) | **47.2** | 4.1 | 1.2 MB | 174 |
| gen2brain/webp (WASM) | 54.9 | 4.6 | 13 KB | 12 |
| chai2010/webp (CGo) | 73.2 | 2.9 | 222 KB | 4 |

### Encode Lossless (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|------:|-------:|
| **deepteams/webp** (Pure Go) | **114** | 16.1 | 20.1 MB | 1,177 |
| gen2brain/webp (WASM) | 180 | 11.4 | 335 KB | 12 |
| nativewebp (Pure Go) | 272 | 7.4 | 85 MB | 2,155 |
| chai2010/webp (CGo) | 899 | 1.9 | 2.5 MB | 4 |

### Decode Lossy (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| **deepteams/webp** (Pure Go) | **9.0** | 21.4 | 2.5 MB | 7 |
| chai2010/webp (CGo) | 9.4 | 22.4 | 6.4 MB | 23 |
| golang.org/x/image/webp | 17.8 | 10.8 | 2.5 MB | 13 |
| gen2brain/webp (WASM) | 21.9 | 11.6 | 608 KB | 40 |

### Decode Lossless (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| chai2010/webp (CGo) | **19.5** | 91.5 | 10.2 MB | 30 |
| **deepteams/webp** (Pure Go) | **20.0** | 91.3 | 7.9 MB | 226 |
| gen2brain/webp (WASM) | 34.3 | 60.2 | 4.4 MB | 46 |
| nativewebp (Pure Go) | 36.7 | 54.9 | 6.1 MB | 50 |
| golang.org/x/image/webp | 39.4 | 45.2 | 6.8 MB | 966 |

Note: each library decodes its own encoder's output. When decoding the *same* bitstream, deepteams/webp and chai2010 CGo are at statistical parity (19.8 vs 19.8 ms on the deepteams-encoded file).

### Encode Lossy Small (Quality 75, 256x256)

| Library | Time (ms) | B/op | Allocs |
|---------|----------:|-----:|-------:|
| gen2brain/webp (WASM) | **2.2** | 257 B | 12 |
| **deepteams/webp** (Pure Go) | **2.4** | 31 KB | 127 |
| chai2010/webp (CGo) | 4.1 | 776 KB | 131,077 |

## Key Takeaways

1. **Fastest lossy encoder overall**: deepteams/webp (47.2ms) is the fastest lossy encoder, 14% faster than gen2brain WASM (54.9ms) and 36% faster than chai2010 CGo (73.2ms). Uses only 1.2 MB per encode with 174 allocs.

2. **Fastest lossless encoder overall**: deepteams/webp lossless encode (114ms) is 37% faster than gen2brain WASM (180ms), 2.4x faster than nativewebp, and 7.9x faster than chai2010 CGo. Best compression among pure Go (1.8 MB compressed output).

3. **Fastest lossy decoder overall**: deepteams/webp lossy decode (9.0ms) beats chai2010 CGo (9.4ms) thanks to NEON loop filters and predictors on arm64, and is 2.0x faster than x/image/webp and 2.4x faster than gen2brain WASM. Lowest memory (2.5 MB) and fewest allocs (7) of any decoder — and `webp.DecodeReuse` drops steady-state decode allocations to a few KB by recycling the output buffers.

4. **Fastest pure Go lossless decoder**: deepteams/webp lossless decode (20.0ms) is 42% faster than gen2brain, 45% faster than nativewebp, and 49% faster than x/image — within 3% of chai2010 CGo, and at statistical parity with it on identical bitstreams thanks to NEON inverse transforms (predictors, cross-color, ARGB conversion).

5. **Consistent performance**: 10-run medians show deepteams/webp is stable (low variance) across lossy/lossless encoding and decoding, with only minor outliers under system contention.

6. **Efficient memory on small images**: On 256x256 images, deepteams/webp uses only 32 KB and 127 allocs, vs chai2010/webp which requires 776 KB and 131,077 allocs due to CGo initialization overhead.

7. **Pure Go, no external runtime**: deepteams/webp and nativewebp are the only libraries working without CGo or WASM runtimes. Cross-compilation is trivial.

8. **Complete feature set**: deepteams/webp is the only pure Go library supporting both lossy and lossless encoding + decoding, plus animation, alpha, metadata, and VP8X extended format.

## Running

```bash
cd benchmark
go test -bench=. -benchmem -count=10 -run=^$ -timeout=30m

# Without CGo (skip chai2010/webp):
CGO_ENABLED=0 go test -bench=. -benchmem -count=10 -run=^$ -timeout=30m

# File size comparison:
go test -v -run=TestFileSizes -count=1
```
