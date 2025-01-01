package aqueduct

import (
	"context"
	"encoding/json"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-ctxutil"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/appctx"
	"github.com/pkg/errors"
	"golang.org/x/exp/maps"
)

type jobHandler func(context.Context, *TSServices, JobRetrier, aqueduct.ReceiveResult) error

// Registry maps each queue to a job handler
type Registry map[string]jobHandler

func RegisterJob[T EnqueableJob](r Registry) {
	var j T
	r[j.Queue()] = baseHandler[T]
}

// AqueductWorker implements the app.Server interface
type AqueductWorker struct {
	worker *aqueduct.Worker
}

// NewWorker returns a new aqueduct worker
func NewWorker(ctx context.Context, s *TSServices, client *Client, environment string, workerType string, r Registry) (*AqueductWorker, error) {
	w, err := aqueduct.NewWorker(
		client.aqueduct,
		client.app,
		maps.Keys(r),
		func(ctx context.Context, rr aqueduct.ReceiveResult) (err error) {
			defer func() {
				if p := recover(); p != nil {
					if e, ok := p.(error); ok {
						err = errors.Wrap(e, "job handler panic")
					} else {
						err = errors.New("job handler panic")
					}
					appctx.Report(ctx, err, map[string]string{"queue": rr.Queue, "job_id": rr.ID, "stack_trace": string(debug.Stack())})
				}
			}()
			if handler, ok := r[rr.Queue]; ok {
				handlerCtx := appctx.With(ctx, kvp.String("gh.aqueduct.job.id", rr.ID))
				return handler(handlerCtx, s, client, rr)
			}
			appctx.Logger(ctx).Error("Could not find handler for the queue.", kvp.String("gh.aqueduct.queue.name", rr.Queue))
			appctx.Report(ctx, errors.New("could not find handler for the queue"), map[string]string{"queue": rr.Queue, "job_id": rr.ID})
			return nil
		},
		aqueduct.WithLogger(appctx.Logger(ctx)),
		aqueduct.WithJobErrorPolicy(aqueduct.NackJobErr),
		aqueduct.WithPool(workerType+"-"+environment),
	)

	return &AqueductWorker{worker: w}, err
}

func (w *AqueductWorker) Start(ctx context.Context) error {
	for {
		err := w.worker.ProcessJob(ctx)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("error processing job")
		}
		if ctx.Err() != nil {
			appctx.Logger(ctx).WithError(ctx.Err()).Info("aqueduct worker shutting down")
			return nil
		}
	}
}

func (w *AqueductWorker) Stop(_ context.Context) error {
	return nil
}

// EnabledQueues computes the set of queues that are both defined in the configuration
// and have an handler associated.
// cfgQueues is a comma separated list of queue names.
// If cfgQueues is empty, then all queues with an handler are considered.
func EnabledQueues(cfgQueues string, registry Registry, logger log.Logger) Registry {
	if cfgQueues == "" {
		// Enable all queues (default)
		return registry
	}

	// Set of queues enabled in the config
	qsConfig := map[string]bool{}
	for _, v := range strings.Split(cfgQueues, ",") {
		qsConfig[v] = false
	}
	out := map[string]jobHandler{}

	// Of all handlers, only keep the ones for queues enabled in the configuration.
	// This makes it possible to deploy different versions of the worker.
	for q := range registry {
		if _, ok := qsConfig[q]; ok {
			out[q] = registry[q]
			qsConfig[q] = true // Flag as seen
		} else {
			logger.Debug("Found handler for queue that is not enabled in the configuration", kvp.String("gh.aqueduct.queue.name", q))
		}
	}
	// Report queues without a handler
	for q, seen := range qsConfig {
		if !seen {
			logger.Debug("Queue is configured but no handler found: it will be ignored.", kvp.String("gh.aqueduct.queue.name", q))
		}
	}
	return out
}

type AqueductString string

const JobIDKey = AqueductString("gh.aqueduct.job.id")

