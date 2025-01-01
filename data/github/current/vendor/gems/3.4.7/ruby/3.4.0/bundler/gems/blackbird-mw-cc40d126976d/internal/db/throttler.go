package db

import (
	"context"
	"time"

	freno "github.com/github/go-freno-client"
)

// WaitOnThrottler waits until the throttler becomes available or the provided timeout elapses.
func WaitOnThrottler(ctx context.Context, throttler freno.Throttler, timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(ctx, 1*time.Minute)
	defer cancel()
	return freno.WaitOnThrottler(ctx, throttler)
}
