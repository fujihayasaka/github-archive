package aqueduct

import (
	"math"
	"math/rand"
)

type RetryBackoffFunc func(retryCount uint8) float64

var DefaultRetryBackoffFunc = func(retryCount uint8) float64 {
	// Same algorithm as in ActiveJob
	// first wait  ~3s, then ~18s, then ~83s, etc
	p := math.Pow(float64(retryCount), 4)
	secs := (p + (rand.Float64() * p * 0.42)) + 2

	return secs
}

var SuggestedFixAlertGenerateJobRetryBackoffFunc = func(retryCount uint8) float64 {
	// first wait  ~2s, then ~4s, then ~8s, etc
	p := math.Pow(2, float64(retryCount))
	secs := (p + (rand.Float64() * p * 0.42))

	return secs
}
