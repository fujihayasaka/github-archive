package remediation

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
)

// ErrStatusChangeNotAllowed is returned when an attempt to change the status of an alert is not allowed.
var ErrStatusChangeNotAllowed = errors.New("status change not allowed")

var allowedTransitions = map[models.AlertStatus][]models.AlertStatus{
	models.AlertStatusOpen:            {models.AlertStatusReviewRequested},
	models.AlertStatusReviewRequested: {models.AlertStatusReviewDenied, models.AlertStatusOpen},
	models.AlertStatusReviewDenied:    {models.AlertStatusReviewRequested},
}

// IsValidStatusTransition validates whether alert status change from currentStatus to newStatus is allowed.
// Valid transitions:
//   - Open → ReviewRequested
//   - ReviewRequested → Open or ReviewDenied
//   - ReviewDenied → ReviewRequested
func IsValidStatusTransition(currentStatus, newStatus models.AlertStatus) bool {
	allowed, ok := allowedTransitions[currentStatus]
	if !ok {
		return false
	}
	return slices.Contains(allowed, newStatus)
}

// RequestAlertClosure updates the alert status to "ReviewRequested" and adds a corresponding event to the timeline.
// It also publishes an alert status changed event.
func RequestAlertClosure(
	ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	userID uint64,
	comment string,
	closureReason *string,
) error {
	if !IsValidStatusTransition(alert.Status, models.AlertStatusReviewRequested) {
		return ErrStatusChangeNotAllowed
	}

	tx := app.Subsystems.Storage.NewTransactor(ctx)
	previousStatus := alert.Status
	alert.Status = models.AlertStatusReviewRequested
	eventBody := models.ReviewRequestedEventBody{
		Comment: comment,
	}
	if closureReason != nil {
		alert.ClosureReason = closureReason
		eventBody.ClosureReason = *closureReason
	}
	tx.AddStep(storage.NewTransitionAlertStep(alert, previousStatus))

	tx.AddStep(storage.NewAlertEventStep(
		alert.ID,
		models.EventReviewRequested,
		&userID,
		eventBody,
	))

	// Create hook to publish alert status changed event
	publishHook := func(ctx context.Context) error {
		// Use 0 for pullRequestID since we don't have it in this context
		// The alert has PullRequestNumber but we need the ID
		return app.Subsystems.EventPublisher.PublishAlertStatusChanged(
			ctx,
			alert,
			previousStatus,
			0,
			&userID,
			comment,
		)
	}

	tx.AddPostUpdateHook(publishHook)

	err := tx.Execute()
	if err != nil {
		return fmt.Errorf("failed to update alert for closure request: %w", err)
	}
	return nil
}

// DenyClosureRequest updates the alert status to "ReviewDenied" and adds a corresponding event to the timeline.
// It also publishes an alert status changed event.
func DenyClosureRequest(
	ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	userID uint64,
	comment string,
) error {
	if !IsValidStatusTransition(alert.Status, models.AlertStatusReviewDenied) {
		return ErrStatusChangeNotAllowed
	}

	tx := app.Subsystems.Storage.NewTransactor(ctx)
	previousStatus := alert.Status
	alert.Status = models.AlertStatusReviewDenied
	eventBody := models.ReviewDeniedEventBody{
		Comment: comment,
	}
	tx.AddStep(storage.NewTransitionAlertStep(alert, previousStatus))

	tx.AddStep(storage.NewAlertEventStep(
		alert.ID,
		models.EventReviewDenied,
		&userID,
		eventBody,
	))

	// Create hook to publish alert status changed event
	publishHook := func(ctx context.Context) error {
		// Use 0 for pullRequestID since we don't have it in this context
		// The alert has PullRequestNumber but we need the ID
		return app.Subsystems.EventPublisher.PublishAlertStatusChanged(
			ctx,
			alert,
			previousStatus,
			0,
			&userID,
			comment,
		)
	}

	tx.AddPostUpdateHook(publishHook)

	err := tx.Execute()
	if err != nil {
		return fmt.Errorf("failed to update alert for closure denied: %w", err)
	}
	return nil
}

// ExpireClosureRequest is called when an ExemptionRequest in the monolith is detected to have expired.
// This moves the alert back to an Open status and adds an event to the timeline indicating that the review request has expired.
// It also publishes an alert status changed event.
func ExpireClosureRequest(
	ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	expiredAt time.Time,
) error {
	// It shouldn't happen that it's trying to expire a dismissal request
	// when there hasn't been one, but let's check just in case.
	if alert.Status != models.AlertStatusReviewRequested {
		return ErrStatusChangeNotAllowed
	}

	tx := app.Subsystems.Storage.NewTransactor(ctx)
	previousStatus := alert.Status
	alert.Status = models.AlertStatusOpen
	var eventBody any // Empty event body for this type
	tx.AddStep(storage.NewTransitionAlertStep(alert, previousStatus))

	alertEventStep := storage.NewAlertEventStep(
		alert.ID,
		models.EventReviewExpired,
		nil,
		eventBody,
	)
	alertEventStep.WithTimestamp(expiredAt)
	tx.AddStep(alertEventStep)

	// Create hook to publish alert status changed event
	publishHook := func(ctx context.Context) error {
		// Use 0 for pullRequestID since we don't have it in this context
		// The alert has PullRequestNumber but we need the ID
		return app.Subsystems.EventPublisher.PublishAlertStatusChanged(
			ctx,
			alert,
			previousStatus,
			0,
			nil,
			"",
		)
	}

	tx.AddPostUpdateHook(publishHook)

	err := tx.Execute()
	if err != nil {
		return fmt.Errorf("failed to update alert for request expired: %w", err)
	}
	return nil
}
