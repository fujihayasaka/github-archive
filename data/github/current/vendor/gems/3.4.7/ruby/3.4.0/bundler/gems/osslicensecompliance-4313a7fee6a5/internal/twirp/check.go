package twirp

import (
	"context"
	"errors"

	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
)

// CheckRepository runs a license policy check for a given repository with an optional commit sha.
func (s *Server) CheckRepository(ctx context.Context, req *proto.CheckRepositoryRequest) (*proto.CheckRepositoryResponse, error) {
	// TEMPORARY: default to "distributed" context if not specified
	// only because distribution contexts are not yet implemented in the UI.
	// Remove during https://github.com/github/dependency-graph/issues/7604
	distributionContext := "distributed"
	if req.Context != "" {
		distributionContext = req.Context
	}
	checkRequest := repocheck.RepositoryCheckRequest{
		Subsystems:     s.app.Subsystems,
		EnterpriseID:   req.EnterpriseId,
		OrganizationID: req.OrganizationId,
		RepositoryID:   req.RepositoryId,
		Context:        distributionContext,
		CommitSHA:      req.CommitSha,
		BaseSHA:        req.BaseSha,
		Logger:         s.app.Logger,
	}
	if checkRequest.BaseSHA == "" || checkRequest.CommitSHA == "" {
		// If either BaseSHA or CommitSHA is empty, we cannot perform a diff check.
		// Return an invalid request error
		return nil, twirp.RequiredArgumentError("base_sha/commit_sha")
	}
	results, err := repocheck.CheckRepository(ctx, checkRequest)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			return nil, twirp.InvalidArgumentError("repository_id", "no policy found for repository/org/enterprise combination")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	var message string

	// When async is implemented, the status may be pending.
	status := proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PASS
	if results.FailureCount > 0 || results.ErrorCount > 0 {
		status = proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_FAIL
		if results.LastError != nil {
			message = results.LastError.Error()
		}
	}

	return &proto.CheckRepositoryResponse{
		Status:  status,
		Message: message,
	}, nil
}
