//go:build amd64

package dsp

// SSE2 implementations of the VP8L inverse spatial predictors
// (predict_lossless_add_amd64.s). Wired into PredictorsAdd so the lossless
// decoder's predictor inverse transform uses them per tile span. SSE2 is
// part of the amd64 baseline, so no CPUID gating is needed.
func init() {
	PredictorsAdd[0] = predictorAdd0SSE2
	PredictorsAdd[1] = predictorAdd1SSE2
	PredictorsAdd[2] = predictorAdd2SSE2
	PredictorsAdd[3] = predictorAdd3SSE2
	PredictorsAdd[4] = predictorAdd4SSE2
	PredictorsAdd[5] = predictorAdd5SSE2
	PredictorsAdd[6] = predictorAdd6SSE2
	PredictorsAdd[7] = predictorAdd7SSE2
	PredictorsAdd[8] = predictorAdd8SSE2
	PredictorsAdd[9] = predictorAdd9SSE2
	PredictorsAdd[10] = predictorAdd10SSE2
	PredictorsAdd[11] = predictorAdd11SSE2
	PredictorsAdd[12] = predictorAdd12SSE2
	PredictorsAdd[13] = predictorAdd13SSE2
}

//go:noescape
func predictorAdd0SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd1SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd2SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd3SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd4SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd5SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd6SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd7SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd8SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd9SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd10SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd11SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd12SSE2(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd13SSE2(in, upper, out []uint32, n int)
