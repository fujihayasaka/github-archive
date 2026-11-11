package repocheck

import (
	"context"
	"errors"
	"fmt"
	"time"

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

	snapStatus, err := GetSnapshotStatus(ctx, app.Logger, app.Subsystems.DiffStatusGetter, checkJob.RepositoryID, checkJob.CommitSHA, checkJob.BaseSHA)
	if err != nil {
		// Not changing the check job status here since this error is retryable,
		// plus we only allow check jobs with status 'Waiting' to be processed.
		app.Subsystems.EventPublisher.PublishLicenseCheckError(ctx, checkJob.CommitSHA, checkJob.RepositoryID, SanitizeError(ErrSnapshotStatus))
		return fmt.Errorf("%w: %w", ErrSnapshotStatus, err)
	}

	if snapStatus.IsWaiting() {
		duration := time.Since(checkJob.CheckStartedAt)
		logger.Info("SnapshotReceived",
			kvp.String("diffStatus", "waiting for snapshots before running check"),
			semconv.CheckJobID(checkJob.ID),
			semconv.RepositoryID(checkJob.RepositoryID),
			semconv.CommitSHA(checkJob.CommitSHA),
			semconv.BaseSHA(checkJob.BaseSHA),
			kvp.String("duration", duration.String()),
		)
		app.StatsClient.DistributionMs("snapshot.waiting.duration", nil, duration)

		checkJob.ExpectedSnapshots = snapStatus.Expected
		checkJob.ReceivedSnapshots = snapStatus.Received
		checkJob.Status = models.Waiting

		app.Subsystems.EventPublisher.PublishLicenseCheckProgress(ctx, checkJob)

		return app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
	}

	// We've received all the snapshots, so we can run the check
	app.StatsClient.DistributionMs("snapshot.waited.duration", nil, time.Since(checkJob.CheckStartedAt))

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

		app.Subsystems.EventPublisher.PublishLicenseCheckError(ctx, checkJob.CommitSHA, checkJob.RepositoryID, SanitizeError(err))

		checkJob.Status = models.Error
		err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
		if err != nil {
			logger.Error("failed to update check job status to error", kvp.String("error", err.Error()))
		}

		return nil // Don't return error to avoid retrying malformed messages
	}

	// Don't want to update these until after validating the request.
	checkJob.ExpectedSnapshots = snapStatus.Expected
	checkJob.ReceivedSnapshots = snapStatus.Received
	err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		app.Subsystems.EventPublisher.PublishLicenseCheckError(ctx, checkJob.CommitSHA, checkJob.RepositoryID, SanitizeError(ErrCheckJobUpdate))
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
	}

	checker := NewChecker(app, app.StatsClient).WithTags(map[string]string{"source": "snapshot_consumer"})
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

// IsWaiting returns true if we are still waiting for snapshots to be received.
func (s *SnapshotDiffStatus) IsWaiting() bool {
	return s.Received < s.Expected
}

// GetSnapshotStatus checks if we need to wait for snapshots to be available before running the check.
// It returns the current diff snapshot status
func GetSnapshotStatus(ctx context.Context, logger log.Logger, diffStatusGetter *dsapiclient.StatusGetter, repositoryID uint64, commitSHA, baseSHA string) (diffStatus *SnapshotDiffStatus, err error) {
	basehead := fmt.Sprintf("%s...%s", baseSHA, commitSHA)
	start := time.Now()
	response, err := diffStatusGetter.SnapshotsDiffStatusGetter.GetSnapshotDiffStatus(ctx, &ds.GetSnapshotDiffStatusRequest{
		RepositoryId: repositoryID,
		Basehead:     basehead,
	})
	diffStatusGetter.Metrics.DistributionMs("dsapi.get_snapshot_diff_status.duration", nil, time.Since(start))
	if err != nil {
		logger.Error("GetSnapshotStatus: error getting snapshot diff status", kvp.String("error_msg", err.Error()))
		return &SnapshotDiffStatus{}, err
	}

	detectors := []string{}
	if response.MissingDetectors != nil {
		detectors = response.MissingDetectors
	}
	return &SnapshotDiffStatus{
		Expected:  response.BaseSnapshotCount,
		Received:  response.HeadSnapshotCount,
		Detectors: detectors,
	}, nil
}
