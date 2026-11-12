package repocheck

import (
	"context"
	"errors"
	"fmt"

	ds "github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dsapiclient"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
)

// SnapshotReceived is the handler for events we receive when a snapshot has been added to DS-API.
// We check to see if we have received all of the expected snapshots. If we have, we can start the
// license check.
func SnapshotReceived(ctx context.Context, app *application.Application, repositoryID uint64, commitSHA string) error {
	logger := app.Logger.Named("SnapshotReceived").WithFields(
		semconv.Method("SnapshotReceived"),
		semconv.RepositoryID(repositoryID),
		semconv.CommitSHA(commitSHA),
	)

	checkJob, err := app.Subsystems.Storage.GetCheckJobByCommit(ctx, repositoryID, commitSHA)
	if err != nil {
		return err
	}
	if checkJob == nil || checkJob.Status != models.Waiting {
		return nil
	}

	// Check if need to wait for snapshots
	var waiting bool
	var diffStatus *SnapshotDiffStatus
	if diffStatus, waiting, err = WaitingForSnapshots(ctx, app.Logger, app.Subsystems.DiffStatusGetter, checkJob.RepositoryID, checkJob.CommitSHA, checkJob.BaseSHA); waiting {
		logger.Info("SnapshotReceived", kvp.String("diffStatus", "waiting for snapshots before running check"))
		checkJob.ExpectedSnapshots = diffStatus.Expected
		checkJob.ReceivedSnapshots = diffStatus.Received
		return app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
	}
	if err != nil {
		return fmt.Errorf("failed checking snapshot wait status: %w", err)
	}

	// We've received all the snapshots, so we can run the check
	// Create a Request based on the checkJob
	var enterpriseID uint64
	if checkJob.EnterpriseID == nil {
		enterpriseID = 0
	} else {
		enterpriseID = *checkJob.EnterpriseID
	}
	// TODO: set context properly from the checkJob
	// https://github.com/github/dependency-graph/issues/7858
	distributionContext := "distributed"
	checkRequest := &Request{
		EnterpriseID:      enterpriseID,
		OrganizationID:    checkJob.OrganizationID,
		RepositoryID:      checkJob.RepositoryID,
		PullRequestID:     checkJob.PullRequestID,
		PullRequestNumber: checkJob.PullRequestNumber,
		Context:           distributionContext,
		BaseSHA:           checkJob.BaseSHA,
		CommitSHA:         checkJob.CommitSHA,
	}
	err = checkRequest.Validate()
	if err != nil {
		var validationErr *ValidationError
		errors.As(err, &validationErr)
		logger.Error("validation error in check request", kvp.Any("missing_fields", validationErr.MissingFields))
		return nil // Don't return error to avoid retrying malformed messages
	}

	// Don't want to update these until after validating the request.
	checkJob.ExpectedSnapshots = diffStatus.Expected
	checkJob.ReceivedSnapshots = diffStatus.Received
	err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		return fmt.Errorf("failed checking snapshot wait status: %w", err)
	}

	checker := NewChecker(app)
	if err := checker.ExecuteJob(ctx, checkJob, checkRequest); err != nil {
		logger.WithError(err).Error("repository check failed")
		return err
	}
	return nil
}

// SnapshotDiffStatus holds the status of snapshot comparison between base and head commits.
type SnapshotDiffStatus struct {
	Expected  uint32
	Received  uint32
	Detectors []string
}

// EmptySnapshotDiffStatus is used when there are no snapshots or an error occurred getting the status.
var EmptySnapshotDiffStatus = SnapshotDiffStatus{
	Expected:  0,
	Received:  0,
	Detectors: []string{},
}

// WaitingForSnapshots checks if we need to wait for snapshots to be available before running the check.
// It returns the current diff status and a boolean indicating if we are still waiting.
func WaitingForSnapshots(ctx context.Context, logger log.Logger, diffStatusGetter *dsapiclient.StatusGetter, repositoryID uint64, commitSHA, baseSHA string) (diffStatus *SnapshotDiffStatus, waiting bool, err error) {
	basehead := fmt.Sprintf("%s...%s", baseSHA, commitSHA)
	response, err := diffStatusGetter.SnapshotsDiffStatusGetter.GetSnapshotDiffStatus(ctx, &ds.GetSnapshotDiffStatusRequest{
		RepositoryId: repositoryID,
		Basehead:     basehead,
	})
	if err != nil {
		logger.Error("WaitingForSnapshots: error getting snapshot diff status", kvp.String("error_msg", err.Error()))
		return &EmptySnapshotDiffStatus, false, err
	}

	waiting = response.HeadSnapshotCount < response.BaseSnapshotCount
	detectors := []string{}
	if response.MissingDetectors != nil {
		detectors = response.MissingDetectors
	}
	return &SnapshotDiffStatus{
		Expected:  response.BaseSnapshotCount,
		Received:  response.HeadSnapshotCount,
		Detectors: detectors,
	}, waiting, nil
}
