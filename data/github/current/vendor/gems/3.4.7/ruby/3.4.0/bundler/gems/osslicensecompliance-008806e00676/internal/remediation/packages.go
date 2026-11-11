package remediation

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type packagePolicyUpdater interface {
	AddPackagePolicy(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error
}

type repositoryPackagePolicyUpdater struct {
	app          *application.Application
	repositoryID uint64
}

func (r *repositoryPackagePolicyUpdater) AddPackagePolicy(ctx context.Context, packagePolicy *proto.PackagePolicy, _ []string) error {
	_, err := r.app.Subsystems.Storage.UpdateRepositoryPolicy(ctx, r.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.Packages = models.AddPackageToPackagePolicyList(newPolicy.Packages, packagePolicy)
		return newPolicy, nil
	})
	if err != nil {
		if !errors.Is(err, storage.ErrNotFound) {
			return err
		}
		// Policy doesn't exist, create a new one
		_, err = r.app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: r.repositoryID,
			CreatedAt:    timestamppb.Now(),
			Packages:     []*proto.PackagePolicy{packagePolicy},
		})
	}
	return err
}

type organizationPackagePolicyUpdater struct {
	app            *application.Application
	organizationID uint64
}

func (o *organizationPackagePolicyUpdater) AddPackagePolicy(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error {
	_, err := o.app.Subsystems.Storage.UpdateOrganizationPolicy(ctx, o.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.DistributionPolicies = models.AddPackageToPolicy(newPolicy, packagePolicy, distributionContexts)
		return newPolicy, nil
	})
	if err != nil {
		if !errors.Is(err, storage.ErrNotFound) {
			return err
		}
		// Policy doesn't exist, create a new one
		newPolicy := &proto.OrganizationPolicy{
			OrganizationId:       o.organizationID,
			CreatedAt:            timestamppb.Now(),
			DistributionPolicies: []*proto.DistributionPolicy{},
		}
		newPolicy.DistributionPolicies = models.AddPackageToPolicy(newPolicy, packagePolicy, distributionContexts)
		_, err = o.app.Subsystems.Storage.CreateOrganizationPolicy(ctx, newPolicy)
	}
	return err
}

type enterprisePackagePolicyUpdater struct {
	app          *application.Application
	enterpriseID uint64
}

func (e *enterprisePackagePolicyUpdater) AddPackagePolicy(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error {
	_, err := e.app.Subsystems.Storage.UpdateEnterprisePolicy(ctx, e.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.DistributionPolicies = models.AddPackageToPolicy(newPolicy, packagePolicy, distributionContexts)
		return newPolicy, nil
	})
	if err != nil {
		if !errors.Is(err, storage.ErrNotFound) {
			return err
		}
		// Policy doesn't exist, create a new one
		newPolicy := &proto.EnterprisePolicy{
			EnterpriseId:         e.enterpriseID,
			CreatedAt:            timestamppb.Now(),
			DistributionPolicies: []*proto.DistributionPolicy{},
		}
		newPolicy.DistributionPolicies = models.AddPackageToPolicy(newPolicy, packagePolicy, distributionContexts)
		_, err = e.app.Subsystems.Storage.CreateEnterprisePolicy(ctx, newPolicy)
	}
	return err
}

func newPackagePolicyUpdater(app *application.Application, alert *models.Alert, level proto.PolicyLevel) packagePolicyUpdater {
	switch level {
	case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
		return &repositoryPackagePolicyUpdater{
			app:          app,
			repositoryID: alert.RepositoryID,
		}
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		return &organizationPackagePolicyUpdater{
			app:            app,
			organizationID: alert.OrganizationID,
		}
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		// This should not happen, because if we're updating the enterprise policy the alert
		// should have an EnterpriseID set. But just in case, we check.
		if alert.EnterpriseID == nil {
			return nil
		}
		return &enterprisePackagePolicyUpdater{
			app:          app,
			enterpriseID: *alert.EnterpriseID,
		}
	default:
		return nil
	}
}

