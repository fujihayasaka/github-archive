// Package remediation handles alert remediation flows including applying licenses to policies
// and closing alerts when remediated.
package remediation

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/github/osslicensecompliance/internal/semconv"
	"github.com/github/osslicensecompliance/internal/storage"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

type licensePolicyUpdater interface {
	AddLicensesToPolicy(ctx context.Context, licenses []string, distributionContexts []string) error
}

func newLicensePolicyUpdater(app *application.Application, policyLevel proto.PolicyLevel, alert *models.Alert) (licensePolicyUpdater, error) {
	switch policyLevel {
	case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
		return &repositoryLicensePolicyUpdater{
			app:          app,
			repositoryID: alert.RepositoryID,
		}, nil
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		return &organizationLicensePolicyUpdater{
			app:            app,
			organizationID: alert.OrganizationID,
		}, nil
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		return &enterpriseLicensePolicyUpdater{
			app:          app,
			enterpriseID: pointers.ValueOrZero(alert.EnterpriseID),
		}, nil
	default:
		return nil, fmt.Errorf("unsupported policy level: %v", policyLevel)
	}
}

type repositoryLicensePolicyUpdater struct {
	app          *application.Application
	repositoryID uint64
}

func (r *repositoryLicensePolicyUpdater) AddLicensesToPolicy(ctx context.Context, licenses, _ []string) error {
	existingPolicy, err := r.app.Subsystems.Storage.GetRepositoryPolicyByRepoID(ctx, r.repositoryID)
	if err != nil && !errors.Is(err, storage.ErrNotFound) {
		return err
	}

	if existingPolicy == nil {
		updatedLicenses := models.AddLicensesToPolicyLicenses(nil, licenses)
		_, err = r.app.Subsystems.Storage.CreateRepositoryPolicy(ctx, &proto.RepositoryPolicy{
			RepositoryId: r.repositoryID,
			Licenses:     updatedLicenses,
		})
	} else {
		_, err = r.app.Subsystems.Storage.UpdateRepositoryPolicy(ctx, r.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
			newPolicy := storage.ProtoCopy(policy)
			newPolicy.Licenses = models.AddLicensesToPolicyLicenses(newPolicy.Licenses, licenses)
			return newPolicy, nil
		})
	}
	return err
}

type organizationLicensePolicyUpdater struct {
	app            *application.Application
	organizationID uint64
}

func (o *organizationLicensePolicyUpdater) AddLicensesToPolicy(ctx context.Context, licenses, distributionContexts []string) error {
	existingPolicy, err := o.app.Subsystems.Storage.GetOrganizationPolicyByOrgID(ctx, o.organizationID)
	if err != nil && !errors.Is(err, storage.ErrNotFound) {
		return err
	}

	if existingPolicy == nil {
		orgPolicy := &proto.OrganizationPolicy{
			OrganizationId: o.organizationID,
		}
		distributionPolicies := models.AddLicensesToPolicy(orgPolicy, licenses, distributionContexts)
		orgPolicy.DistributionPolicies = distributionPolicies
		_, err = o.app.Subsystems.Storage.CreateOrganizationPolicy(ctx, orgPolicy)
	} else {
		_, err = o.app.Subsystems.Storage.UpdateOrganizationPolicy(ctx, o.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
			newPolicy := storage.ProtoCopy(policy)

			distributionPolicies := models.AddLicensesToPolicy(newPolicy, licenses, distributionContexts)
			newPolicy.DistributionPolicies = distributionPolicies
			return newPolicy, nil
		})
	}
	return err
}

type enterpriseLicensePolicyUpdater struct {
	app          *application.Application
	enterpriseID uint64
}

func (e *enterpriseLicensePolicyUpdater) AddLicensesToPolicy(ctx context.Context, licenses, distributionContexts []string) error {
	existingPolicy, err := e.app.Subsystems.Storage.GetEnterprisePolicyByEnterpriseID(ctx, e.enterpriseID)
	if err != nil && !errors.Is(err, storage.ErrNotFound) {
		return err
	}

	if existingPolicy == nil {
		enterprisePolicy := &proto.EnterprisePolicy{
			EnterpriseId: e.enterpriseID,
		}
		distributionPolicies := models.AddLicensesToPolicy(enterprisePolicy, licenses, distributionContexts)
		enterprisePolicy.DistributionPolicies = distributionPolicies
		_, err = e.app.Subsystems.Storage.CreateEnterprisePolicy(ctx, enterprisePolicy)
	} else {
		_, err = e.app.Subsystems.Storage.UpdateEnterprisePolicy(ctx, e.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
			newPolicy := storage.ProtoCopy(policy)
			distributionPolicies := models.AddLicensesToPolicy(newPolicy, licenses, distributionContexts)
			newPolicy.DistributionPolicies = distributionPolicies
			return newPolicy, nil
		})
	}
	return err
}

