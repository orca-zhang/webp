//go:build arm64

package dsp

// NEON implementations of the VP8L inverse spatial predictors
// (predict_lossless_add_arm64.s). Wired into PredictorsAdd so the lossless
// decoder's predictor inverse transform uses them per tile span.
func init() {
	PredictorsAdd[0] = predictorAdd0NEON
	PredictorsAdd[1] = predictorAdd1NEON
	PredictorsAdd[2] = predictorAdd2NEON
	PredictorsAdd[3] = predictorAdd3NEON
	PredictorsAdd[4] = predictorAdd4NEON
	PredictorsAdd[5] = predictorAdd5NEON
	PredictorsAdd[6] = predictorAdd6NEON
	PredictorsAdd[7] = predictorAdd7NEON
	PredictorsAdd[8] = predictorAdd8NEON
	PredictorsAdd[9] = predictorAdd9NEON
	PredictorsAdd[10] = predictorAdd10NEON
	PredictorsAdd[11] = predictorAdd11NEON
	PredictorsAdd[12] = predictorAdd12NEON
	PredictorsAdd[13] = predictorAdd13NEON
}

//go:noescape
func predictorAdd0NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd1NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd2NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd3NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd4NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd5NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd6NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd7NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd8NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd9NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd10NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd11NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd12NEON(in, upper, out []uint32, n int)

//go:noescape
func predictorAdd13NEON(in, upper, out []uint32, n int)
