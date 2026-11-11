// Package eventjob provides handlers for processing event-related jobs from the queue.
package eventjob

import (
	"context"
	"fmt"

	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/events"
	"github.com/github/sweagentd/internal/events/hydro"
	"github.com/github/sweagentd/internal/featureflags"
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
func Handler(obsv observability.Exporters, ffClient featureflags.Client, queue requeue, limits limiter.RateLimiter, handler events.EventsHandler) aqueduct.JobHandler {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) (context.Context, error) {
		ctx, span := obsv.Tracer.Start(ctx, "aqueduct.jobs.eventjob.Handler")
		defer span.End()

		switch rr.Queue {
		case jobs.EventJobQueueName, jobs.EventJobBackgroundQueueName:
			var job jobs.EventJob
			err := job.Unmarshal(rr.Payload)
			if err != nil {
				return ctx, fmt.Errorf("failed to unmarshal event job: %w", err)
			}

			addHydroMessageToRequestContext(ctx, obsv, &job)
			if job.GithubRequestId != "" {
				ctx = requestid.WithGitHubRequestID(ctx, job.GithubRequestId)
			}

			log := obsv.LoggerWithTelemetry(ctx)

			log.Info("processing event job")
			_, event, err := hydro.EventForTopic(ctx, job.Topic, &job)
			if err != nil {
				if hydro.IsMessageNotApplicable(err) {
					obsv.LoggerWithTelemetry(ctx).Info("event not applicable, skipping processing")
					return ctx, nil
				}
				return ctx, fmt.Errorf("failed to get event for topic %q: %w", job.Topic, err)
			}

			// EventForTopic adds the event to the context, so we reload the log
			log = obsv.LoggerWithTelemetry(ctx)

			log.Info("checking rate limits for event job")
			duration, delay := limits.DelayProcessing(ctx, job.OwnerId, job.RepositoryId, uint8(gg.CoreCategory), uint8(gg.GraphqlCategory))
			if !delay {
				log.Info("rate limit check passed")
				return ctx, handler.Process(ctx, event)
			}

			log.Info("rate limit exceeded")
			if jobs.HasExceededMaxRequeues(&job) {
				log.Warn("event job has exceeded max requeues, dropping job")
				return ctx, jobs.ErrExceededMaxRequeues
			}

			log.Info("requeuing event job")
			_, err = queue.RequeueJobWithDelay(ctx, &job, duration)
			if err != nil {
				return ctx, fmt.Errorf("failed to requeue event job with delay: %w", err)
			}

			log.Info("finished requeuing event job")
			return ctx, nil

		default:
			return ctx, fmt.Errorf("unknown queue %q", rr.Queue)
		}
	}
}

func addHydroMessageToRequestContext(ctx context.Context, obsv observability.Exporters, job *jobs.EventJob) {
	// TODO (colbylwilliams): consider if it would be useful to have the
	// partition and offset from the original hydro event here
	err := requestctx.AddHydroMessage(ctx, requestctx.HydroEvent{
		EnvelopeId: job.Id,
		Topic:      job.Topic,
	})
	if err != nil {
		obsv.LogAndReportError(ctx, err, "failed to add hydro message to request context")
	}
}
