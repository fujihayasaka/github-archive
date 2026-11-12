package twirpserver

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sandbox"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
)

// ResumeAgentCompute resumes a CLI sandbox VM after a previous stop. If
// the sandbox is still running (the common case when upstream
// bookkeeping over-eagerly issues resume requests for a VM that was
// never actually suspended), the handler is a no-op: the existing tmux
// `copilot --remote --continue` session and its already-injected tokens
// are left untouched.
//
// When the sandbox is genuinely not-running, this handler runs the full
// recovery flow introduced by PR #13074: ResumeSandbox to unsuspend,
// mint a fresh user-to-server token, then kill the existing tmux
// `copilot` session in the VM and start a new detached one running
// `copilot --remote --continue` against the fresh token.
//
// Concurrent ResumeAgentCompute calls for the same compute_id can race the
// kill-then-relaunch step. We rely on the stopguard bump plus upstream
// orchestration (e.g., the launch service serializing per-sandbox actions)
// to prevent overlap rather than locking in-process; sweagentd is
// multi-replica and a local lock would be ineffective anyway.
func (s *Server) ResumeAgentCompute(ctx context.Context, req *jobs_pb.ResumeAgentComputeRequest) (*jobs_pb.ResumeAgentComputeResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.ResumeAgentCompute")
	defer span.End()

	if req.ComputeId == "" {
		return nil, twirp.RequiredArgumentError("compute_id")
	}
	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}

	logger := s.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("compute_id", req.ComputeId),
		kvp.Uint64("actor_id", req.ActorId),
	)
	metricTags := s.obsv.TelemetryTags(ctx)

	// Invalidate any pending delayed StopAgentCompute for this compute by
	// bumping the generation. A still-in-flight stop job will fail its
	// IsCurrent check and become a no-op. We do this even on the no-op
	// path: if upstream had scheduled a delayed stop, that stop is now
	// unwanted since a fresh user turn is in flight.
	if s.stopGuard != nil {
		_, err := s.stopGuard.Record(req.ComputeId)
		if err != nil {
			logger.WithError(err).Warn("failed to invalidate stop-agent-compute generation; pending stop job may still fire")
		}
	}

	// Query the authoritative platform state. If this fails we fail
	// closed rather than falling through to the destructive resume
	// path — a transient Launch hiccup must not be allowed to nuke a
	// healthy in-VM tmux session.
	state, err := s.sandboxService.GetSandboxState(ctx, req.ComputeId, req.ActorId)
	if err != nil {
		s.obsv.Increment(ctx, "sandbox.cli_resume_state_query_error", metricTags)
		logger.WithError(err).Error("failed to query sandbox state for resume; failing closed to avoid disrupting a possibly-running session")
		return nil, twirp.NewError(twirp.Internal, "failed to query sandbox state for resume")
	}

	// Fast path: the VM is already running, so any "resume" request from
	// upstream is bookkeeping noise. Leave the existing tmux session and
	// its tokens alone — re-using those tokens is fine because the
	// session has been continuously alive since the last real
	// create/resume, so the token-age budget is identical to a "no stop
	// ever happened" scenario. Do NOT re-mint here: a fresh mint per
	// turn is exactly the destructive overhead this handler was created
	// to prevent (see PR #13074).
	if sandbox.IsSandboxRunning(state) {
		s.obsv.Increment(ctx, "sandbox.cli_resume_noop_running", metricTags)
		logger.WithFields(kvp.String("state", state)).
			Info("sandbox already running; skipping CLI resume to avoid disrupting in-VM tmux session")
		return &jobs_pb.ResumeAgentComputeResponse{}, nil
	}

	// Full resume path: the VM is genuinely suspended/stopped (or in
	// some other non-running state). Run the recovery flow.
	s.obsv.Increment(ctx, "sandbox.cli_resume_full", metricTags)
	logger.WithFields(kvp.String("state", state)).
		Info("sandbox not running; performing full CLI resume")

	info, err := s.sandboxService.GetSandboxInfo(ctx, req.ComputeId, req.ActorId)
	if err != nil {
		if errors.Is(err, sandbox.ErrSandboxLabelsMissing) {
			s.obsv.Increment(ctx, "sandbox.cli_resume_labels_missing", metricTags)
			logger.WithError(err).Error("cannot resume sandbox: required labels missing")
			return nil, twirp.NewError(twirp.Internal, "sandbox missing required labels; cannot resume")
		}
		logger.WithError(err).Error("failed to read sandbox info")
		return nil, twirp.NewError(twirp.Internal, "failed to read sandbox info")
	}
	logger = logger.WithFields(
		kvp.Int64("repository_id", info.RepositoryID),
		kvp.Int64("agent_id", info.AgentID),
	)

	repo, err := s.ghTwirp.GetRepoById(ctx, info.RepositoryID)
	if err != nil {
		logger.WithError(err).Error("failed to look up repository for resume")
		return nil, twirp.NewError(twirp.Internal, fmt.Sprintf("repository %d not found", info.RepositoryID))
	}
	repoNWO := fmt.Sprintf("%s/%s", repo.GetOwnerLogin(), repo.GetName())

	err = s.sandboxService.ResumeSandbox(ctx, req.ComputeId, req.ActorId)
	if err != nil {
		logger.WithError(err).Error("failed to resume sandbox VM")
		return nil, twirp.NewError(twirp.Internal, "failed to resume agent compute")
	}

	// From this point on, any failure leaves a running sandbox we must
	// best-effort stop so it does not linger on Launch's books.
	tokenResp, err := s.ghTwirp.SweagentdAPI().MintUserToServerTokenForRepos(ctx, &sweagentdTwirp.MintUserToServerTokenForReposRequest{
		UserId:  req.ActorId,
		AgentId: info.AgentID,
		Repositories: []*sweagentdTwirp.RepositoryScope{{
			RepositoryId: uint64(info.RepositoryID),
			Permissions:  agentComputeTokenPermissions,
		}},
	})
	if err != nil {
		s.obsv.Increment(ctx, "sandbox.cli_resume_token_mint_error", metricTags)
		logger.WithError(err).Error("failed to mint fresh token for resume")
		s.bestEffortStopAfterResume(ctx, req.ComputeId, req.ActorId)
		return nil, twirp.InternalErrorWith(goerrors.Errorf("failed to mint token: %w", err))
	}
	if tokenResp == nil || tokenResp.Token == "" {
		s.obsv.Increment(ctx, "sandbox.cli_resume_token_mint_error", metricTags)
		logger.Error("token mint returned empty token on resume")
		s.bestEffortStopAfterResume(ctx, req.ComputeId, req.ActorId)
		return nil, twirp.NewError(twirp.Internal, "empty token returned for resume")
	}

	freshEnv := map[string]string{
		"GITHUB_COPILOT_API_TOKEN": tokenResp.Token,
		"GITHUB_COPILOT_GIT_TOKEN": tokenResp.Token,
		"GITHUB_TOKEN":             tokenResp.Token,
		"REMOTE_JSON_RPC":          "true",
	}
	err = s.sandboxService.ResumeCopilotCLI(ctx, req.ComputeId, req.ActorId, repoNWO, freshEnv)
	if err != nil {
		logger.WithError(err).Error("failed to relaunch Copilot CLI on resumed sandbox")
		s.bestEffortStopAfterResume(ctx, req.ComputeId, req.ActorId)
		return nil, twirp.NewError(twirp.Internal, "failed to relaunch Copilot CLI on resumed sandbox")
	}

	logger.Info("Sandbox resumed and Copilot CLI relaunched with --continue")
	return &jobs_pb.ResumeAgentComputeResponse{}, nil
}

// bestEffortStopAfterResume mirrors the launcher-resumeAgent pattern: once
// ResumeSandbox has succeeded, any subsequent failure should not leave the
// VM running with a stale or no copilot session.
func (s *Server) bestEffortStopAfterResume(ctx context.Context, computeID string, actorID uint64) {
	stopCtx := context.WithoutCancel(ctx)
	stopErr := s.sandboxService.StopSandbox(stopCtx, computeID, actorID)
	if stopErr != nil {
		s.obsv.Increment(stopCtx, "sandbox.cli_resume_stop_after_failure_error", stats.Tags{})
		s.obsv.LoggerWithTelemetry(stopCtx).WithError(stopErr).Warn("failed to stop sandbox after resume failure")
	}
}
