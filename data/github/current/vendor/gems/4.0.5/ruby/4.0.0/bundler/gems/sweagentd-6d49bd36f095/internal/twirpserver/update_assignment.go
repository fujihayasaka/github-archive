package twirpserver

import (
	"context"
	"errors"

	store "github.com/github/sweagentd/internal/jobs/store"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
)

// UpdateAssignment patches fields on an existing assignment.
// Only non-zero fields in the request are applied. The operation is idempotent.
func (s *Server) UpdateAssignment(ctx context.Context, req *jobs_pb.UpdateAssignmentRequest) (*jobs_pb.UpdateAssignmentResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.UpdateAssignment")
	defer span.End()

	if req.AssignmentId == "" {
		return nil, twirp.RequiredArgumentError("assignment_id")
	}
	if req.OwnerId == 0 {
		return nil, twirp.RequiredArgumentError("owner_id")
	}
	if req.RepoId == 0 {
		return nil, twirp.RequiredArgumentError("repo_id")
	}

	assignment, err := s.jobStore.GetAssignment(ctx, req.OwnerId, req.RepoId, req.AssignmentId)
	if err != nil {
		if errors.Is(err, store.ErrAssignmentNotFound) {
			return nil, twirp.NotFoundError("assignment not found")
		}
		s.obsv.LogAndReportError(ctx, err, "getting assignment for update")
		return nil, twirp.InternalErrorWith(err)
	}

	patch := store.AssignmentPatch{}

	if req.PullRequestId != 0 {
		prID := req.PullRequestId
		patch.PullRequestID = &prID
	}
	if req.PullRequestNumber != 0 {
		prNumber := int(req.PullRequestNumber)
		patch.PullRequestNumber = &prNumber
	}

	// Skip the write if the patch is empty or all requested fields already match
	// the stored assignment (idempotency: avoid unnecessary writes and ETag bumps).
	needsUpdate := (patch.PullRequestID != nil && assignment.PullRequestID != *patch.PullRequestID) ||
		(patch.PullRequestNumber != nil && assignment.PullRequestNumber != *patch.PullRequestNumber)
	if !needsUpdate {
		return &jobs_pb.UpdateAssignmentResponse{}, nil
	}

	err = s.jobStore.PatchAssignment(ctx, assignment, patch)
	if err != nil {
		if errors.Is(err, store.ErrPreconditionFailedOnUpdate) {
			// Concurrent update changed the ETag. Re-fetch and check whether the
			// desired state was already applied (idempotency).
			current, refetchErr := s.jobStore.GetAssignment(ctx, req.OwnerId, req.RepoId, req.AssignmentId)
			if refetchErr != nil {
				s.obsv.LogAndReportError(ctx, refetchErr, "re-fetching assignment after conflict")
				return nil, twirp.InternalErrorWith(refetchErr)
			}

			alreadyApplied := (patch.PullRequestID == nil || current.PullRequestID == *patch.PullRequestID) &&
				(patch.PullRequestNumber == nil || current.PullRequestNumber == *patch.PullRequestNumber)
			if alreadyApplied {
				return &jobs_pb.UpdateAssignmentResponse{}, nil
			}

			return nil, twirp.NewError(twirp.Aborted, "concurrent update conflict, please retry")
		}
		s.obsv.LogAndReportError(ctx, err, "patching assignment")
		return nil, twirp.InternalErrorWith(err)
	}

	return &jobs_pb.UpdateAssignmentResponse{}, nil
}
