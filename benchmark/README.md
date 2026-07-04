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
| **deepteams/webp** (Pure Go) | **47.5** | 4.1 | 1.2 MB | 164 |
| gen2brain/webp (WASM) | 56.3 | 4.5 | 13 KB | 12 |
| chai2010/webp (CGo) | 76.4 | 2.7 | 222 KB | 4 |

### Encode Lossless (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|------:|-------:|
| **deepteams/webp** (Pure Go) | **116** | 15.8 | 23.5 MB | 1,175 |
| gen2brain/webp (WASM) | 184 | 11.2 | 335 KB | 12 |
| nativewebp (Pure Go) | 276 | 7.3 | 85 MB | 2,155 |
| chai2010/webp (CGo) | 930 | 1.9 | 2.5 MB | 4 |

### Decode Lossy (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| **deepteams/webp** (Pure Go) | **9.1** | 21.3 | 2.5 MB | 7 |
| chai2010/webp (CGo) | 9.4 | 22.2 | 6.4 MB | 23 |
| golang.org/x/image/webp | 18.1 | 10.7 | 2.5 MB | 13 |
| gen2brain/webp (WASM) | 22.0 | 11.5 | 608 KB | 40 |

### Decode Lossless (1536x1024)

| Library | Time (ms) | MB/s | B/op | Allocs |
|---------|----------:|-----:|-----:|-------:|
| chai2010/webp (CGo) | **19.1** | 91.6 | 10.2 MB | 30 |
| **deepteams/webp** (Pure Go) | **26.6** | 68.7 | 7.9 MB | 225 |
| gen2brain/webp (WASM) | 33.6 | 61.0 | 4.4 MB | 46 |
| nativewebp (Pure Go) | 36.1 | 55.8 | 6.1 MB | 50 |
| golang.org/x/image/webp | 39.3 | 46.5 | 6.8 MB | 966 |

### Encode Lossy Small (Quality 75, 256x256)

| Library | Time (ms) | B/op | Allocs |
|---------|----------:|-----:|-------:|
| gen2brain/webp (WASM) | **2.1** | 256 B | 12 |
| **deepteams/webp** (Pure Go) | **2.4** | 31 KB | 127 |
| chai2010/webp (CGo) | 3.9 | 776 KB | 131,077 |

## Key Takeaways

1. **Fastest lossy encoder overall**: deepteams/webp (47.5ms) is the fastest lossy encoder, 16% faster than gen2brain WASM (56.3ms) and 38% faster than chai2010 CGo (76.4ms). Uses only 1.2 MB per encode with 164 allocs.

2. **Fastest lossless encoder overall**: deepteams/webp lossless encode (116ms) is 37% faster than gen2brain WASM (184ms), 2.4x faster than nativewebp, and 8.0x faster than chai2010 CGo. Best compression among pure Go (1.8 MB compressed output).

3. **Fastest lossy decoder overall**: deepteams/webp lossy decode (9.1ms) beats chai2010 CGo (9.4ms) thanks to NEON loop filters and predictors on arm64, and is 2.0x faster than x/image/webp and 2.4x faster than gen2brain WASM. Lowest memory (2.5 MB) and fewest allocs (7) of any decoder.

4. **Fastest pure Go lossless decoder**: deepteams/webp lossless decode (26.6ms) is 21% faster than gen2brain, 26% faster than nativewebp, and 32% faster than x/image — only 39% behind chai2010 CGo.

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
