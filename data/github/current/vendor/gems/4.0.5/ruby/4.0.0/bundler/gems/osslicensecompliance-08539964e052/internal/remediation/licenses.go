package remediation

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/policy"
	"github.com/github/osslicensecompliance/internal/semconv"
	"github.com/github/osslicensecompliance/internal/storage"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// AddLicensesToPolicyForAlert adds the specified licenses to the policy at the given level for the alert,
// then checks if the alert can be closed as a result. It updates the alert timeline with appropriate
// events. Then it also asynchronously checks other alerts that might be affected by the policy change.
func AddLicensesToPolicyForAlert(ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	licenses []string,
	req *proto.AddLicensesForAlertRequest,
	closureReason *string,
) error {
	entityID := getEntityIDForLevel(req.PolicyLevel, alert)
	policyWriter, err := policy.NewWriter(app, req.PolicyLevel, entityID)
	if err != nil {
		return fmt.Errorf("failed to create policy writer: %w", err)
	}

	err = policyWriter.AddLicenses(ctx, licenses, req.GetContexts())
	if err != nil {
		return fmt.Errorf("failed to add licenses to policy: %w", err)
	}

	licensesAddedEventBody := models.LicensesAddedEventBody{
		Licenses: licenses,
		Level:    models.PolicyLevelToString(req.PolicyLevel),
	}

	updater := &alertUpdaterForLicenses{
		licenses: licenses,
		app:      app,
	}

	return updateAlertForPolicyChange(ctx,
		app, alert, req.UserId, req.Comment,
		models.AlertResolutionLicensesAdded, closureReason,
		licensesAddedEventBody, req.PolicyLevel, updater)
}

// alertUpdaterForLicenses is an implementation of alertUpdaterForPolicyChange that is used when licenses are added to a policy.
type alertUpdaterForLicenses struct {
	licenses []string
	app      *application.Application
}

// GetEventType returns the event type for adding licenses.
func (aufl *alertUpdaterForLicenses) GetEventType() models.AlertEventType {
	return models.EventLicensesAdded
}

// GetOpenAlerts gets open alerts that are relevant for the added licenses within the specified scope.
func (aufl *alertUpdaterForLicenses) GetOpenAlerts(ctx context.Context, scope storage.AlertScope) ([]*models.Alert, error) {
	// Get open alerts that match any of the added licenses within the specified scope
	return aufl.app.Subsystems.Storage.GetOpenAlertsByLicenses(ctx, aufl.licenses, scope)
}

var _ alertUpdaterForPolicyChange = (*alertUpdaterForLicenses)(nil)

