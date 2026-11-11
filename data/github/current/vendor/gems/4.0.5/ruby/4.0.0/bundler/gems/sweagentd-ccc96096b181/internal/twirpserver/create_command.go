package twirpserver

import (
	"context"
	"errors"
	"strings"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/command"
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

	app, err := s.appProvider.FindByID(job.AgentID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get agent for job: %w", err)
	}

	// Validate the user/repo has the agent enabled
	isEnabled, _, err := s.ghTwirp.IsAgentEnabled(ctx, app.AppID(), req.ActorId, req.RepoId)
	if err != nil {
		return nil, goerrors.Errorf("failed to check repo enablement: %w", err)
	}
	if !isEnabled {
		return nil, twirp.Aborted.Error("user or repo does not have CCA enabled")
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

	// Check if user has sufficient quota before accepting the command
	hasSufficientQuota, _, err := githubtwirp.CheckPremiumQuota(ctx, s.ghTwirp, s.ffClient, s.obsv, req.OwnerId, req.RepoId, int64(cu.Id))
	if err != nil {
		if !errors.Is(err, githubtwirp.ErrCustomerSelectionRequired) {
			return nil, goerrors.Errorf("failed to check quota: %w", err)
		}
		// Check if the feature flag is enabled to determine behavior
		if s.ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentSelectCustomerError, job) {
			// Feature flag enabled: return error to client
			s.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in Copilot settings, returning error")
			return nil, twirp.FailedPrecondition.Error("customer selection required")
		}
		// Feature flag disabled: log and continue (skip quota check)
		s.obsv.LoggerWithTelemetry(ctx).Info("user needs to select customer in Copilot settings, but continuing due to feature flag")
	} else if !hasSufficientQuota {
		return nil, twirp.ResourceExhausted.Error("insufficient premium quota to create command")
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
