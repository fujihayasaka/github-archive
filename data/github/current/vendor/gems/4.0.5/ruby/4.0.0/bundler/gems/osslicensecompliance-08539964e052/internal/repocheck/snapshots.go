package repocheck

import (
	"context"
	"errors"
	"fmt"
	"time"

	ds "github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-server/runtime/telemetry/reporter"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dsapiclient"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
)

// SnapshotReceived is the handler for events we receive when a snapshot has been added to DS-API.
// It looks up a CheckJob by commit SHA and wakes it if found and in Waiting status.
func SnapshotReceived(ctx context.Context, app *application.Application, repositoryID uint64, commitSHA string) error {
	checkJob, err := app.Subsystems.Storage.GetCheckJobByCommit(ctx, repositoryID, commitSHA)
	if err != nil {
		return err
	}
	return WakeCheckJob(ctx, app, checkJob)
}

// WakeCheckJob processes a waiting CheckJob: checks snapshot status, and if all snapshots
// are received, executes the license check. If checkJob is nil or not in Waiting status,
// it returns nil (no-op).
func WakeCheckJob(ctx context.Context, app *application.Application, checkJob *models.CheckJob) error {
	if checkJob == nil || checkJob.Status != models.Waiting {
		return nil
	}

	logger := app.Logger.Named("WakeCheckJob").WithFields(
		semconv.Method("WakeCheckJob"),
		semconv.RepositoryID(checkJob.RepositoryID),
		semconv.CommitSHA(checkJob.CommitSHA),
		semconv.CheckJobID(checkJob.ID),
	)

	var forkRepositoryID uint64
	if checkJob.ForkRepositoryID != nil {
		forkRepositoryID = *checkJob.ForkRepositoryID
		logger = logger.WithFields(semconv.ForkRepositoryID(forkRepositoryID))
	}

	snapStatus, err := GetSnapshotStatus(ctx, app.Logger, app.Subsystems.DiffStatusGetter, checkJob.RepositoryID, checkJob.CommitSHA, checkJob.BaseSHA, forkRepositoryID, checkJob.OrganizationID)
	if err != nil {
		// Not changing the check job status here since this error is retryable,
		// plus we only allow check jobs with status 'Waiting' to be processed.
		app.Subsystems.EventPublisher.PublishLicenseCheckError(ctx, checkJob.CommitSHA, checkJob.RepositoryID, SanitizeError(ErrSnapshotStatus))
		return fmt.Errorf("%w: %w", ErrSnapshotStatus, err)
	}

	if snapStatus.IsWaiting() {
		duration := time.Since(checkJob.CheckStartedAt)
		logger.Info("WakeCheckJob",
			kvp.String("diffStatus", "waiting for snapshots before running check"),
			semconv.BaseSHA(checkJob.BaseSHA),
			kvp.String("duration", duration.String()),
		)
		app.StatsClient.DistributionMs("snapshot.waiting.duration", nil, duration)

		checkJob.ExpectedSnapshots = snapStatus.Expected
		checkJob.ReceivedSnapshots = snapStatus.Received
		checkJob.MissingDetectors = snapStatus.MissingDetectors
		checkJob.DependabotPending = snapStatus.DependabotPending
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
		ForkRepositoryID:  forkRepositoryID,
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
			if reportErr := reporter.ReportWithValues(ctx, err, nil); reportErr != nil {
				logger.WithError(reportErr).Error("failed to report error to Sentry")
			}
		}

		return nil // Don't return error to avoid retrying malformed messages
	}

	// Don't want to update these until after validating the request.
	// Clear MissingDetectors — we have all snapshots now (snapStatus.MissingDetectors is empty).
	checkJob.ExpectedSnapshots = snapStatus.Expected
	checkJob.ReceivedSnapshots = snapStatus.Received
	checkJob.MissingDetectors = snapStatus.MissingDetectors
	checkJob.DependabotPending = snapStatus.DependabotPending
	err = app.Subsystems.Storage.UpdateCheckJob(ctx, checkJob)
	if err != nil {
		app.Subsystems.EventPublisher.PublishLicenseCheckError(ctx, checkJob.CommitSHA, checkJob.RepositoryID, SanitizeError(ErrCheckJobUpdate))
		return fmt.Errorf("%w: %w", ErrCheckJobUpdate, err)
	}

	checker := NewChecker(app, app.StatsClient).WithTags(map[string]string{"source": "snapshot_consumer"})
	return checker.ExecuteJob(ctx, checkJob, checkRequest)
}

// SnapshotDiffStatus holds the status of snapshot comparison between base and head commits.
type SnapshotDiffStatus struct {
	Expected          uint32
	Received          uint32
	MissingDetectors  []string
	DependabotPending bool
}

// IsWaiting returns true if we are still waiting for snapshots to be received.
func (s *SnapshotDiffStatus) IsWaiting() bool {
	return s.Received < s.Expected || s.DependabotPending
}

// GetSnapshotStatus checks if we need to wait for snapshots to be available before running the check.
// It returns the current diff snapshot status
func GetSnapshotStatus(ctx context.Context, logger log.Logger, diffStatusGetter *dsapiclient.StatusGetter, repositoryID uint64, commitSHA, baseSHA string, forkRepositoryID, ownerID uint64) (diffStatus *SnapshotDiffStatus, err error) {
	basehead := fmt.Sprintf("%s...%s", baseSHA, commitSHA)
	start := time.Now()
	response, err := diffStatusGetter.SnapshotsDiffStatusGetter.GetSnapshotDiffStatus(ctx, &ds.GetSnapshotDiffStatusRequest{
		RepositoryId:       repositoryID,
		Basehead:           basehead,
		TargetRepositoryId: forkRepositoryID,
		OwnerId:            ownerID,
	})
	diffStatusGetter.Metrics.DistributionMs("dsapi.get_snapshot_diff_status.duration", nil, time.Since(start))
	if err != nil {
		return &SnapshotDiffStatus{}, err
	}

	missingDetectors := []string{}
	if response.MissingDetectors != nil {
		missingDetectors = response.MissingDetectors
	}
	return &SnapshotDiffStatus{
		Expected:          response.BaseSnapshotCount,
		Received:          response.HeadSnapshotCount,
		MissingDetectors:  missingDetectors,
		DependabotPending: response.DependabotPending,
	}, nil
}
