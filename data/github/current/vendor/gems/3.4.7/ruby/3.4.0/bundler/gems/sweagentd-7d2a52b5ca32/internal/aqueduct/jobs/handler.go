// Package jobs provides the job handler and hooks for processing jobs from the queue.
//
// IMPORTANT: We only want to sleep if the *secondary* rate limit is exceeded.
// Sleeping occupies the worker and prevents it from receiving additional jobs.
// The secondary rate limit is a global limit that spans all installations and
// users, so preventing the worker from receiving jobs during this limit is the
// correct behavior. This is accomplished by checking the secondary limits in
// the [BeforeReceive] hook.
//
// Primary rate limits on the other hand, are installation/user specific.
// Sleeping on primary rate limits would allow a single installation or user
// to monopolize the workers, preventing jobs for other installations/users
// from being processed. Obviously, this is not the desired behavior. Instead,
// for primary limits, we requeue/schedule the job to be retried after the rate
// limit reset time. This ensures we process rate-limited jobs quickly, freeing
// up the worker to receive other jobs in the meantime. Primary rate limits are
// checked in the [Handler] function.
package jobs

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	aq "github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
)

type requeue interface {
	RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error)
}

// ErrExceededMaxRequeues is returned when a job has exceeded its maximum requeue
// count and should not be requeued again.
//
// We limit the number of times a job can be requeued to prevent abuse, so this
// error indicates that the job should be failed and not retried again.
var ErrExceededMaxRequeues = errors.New("job has exceeded maximum requeue count")

// DefaultReceiveHook is a no-op hook that can be used in place of a queue hook
var DefaultReceiveHook aq.BeforeReceiveHook = func(ctx context.Context) (context.Context, error) {
	// The context returned by BeforeReceive is passed into Handler
	// so setting the CtxData here guarantees it's available in Handlers
	ctx = requestctx.NewContext(ctx)
	return ctx, nil
}

// BeforeReceive is called before attempting to receive a job from the queue.
// It receives the work context and should return an error if the hook fails.
//
// This is where we check if we've exceeded our secondary (global/abuse) rate
// limit and wait/sleep until our secondary rate limit resets.
func BeforeReceive(obsv observability.Exporters, rateLimiter limiter.RateLimiter, hook aq.BeforeReceiveHook) aq.BeforeReceiveHook {
	return func(ctx context.Context) (context.Context, error) {
		// The context returned by BeforeReceive is passed into Handler
		// so setting the CtxData here guarantees it's available in Handlers
		ctx = requestctx.NewContext(ctx)

		duration, wait := rateLimiter.WaitToReceive(ctx)
		if !wait {
			return hook(ctx)
		}

		obsv.LoggerWithTelemetry(ctx).Info("Secondary limit exceeded, waiting to receive job")

		obsv.Statter.Counter("aqueduct.worker.secondary_limit_exceeded", obsv.TelemetryTags(ctx), 1)
		obsv.Statter.DistributionMs("aqueduct.worker.secondary_limit_wait_time", obsv.TelemetryTags(ctx), duration)

		select {
		case <-ctx.Done():
			return ctx, ctx.Err()
		case <-time.After(duration):
		}

		return hook(ctx)
	}
}

// Handler is a wrapper for job-specific [aq.JobHandler]s that adds telemetry and
// error handling.
//
// The downstream handler should do the actual job processing, including rate
// limiting and requeuing/scheduling jobs as necessary.
func Handler(obsv observability.Exporters, queue requeue, handler aq.JobHandler) aq.JobHandler {
	return func(ctx context.Context, rr aq.ReceiveResult) (context.Context, error) {
		if requestID := requestid.GetGitHubRequestID(ctx); requestID == "" {
			ctx = requestid.WithNewGitHubRequestID(ctx)
		}

		err := AddReceivedJobToRequestContext(ctx, obsv, rr)
		if err != nil {
			return ctx, fmt.Errorf("failed to add received job to request context: %w", err)
		}

		obsv.LoggerWithTelemetry(ctx).Info(fmt.Sprintf("processing job from %s", rr.Queue))

		// Call the actual handler here so we can handle known errors ourselves
		returnCtx, err := handler(ctx, rr)
		if err == nil {
			return returnCtx, nil
		}

		obsv.LoggerWithTelemetry(returnCtx).WithError(err).Error("error processing job")

		err = handleRateLimitErrors(returnCtx, obsv, queue, rr, err)
		if err == nil {
			obsv.LoggerWithTelemetry(returnCtx).Info("successfully handled rate limit error")
			// If we handled the rate limit error, return nil so the job is not retried
			return returnCtx, nil
		}

		if limiter.IsQueuedJobsExceededError(err) {
			// If the actor has exceeded their max queued jobs, we fail the job
			// and do not retry it.
			obsv.Statter.Counter("aqueduct.worker.job.actor_exceeded_max_queued_jobs", obsv.TelemetryTags(returnCtx), 1)
			obsv.LoggerWithTelemetry(returnCtx).WithError(err).Error("actor has exceeded maximum queued jobs")
			return returnCtx, nil
		}

		if errors.Is(err, ErrExceededMaxRequeues) {
			// If we've exceeded the maximum requeue count, it indicates abuse or
			// a misconfiguration. We stop attempting to process the job and
			// log the error, but do not return an error to Aqueduct to prevent
			// the job from being retried.
			obsv.Statter.Counter("aqueduct.worker.job.exceeded_max_requeues", obsv.TelemetryTags(returnCtx), 1)
			obsv.LoggerWithTelemetry(returnCtx).WithError(err).Error("job has exceeded maximum requeue count")
			return returnCtx, nil
		}
		return returnCtx, err
	}
}

