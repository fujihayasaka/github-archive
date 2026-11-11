// Package agentjob provides handlers for processing agent-related jobs from the queue.
package agentjob

import (
	"context"
	"fmt"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobexecutor"
	db "github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

type requeue interface {
	RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error)
}

type jobservice interface {
	GetJobQueuedForExecution(ctx context.Context, queueJob *jobs.AgentJob) (*db.Job, error)
	FinalizeUnexecutedJob(ctx context.Context, job *db.Job, status db.JobStatus, errorMessage string) error
}

// Handler creates a job handler for processing agent jobs from the queue.
func Handler(obsv observability.Exporters, ffClient featureflags.Client, queue requeue, rateLimiter limiter.RateLimiter, jobLimiter *limiter.JobLimiter, service jobservice, executor jobexecutor.JobExecutor) aqueduct.JobHandler {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) (context.Context, error) {
		ctx, span := obsv.Tracer.Start(ctx, "aqueduct.jobs.agentjob.Handler")
		defer span.End()

		switch rr.Queue {
		case jobs.AgentJobQueueName:
			var job jobs.AgentJob
			err := job.Unmarshal(rr.Payload)
			if err != nil {
				return ctx, fmt.Errorf("failed to unmarshal agent job: %w", err)
			}

			addJobToRequestContext(ctx, obsv, &job)
			if job.GithubRequestId != "" {
				ctx = requestid.WithGitHubRequestID(ctx, job.GithubRequestId)
			}

			log := obsv.LoggerWithTelemetry(ctx)

			log.Info("checking rate limits for agent job")
			duration, delay := rateLimiter.DelayProcessing(ctx, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			if delay {
				log.Info("rate limit exceeded")
				return ctx, requeueJob(ctx, obsv, queue, service, &job, duration)
			}

			log.Info("rate limit check passed")

			log.Info("checking concurrent job limits for agent job")
			duration, delay = jobLimiter.DelayProcessing(ctx, job.ActorId)
			if delay {
				log.Info("concurrent job limit exceeded")
				return ctx, requeueJob(ctx, obsv, queue, service, &job, duration)
			}

			log.Info("job limit check passed")

			log.Info("processing agent job")
			return ctx, executor.ProcessJob(ctx, &job)

		default:
			return ctx, fmt.Errorf("unknown queue %q", rr.Queue)
		}
	}
}

func requeueJob(ctx context.Context, obsv observability.Exporters, queue requeue, service jobservice, job *jobs.AgentJob, delay time.Duration) error {
	if jobs.HasExceededMaxRequeues(job) {
		obsv.LoggerWithTelemetry(ctx).Warn("agent job has exceeded max requeues, dropping job")
		failJob(ctx, obsv, service, job, "too many agent jobs in progress")
		return jobs.ErrExceededMaxRequeues
	}

	obsv.LoggerWithTelemetry(ctx).Info("requeuing agent job")
	_, err := queue.RequeueJobWithDelay(ctx, job, delay)
	if err != nil {
		obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to requeue agent job")
		failJob(ctx, obsv, service, job, "")
		return fmt.Errorf("failed to requeue agent job with delay: %w", err)
	}

	obsv.LoggerWithTelemetry(ctx).Info("finished requeuing agent job")
	return nil
}

// failJob marks the job as failed using the provided jobservice.
//
// NOTE: This is a best-effort attempt. If we error again here, the error is
// logged and reported, but not returned, since we're already in an error path.
func failJob(ctx context.Context, obsv observability.Exporters, service jobservice, queueJob *jobs.AgentJob, errorMessage string) {
	// Log the errors but don't return, otherwise Aqueduct will retry the
	// job and we're already at the point we're trying to clean up the job
	// due to a failure.

	job, err := service.GetJobQueuedForExecution(ctx, queueJob)
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to get job for failed agent job")
		return
	}

	err = service.FinalizeUnexecutedJob(ctx, job, db.JobStatusFailed, errorMessage)
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to finalize unexecuted agent job")
	}
}

func addJobToRequestContext(ctx context.Context, obsv observability.Exporters, job *jobs.AgentJob) {
	err := requestctx.AddJob(ctx, &requestctx.CtxJob{
		ID:           job.JobId,
		AssignmentID: job.AssignmentId,
		RepoID:       job.RepositoryId,
		OwnerID:      job.OwnerId,
		SessionID:    job.SessionId,
		ActorID:      job.ActorId,
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add job to request context")
	}
}
