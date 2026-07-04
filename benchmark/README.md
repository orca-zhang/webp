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
| **deepteams/webp** (Pure Go) | **47.8** | 4.0 | 1.2 MB | 166 |
| gen2brain/webp (WASM) | 56.9 | 4.4 | 13 KB | 12 |
| chai2010/webp (CGo) | 76.4 | 2.7 | 222 KB | 4 |

### Encode Lossless (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|------:|-------:|
| **deepteams/webp** (Pure Go) | **116** | 15.8 | 20.1 MB | 1,177 |
| gen2brain/webp (WASM) | 187 | 11.0 | 335 KB | 12 |
| nativewebp (Pure Go) | 280 | 7.2 | 85 MB | 2,155 |
| chai2010/webp (CGo) | 929 | 1.9 | 2.5 MB | 4 |

### Decode Lossy (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| **deepteams/webp** (Pure Go) | **9.3** | 20.7 | 2.5 MB | 7 |
| chai2010/webp (CGo) | 9.6 | 21.8 | 6.4 MB | 23 |
| golang.org/x/image/webp | 18.4 | 10.5 | 2.5 MB | 13 |
| gen2brain/webp (WASM) | 22.2 | 11.4 | 608 KB | 40 |

### Decode Lossless (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| **deepteams/webp** (Pure Go) | **17.0** | 107.3 | 8.3 MB | 225 |
| chai2010/webp (CGo) | 19.2 | 91.3 | 10.2 MB | 30 |
| gen2brain/webp (WASM) | 34.0 | 60.4 | 4.4 MB | 46 |
| nativewebp (Pure Go) | 35.6 | 56.5 | 6.1 MB | 50 |
| golang.org/x/image/webp | 38.7 | 47.3 | 6.8 MB | 966 |

### Encode Lossy Small (Quality 75, 256x256)

| Library | Time (ms) | B/op | Allocs |
|---------|----------:|-----:|-------:|
| gen2brain/webp (WASM) | **2.2** | 257 B | 12 |
| **deepteams/webp** (Pure Go) | **2.4** | 31 KB | 127 |
| chai2010/webp (CGo) | 3.9 | 776 KB | 131,077 |

## Key Takeaways

1. **Fastest lossy encoder overall**: deepteams/webp (47.8ms) is the fastest lossy encoder, 16% faster than gen2brain WASM (56.9ms) and 37% faster than chai2010 CGo (76.4ms). Uses only 1.2 MB per encode with 166 allocs.

2. **Fastest lossless encoder overall**: deepteams/webp lossless encode (116ms) is 38% faster than gen2brain WASM (187ms), 2.4x faster than nativewebp, and 8.0x faster than chai2010 CGo. Best compression among pure Go (1.8 MB compressed output).

3. **Fastest lossy decoder overall**: deepteams/webp lossy decode (9.3ms) beats chai2010 CGo (9.6ms) thanks to NEON loop filters and predictors on arm64, and is 2.0x faster than x/image/webp and 2.4x faster than gen2brain WASM. Lowest memory (2.5 MB) and fewest allocs (7) of any decoder — and `webp.DecodeReuse` drops steady-state decode allocations to a few KB by recycling the output buffers.

4. **Fastest lossless decoder overall**: deepteams/webp lossless decode (17.0ms) beats chai2010 CGo (19.2ms) by 11%, and is 2.0x faster than gen2brain, 2.1x faster than nativewebp, and 2.3x faster than x/image — thanks to SIMD inverse transforms (predictors, cross-color, ARGB conversion) and a register-resident entropy decoding loop.

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
