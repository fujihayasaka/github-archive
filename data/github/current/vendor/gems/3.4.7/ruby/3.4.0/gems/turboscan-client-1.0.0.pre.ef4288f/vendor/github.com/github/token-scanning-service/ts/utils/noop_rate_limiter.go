package utils

import (
	"time"
)

// This is a noop implementation of ratelimit.Limiter.
// Use this in tests to verify that we're rate limiting correctly.
type NoopRateLimiter struct {
	callCount int
}

func NewNoopRateLimiter() *NoopRateLimiter {
	return &NoopRateLimiter{
		callCount: 0,
	}
}

func (n *NoopRateLimiter) Take() time.Time {
	n.callCount++
	return time.Now()
}

func (n *NoopRateLimiter) GetCallCount() int {
	return n.callCount
}