// OnError is a hook function that is called when a worker encounters an error.
// It receives the worker instance, work context, and the error that occurred.
// The worker parameter can be used to call worker.Shutdown() for graceful shutdown.
// The context parameter is read-only and should not be canceled.
func OnError(obsv observability.Exporters) aq.ErrorHook {
	return func(worker *aq.Worker, ctx context.Context, err error) {
		obsv.LogAndReportError(ctx, err, "error processing job off queue")
	}
}

// HasExceededMaxRequeues returns true if the job has exceeded its maximum requeue
// count. If the job's is less than 1, it defaults to 1 to prevent infinite requeues.
func HasExceededMaxRequeues(job sweagentd.AqueductJob) bool {
	return job.GetRequeueCount() >= max(1, job.MaxRequeueCount())
}

// handleRateLimitErrors checks if the error is a rate limit error and attempts to
// requeue the job with a delay based on the rate limit reset time.
//
// If the job has exceeded its maximum requeue count, it returns ErrExceededMaxRequeues
// to indicate that the job should be failed and not retried again.
//
// If the error is not a rate limit error, it is returned as-is.
func handleRateLimitErrors(ctx context.Context, obsv observability.Exporters, queue requeue, rr aq.ReceiveResult, err error) error {
	// If the error is not a rate limit error, return it as-is
	if !limiter.IsAnyRateLimitError(err) {
		return err
	}

	// Check up front if we've exceeded maximum requeues by looking at the headers.
	// Sending this information in the headers is new, so we still check the job
	// itself below for backwards compatibility.
	current, maximum, found := getRequeueFromHeaders(rr.Headers)
	if found && current >= maximum {
		// If we've exceeded the maximum requeue count, we can't requeue the
		// job in response to a rate limit error. Instead, we overwrite the
		// error to ErrExceededMaxRequeues so the caller can handle it
		// appropriately (i.e. fail the job and stop retrying).
		return ErrExceededMaxRequeues
	}

	obsv.LoggerWithTelemetry(ctx).Info("handling rate limit error in base handler")

	var delay time.Duration
	var primary *limiter.RateLimitError
	var secondary *limiter.AbuseRateLimitError
	switch {
	case errors.As(err, &primary):
		obsv.LoggerWithTelemetry(ctx).Warn("primary rate limit exceeded while processing job")
		delay = primary.DurationUntilReset()
	case errors.As(err, &secondary):
		obsv.LoggerWithTelemetry(ctx).Warn("secondary rate limit exceeded while processing job")
		delay = secondary.DurationUntilReset()
	default:
		// This should never happen since we checked IsAnyRateLimitError above
		return err
	}

	if delay <= 0 {
		obsv.LoggerWithTelemetry(ctx).Error("rate limit error did not specify a valid delay")
		// If we don't have a delay, we can't requeue the job, return the original error
		return err
	}

	job, getJobErr := getJob(ctx, rr)
	if getJobErr != nil {
		obsv.LogAndReportError(ctx, getJobErr, "failed to get job from receive result while handling rate limit error")
		// If we can't get the job, we can't requeue it, return the original error
		return err
	}

	// Check if we've exceeded the maximum requeue count before attempting to requeue
	// the job. We check both the job itself and the headers for backwards compatibility.
	if HasExceededMaxRequeues(job) {
		obsv.LoggerWithTelemetry(ctx).Warn("job has exceeded maximum requeues, not requeuing after rate limit error")
		return ErrExceededMaxRequeues
	}

	obsv.LoggerWithTelemetry(ctx).Info("requeuing job with delay after rate limit error")
	_, requeueErr := queue.RequeueJobWithDelay(ctx, job, delay)
	if requeueErr != nil {
		// If we fail to requeue the job, we return the original error
		// from the handler so the caller can decide what to do with it.
		obsv.LogAndReportError(ctx, requeueErr, "failed to requeue job after rate limit error")
		return err
	}

	obsv.LoggerWithTelemetry(ctx).Info("successfully requeued job after rate limit error")

	// If we successfully requeued the job, we swallow the original error and
	// return nil to indicate we've handled it.
	return nil
}

func getJob(ctx context.Context, rr aq.ReceiveResult) (sweagentd.AqueductJob, error) {
	switch rr.Queue {
	case EventJobQueueName, EventJobBackgroundQueueName:
		var job EventJob
		err := job.Unmarshal(rr.Payload)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal event job: %w", err)
		}
		return &job, nil

	case APIJobQueueName:
		var job APIJob
		err := job.Unmarshal(rr.Payload)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal api job: %w", err)
		}
		return &job, nil

	case AgentJobQueueName:
		var job AgentJob
		err := job.Unmarshal(rr.Payload)
		if err != nil {
			return nil, fmt.Errorf("failed to unmarshal agent job: %w", err)
		}
		return &job, nil

	default:
		return nil, fmt.Errorf("unknown job queue: %s", rr.Queue)
	}
}

// getRequeueFromHeaders extracts the current and maximum requeue counts from the
// job headers and returns them along with a boolean indicating if either header
// was found.
// If the maximum requeue count is less than 1, it defaults to 1 to allow at least
// one requeue.
func getRequeueFromHeaders(headers map[string]string) (current, maximum int32, found bool) {
	current = 0
	maximum = 0
	val, ok := headers[RequeueCountHeader]
	if ok {
		i, err := strconv.ParseInt(val, 10, 32)
		if err == nil {
			found = true
			current = int32(i)
		}
	}

	val, ok = headers[RequeueMaxCountHeader]
	if ok {
		i, err := strconv.ParseInt(val, 10, 32)
		if err == nil && i > 0 {
			found = true
			maximum = int32(i)
		}
	}
	// If we found the header but it was invalid, default maximum to 1
	if found && maximum < 1 {
		maximum = 1
	}

	return current, maximum, found
}
