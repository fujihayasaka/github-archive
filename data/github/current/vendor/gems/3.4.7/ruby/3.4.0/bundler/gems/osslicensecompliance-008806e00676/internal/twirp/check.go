package twirp

import (
	"context"
	"errors"
	"math"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/repocheck"
	"github.com/github/osslicensecompliance/internal/semconv"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
	"go.uber.org/zap/zapcore"
)

// CheckRepository runs a license policy check for a given repository with an optional commit sha.
func (s *Server) CheckRepository(ctx context.Context, req *proto.CheckRepositoryRequest) (*proto.CheckRepositoryResponse, error) {
	// Check DB for existing CheckJob for this repo/pr
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.PullRequestNumber == 0 {
		return nil, twirp.RequiredArgumentError("pull_request_number")
	}
	var pullRequestNumber uint32
	var ok bool
	if pullRequestNumber, ok = toUint32(req.PullRequestNumber); !ok {
		return nil, twirp.InvalidArgumentError("pullRequestNumber out of range", "must be between 0 and 4294967295 (uint32 max)")
	}

	checkJob, err := s.app.Subsystems.Storage.GetCheckJob(ctx, req.RepositoryId, pullRequestNumber)
	if err != nil && !errors.Is(err, storage.ErrNotFound) {
		return nil, twirp.InternalErrorWith(err)
	}
	if checkJob != nil && checkJob.CommitSHA == req.CommitSha && checkJob.BaseSHA == req.BaseSha {
		// existing PR with no new commits
		var respStatus proto.RepositoryCheckStatus
		switch checkJob.Status {
		case models.Starting, models.Waiting, models.Running:
			respStatus = proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PENDING
			return &proto.CheckRepositoryResponse{
				Status:  respStatus,
				Message: "", // TODO: This will be used later to inform user of progress
			}, nil
		case models.Pass:
			respStatus = proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PASS
			return &proto.CheckRepositoryResponse{
				Status:  respStatus,
				Message: "",
			}, nil
		case models.Fail:
			respStatus = proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_FAIL
			return &proto.CheckRepositoryResponse{
				Status:  respStatus,
				Message: "",
			}, nil
		}
		// This should not happen, but handle it just in case
		return &proto.CheckRepositoryResponse{
			Status:  proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_UNKNOWN,
			Message: "",
		}, nil
	}

	// if no CheckJob for PR or there is a new commit or change in base, run the check in background
	go s.startCheckRepository(context.Background(), req, pullRequestNumber, checkJob) //nolint:contextcheck // Background job should not inherit cancellation or values from request context

	return &proto.CheckRepositoryResponse{
		Status:  proto.RepositoryCheckStatus_REPOSITORY_CHECK_STATUS_PENDING,
		Message: "",
	}, nil
}

func (s *Server) startCheckRepository(ctx context.Context, req *proto.CheckRepositoryRequest, pullRequestNumber uint32, checkJob *models.CheckJob) {
	fields := []zapcore.Field{semconv.Method("startCheckRepository")}
	fields = append(fields, semconv.RepoCheckRequestFields(
		req.EnterpriseId, req.OrganizationId, req.RepositoryId,
		req.PullRequestId, pullRequestNumber, req.CommitSha, req.BaseSha)...)

	logger := s.app.Logger.Named("twirp-check").WithFields(fields...)

	// TEMPORARY: default to "distributed" context if not specified
	// only because distribution contexts are not yet implemented in the UI.
	// Remove during https://github.com/github/dependency-graph/issues/7604
	distributionContext := "distributed"
	if req.Context != "" {
		distributionContext = req.Context
	}
	checkRequest := &repocheck.Request{
		EnterpriseID:      req.EnterpriseId,
		OrganizationID:    req.OrganizationId,
		RepositoryID:      req.RepositoryId,
		PullRequestID:     req.PullRequestId,
		PullRequestNumber: pullRequestNumber,
		Context:           distributionContext,
		CommitSHA:         req.CommitSha,
		BaseSHA:           req.BaseSha,
	}

	checker := repocheck.NewChecker(s.app)
	if err := checker.Start(ctx, checkJob, checkRequest); err != nil {
		// We log errors but do not return failure response because this is a background job
		// and the user has already received a success response for the twirp request.
		logger.Error("background check repository failed", kvp.String("error", err.Error()))
	}
}

func toUint32(i uint64) (value uint32, ok bool) {
	if i > math.MaxUint32 {
		return math.MaxUint32, false
	}
	return uint32(i), true
}
