package twirpserver

import (
	"context"
	"errors"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	gg "github.com/google/go-github/v75/github"
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

	// Surface quota errors at assignment creation time if actor_id is provided.
	// Note: actor_id is optional for backwards compatibility during the migration period.
	// Once all clients are updated to send actor_id, this should be made required.
	if req.ActorId != 0 {
		err := CheckQuota(ctx, s.ghTwirp, s.ffClient, s.obsv, req.OwnerId, req.RepoId, req.ActorId, "assignment")
		if err != nil {
			return nil, err
		}
	}

	// TODO: Assignments need to store the repo's owner/repo node IDs for GraphQL usage
	// For now, we need to fetch those from the REST API because our internal monolith-twirp
	// API doesn't return them. We'll be able to migrate to usersd/reposd soon.
	gh, err := s.ghf.NewClientFromRepo(ctx, s.appProvider.CopilotApp(), req.RepoId, req.OwnerId)
	if err != nil {
		s.obsv.LogAndReportError(ctx, err, "creating gh client from repo")
		var twerr twirp.Error
		if errors.As(err, &twerr) {
			return nil, twerr
		}
		return nil, twirp.InternalErrorWith(err)
	}
	repo, err := gh.GetRepositoryByID(ctx, req.RepoId)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	additionalRepositories, err := s.fetchAdditionalRepositories(ctx, req.GetAdditionalRepositories(), req.GetActorId(), req.GetRepoId())
	if err != nil {
		return nil, goerrors.Errorf("failed to fetch additional repositories: %w", err)
	}

	return s.createAssignment(ctx, req.OwnerId, req.RepoId, repo, additionalRepositories)
}

// createAssignment contains the core assignment creation logic without quota checking.
// Internal callers that have already performed quota checks should use this directly.
// The repo parameter must be pre-fetched by the caller.
func (s *Server) createAssignment(ctx context.Context, ownerID, repoID int64, repo *gg.Repository, additionalRepositories []*gg.Repository) (*jobs_pb.CreateAssignmentResponse, error) {
	// Create a new assignment with no resources
	// Check the feature flag using repo ID since this endpoint doesn't have user context
	useAsyncSessions := s.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentUseAsyncSessions, repoID)
	assignment := jobs.NewAssignment(
		ownerID,
		repoID,
		*repo.Owner.NodeID,
		*repo.NodeID,
		*repo.Owner.Login,
		*repo.Name,
		useAsyncSessions,
	)

	// Set the created timestamp
	assignment.CreatedAt = time.Now().Unix()

	if len(additionalRepositories) > 0 {
		assignment.AdditionalRepositories = make([]jobs.RepositoryRef, len(additionalRepositories))
		for i, additionalRepository := range additionalRepositories {
			assignment.AdditionalRepositories[i] = jobs.RepositoryRef{
				RepoID:      *additionalRepository.ID,
				OwnerID:     *additionalRepository.Owner.ID,
				RepoNodeID:  *additionalRepository.NodeID,
				OwnerNodeID: *additionalRepository.Owner.NodeID,
			}
		}
	}

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