// baseHandler is the simplest handler we can have for a job. It includes observability and unmarshaling of the job from the queue.
func baseHandler[T EnqueableJob](ctx context.Context, s *TSServices, client JobRetrier, rr aqueduct.ReceiveResult) error {
	if v, ok := rr.Headers[headers.Tenant]; ok {
		ctx = tenant.TenantContext(ctx, v)
		ctx = appctx.With(ctx, kvp.String("gh.turboscan.tenant", v))
	} else {
		appctx.Logger(ctx).Debug("tenant data missing in job")
		// We want to continue the job if the tenant headers are missing since we don't need the tenant headers for customers not on Proxima.
		// We'll just want to log any missing tenant headers for debugging purposes while continuing the job.
	}

	if v, ok := rr.Headers[headers.TenantID]; ok {
		ctx = tenant.TenantIDContext(ctx, v)
		ctx = appctx.With(ctx, kvp.String("gh.turboscan.tenant.id", v))
	} else {
		appctx.Logger(ctx).Debug("tenantID data missing in job")
		// We want to continue the job if the tenant ID headers are missing since tenant information is only available in Proxima and not in GHES or dotCom.
	}

	// Make sure we use tags consistently
	ctx = appctx.With(ctx, kvp.String("gh.aqueduct.job.id", rr.ID), kvp.String("gh.aqueduct.queue.name", rr.Queue))
	// we also need to be able to read JobID back from the context
	ctx = context.WithValue(ctx, JobIDKey, rr.ID)

	// prevent cancelled parent context from stopping in-progress jobs
	// if outer context is complete, give a grace period before cancelling job context
	// aqueductsvc k8s terminationGracePeriodSeconds: is 300 (5 mins), so kill jobs 1 min early to allow other cleanup
	jobCtx, jobCtxCancelFunc := ctxutil.DelayedCancel(ctx, 4*time.Minute)
	defer jobCtxCancelFunc()

	// prevent cancelled parent context from breaking retry logic
	// prefer to always do this if at all possible
	retryCtx, retryCtxCancelFunc := context.WithCancel(ctxutil.DetachedCancel(ctx))
	defer retryCtxCancelFunc()

	ctx = appctx.WithStats(ctx, appctx.Stats(ctx).WithTags(stats.Tags{"queue": rr.Queue}))

	appctx.Logger(ctx).Info("Processing job")

	var retryCount uint8
	if v, ok := rr.Headers[RetryCountHeader]; ok {
		vv, err := strconv.ParseUint(v, 10, 8)
		if err == nil {
			retryCount = uint8(vv)
		}
	}
	appctx.Stats(ctx).Counter("aqueduct_worker.process_job", stats.Tags{"retry": strconv.FormatBool(retryCount > 0)}, 1)

	var job T
	if err := json.Unmarshal(rr.Payload, &job); err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to unmarshal payload")
		return errors.Wrap(err, "failed to unmarshal payload")
	}

	// Add job properties to the context, logger and stats
	jobCtx = appctx.With(jobCtx, kvp.String("gh.aqueduct.job.name", job.Name()))
	// Add repository ID to the context if it's available
	if repoID := job.GetRepositoryID(); repoID != nil {
		jobCtx = appctx.WithKVPs(jobCtx, *repoID)
	}
	jobCtx = appctx.WithAqueductJobRetryCount(jobCtx, retryCount)

	ctx = appctx.WithStats(ctx, appctx.Stats(ctx).WithTags(stats.Tags{"job_name": job.Name()}))

	startTime := time.Now()
	err := job.Perform(jobCtx, s)
	duration := time.Since(startTime)
	appctx.Stats(ctx).DistributionMs("aqueduct_worker.process_duration", nil, duration)

	// When perform returns an error, we want to retry the job.
	if err == nil {
		if ctx.Err() != nil {
			appctx.Logger(ctx).Info("aqueduct context done, final job completed")
		}
		return nil
	}

	appctx.Logger(ctx).WithError(err).Error("Job failed.", kvp.Uint8("gh.turboscan.retry.count", retryCount))

	if retryCount < MaxRetryCount {
		// We want to retry the job
		retryCount++
		if _, err := client.RetryLater(retryCtx, job, retryCount); err != nil {
			appctx.Logger(ctx).WithError(err).Error("Failed to enqueue job for retry.", kvp.Uint8("gh.turboscan.retry.count", retryCount))
		}
		if ctx.Err() != nil {
			appctx.Logger(ctx).WithError(err).Info("aqueduct context done, final job failed")
		}
	} else {
		appctx.Logger(ctx).WithError(err).Error("Job failed too many times, giving up.", kvp.Uint8("gh.turboscan.retry.count", retryCount))
		appctx.Report(retryCtx, errors.Wrap(err, "Job failed too many times, giving up."), map[string]string{"queue": rr.Queue, "job_id": rr.ID})
		appctx.Stats(ctx).Counter("aqueduct_worker.gave_up", nil, 1)
	}

	return err
}
