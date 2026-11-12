package twirpserver

import (
	"context"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// CreateAssignment creates a new empty assignment for the given repository.
func (s *Server) CreateAssignment(ctx context.Context, req *jobs_pb.CreateAssignmentRequest) (*jobs_pb.CreateAssignmentResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateAssignment")
	defer span.End()

	// Validate the request fields
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}

	// TODO: Assignments need to store the repo's owner/repo node IDs for GraphQL usage
	// For now, we need to fetch those from the REST API because our internal monolith-twirp
	// API doesn't return them. We'll be able to migrate to usersd/reposd soon.
	gh, err := s.ghf.NewClientFromRepo(ctx, s.appProvider.CopilotApp(), req.RepoId, req.OwnerId)
	if err != nil {
		s.obsv.LogAndReportError(ctx, err, "creating gh client from repo")
		return nil, twirp.InternalErrorWith(err)
	}
	repo, err := gh.GetRepositoryByID(ctx, req.RepoId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	// Create a new assignment with no resources
	// Check the feature flag using repo ID since this endpoint doesn't have user context
	useAsyncSessions := s.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, req.RepoId)
	assignment := jobs.NewAssignment(
		req.OwnerId,
		req.RepoId,
		*repo.Owner.NodeID,
		*repo.NodeID,
		*repo.Owner.Login,
		*repo.Name,
		useAsyncSessions,
	)

	// Set the created timestamp
	assignment.CreatedAt = time.Now().Unix()

	// Persist the assignment
	createdAssignment, err := s.jobStore.CreateAssignment(ctx, assignment)
	if err != nil {
		s.obsv.LogAndReportError(ctx, err, "creating assignment")
		return nil, twirp.InternalErrorWith(err)
	}

	return &jobs_pb.CreateAssignmentResponse{
		Id:        createdAssignment.ID,
		CreatedAt: createdAssignment.CreatedAt,
		OwnerId:   createdAssignment.OwnerID,
		RepoId:    createdAssignment.RepoID,
	}, nil
}
