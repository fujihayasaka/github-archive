// Package apijob provides handlers for processing api-related jobs from the queue.
package apijob

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
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
	FinalizeJob(ctx context.Context, job *db.Job, jobStatus db.JobStatus, jobError *db.JobError, completedAt int64) error
	GetJobQueuedForProcessing(ctx context.Context, queueJob *jobs.APIJob) (*db.Assignment, *db.Job, error)
	Process(ctx context.Context, job *jobs.APIJob) error
}

// Handler creates a job handler for processing api jobs from the queue.
func Handler(obsv observability.Exporters, ffClient featureflags.Client, queue requeue, limits limiter.RateLimiter, service jobservice) aqueduct.JobHandler {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) (context.Context, error) {
		ctx, span := obsv.Tracer.Start(ctx, "aqueduct.jobs.apijob.Handler")
		defer span.End()

		switch rr.Queue {
		case jobs.APIJobQueueName:
			var job jobs.APIJob
			err := job.Unmarshal(rr.Payload)
			if err != nil {
				return ctx, goerrors.Errorf("failed to unmarshal api job: %w", err)
			}

			addAgentToRequestContext(ctx, obsv, &job)
			addJobToRequestContext(ctx, obsv, &job)
			if job.GithubRequestId != "" {
				ctx = requestid.WithGitHubRequestID(ctx, job.GithubRequestId)
			}

			log := obsv.LoggerWithTelemetry(ctx)

			log.Info("checking rate limits for api job")
			duration, delay := limits.DelayProcessing(ctx, job.AgentId, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			if !delay {
				log.Info("rate limit check passed")
				return ctx, service.Process(ctx, &job)
			}

			log.Info("rate limit exceeded")

			// If we hit primary (user) rate limits, any subsequent logic/error
			// handling must not result in additional GitHub or CAPI API calls.
			//
			// We must also ensure we handle any errors gracefully, as returning
			// an error here will cause Aqueduct to immediately retry the job,
			// which will likely cause a tight loop of retries and failures,
			// exacerbating the rate limit issue and starving our worker pool.

			if jobs.HasExceededMaxRequeues(&job) {
				log.Warn("api job has exceeded max requeues, dropping job")
				failJob(ctx, obsv, service, &job, "exceeded max requeues while rate limited")
				return ctx, jobs.ErrExceededMaxRequeues
			}

			log.Info("requeuing api job")
			_, err = queue.RequeueJobWithDelay(ctx, &job, duration)
			if err != nil {
				log.WithError(err).Error("failed to requeue api job")
				failJob(ctx, obsv, service, &job, "failed to requeue job while rate limited")
				return ctx, goerrors.Errorf("failed to requeue api job with delay: %w", err)
			}

			log.Info("finished requeuing api job")
			return ctx, nil

		default:
			return ctx, goerrors.Errorf("unknown queue %q", rr.Queue)
		}
	}
}

// failJob marks the job as failed using the provided jobservice.
//
// NOTE: This is a best-effort attempt. If we error again here, the error is
// logged and reported, but not returned, since we're already in an error path.
func failJob(ctx context.Context, obsv observability.Exporters, service jobservice, queueJob *jobs.APIJob, errorMessage string) {
	// Log the errors but don't return, otherwise Aqueduct will retry the job and
	// we're already at the point we're trying to clean up the job due to a failure.
	//
	// TODO (colbylwilliams): Unfortunately, as we can't make additional API calls
	// at this point, we can't update the session status or error message.

	obsv.LoggerWithTelemetry(ctx).WithError(goerrors.New("failed to process api job")).Error(errorMessage)
	_, job, err := service.GetJobQueuedForProcessing(ctx, queueJob)
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to get job for failed api job")
		return
	}

	now := time.Now().Unix()
	err = service.FinalizeJob(ctx, job, db.JobStatusFailed, &db.JobError{Service: "sweagentd", ResponseStatusCode: "api_job_processing_failure"}, now)
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to finalize unexecuted api job")
	}
}

func addAgentToRequestContext(ctx context.Context, obsv observability.Exporters, job *jobs.APIJob) {
	if job.AgentId == 0 {
		return
	}
	err := requestctx.AddAgent(ctx, &requestctx.CtxAgent{
		ID: job.AgentId,
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add agent to request context")
	}
}

func addJobToRequestContext(ctx context.Context, obsv observability.Exporters, job *jobs.APIJob) {
	err := requestctx.AddJob(ctx, &requestctx.CtxJob{
		ID:           job.JobId,
		AssignmentID: job.AssignmentId,
		RepoID:       job.RepositoryId,
		OwnerID:      job.OwnerId,
		SessionID:    job.SessionId,
		ActorID:      job.ActorId,
		Agent: requestctx.CtxAgent{
			ID: job.AgentId,
		},
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add job to request context")
	}
}
