package twirpserver

import (
	"context"

	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// DeleteAgentCompute tears down a previously created compute environment.
// Currently backed by GitHub Sandbox VMs via the sandbox service.
func (s *Server) DeleteAgentCompute(ctx context.Context, req *jobs_pb.DeleteAgentComputeRequest) (*jobs_pb.DeleteAgentComputeResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.DeleteAgentCompute")
	defer span.End()

	if req.ComputeId == "" {
		return nil, twirp.RequiredArgumentError("compute_id")
	}
	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}

	// Invalidate any pending delayed StopAgentCompute for this compute by
	// bumping the generation. A still-in-flight stop job will fail its
	// IsCurrent check and become a no-op against the now-deleted sandbox.
	if s.stopGuard != nil {
		_, err := s.stopGuard.Record(req.ComputeId)
		if err != nil {
			s.obsv.LoggerWithTelemetry(ctx).WithError(err).Warn("failed to invalidate stop-agent-compute generation; pending stop job may still fire")
		}
	}

	err := s.sandboxService.DeleteSandbox(ctx, req.ComputeId, req.ActorId)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to delete agent compute")
		return nil, twirp.NewError(twirp.Internal, "failed to delete agent compute")
	}

	return &jobs_pb.DeleteAgentComputeResponse{}, nil
}
