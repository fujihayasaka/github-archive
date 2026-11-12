// Package remediation handles alert remediation flows including applying licenses to policies
// and closing alerts when remediated.
package remediation

import (
	"context"
	"fmt"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
)

// GetDistributionContextForRepository is a placeholder. The idea is that this function will,
// when we do the multiple policy work, find out what the distribution context for the given repository is.
// For now, we just return "distributed" as that is the only context we have.
func GetDistributionContextForRepository(ctx context.Context, app *application.Application, repositoryID uint64) (string, error) {
	return "distributed", nil
}

// closeSideEffectAlert attempts to close an alert as a side effect of a policy change.
// Returns true if the alert was closed, false if it didn't need closing, and error if something went wrong.
func closeSideEffectAlert(
	ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	policy *models.CompletePolicy,
	eventStep storage.Step,
	resolution models.AlertResolution,
) (bool, error) {
	if alert.Status == models.AlertStatusClosed {
		return false, nil
	}

	satisfies, err := verifyAlertSatisfiesPolicyFromPolicy(ctx, app, alert, policy)
	if err != nil {
		return false, fmt.Errorf("failed to verify if alert satisfies policy: %w", err)
	}

	if !satisfies {
		return false, nil
	}

	tx := app.Subsystems.Storage.NewTransactor(ctx)

	// Capture previous status to check if we should publish event
	previousStatus := alert.Status

	// Create hook to publish alert status changed event
	publishHook := func(ctx context.Context) error {
		return app.Subsystems.EventPublisher.PublishAlertStatusChanged(
			ctx,
			alert,
			previousStatus,
			0,
		)
	}

	alert.Status = models.AlertStatusClosed
	alert.Resolution = resolution
	policyEdited := models.ClosureReasonPolicyEdited
	alert.ClosureReason = &policyEdited
	tx.AddStep(storage.NewCloseAlertStep(alert))
	tx.AddStep(eventStep)
	tx.AddStep(storage.NewAlertEventStep(
		alert.ID,
		models.EventClosed,
		nil,
		models.CloseAlertEventBody{},
	))

	tx.AddPostUpdateHook(publishHook)

	if alert.PullRequestNumber != nil {
		step, result := storage.NewPassCheckJobIfNoAlertsStep(alert.RepositoryID, *alert.PullRequestNumber)
		tx.AddStep(step)

		checkJob, err := app.Subsystems.Storage.GetCheckJob(ctx, alert.RepositoryID, *alert.PullRequestNumber)
		if err != nil {
			return false, fmt.Errorf("failed to get check job: %w", err)
		}
		tx.AddPostUpdateHook(newCheckJobPassedHook(app, checkJob, result))
	}

	err = tx.Execute()
	if err != nil {
		return false, fmt.Errorf("failed to execute transaction to close alert: %w", err)
	}

	return true, nil
}

// newCheckJobPassedHook returns a PostUpdateHook that publishes a LicenseCheckProgressed event
// when the check job was updated to pass. The result is inspected inside the hook (after steps
// have executed) so it correctly reflects whether the update happened.
func newCheckJobPassedHook(app *application.Application, checkJob *models.CheckJob, result *storage.PassCheckJobResult) storage.PostUpdateHook {
	return func(ctx context.Context) error {
		if !result.Updated || checkJob == nil {
			return nil
		}

		app.Subsystems.EventPublisher.PublishLicenseCheckPass(ctx, checkJob.CommitSHA, checkJob.RepositoryID)
		return nil
	}
}
