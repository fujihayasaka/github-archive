package workerpool

import (
	"context"
	"time"

	"github.com/github/launch/observability/logger"
)

// Workers is a manager of worker threads.
type Workers interface {
	// Run runs job in a background thread, logs about it, and reports metrics for it.
	Run(ctx context.Context, jobName string, job JobFunc) error
	// Periodically runs a job in a background thread with the given interval.
	Periodically(interval time.Duration, jobName string, job JobFunc)
	// Stop waits for all running jobs to shut down.
	Stop()
	// Active indicates how many workers are currently active
	Active() int64

	// done is closed when the pool is shutting down.
	done() <-chan struct{}
	// logger exposes a logger.Logger.
	logger() logger.Logger
}
