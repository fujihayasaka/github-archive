package remediation

import (
	"context"
	"fmt"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/semconv"
)

// PublishEventsForAffectedPRs publishes LicenseCheckCompleteEvents for all PRs affected by closed alerts.
// This ensures dotcom is notified when policy changes result in alerts being closed, so it can sync its state.
func PublishEventsForAffectedPRs(ctx context.Context, app *application.Application, closedAlerts []*models.Alert) error {
	// Group alerts by repository and PR
	type prKey struct {
		repositoryID      uint64
		pullRequestNumber uint32
	}
	affectedPRs := make(map[prKey]bool)

	for _, alert := range closedAlerts {
		if alert.PullRequestNumber != nil {
			key := prKey{
				repositoryID:      alert.RepositoryID,
				pullRequestNumber: *alert.PullRequestNumber,
			}
			affectedPRs[key] = true
		}
	}

	// For each affected PR, fetch current state and publish event
	for pr := range affectedPRs {
		if err := publishEventForPR(ctx, app, pr.repositoryID, pr.pullRequestNumber); err != nil {
			// Log error but continue with other PRs
			app.Logger.Named("policy-change-events").WithError(err).Error("failed to publish event for affected PR",
				semconv.RepositoryID(pr.repositoryID),
				semconv.PullRequestNumber(pr.pullRequestNumber),
			)
		}
	}

	return nil
}

func publishEventForPR(ctx context.Context, app *application.Application, repositoryID uint64, prNumber uint32) error {
	// Get the check job for this PR. The check job contains:
	// - PullRequestID: GitHub's internal PR ID needed for event publishing
	// - CommitSHA and BaseSHA: commit information needed for event publishing
	// - EnterpriseID and OrganizationID: needed to fetch the complete policy for remediation guidance
	// If no check job exists, the PR hasn't been checked yet, so there's nothing to update.
	checkJob, err := app.Subsystems.Storage.GetCheckJob(ctx, repositoryID, prNumber)
	if err != nil {
		return fmt.Errorf("failed to get check job: %w", err)
	}
	if checkJob == nil {
		// No check job exists for this PR, nothing to publish
		return nil
	}

	// Get all currently open alerts for this PR (returns map[string][]*models.Alert)
	openAlertsMap, err := app.Subsystems.Storage.GetOpenAlerts(ctx, repositoryID, &prNumber)
	if err != nil {
		return fmt.Errorf("failed to get open alerts: %w", err)
	}

	// Flatten the map into a slice
	var openAlerts []*models.Alert
	for _, alerts := range openAlertsMap {
		openAlerts = append(openAlerts, alerts...)
	}

	// Publish the event with current state
	err = app.Subsystems.EventPublisher.PublishPRLicenseCheckCompleteEvent(
		ctx,
		repositoryID,
		checkJob.PullRequestID,
		prNumber,
		checkJob.CommitSHA,
		checkJob.BaseSHA,
		openAlerts,
		"", // No remediation guidance for closed alerts
	)
	if err != nil {
		return fmt.Errorf("failed to publish PR license check complete event: %w", err)
	}

	app.Logger.Named("policy-change-events").Info("published event for PR after policy change",
		semconv.RepositoryID(repositoryID),
		semconv.PullRequestNumber(prNumber),
	)

	return nil
}