// updateAlertForPolicyChange is the common code between license and package policy updates.
// It is called after the policy change and is responsible for the real work of updating alerts.
func updateAlertForPolicyChange(ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	userID uint64,
	comment string,
	resolution models.AlertResolution,
	closureReason *string,
	eventBody any,
	policyLevel proto.PolicyLevel,
	updater alertUpdaterForPolicyChange,
) error {
	tx := app.Subsystems.Storage.NewTransactor(ctx)

	// If alert is in ReviewRequested state, add a ReviewApproved event first
	if alert.Status == models.AlertStatusReviewRequested {
		reviewApprovedBody := models.ReviewApprovedEventBody{
			Comment: comment,
		}
		tx.AddStep(storage.NewAlertEventStep(
			alert.ID,
			models.EventReviewApproved,
			&userID,
			reviewApprovedBody,
		))
	}

	tx.AddStep(storage.NewAlertEventStep(
		alert.ID,
		updater.GetEventType(),
		&userID,
		eventBody,
	))

	// The policy has been updated, so we want to commit the changes thus far.
	err := tx.Execute()
	if err != nil {
		return fmt.Errorf("failed to execute transaction: %w", err)
	}

	// Now we need to verify that the alert should be closed and then
	// close it.
	satisfies, err := verifyAlertSatisfiesPolicy(ctx, app, alert)
	if err != nil {
		return fmt.Errorf("failed to verify alert satisfies policy: %w", err)
	}

	if satisfies && alert.Status != models.AlertStatusClosed {
		tx = app.Subsystems.Storage.NewTransactor(ctx)
		var eventBody models.CloseAlertEventBody
		previousStatus := alert.Status

		// If the alert was in review_requested status, use the requestor's ID who requested the review
		closeEventUserID := &userID
		if previousStatus == models.AlertStatusReviewRequested {
			requestorUserID := getRequestorUserID(ctx, app, alert.ID)
			if requestorUserID != nil {
				closeEventUserID = requestorUserID
			}
		}

		// If the alert was closed by a reviewer directly adding licenses,
		// we want to include their comment in the close event and use their
		// closure reason.
		if previousStatus != models.AlertStatusReviewRequested {
			eventBody.Comment = comment
			alert.ClosureReason = closureReason
		}
		alert.Status = models.AlertStatusClosed
		alert.Resolution = resolution
		tx.AddStep(storage.NewCloseAlertStep(alert))

		tx.AddStep(storage.NewAlertEventStep(
			alert.ID,
			models.EventClosed,
			closeEventUserID,
			eventBody,
		))

		if alert.PullRequestNumber != nil {
			step, result := storage.NewPassCheckJobIfNoAlertsStep(alert.RepositoryID, *alert.PullRequestNumber)
			tx.AddStep(step)

			checkJob, err := app.Subsystems.Storage.GetCheckJob(ctx, alert.RepositoryID, *alert.PullRequestNumber)
			if err != nil {
				return fmt.Errorf("failed to get check job: %w", err)
			}
			tx.AddPostUpdateHook(newCheckJobPassedHook(app, checkJob, result))
		}

		// Create hook to publish alert status changed event
		publishHook := func(ctx context.Context) error {
			return app.Subsystems.EventPublisher.PublishAlertStatusChanged(
				ctx,
				alert,
				previousStatus,
				0,
				eventpublisher.WithUserID(&userID),
				eventpublisher.WithComment(&comment),
				eventpublisher.WithClosureEventUserID(closeEventUserID),
			)
		}
		tx.AddPostUpdateHook(publishHook)

		err = tx.Execute()
		if err != nil {
			return fmt.Errorf("failed to execute transaction for closing alert: %w", err)
		}
	}

	// Make a copy of the alert to avoid race condition with concurrent access
	alertCopy := *alert
	// Spawn async goroutine to close other affected alerts AND publish events for all affected PRs (including the original)
	// WithoutCancel detaches from request cancellation while preserving context tags
	asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 1*time.Minute)
	app.BackgroundWorkAdd(1)
	go func() {
		defer cancel()
		defer app.BackgroundWorkDone()

		enterpriseID := pointers.ValueOrZero(alertCopy.EnterpriseID)
		organizationID := alertCopy.OrganizationID
		repositoryID := alertCopy.RepositoryID

		err := checkAndCloseAffectedAlertsForPolicyChange(
			asyncCtx,
			app,
			eventBody,
			policyLevel,
			enterpriseID,
			organizationID,
			repositoryID,
			&userID,
			&alertCopy, // Pass the original alert so it can be included in event publishing
			resolution,
			updater,
		)
		if err != nil {
			app.Logger.Named("alert-remediation").WithError(err).Error("failed to close affected alerts asynchronously")
		}
	}()
	return nil
}

