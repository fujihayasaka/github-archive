package remediation

import (
	"context"
	"fmt"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/policy"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// AddPackagePolicyForAlert adds a new package allow policy for the given alert at the specified policy level.
func AddPackagePolicyForAlert(ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	packagePolicy *proto.PackagePolicy,
	distributionContexts []string,
	level proto.PolicyLevel,
	comment string,
	userID uint64,
	closureReason *string,
) error {
	entityID := getEntityIDForLevel(level, alert)
	policyWriter, err := policy.NewWriter(app, level, entityID)
	if err != nil {
		return fmt.Errorf("failed to create policy writer: %w", err)
	}

	err = policyWriter.AddPackage(ctx, packagePolicy, distributionContexts)
	if err != nil {
		return fmt.Errorf("failed to add package policy: %w", err)
	}

	// Record an alert event for the exception addition
	eventBodyPayload := models.ExceptionAddedEventBody{
		PackageManager: models.PackageManagerToString(packagePolicy.PackageManager),
		PackageName:    packagePolicy.Name,
		Level:          models.PolicyLevelToString(level),
	}

	updater := &alertUpdaterForPackages{
		app:           app,
		packagePolicy: packagePolicy,
	}

	return updateAlertForPolicyChange(ctx,
		app, alert, userID, comment,
		models.AlertResolutionExceptionAdded, closureReason,
		eventBodyPayload, level, updater)
}

type alertUpdaterForPackages struct {
	app           *application.Application
	packagePolicy *proto.PackagePolicy
}

func (aup *alertUpdaterForPackages) GetEventType() models.AlertEventType {
	return models.EventExceptionAdded
}

func (aup *alertUpdaterForPackages) GetOpenAlerts(ctx context.Context, scope storage.AlertScope) ([]*models.Alert, error) {
	return aup.app.Subsystems.Storage.GetOpenAlertsByPackage(ctx, aup.packagePolicy.PackageManager, aup.packagePolicy.Name, scope)
}

// CheckAndCloseAffectedAlertsForPackages checks for other open alerts that are affected by the addition
// of a package policy and closes them if they are remediated by the new policy.
// After closing alerts, it publishes LicenseCheckCompleteEvents for affected PRs to sync dotcom state.
// The originalAlert parameter should be the alert that triggered the package policy addition - it will be included when publishing events.
func CheckAndCloseAffectedAlertsForPackages(ctx context.Context,
	app *application.Application,
	eventBody models.ExceptionAddedEventBody,
	policyLevel proto.PolicyLevel,
	packagePolicy *proto.PackagePolicy,
	completePolicy *models.CompletePolicy,
	enterpriseID, organizationID, repositoryID uint64,
	userID *uint64,
	originalAlert *models.Alert,
) error {
	updater := &alertUpdaterForPackages{
		app:           app,
		packagePolicy: packagePolicy,
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
		models.AlertResolutionExceptionAdded,
		updater)
}
