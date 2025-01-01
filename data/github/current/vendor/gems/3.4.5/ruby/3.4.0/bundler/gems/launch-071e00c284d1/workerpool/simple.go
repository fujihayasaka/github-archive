package workerpool

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/utils/appcontext"
)

// NewSimple creates a worker that always spins up a new goroutine for every job.
// Note: since statter.Periodically never completes, Simple worker pools will
// not be garbage collected until the statter is.
func NewSimple(log logger.Logger, stats statter.Statter) *Simple {
	s := &Simple{
		log:   log,
		stats: stats,
		tags:  statter.Tags{workerTypeKey: "simple", "host": mu.AppHost()},
		_done: make(chan struct{}),
		cond:  sync.NewCond(&sync.Mutex{}),
	}
	stats.Periodically(s.reportCounts)
	return s
}

type Simple struct {
	log   logger.Logger
	stats statter.Statter

	_done chan struct{}
	cond  *sync.Cond
	once  sync.Once

	active int64
	tags   statter.Tags
}

func (s *Simple) Active() int64 {
	return atomic.LoadInt64(&s.active)
}

func (s *Simple) Run(ctx context.Context, jobName string, job JobFunc) error {
	// prepare a new follow span
	opName := fmt.Sprintf("Simple.Run.%s", jobName)
	_, span := tracing.StartWithOpFuncName(ctx, opName, trace.WithAttributes(
		attribute.String("gh.launch.worker.job_name", jobName),
	))
	// and apply it to the job context
	jobCtx := appcontext.Fork(ctx)

	s.start()
	go func(ctx context.Context) {
		// s.end() must be placed first because defer statements are LIFO
		// and the span must be closed before the job ends
		defer s.end()
		defer span.End()

		run(ctx, s.log, s.stats, jobName, job)
	}(jobCtx)

	return nil
}

// RunNonBlocking runs job fun - unlike Run it makes it clear it this implementation can't fail to start
func (s *Simple) RunNonBlocking(ctx context.Context, jobName string, job JobFunc) {
	// ignore error - we never have an error from Run
	s.Run(ctx, jobName, job) // nolint: errcheck
}

func (s *Simple) Periodically(interval time.Duration, jobName string, job JobFunc) {
	go runPeriodically(s, interval, jobName, job)
}

func (s *Simple) Stop() {
	s.once.Do(func() {
		close(s._done)
	})

	s.cond.L.Lock()
	for s.active > 0 {
		s.cond.Wait()
	}
	s.cond.L.Unlock()
}

func (s *Simple) done() <-chan struct{} {
	return s._done
}

func (s *Simple) logger() logger.Logger {
	return s.log
}

func (s *Simple) reportCounts(statter.Statter) {
	ctx := context.Background()
	active := s.Active()
	s.stats.Gauge(ctx, activeWorkersGauge, s.tags, active)
	s.stats.Gauge(ctx, totalWorkersGauge, s.tags, active)
}

func (s *Simple) start() {
	s.cond.L.Lock()
	atomic.AddInt64(&s.active, 1)
	s.cond.L.Unlock()
	// don't bother broadcasting - Stop() is only thing that waits, and only waits if active >= 1 anyway,
	// so doesn't need to be woken just to fail check again
}

func (s *Simple) end() {
	s.cond.L.Lock()
	atomic.AddInt64(&s.active, -1)
	s.cond.L.Unlock()
	s.cond.Broadcast()
}
