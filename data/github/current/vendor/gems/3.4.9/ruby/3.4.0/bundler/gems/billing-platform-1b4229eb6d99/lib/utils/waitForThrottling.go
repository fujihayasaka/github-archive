package utils

import (
	"math/rand/v2"
	"time"
)

func WaitForThrottling(retryAttempt int, jitter bool) {
	baseTime := 500
	if jitter {
		baseTime = getRandomInt(500, 3000)
	}
	n := baseTime * retryAttempt
	time.Sleep(time.Duration(n) * time.Millisecond)
}

func getRandomInt(min int, max int) int {
	return rand.IntN(max-min) + min
}