// AddLicensesToPolicyForAlert applies the given licenses to the specified policy level
func AddLicensesToPolicyForAlert(ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	licenses []string,
	req *proto.AddLicensesForAlertRequest,
) error {
	policyUpdater, err := newLicensePolicyUpdater(app, req.PolicyLevel, alert)
	if err != nil {
		return fmt.Errorf("failed to create policy updater: %w", err)
	}

	err = policyUpdater.AddLicensesToPolicy(ctx, licenses, req.GetContexts())
	if err != nil {
		return fmt.Errorf("failed to add licenses to policy: %w", err)
	}

	// If alert is in ReviewRequested state, add a ReviewApproved event first
	if alert.Status == models.ReviewRequested {
		reviewApprovedBody := models.ReviewApprovedEventBody{
			Comment: req.Comment,
		}
		reviewApprovedBytes, err := json.Marshal(reviewApprovedBody)
		if err != nil {
			return fmt.Errorf("failed to marshal review approved event body: %w", err)
		}

		reviewApprovedEvent := models.AlertEvent{
			AlertID:   alert.ID,
			EventType: models.EventReviewApproved,
			UserID:    &req.UserId,
			EventBody: reviewApprovedBytes,
		}
		if err := app.Subsystems.Storage.CreateAlertEvent(ctx, reviewApprovedEvent); err != nil {
			return err
		}
	}

	eventBodyPayload := models.LicensesAddedEventBody{
		Licenses: licenses,
		Level:    models.PolicyLevelToString(req.PolicyLevel),
	}

	eventBodyBytes, err := json.Marshal(eventBodyPayload)
	if err != nil {
		return fmt.Errorf("failed to marshal event body: %w", err)
	}

	addLicensesEvent := models.AlertEvent{
		AlertID:   alert.ID,
		EventType: models.EventLicensesAdded,
		UserID:    &req.UserId,
		EventBody: eventBodyBytes,
	}
	if err := app.Subsystems.Storage.CreateAlertEvent(ctx, addLicensesEvent); err != nil {
		return err
	}

	policy, err := app.Subsystems.Storage.GetCompletePolicy(ctx, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
	if err != nil {
		return err
	}

	err = closeRemediatedAlert(ctx, app, alert, policy, &req.UserId, models.PolicyChanged)
	if err != nil {
		return err
	}

	// Spawn async goroutine to close affected alerts
	go func() {
		asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 1*time.Minute)
		defer cancel()

		if err := CheckAndCloseAffectedAlertsForLicenses(
			asyncCtx,
			app,
			eventBodyPayload,
			req.PolicyLevel,
			pointers.ValueOrZero(alert.EnterpriseID),
			alert.OrganizationID,
			alert.RepositoryID,
			&req.UserId,
		); err != nil {
			app.Logger.Named("alert-remediation").WithError(err).Error("failed to close affected alerts asynchronously")
		}
	}()

	return nil
}

func closeRemediatedAlert(
	ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	policy *models.CompletePolicy,
	userID *uint64,
	resolution models.AlertResolution,
) error {
	distributionContext, err := GetDistributionContextForRepository(ctx, app, alert.RepositoryID)
	if err != nil {
		return fmt.Errorf("failed to get distribution context for repository: %w", err)
	}

	satisfies, err := evaluator.AlertSatisfiesPolicy(alert, policy, distributionContext)
	if err != nil {
		return err
	}

	if !satisfies {
		app.Logger.Named("alert-remediation").WithFields(
			semconv.RepositoryID(alert.RepositoryID),
			semconv.AlertNumber(alert.Number),
			semconv.SPDXExpression(alert.SPDXLicenseExpression),
			semconv.DistributionContext(distributionContext),
		).Info("alert does not satisfy policy, not closing")
		return nil
	}

	if err := app.Subsystems.Storage.CloseAlertWithEvent(ctx, alert, userID, resolution, nil); err != nil {
		return fmt.Errorf("failed to close alert with event: %w", err)
	}

	if alert.PullRequestNumber != nil {
		err = app.Subsystems.Storage.ChangeCheckJobStatusFromAlerts(ctx, alert.RepositoryID, *alert.PullRequestNumber)
		if err != nil {
			return fmt.Errorf("failed to change check job status from alerts: %w", err)
		}
	}

	return nil
}

