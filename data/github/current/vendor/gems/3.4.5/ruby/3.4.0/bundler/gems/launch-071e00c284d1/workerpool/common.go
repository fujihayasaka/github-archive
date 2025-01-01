package workerpool

import (
	"context"
	"fmt"
	"runtime/debug"
	"time"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
)

// JobFunc is a thing that can be run in a background thread.
type JobFunc func(context.Context) error

const (
	jobStartMetric     = "job.start.count"
	jobQueueTimeMetric = "job.queued.time"
	jobsQueuedGauge    = "jobs.queued"
	activeWorkersGauge = "workers.active"
	totalWorkersGauge  = "workers.total"

	workerTypeKey = "worker_type"
	jobNameKey    = "job"
	statusKey     = "status"

	successStatus = "success"
	failedStatus  = "failed"
)

func run(ctx context.Context, log logger.Logger, statter statter.Statter, jobName string, job JobFunc) string {
	var result string
	_run(ctx, log, statter, jobName, job, func(s string) { result = s })
	return result
}

func _run(ctx context.Context, log logger.Logger, stats statter.Statter, jobName string, job JobFunc, status func(string)) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.launch.worker.job_name", jobName),
	))
	defer span.End()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	ctx = ctxstash.WithFields(ctx, kvp.String(jobNameKey, jobName))
	mw.TagStatsWith(ctx, reqmeta.Tags{jobNameKey: jobName})

	log.Debug(ctx, "start job")
	stats.Counter(ctx, jobStartMetric, nil, 1) // Count the start, in case the statter is stopped before this job finishes
	result := failedStatus
	defer func() {
		log.Debug(ctx, "finish job", kvp.String(statusKey, result))
		status(result)
	}()

	defer func() {
		if rvr := recover(); rvr != nil {
			err, ok := rvr.(error)
			if !ok {
				err = fmt.Errorf("%v", rvr)
			}
			log.Report(ctx, errors.WithStack(err), kvp.String("exception_detail", string(debug.Stack())))
		}
	}()

	err := job(ctx)
	if err != nil {
		log.Report(ctx, tracing.RecordError(span, err))
		return
	}
	result = successStatus
}

var iterationDoneFlag struct{}

// runPeriodically is called by a Workers implementation's Periodically method.
//
// Each implementation is expected to test Periodically independently so that
// it can test interactions with other jobs in a type-specific way.
func runPeriodically(w Workers, interval time.Duration, jobName string, job JobFunc) {
	iterationDone := make(chan struct{}, 1)
	defer close(iterationDone)

	for {
		select {
		case <-w.done():
			// The pool is shutting down, so we're done here!
			return
		case <-time.After(interval):
			runPeriodicJob(w, jobName, job, iterationDone)
		}
	}
}

func runPeriodicJob(w Workers, jobName string, job JobFunc, iterationDone chan struct{}) {
	err := w.Run(context.Background(), jobName, func(jobCtx context.Context) error {
		// Let the periodic func know that it's OK to queue another iteration.
		defer func() { iterationDone <- iterationDoneFlag }()
		select {
		case <-w.done():
			// The pool is shutting down, so don't start the job.
			return nil
		default:
			return job(jobCtx)
		}
	})
	if err != nil {
		w.logger().Report(context.Background(), err, kvp.String("job_name", jobName))
	}
	// Wait until the job finishes before returning and starting the timer for the next one.
	<-iterationDone
}
