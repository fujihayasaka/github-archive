// Package agentjob provides handlers for processing agent-related jobs from the queue.
package agentjob

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobexecutor"
	db "github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

type requeue interface {
	RequeueJobWithDelay(ctx context.Context, job sweagentd.AqueductJob, delay time.Duration) (string, error)
}

type jsvc interface {
	GetJobQueuedForExecution(ctx context.Context, queueJob *jobs.AgentJob) (*db.Job, error)
	FinalizeUnexecutedJob(ctx context.Context, job *db.Job, status db.JobStatus, jobError *db.JobError) error
}

// Handler creates a job handler for processing agent jobs from the queue.
func Handler(obsv observability.Exporters, ffClient featureflags.Client, queue requeue, rateLimiter limiter.RateLimiter, jobLimiter *limiter.JobLimiter, appProvider *agenticapp.Provider, service jsvc, executor jobexecutor.JobExecutor) aqueduct.JobHandler {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) (context.Context, error) {
		ctx, span := obsv.Tracer.Start(ctx, "aqueduct.jobs.agentjob.Handler")
		defer span.End()

		switch rr.Queue {
		case jobs.AgentJobQueueName:
			var job jobs.AgentJob
			err := job.Unmarshal(rr.Payload)
			if err != nil {
				return ctx, goerrors.Errorf("failed to unmarshal agent job: %w", err)
			}

			addAgentToRequestContext(ctx, obsv, ffClient, appProvider, &job)
			addJobToRequestContext(ctx, obsv, &job)
			if job.GithubRequestId != "" {
				ctx = requestid.WithGitHubRequestID(ctx, job.GithubRequestId)
			}

			log := obsv.LoggerWithTelemetry(ctx)

			var duration time.Duration
			var delay bool
			if ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentSkipSecondaryRateLimitCache) {
				duration, delay = rateLimiter.DelayProcessingPrimaryOnly(ctx, job.AgentId, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			} else {
				duration, delay = rateLimiter.DelayProcessing(ctx, job.AgentId, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			}
			log.WithFields(kvp.Bool("success", !delay)).Info("rate limit check")
			if delay {
				return ctx, requeueJob(ctx, obsv, queue, service, &job, duration)
			}

			duration, delay = jobLimiter.DelayProcessing(ctx, job.ActorId, job.AgentId)
			switch {
			case ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWESkipAgentJobConcurrencyLimit, job.ActorId):
				if delay {
					log.WithFields(kvp.Bool("success", false), kvp.Bool("bypassed", true)).Warn("concurrent job limit check")
				} else {
					log.WithFields(kvp.Bool("success", true)).Info("concurrent job limit check")
				}
			default:
				if delay {
					log.WithFields(kvp.Bool("success", false)).Info("concurrent job limit check")
					return ctx, requeueJob(ctx, obsv, queue, service, &job, duration)
				}
				log.WithFields(kvp.Bool("success", true)).Info("concurrent job limit check")
			}

			log.Info("processing agent job")
			return ctx, executor.ProcessJob(ctx, &job)

		default:
			return ctx, goerrors.Errorf("unknown queue %q", rr.Queue)
		}
	}
}

func requeueJob(ctx context.Context, obsv observability.Exporters, queue requeue, service jsvc, job *jobs.AgentJob, delay time.Duration) error {
	log := obsv.LoggerWithTelemetry(ctx)

	if jobs.HasExceededMaxRequeues(job) {
		log.Warn("agent job has exceeded max requeues, dropping job")
		failJob(ctx, obsv, service, job, &db.JobError{
			Service:            "sweagentd",
			ResponseStatusCode: "rate_limit_exceeded",
			Message:            "Copilot was unable to start work because you have queued many other jobs and this job had to wait too long to start. Please try again later.",
		})
		return jobs.ErrExceededMaxRequeues
	}

	_, err := queue.RequeueJobWithDelay(ctx, job, delay)
	if err != nil {
		log.WithFields(kvp.Bool("success", false)).WithError(err).Error("requeue agent job")
		failJob(ctx, obsv, service, job, &db.JobError{
			Service:            "sweagentd",
			ResponseStatusCode: "requeue_failure",
			Message:            "failed to requeue agent job",
		})
		return goerrors.Errorf("failed to requeue agent job with delay: %w", err)
	}

	log.WithFields(kvp.Bool("success", true)).Info("requeue agent job")
	return nil
}

// failJob marks the job as failed using the provided jobservice.
//
// NOTE: This is a best-effort attempt. If we error again here, the error is
// logged and reported, but not returned, since we're already in an error path.
func failJob(ctx context.Context, obsv observability.Exporters, service jsvc, queueJob *jobs.AgentJob, jobError *db.JobError) {
	// Log the errors but don't return, otherwise Aqueduct will retry the
	// job and we're already at the point we're trying to clean up the job
	// due to a failure.

	job, err := service.GetJobQueuedForExecution(ctx, queueJob)
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to get job for failed agent job")
		return
	}

	err = service.FinalizeUnexecutedJob(ctx, job, db.JobStatusFailed, jobError)
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to finalize unexecuted agent job")
	}
}

// NewFailJobFunc creates a jobs.FailJobFunc that finalizes agent jobs as failed
// in the database. This is used by the outer jobs.Handler to finalize jobs that
// cannot be requeued after a transient error.
func NewFailJobFunc(obsv observability.Exporters, service jsvc) jobs.FailJobFunc {
	return func(ctx context.Context, rr aqueduct.ReceiveResult, errorCode string, errorMessage string) {
		var job jobs.AgentJob
		err := job.Unmarshal(rr.Payload)
		if err != nil {
			obsv.LogAndReportError(ctx, err, "failed to unmarshal agent job for failure")
			obsv.Statter.Counter("aqueduct.worker.job.fail_unmarshal_error", stats.Tags{"source": "agent_job"}, 1)
			return
		}
		failJob(ctx, obsv, service, &job, &db.JobError{
			Service:            "sweagentd",
			ResponseStatusCode: errorCode,
			Message:            errorMessage,
		})
	}
}

func addAgentToRequestContext(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, appProvider *agenticapp.Provider, job *jobs.AgentJob) {
	if job.AgentId == 0 {
		return
	}
	err := requestctx.AddAgent(ctx, &requestctx.CtxAgent{
		ID: job.AgentId,
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add agent to request context")
	}
	if appProvider == nil {
		return
	}
	app, err := appProvider.FindByID(ctx, job.AgentId)
	if err != nil {
		return
	}
	jobservice.SetCtxAgent(ctx, obsv, ffClient, app, job.AgentId)
}

func addJobToRequestContext(ctx context.Context, obsv observability.Exporters, job *jobs.AgentJob) {
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
