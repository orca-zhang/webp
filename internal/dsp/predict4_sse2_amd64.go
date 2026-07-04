//go:build amd64

package dsp

// This init wires the 4x4 luma predictor table to the SSE2 kernels in
// predict4_sse2_amd64.s. It runs after dsp.go's init (which fills the tables
// with the scalar Go implementations) due to alphabetical file ordering,
// mirroring what dsp_arm64.go does for NEON. It is kept separate from
// dsp_amd64.go so the 4x4 predictor wiring lives next to its stubs.
func init() {
	// 4x4 luma prediction modes (all 10 in SSE2; see PredLuma4Direct in
	// predict_lossy_direct_amd64.go).
	PredLuma4[0] = dc4asmSSE2
	PredLuma4[1] = tm4asmSSE2
	PredLuma4[2] = ve4asmSSE2
	PredLuma4[3] = he4asmSSE2
	PredLuma4[4] = rd4asmSSE2
	PredLuma4[5] = vr4asmSSE2
	PredLuma4[6] = ld4asmSSE2
	PredLuma4[7] = vl4asmSSE2
	PredLuma4[8] = hd4asmSSE2
	PredLuma4[9] = hu4asmSSE2
}

// --- SSE2 assembly function stubs (predict4_sse2_amd64.s) ---

//go:noescape
func dc4asmSSE2(dst []byte, off int)

//go:noescape
func tm4asmSSE2(dst []byte, off int)

//go:noescape
func ve4asmSSE2(dst []byte, off int)

//go:noescape
func he4asmSSE2(dst []byte, off int)

//go:noescape
func rd4asmSSE2(dst []byte, off int)

//go:noescape
func vr4asmSSE2(dst []byte, off int)

//go:noescape
func ld4asmSSE2(dst []byte, off int)

//go:noescape
func vl4asmSSE2(dst []byte, off int)

//go:noescape
func hd4asmSSE2(dst []byte, off int)

//go:noescape
func hu4asmSSE2(dst []byte, off int)
