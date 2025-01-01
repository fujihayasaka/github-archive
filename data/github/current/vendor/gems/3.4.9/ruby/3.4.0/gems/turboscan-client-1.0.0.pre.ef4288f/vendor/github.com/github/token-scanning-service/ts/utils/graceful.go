package utils

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// NewGracefulContext spins up a new background context that will be cancelled gracefulDuration after
// the global context is cancelled. Callers should be mindful to always call the returned context.CancelFunc so it does not leak.
// !!NOTE!! Values from the passed in globalContext **will not** be included in the returned graceful context.
func NewGracefulContext(globalCtx context.Context, graceTimeout time.Duration, logger log.Logger) (context.Context, context.CancelFunc) {
	gracefulCtx, cancelGracefulCtx := context.WithCancel(context.Background())

	go func() {
		select {
		case <-globalCtx.Done():
			startShutdown := time.Now()
			logger.Info("global context cancelled; sleeping until graceful context is itself cancelled", kvp.Float64("graceful_duration_sec", graceTimeout.Seconds()))
			// wait for all the jobs to complete, or
			select {
			case <-gracefulCtx.Done():
				// happy path
				logger.Info("graceful context cancelled externally, did not timeout", kvp.Int64("time_waited_ms", time.Since(startShutdown).Milliseconds()))
			case <-time.After(graceTimeout):
				cancelGracefulCtx()
				logger.Info("timed out waiting for caller to gracefully cancel the context context cancellation, had to force cancellation", kvp.Int64("time_waited_ms", time.Since(startShutdown).Milliseconds()))
			}
		case <-gracefulCtx.Done():
			// noop
		}
	}()

	return gracefulCtx, cancelGracefulCtx
}