// CheckAndCloseAffectedAlertsForLicenses finds and closes alerts that are now satisfied due to licenses being added to a policy.
// This function should be called asynchronously by callers to avoid blocking.
func CheckAndCloseAffectedAlertsForLicenses(ctx context.Context, app *application.Application, eventBody models.LicensesAddedEventBody, policyLevel proto.PolicyLevel, enterpriseID, organizationID, repositoryID uint64, userID *uint64) error {
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

	alerts, err := app.Subsystems.Storage.GetOpenAlertsByLicenses(ctx, eventBody.Licenses, scope)
	if err != nil {
		return fmt.Errorf("failed to get open alerts by licenses: %w", err)
	}

	slices.SortFunc(alerts, models.CompareAlertsByScope)

	var policy *models.CompletePolicy
	for _, alert := range alerts {
		var err error
		if policy == nil {
			policy, err = app.Subsystems.Storage.GetCompletePolicy(ctx, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
		} else {
			policy, err = app.Subsystems.Storage.GetCompletePolicyFromPolicy(ctx, policy, pointers.ValueOrZero(alert.EnterpriseID), alert.OrganizationID, alert.RepositoryID)
		}
		if err != nil {
			app.Logger.Named("side-effect-alert").WithError(err).Error(fmt.Sprintf("failed to get complete policy for alert %d, continuing with other alerts", alert.ID))
			policy = nil
			continue
		}

		if err := closeSideEffectAlert(ctx, app, alert, policy, eventBody, models.EventLicensesAdded, models.PolicyChanged, userID); err != nil {
			app.Logger.Named("side-effect-alert").WithError(err).Error("failed to close side-effect alert")
		}
	}

	return nil
}

func closeSideEffectAlert(
	ctx context.Context,
	app *application.Application,
	alert *models.Alert,
	policy *models.CompletePolicy,
	eventBody jsonEventBody,
	eventType models.AlertEventType,
	resolution models.AlertResolution,
	userID *uint64,
) error {
	distributionContext, err := GetDistributionContextForRepository(ctx, app, alert.RepositoryID)
	if err != nil {
		return fmt.Errorf("failed to get distribution context for repository: %w", err)
	}
	satisfies, err := evaluator.AlertSatisfiesPolicy(alert, policy, distributionContext)
	if err != nil {
		return err
	}

	if !satisfies {
		app.Logger.Named("alert-remediation").WithFields(
			semconv.RepositoryID(alert.RepositoryID),
			semconv.AlertNumber(alert.Number),
			semconv.SPDXExpression(alert.SPDXLicenseExpression),
			semconv.DistributionContext(distributionContext),
		).Info("alert does not satisfy policy, not closing")
		return nil
	}

	eventBodyBytes, err := eventBody.ToJSON()
	if err != nil {
		return fmt.Errorf("failed to marshal licenses added event body: %w", err)
	}

	remediationEvent := models.AlertEvent{
		AlertID:   alert.ID,
		EventType: eventType,
		UserID:    userID,
		EventBody: eventBodyBytes,
	}
	if err := app.Subsystems.Storage.CreateAlertEvent(ctx, remediationEvent); err != nil {
		return fmt.Errorf("failed to create remediation event: %w", err)
	}

	// Pass nil userID to indicate system-initiated closure
	if err := app.Subsystems.Storage.CloseAlertWithEvent(ctx, alert, nil, resolution, nil); err != nil {
		return fmt.Errorf("failed to close alert with event: %w", err)
	}

	if alert.PullRequestNumber != nil {
		err = app.Subsystems.Storage.ChangeCheckJobStatusFromAlerts(ctx, alert.RepositoryID, *alert.PullRequestNumber)
		if err != nil {
			return fmt.Errorf("failed to change check job status from alerts: %w", err)
		}
	}

	return nil
}