// verifyAlertSatisfiesPolicy checks if the alert is no longer relevant with the updated policy.
func verifyAlertSatisfiesPolicy(ctx context.Context, app *application.Application, alert *models.Alert) (bool, error) {
	completePolicy, err := app.Subsystems.Storage.GetCompletePolicy(ctx, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
	if err != nil {
		return false, fmt.Errorf("failed to get complete policy: %w", err)
	}

	return verifyAlertSatisfiesPolicyFromPolicy(ctx, app, alert, completePolicy)
}

// verifyAlertSatisfiesPolicyFromPolicy checks if the alert satisfies the given complete policy.
// This is used to avoid refetching the complete policy multiple times when checking multiple alerts affected by the same policy change.
func verifyAlertSatisfiesPolicyFromPolicy(ctx context.Context, app *application.Application, alert *models.Alert, completePolicy *models.CompletePolicy) (bool, error) {
	distributionContext, err := GetDistributionContextForRepository(ctx, app, alert.RepositoryID)
	if err != nil {
		return false, fmt.Errorf("failed to get distribution context for repository: %w", err)
	}

	satisfies, err := evaluator.AlertSatisfiesPolicy(alert, completePolicy, distributionContext)
	if err != nil {
		return false, err
	}

	if !satisfies {
		app.Logger.Named("alert-remediation").WithFields(
			semconv.RepositoryID(alert.RepositoryID),
			semconv.AlertNumber(alert.Number),
			semconv.SPDXExpression(alert.SPDXLicenseExpression),
			semconv.DistributionContext(distributionContext),
		).Info("alert does not satisfy policy, not closing")
		return false, nil
	}
	return true, nil
}

// alertUpdaterForPolicyChange pulls out the differences between package updates and license updates
// so that the common code can work in both cases.
type alertUpdaterForPolicyChange interface {
	GetEventType() models.AlertEventType
	GetOpenAlerts(ctx context.Context, scope storage.AlertScope) ([]*models.Alert, error)
}

// checkAndCloseAffectedAlertsForPolicyChange finds and closes alerts that are now satisfied due to the policy being updated.
// This function should be called asynchronously by callers to avoid blocking.
// After closing alerts, it publishes LicenseCheckCompleteEvents for affected PRs to sync dotcom state.
// The originalAlert parameter should be the alert that triggered the policy addition - it will be included when publishing events.
func checkAndCloseAffectedAlertsForPolicyChange(ctx context.Context,
	app *application.Application,
	eventBody any,
	policyLevel proto.PolicyLevel,
	enterpriseID, organizationID, repositoryID uint64,
	userID *uint64,
	originalAlert *models.Alert,
	resolution models.AlertResolution,
	updater alertUpdaterForPolicyChange,
) error {
	var scope storage.AlertScope

	switch policyLevel {
	case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
		scope = storage.NewRepositoryScope(repositoryID)
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		scope = storage.NewOrganizationScope(organizationID)
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		scope = storage.NewEnterpriseScope(enterpriseID)
	default:
		return fmt.Errorf("invalid policy level: %v", policyLevel)
	}

	alerts, err := updater.GetOpenAlerts(ctx, scope)
	if err != nil {
		return fmt.Errorf("failed to get open alerts: %w", err)
	}

	slices.SortFunc(alerts, models.CompareAlertsByScope)

	var cachedPolicy *models.CompletePolicy
	var closedAlerts []*models.Alert

	for _, alert := range alerts {
		var err error
		if cachedPolicy == nil {
			cachedPolicy, err = app.Subsystems.Storage.GetCompletePolicy(ctx, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
		} else {
			cachedPolicy, err = app.Subsystems.Storage.GetCompletePolicyFromPolicy(ctx, cachedPolicy, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
		}
		if err != nil {
			app.Logger.Named("side-effect-alert").WithError(err).Error(fmt.Sprintf("failed to get complete policy for alert %d, continuing with other alerts", alert.ID))
			cachedPolicy = nil
			continue
		}

		alertEventStep := storage.NewAlertEventStep(
			alert.ID,
			updater.GetEventType(),
			userID, // policy change event uses the remediator's user ID
			eventBody,
		)

		closed, err := closeSideEffectAlert(ctx, app, alert, cachedPolicy, alertEventStep, resolution)
		if err != nil {
			app.Logger.Named("side-effect-alert").WithError(err).Error("failed to close side-effect alert")
		} else if closed {
			// Track successfully closed alerts
			closedAlerts = append(closedAlerts, alert)
		}
	}

	// Include the original alert in the list for event publishing (it was already closed synchronously, so it's not returned with the others)
	// Only add it if it's not nil (it will be nil for direct policy updates that don't start from an alert)
	if originalAlert != nil {
		closedAlerts = append(closedAlerts, originalAlert)
	}

	// Publish events for all PRs affected by closed alerts (including the original if present)
	if len(closedAlerts) > 0 {
		err := PublishEventsForAffectedPRs(ctx, app, closedAlerts)
		if err != nil {
			// Log but don't fail - events are best-effort
			app.Logger.Named("side-effect-alert").WithError(err).Error("failed to publish events for affected PRs")
		}
	}

	return nil
}

// CheckAndCloseAffectedAlertsForLicenses finds and closes alerts that are now satisfied due to licenses being added to a policy.
// This function should be called asynchronously by callers to avoid blocking.
// After closing alerts, it publishes LicenseCheckCompleteEvents for affected PRs to sync dotcom state.
// The originalAlert parameter should be the alert that triggered the license addition - it will be included when publishing events.
func CheckAndCloseAffectedAlertsForLicenses(ctx context.Context, app *application.Application, eventBody models.LicensesAddedEventBody, policyLevel proto.PolicyLevel, enterpriseID, organizationID, repositoryID uint64, userID *uint64, originalAlert *models.Alert) error {
	updater := &alertUpdaterForLicenses{
		licenses: eventBody.Licenses,
		app:      app,
	}
	return checkAndCloseAffectedAlertsForPolicyChange(ctx,
		app,
		eventBody,
		policyLevel,
		enterpriseID,
		organizationID,
		repositoryID,
		userID,
		originalAlert,
		models.AlertResolutionLicensesAdded,
		updater)
}

func getEntityIDForLevel(level proto.PolicyLevel, alert *models.Alert) uint64 {
	switch level {
	case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
		return alert.RepositoryID
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		return alert.OrganizationID
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		return pointers.ValueOrZero(alert.EnterpriseID)
	default:
		return 0
	}
}

// getRequestorUserID retrieves the user ID of the person who requested the review.
func getRequestorUserID(ctx context.Context, app *application.Application, alertID uint64) *uint64 {
	events, err := app.Subsystems.Storage.GetAlertEvents(ctx, alertID)
	if err != nil {
		app.Logger.Named("alert-remediation").WithError(err).Error("failed to get alert events")
		return nil
	}

	// Find the most recent review_requested event
	for i := len(events) - 1; i >= 0; i-- {
		if events[i].EventType == models.EventReviewRequested {
			return events[i].UserID
		}
	}
	return nil
}
