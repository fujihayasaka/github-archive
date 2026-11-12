// Package eventjob provides handlers for processing event-related jobs from the queue.
package eventjob

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
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

// Handler creates a job handler for processing event jobs from the queue.
func Handler(obsv observability.Exporters, ffClient featureflags.Client, queue requeue, limits limiter.RateLimiter, p *agenticapp.Provider, handler events.EventsHandler) aqueduct.JobHandler {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) (context.Context, error) {
		ctx, span := obsv.Tracer.Start(ctx, "aqueduct.jobs.eventjob.Handler")
		defer span.End()

		switch rr.Queue {
		case jobs.EventJobQueueName, jobs.EventJobTriggerQueueName, jobs.EventJobBackgroundQueueName:
			var job jobs.EventJob
			err := job.Unmarshal(rr.Payload)
			if err != nil {
				return ctx, goerrors.Errorf("failed to unmarshal event job: %w", err)
			}

			addAgentToRequestContext(ctx, obsv, ffClient, p, &job)
			addHydroMessageToRequestContext(ctx, obsv, &job)
			if job.GithubRequestId != "" {
				ctx = requestid.WithGitHubRequestID(ctx, job.GithubRequestId)
			}

			log := obsv.LoggerWithTelemetry(ctx)

			log.Info("processing event job")
			_, event, err := hydro.EventForTopic(ctx, job.Topic, &job, p)
			if err != nil {
				if hydro.IsMessageNotApplicable(err) {
					obsv.LoggerWithTelemetry(ctx).Info("event not applicable, skipping processing")
					return ctx, nil
				}
				return ctx, goerrors.Errorf("failed to get event for topic %q: %w", job.Topic, err)
			}

			// EventForTopic adds the event to the context, so we reload the log
			log = obsv.LoggerWithTelemetry(ctx)

			var duration time.Duration
			var delay bool
			if ffClient.IsEnabled(ctx, featureflags.CopilotSWEAgentSkipSecondaryRateLimitCache) {
				duration, delay = limits.DelayProcessingPrimaryOnly(ctx, job.AgentId, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			} else {
				duration, delay = limits.DelayProcessing(ctx, job.AgentId, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			}
			log.WithFields(kvp.Bool("success", !delay)).Info("rate limit check")
			if !delay {
				return ctx, handler.Process(ctx, event)
			}

			if jobs.HasExceededMaxRequeues(&job) {
				log.Warn("event job has exceeded max requeues, dropping job")
				return ctx, jobs.ErrExceededMaxRequeues
			}

			_, err = queue.RequeueJobWithDelay(ctx, &job, duration)
			if err != nil {
				log.WithFields(kvp.Bool("success", false)).WithError(err).Error("requeue event job")
				return ctx, goerrors.Errorf("failed to requeue event job with delay: %w", err)
			}

			log.WithFields(kvp.Bool("success", true)).Info("requeue event job")
			return ctx, nil

		default:
			return ctx, goerrors.Errorf("unknown queue %q", rr.Queue)
		}
	}
}

func addAgentToRequestContext(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, appProvider *agenticapp.Provider, job *jobs.EventJob) {
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

func addHydroMessageToRequestContext(ctx context.Context, obsv observability.Exporters, job *jobs.EventJob) {
	// TODO (colbylwilliams): consider if it would be useful to have the
	// partition and offset from the original hydro event here
	err := requestctx.AddHydroMessage(ctx, requestctx.HydroEvent{
		EnvelopeID: job.Id,
		Topic:      job.Topic,
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add hydro message to request context")
	}
}
