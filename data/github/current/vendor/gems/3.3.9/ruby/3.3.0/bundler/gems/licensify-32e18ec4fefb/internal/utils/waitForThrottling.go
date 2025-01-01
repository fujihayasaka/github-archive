// Package utils contains Various utility functions
package utils

import (
	"crypto/rand"
	"math/big"
	"time"
)

// WaitForThrottling is used to control rate of cosmos retries
func WaitForThrottling(retryAttempt int, jitter bool) {
	baseTime := 500
	if jitter {
		baseTime = getRandomInt(500, 3000)
	}
	n := baseTime * retryAttempt
	time.Sleep(time.Duration(n) * time.Millisecond)
}

// getRandomInt gets a random int within a range
func getRandomInt(minInt, maxInt int) int {
	rangeMax := maxInt - minInt
	randInt, _ := rand.Int(rand.Reader, big.NewInt(int64(rangeMax)))
	return int(randInt.Int64() + int64(minInt))
}
