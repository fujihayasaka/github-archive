package twirpserver

import (
	"context"
	"errors"
	"strings"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/sweagentd"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// CreateCommand creates a new command for an existing job.
func (s *Server) CreateCommand(ctx context.Context, req *jobs_pb.CreateCommandRequest) (*jobs_pb.CreateCommandResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateCommand")
	defer span.End()

	// Validate the request fields
	if req.JobId == "" {
		return nil, twirp.RequiredArgumentError("job_id")
	}
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}
	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}
	if req.ExternalId == "" {
		return nil, twirp.RequiredArgumentError("external_id")
	}
	if strings.TrimSpace(req.Content) == "" {
		return nil, twirp.RequiredArgumentError("content")
	}
	if req.Timestamp == 0 {
		return nil, twirp.RequiredArgumentError("timestamp")
	}

	job, err := s.jobService.GetJobByID(ctx, req.OwnerId, req.RepoId, req.JobId)
	if err != nil {
		return nil, twirp.NotFoundError("no job found for ID")
	}

	app, err := s.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get agent for job: %w", err)
	}

	// Validate the user/repo has the agent enabled.
	// First-party external agents that manage their own enablement checks
	// are exempt from the monolith's disallow-flag gate.
	isEnabled, _, err := s.ghTwirp.IsAgentEnabled(ctx, app.AppID(), req.ActorId, req.RepoId)
	if err != nil {
		return nil, goerrors.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		if app.IsThirdPartyApp() {
			return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
		}
		if exempt, ok := app.(sweagentd.AgenticAppEnablementExempt); !ok || !exempt.SkipEnablementCheck() {
			return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
		}
	}

	// Need to get the user's details
	cu, err := s.ghTwirp.GetCopilotUserDetails(ctx, req.ActorId)
	if err != nil {
		return nil, goerrors.Errorf("failed to get user's Copilot details: %w", err)
	}

	// For now commands can only be created by the job's actor
	if job.ActorID != int64(cu.Id) {
		return nil, twirp.NotFoundError("no job found for ID")
	}

	// Check if user has sufficient quota before accepting the command.
	// Quota-exempt apps (e.g. Code Scanning) have their own billing model.
	if !s.appProvider.IsAgentCheckExempt(ctx, s.ffClient, job.AgentID, req.RepoId) {
		err = CheckQuota(ctx, s.ghTwirp, s.ffClient, s.obsv, req.OwnerId, req.RepoId, int64(cu.Id), "command")
		if err != nil {
			return nil, err
		}
	}

	createdCommand, err := s.jobService.CreateCommandForJob(ctx, job, req.ExternalId, int64(cu.Id), req.Content, req.Timestamp)
	if err != nil {
		if errors.Is(err, command.ErrJobIsTerminal) {
			return nil, twirp.FailedPrecondition.Error("cannot create command for job in terminal state")
		}
		return nil, goerrors.Errorf("failed to add command to job: %w", err)
	}

	return &jobs_pb.CreateCommandResponse{
		Id:         createdCommand.ID,
		ExternalId: createdCommand.ExternalID,
		JobId:      createdCommand.JobID,
	}, nil
}
