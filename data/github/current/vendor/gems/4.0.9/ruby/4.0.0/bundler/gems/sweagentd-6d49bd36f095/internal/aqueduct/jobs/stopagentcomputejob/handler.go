// Package stopagentcomputejob provides a handler for processing delayed
// stop-agent-compute jobs from the queue.
package stopagentcomputejob

import (
	"context"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// sandboxStopper is the subset of the sandbox service required by this
// handler.
type sandboxStopper interface {
	StopSandbox(ctx context.Context, computeID string, actorID uint64) error
}

// generationChecker reports whether a given generation is still the current
// one for a compute ID. A non-current generation indicates a newer
// StopAgentCompute request has superseded this one and the job should be
// skipped.
type generationChecker interface {
	IsCurrent(computeID string, generation int64) bool
}

// Handler creates a job handler that stops an agent compute by invoking the
// sandbox service. The job is queued by the Twirp StopAgentCompute endpoint
// with a delay so that the underlying sandbox is not stopped immediately.
//
// Before invoking the sandbox service, the handler checks the supplied
// [generationChecker] to ensure the job has not been superseded by a later
// StopAgentCompute request for the same compute ID.
func Handler(obsv observability.Exporters, sandboxService sandboxStopper, guard generationChecker) aqueduct.JobHandler {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) (context.Context, error) {
		ctx, span := obsv.Tracer.Start(ctx, "aqueduct.jobs.stopagentcomputejob.Handler")
		defer span.End()

		if rr.Queue != jobs.StopAgentComputeJobQueueName {
			return ctx, goerrors.Errorf("unknown queue %q", rr.Queue)
		}

		var job jobs.StopAgentComputeJob
		err := job.Unmarshal(rr.Payload)
		if err != nil {
			return ctx, goerrors.Errorf("failed to unmarshal stop agent compute job: %w", err)
		}

		if job.GithubRequestId != "" {
			ctx = requestid.WithGitHubRequestID(ctx, job.GithubRequestId)
		}

		log := obsv.LoggerWithTelemetry(ctx).WithFields(
			kvp.String("compute_id", job.ComputeId),
			kvp.Int64("generation", job.Generation),
		)

		if job.ComputeId == "" {
			log.Error("stop agent compute job missing compute_id, dropping")
			return ctx, nil
		}

		if guard != nil && !guard.IsCurrent(job.ComputeId, job.Generation) {
			obsv.Statter.Counter("aqueduct.worker.stop_agent_compute.superseded", obsv.TelemetryTags(ctx), 1)
			log.Info("stop agent compute job superseded by newer request, skipping")
			return ctx, nil
		}

		log.Info("processing delayed stop agent compute job")

		err = sandboxService.StopSandbox(ctx, job.ComputeId, uint64(job.ActorId))
		if err != nil {
			return ctx, goerrors.Errorf("failed to stop agent compute: %w", err)
		}

		return ctx, nil
	}
}
