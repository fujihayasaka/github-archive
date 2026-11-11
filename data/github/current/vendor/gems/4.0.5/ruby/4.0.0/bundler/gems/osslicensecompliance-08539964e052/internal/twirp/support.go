package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/repocheck"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func convertCheckStatusToProto(status models.CheckStatus) proto.CheckJobStatus {
	switch status {
	case models.Starting:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_STARTING
	case models.Waiting:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_WAITING
	case models.Running:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_RUNNING
	case models.Pass:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_PASS
	case models.Fail:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_FAIL
	case models.Error:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_ERROR
	default:
		return proto.CheckJobStatus_CHECK_JOB_STATUS_UNKNOWN
	}
}

// CheckStatus gets the status of a CheckRepository process.
func (s *Server) CheckStatus(ctx context.Context, req *proto.CheckStatusRequest) (*proto.CheckStatusResponse, error) {
	prNumber, ok := toUint32(req.PullRequestNumber)
	if !ok {
		return nil, twirp.InvalidArgumentError("pull_request_number", "must be between 0 and 4294967295 (uint32 max)")
	}

	result, err := s.app.Subsystems.Storage.GetCheckJob(ctx, req.RepositoryId, prNumber)
	if result == nil && err == nil {
		return nil, twirp.NotFoundError(fmt.Sprintf("no license check job found for repository %d and pull request number %d", req.RepositoryId, req.PullRequestNumber))
	}
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	var enterpriseID uint64
	if result.EnterpriseID != nil {
		enterpriseID = *result.EnterpriseID
	}

	return &proto.CheckStatusResponse{
		Id:                result.ID,
		Status:            convertCheckStatusToProto(result.Status),
		CheckStartedAt:    timestamppb.New(result.CheckStartedAt),
		RepositoryId:      result.RepositoryID,
		OrganizationId:    result.OrganizationID,
		PullRequestId:     result.PullRequestID,
		PullRequestNumber: uint64(result.PullRequestNumber),
		EnterpriseId:      enterpriseID,
		BaseSha:           result.BaseSHA,
		CommitSha:         result.CommitSHA,
		ExpectedSnapshots: result.ExpectedSnapshots,
		ReceivedSnapshots: result.ReceivedSnapshots,
		MissingDetectors:  result.MissingDetectors,
	}, nil
}

// GetAlertsForPullRequest retrieves all alerts for a specific repository and pull request.
// This lives in support.go because it's only used by stafftools at this time.
func (s *Server) GetAlertsForPullRequest(ctx context.Context, req *proto.GetAlertsForPullRequestRequest) (*proto.GetAlertsForPullRequestResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.PullRequestNumber == 0 {
		return nil, twirp.RequiredArgumentError("pull_request_number")
	}

	prNumber, ok := toUint32(req.PullRequestNumber)
	if !ok {
		return nil, twirp.InvalidArgumentError("pull_request_number", "must be between 0 and 4294967295 (uint32 max)")
	}

	alerts, err := s.app.Subsystems.Storage.GetAlertsForPullRequest(ctx, req.RepositoryId, prNumber)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	protoAlerts := make([]*proto.Alert, 0, len(alerts))
	for _, alert := range alerts {
		protoAlert := modelToProtoAlert(alert)
		protoAlerts = append(protoAlerts, protoAlert)
	}

	return &proto.GetAlertsForPullRequestResponse{
		Alerts: protoAlerts,
	}, nil
}

// RestartCheckJob restarts a license check for an existing CheckJob.
// This is used for support requests to re-run a check without requiring a new commit.
func (s *Server) RestartCheckJob(ctx context.Context, req *proto.RestartCheckJobRequest) (*proto.RestartCheckJobResponse, error) {
	if req.RepositoryId == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}
	if req.PullRequestNumber == 0 {
		return nil, twirp.RequiredArgumentError("pull_request_number")
	}

	prNumber, ok := toUint32(req.PullRequestNumber)
	if !ok {
		return nil, twirp.InvalidArgumentError("pull_request_number", "must be between 0 and 4294967295 (uint32 max)")
	}

	checkJob, err := s.app.Subsystems.Storage.GetCheckJob(ctx, req.RepositoryId, prNumber)
	if checkJob == nil && err == nil {
		return nil, twirp.NotFoundError(fmt.Sprintf("no license check job found for repository %d and pull request number %d", req.RepositoryId, req.PullRequestNumber))
	}
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if checkJob.Status != models.Pass && checkJob.Status != models.Fail && checkJob.Status != models.Error && checkJob.Status != models.Waiting {
		return nil, twirp.InvalidArgumentError("status", fmt.Sprintf("check job must be in Pass, Fail, Error, or Waiting status to restart, current status is %s", checkJob.Status))
	}

	// Restart the check job in background
	asyncCtx := context.WithoutCancel(ctx) // Background job should not inherit cancellation or values from request context
	go s.restartCheckJob(asyncCtx, checkJob)

	return &proto.RestartCheckJobResponse{
		Success: true,
	}, nil
}

func (s *Server) restartCheckJob(ctx context.Context, checkJob *models.CheckJob) {
	logger := s.app.Logger.Named("twirp-support")
	logger.Info("Restarting check job",
		kvp.Uint64("repository_id", checkJob.RepositoryID),
		kvp.Uint32("pull_request_number", checkJob.PullRequestNumber))

	// Build a request from the existing checkJob data
	checkRequest := &repocheck.Request{
		EnterpriseID:      pointers.ValueOrZero(checkJob.EnterpriseID),
		OrganizationID:    checkJob.OrganizationID,
		RepositoryID:      checkJob.RepositoryID,
		PullRequestID:     checkJob.PullRequestID,
		ForkRepositoryID:  pointers.ValueOrZero(checkJob.ForkRepositoryID),
		PullRequestNumber: checkJob.PullRequestNumber,
		Context:           "distributed", // Default context for restart
		CommitSHA:         checkJob.CommitSHA,
		BaseSHA:           checkJob.BaseSHA,
	}

	checker := repocheck.NewChecker(s.app, s.app.StatsClient).WithTags(map[string]string{"source": "twirp-restart"})
	if err := checker.Start(ctx, checkJob, checkRequest); err != nil {
		logger.Error("restart check job failed", kvp.String("error", err.Error()))
		if reportErr := reporter.Report(ctx, err); reportErr != nil {
			logger.WithError(reportErr).Error("failed to report error to Sentry")
		}
	}
}
