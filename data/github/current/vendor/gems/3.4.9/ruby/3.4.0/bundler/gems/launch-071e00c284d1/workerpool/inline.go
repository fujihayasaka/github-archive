package workerpool

import (
	"context"
	"time"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

// NewInline creates a worker that runs the given job inline, before returning.
func NewInline(log logger.Logger, statter statter.Statter) Workers {
	i := &inline{
		log:   log,
		stats: statter,
		_done: make(chan struct{}),
	}
	return i
}

type inline struct {
	log   logger.Logger
	stats statter.Statter

	_done chan struct{}
}

// Active for inline worker pool will always return -1
func (i *inline) Active() int64 {
	return -1
}

func (i *inline) Run(ctx context.Context, jobName string, job JobFunc) error {
	run(ctx, i.log, i.stats, jobName, job)

	// run reports its own errors, so this job can return nil because "hey,
	// i started your func, that's all that matters here."
	return nil
}

func (i *inline) Periodically(interval time.Duration, jobName string, job JobFunc) {
	go runPeriodically(i, interval, jobName, job)
}

func (i *inline) Stop() {
	close(i._done)
}

func (i *inline) done() <-chan struct{} {
	return i._done
}

func (i *inline) logger() logger.Logger {
	return i.log
}
