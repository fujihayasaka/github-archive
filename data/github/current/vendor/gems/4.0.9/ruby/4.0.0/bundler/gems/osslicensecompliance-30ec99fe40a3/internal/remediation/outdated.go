package remediation

import (
	"context"
	"fmt"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
)

// CloseOutdatedAlerts closes the given alerts with resolution "outdated" and closure reason "fixed", and adds corresponding alert events to the timeline.
func CloseOutdatedAlerts(ctx context.Context,
	app *application.Application,
	alerts []*models.Alert,
	pullRequestID uint64,
) {
	for _, alert := range alerts {
		previousStatus := alert.Status
		alert.Status = models.AlertStatusClosed
		alert.Resolution = models.AlertResolutionOutdated
		fixed := models.ClosureReasonFixed
		alert.ClosureReason = &fixed

		tx := app.Subsystems.Storage.NewTransactor(ctx)
		tx.AddStep(storage.NewCloseAlertStep(alert))

		eventBody := models.CloseAlertEventBody{}
		tx.AddStep(storage.NewAlertEventStep(
			alert.ID,
			models.EventClosed,
			nil,
			eventBody,
		))

		// Create hook to publish alert status changed event
		// userID is nil since it is a system-initiated closure
		publishHook := func(ctx context.Context) error {
			return app.Subsystems.EventPublisher.PublishAlertStatusChanged(
				ctx,
				alert,
				previousStatus,
				pullRequestID,
				nil,
				"",
			)
		}
		tx.AddPostUpdateHook(publishHook)
		err := tx.Execute()
		if err != nil {
			app.Logger.WithError(err).Error(fmt.Sprintf("Failed to close outdated alert (ID: %d)", alert.ID))
		}
	}
}
