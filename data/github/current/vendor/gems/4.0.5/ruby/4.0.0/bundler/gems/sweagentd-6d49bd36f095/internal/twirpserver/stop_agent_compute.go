package twirpserver

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// DefaultStopAgentComputeDelay is the delay applied to a StopAgentCompute
// request when the caller does not specify one. The request is persisted as
// an Aqueduct job that is delivered after this delay.
const DefaultStopAgentComputeDelay = 10 * time.Minute

// StopAgentCompute stops a running compute environment without deleting it.
// The sandbox is suspended and can be resumed later via ResumeAgentCompute.
//
// By default the actual stop is performed asynchronously via an Aqueduct job
// scheduled to run [DefaultStopAgentComputeDelay] after the request is
// received. Callers may override this by setting the request's Delay field:
//
//   - Delay unset (nil): use [DefaultStopAgentComputeDelay].
//   - Delay == 0: stop the compute immediately, synchronously, without
//     scheduling a job.
//   - Delay > 0: schedule the job to be delivered after the specified
//     duration.
//
// When the request is scheduled (delay > 0), a subsequent StopAgentCompute
// call for the same compute ID supersedes the prior request: each call
// increments a per-compute "generation" in the cache, and the handler skips
// processing if its job's generation no longer matches the cached value.
func (s *Server) StopAgentCompute(ctx context.Context, req *jobs_pb.StopAgentComputeRequest) (*jobs_pb.StopAgentComputeResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.StopAgentCompute")
	defer span.End()

	if req.ComputeId == "" {
		return nil, twirp.RequiredArgumentError("compute_id")
	}
	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}

	delay := DefaultStopAgentComputeDelay
	if req.Delay != nil {
		delay = req.Delay.AsDuration()
	}
	if delay < 0 {
		return nil, twirp.InvalidArgumentError("delay", "must not be negative")
	}

	log := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("compute_id", req.ComputeId),
		kvp.Duration("delay", delay),
	)

	// delay == 0 means stop immediately and skip the queue.
	if delay == 0 {
		// Best-effort invalidation of any previously scheduled stop job for this
		// compute so it won't fire after this synchronous stop.
		if s.stopGuard != nil {
			_, recordErr := s.stopGuard.Record(req.ComputeId)
			if recordErr != nil {
				log.WithError(recordErr).Warn("failed to invalidate stop-agent-compute generation for synchronous stop")
			}
		}

		err := s.sandboxService.StopSandbox(ctx, req.ComputeId, req.ActorId)
		if err != nil {
			log.WithError(err).Error("failed to stop agent compute synchronously")
			return nil, twirp.NewError(twirp.Internal, "failed to stop agent compute")
		}
		log.Info("stopped agent compute synchronously")
		return &jobs_pb.StopAgentComputeResponse{}, nil
	}

	generation, err := s.stopGuard.Record(req.ComputeId)
	if err != nil {
		log.WithError(err).Error("failed to record stop agent compute generation")
		return nil, twirp.NewError(twirp.Internal, "failed to schedule stop agent compute")
	}

	job := aqueductJobs.NewStopAgentComputeJob(
		ctx,
		req.ComputeId,
		int64(req.ActorId),
		generation,
	)

	deliverAt := time.Now().Add(delay)
	_, err = s.aqueductClient.ScheduleJob(ctx, job, deliverAt)
	if err != nil {
		log.WithError(err).Error("failed to schedule stop agent compute job")
		return nil, twirp.NewError(twirp.Internal, "failed to schedule stop agent compute")
	}

	log.WithFields(kvp.Int64("generation", generation)).Info("scheduled delayed stop agent compute")

	return &jobs_pb.StopAgentComputeResponse{}, nil
}
