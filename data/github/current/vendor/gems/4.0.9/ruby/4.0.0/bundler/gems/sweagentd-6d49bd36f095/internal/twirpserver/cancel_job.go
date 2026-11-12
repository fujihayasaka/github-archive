package twirpserver

import (
	"context"
	"errors"

	"github.com/github/go-mark"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobservice"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// CancelJob cancels a job by its associated session ID.
func (s *Server) CancelJob(ctx context.Context, req *jobs_pb.CancelJobRequest) (*jobs_pb.CancelJobResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CancelJob")
	defer span.End()

	if s.jobExecutor == nil {
		return nil, twirp.InternalError("job executor not configured")
	}

	if req.SessionId == "" {
		return nil, twirp.RequiredArgumentError("session_id")
	}
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}

	// Look up the job by session ID
	job, err := s.jobService.GetJobBySessionID(ctx, req.OwnerId, req.RepoId, req.SessionId)
	if err != nil {
		if jobservice.IsJobNotFound(err) {
			return nil, twirp.NotFoundError("no job found for session ID")
		}
		return nil, goerrors.Errorf("failed to get job by session ID: %w", err)
	}
	if job == nil {
		return nil, twirp.NotFoundError("no job found for session ID")
	}

	// Create a GitHub client for the job's agent app so we can terminate workflow runs
	app, err := s.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return nil, goerrors.Errorf("failed to find app for agent: %w", err)
	}

	gh, err := s.ghf.NewClientFromRepo(ctx, app, req.RepoId, req.OwnerId)
	if err != nil {
		return nil, goerrors.Errorf("failed to create github client: %w", err)
	}

	// Resolve the repo NWO from the numeric IDs
	repo, err := gh.GetRepositoryByID(ctx, req.RepoId)
	if err != nil {
		return nil, goerrors.Errorf("failed to get repository: %w", err)
	}

	err = s.jobExecutor.CancelJob(ctx, gh, job, repo.GetOwner().GetLogin(), repo.GetName())
	if err != nil {
		if errors.Is(err, mark.ErrAlreadyExists) {
			return nil, twirp.FailedPrecondition.Error(err.Error())
		}
		return nil, goerrors.Errorf("failed to cancel job: %w", err)
	}

	return &jobs_pb.CancelJobResponse{
		Status: convertJobStatus(job.Status),
	}, nil
}