// AddPackagePolicyForAlert adds a new package allow policy for the given alert at the specified policy level.
func AddPackagePolicyForAlert(ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	packagePolicy *proto.PackagePolicy,
	distributionContexts []string,
	level proto.PolicyLevel,
	comment string,
	userID uint64,
) error {
	policyUpdater := newPackagePolicyUpdater(app, alert, level)
	if policyUpdater == nil {
		return errors.New("invalid policy level")
	}
	err := policyUpdater.AddPackagePolicy(ctx, packagePolicy, distributionContexts)
	if err != nil {
		return fmt.Errorf("failed to add package policy: %w", err)
	}

	// If alert is in ReviewRequested state, add a ReviewApproved event first
	if alert.Status == models.ReviewRequested {
		reviewApprovedBody := models.ReviewApprovedEventBody{
			Comment: comment,
		}
		reviewApprovedBytes, err := json.Marshal(reviewApprovedBody)
		if err != nil {
			return fmt.Errorf("failed to marshal review approved event body: %w", err)
		}

		reviewApprovedEvent := models.AlertEvent{
			AlertID:   alert.ID,
			EventType: models.EventReviewApproved,
			UserID:    &userID,
			EventBody: reviewApprovedBytes,
		}
		if err := app.Subsystems.Storage.CreateAlertEvent(ctx, reviewApprovedEvent); err != nil {
			return err
		}
	}

	// Record an alert event for the exception addition
	eventBodyPayload := models.ExceptionAddedEventBody{
		PackageManager: models.PackageManagerToString(packagePolicy.PackageManager),
		PackageName:    packagePolicy.Name,
		Level:          models.PolicyLevelToString(level),
	}

	eventBodyBytes, err := json.Marshal(eventBodyPayload)
	if err != nil {
		return fmt.Errorf("failed to marshal event body: %w", err)
	}

	addExceptionEvent := models.AlertEvent{
		AlertID:   alert.ID,
		EventType: models.EventExceptionAdded,
		UserID:    &userID,
		EventBody: eventBodyBytes,
	}
	if err := app.Subsystems.Storage.CreateAlertEvent(ctx, addExceptionEvent); err != nil {
		return err
	}

	policy, err := app.Subsystems.Storage.GetCompletePolicy(ctx, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
	if err != nil {
		return err
	}

	err = closeRemediatedAlert(ctx, app, alert, policy, &userID, models.ExceptionAdded)
	if err != nil {
		return fmt.Errorf("failed to close remediated alert: %w", err)
	}

	go func() {
		asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 1*time.Minute)
		defer cancel()
		if err := CheckAndCloseAffectedAlertsForPackages(asyncCtx,
			app,
			eventBodyPayload,
			level,
			packagePolicy,
			policy,
			pointers.ValueOrZero(alert.EnterpriseID),
			alert.OrganizationID,
			alert.RepositoryID,
			&userID,
		); err != nil {
			app.Logger.Named("remediation").WithError(err).Error("failed to check and close affected alerts for packages asynchronously")
		}
	}()

	return nil
}

// CheckAndCloseAffectedAlertsForPackages checks for other open alerts that are affected by the addition
// of a package policy and closes them if they are remediated by the new policy.
func CheckAndCloseAffectedAlertsForPackages(ctx context.Context,
	app *application.Application,
	eventBody models.ExceptionAddedEventBody,
	policyLevel proto.PolicyLevel,
	packagePolicy *proto.PackagePolicy,
	completePolicy *models.CompletePolicy,
	enterpriseID, organizationID, repositoryID uint64,
	userID *uint64,
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

	alerts, err := app.Subsystems.Storage.GetOpenAlertsByPackage(ctx, packagePolicy.PackageManager, packagePolicy.Name, scope)
	if err != nil {
		return fmt.Errorf("failed to get open alerts by package: %w", err)
	}

	// Sort alerts to optimize policy retrievals by changing as little of the scope as possible
	// from one alert to the next.
	slices.SortFunc(alerts, models.CompareAlertsByScope)
	policy := completePolicy
	for _, alert := range alerts {
		alertEnterpriseID := pointers.ValueOrZero(alert.EnterpriseID)
		policy, err = app.Subsystems.Storage.GetCompletePolicyFromPolicy(ctx, policy, alertEnterpriseID, alert.OrganizationID, alert.RepositoryID)
		if err != nil {
			app.Logger.Named("side-effect-alert").WithError(err).Error(fmt.Sprintf("failed to get complete policy for alert %d, continuing with other alerts", alert.ID))
			continue
		}
		if err := closeSideEffectAlert(ctx, app, alert, policy, eventBody, models.EventExceptionAdded, models.PolicyChanged, userID); err != nil {
			app.Logger.Named("side-effect-alert").WithError(err).Error("failed to close side-effect alert")
		}
	}

	return nil
}
