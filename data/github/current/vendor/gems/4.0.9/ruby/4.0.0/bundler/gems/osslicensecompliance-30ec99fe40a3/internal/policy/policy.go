// Package policy provides operations for updating license policies across different levels
// (repository, organization, enterprise).
package policy

import (
	"context"
	"errors"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// ErrDistributionContextRequired is returned when a remove operation is attempted without a distribution context.
var ErrDistributionContextRequired = errors.New("distributionContext is required for organization/enterprise policies")

func publishPolicyChangedAsync(ctx context.Context, app *application.Application, publisher *eventpublisher.Publisher, event eventpublisher.PolicyChangedEvent) {
	// WithoutCancel detaches from request cancellation while preserving context tags
	asyncCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
	app.BackgroundWorkAdd(1)
	go func() {
		defer cancel()
		defer app.BackgroundWorkDone()
		err := publisher.PublishPolicyChanged(asyncCtx, event)
		if err != nil {
			app.Logger.Named("policy").WithError(err).Error("failed to publish policy changed event")
		}
	}()
}

type repositoryWriter struct {
	app          *application.Application
	storage      *storage.Storage
	publisher    *eventpublisher.Publisher
	repositoryID uint64
}

func (r *repositoryWriter) AddLicenses(ctx context.Context, licenses, _ []string) error {
	result, err := r.storage.UpsertRepositoryPolicy(ctx, r.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.Licenses = models.AddLicensesToPolicyLicenses(newPolicy.Licenses, licenses)
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	action := eventpublisher.PolicyActionLicenseAdded
	if result.WasCreated {
		action = eventpublisher.PolicyActionPolicyCreated
	}
	publishPolicyChangedAsync(ctx, r.app, r.publisher, eventpublisher.PolicyChangedEvent{
		Action:   action,
		Level:    eventpublisher.PolicyLevelRepository,
		EntityID: r.repositoryID,
	})
	return nil
}

func (r *repositoryWriter) AddPackage(ctx context.Context, packagePolicy *proto.PackagePolicy, _ []string) error {
	result, err := r.storage.UpsertRepositoryPolicy(ctx, r.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.Packages = models.AddPackageToPackagePolicyList(newPolicy.Packages, packagePolicy)
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	action := eventpublisher.PolicyActionPackageExemptionAdded
	if result.WasCreated {
		action = eventpublisher.PolicyActionPolicyCreated
	}
	publishPolicyChangedAsync(ctx, r.app, r.publisher, eventpublisher.PolicyChangedEvent{
		Action:   action,
		Level:    eventpublisher.PolicyLevelRepository,
		EntityID: r.repositoryID,
	})
	return nil
}

func (r *repositoryWriter) RemoveLicenses(ctx context.Context, spdxIDs []string, _ string) error {
	_, err := r.storage.UpsertRepositoryPolicy(ctx, r.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.Licenses = removeLicensesFromPolicyLicenses(newPolicy.Licenses, spdxIDs)
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	publishPolicyChangedAsync(ctx, r.app, r.publisher, eventpublisher.PolicyChangedEvent{
		Action:   eventpublisher.PolicyActionLicenseRemoved,
		Level:    eventpublisher.PolicyLevelRepository,
		EntityID: r.repositoryID,
	})
	return nil
}

func (r *repositoryWriter) RemovePackages(ctx context.Context, packages []*proto.PackagePolicy, _ string) error {
	_, err := r.storage.UpsertRepositoryPolicy(ctx, r.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.Packages = removePackagesFromList(newPolicy.Packages, packages)
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	publishPolicyChangedAsync(ctx, r.app, r.publisher, eventpublisher.PolicyChangedEvent{
		Action:   eventpublisher.PolicyActionPackageExemptionRemoved,
		Level:    eventpublisher.PolicyLevelRepository,
		EntityID: r.repositoryID,
	})
	return nil
}

type organizationWriter struct {
	app            *application.Application
	storage        *storage.Storage
	publisher      *eventpublisher.Publisher
	organizationID uint64
}

func (o *organizationWriter) AddLicenses(ctx context.Context, licenses, distributionContexts []string) error {
	result, err := o.storage.UpsertOrganizationPolicy(ctx, o.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		distributionPolicies := models.AddLicensesToPolicy(newPolicy, licenses, distributionContexts)
		newPolicy.DistributionPolicies = distributionPolicies
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	action := eventpublisher.PolicyActionLicenseAdded
	if result.WasCreated {
		action = eventpublisher.PolicyActionPolicyCreated
	}
	publishPolicyChangedAsync(ctx, o.app, o.publisher, eventpublisher.PolicyChangedEvent{
		Action:               action,
		Level:                eventpublisher.PolicyLevelOrganization,
		EntityID:             o.organizationID,
		DistributionContexts: distributionContexts,
	})
	return nil
}

func (o *organizationWriter) AddPackage(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error {
	result, err := o.storage.UpsertOrganizationPolicy(ctx, o.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.DistributionPolicies = models.AddPackageToPolicy(newPolicy, packagePolicy, distributionContexts)
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	action := eventpublisher.PolicyActionPackageExemptionAdded
	if result.WasCreated {
		action = eventpublisher.PolicyActionPolicyCreated
	}
	publishPolicyChangedAsync(ctx, o.app, o.publisher, eventpublisher.PolicyChangedEvent{
		Action:               action,
		Level:                eventpublisher.PolicyLevelOrganization,
		EntityID:             o.organizationID,
		DistributionContexts: distributionContexts,
	})
	return nil
}

func (o *organizationWriter) RemoveLicenses(ctx context.Context, spdxIDs []string, distributionContext string) error {
	if distributionContext == "" {
		return ErrDistributionContextRequired
	}
	_, err := o.storage.UpsertOrganizationPolicy(ctx, o.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		for _, dp := range newPolicy.DistributionPolicies {
			if dp.Name == distributionContext {
				dp.Licenses = removeLicensesFromPolicyLicenses(dp.Licenses, spdxIDs)
			}
		}
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	publishPolicyChangedAsync(ctx, o.app, o.publisher, eventpublisher.PolicyChangedEvent{
		Action:               eventpublisher.PolicyActionLicenseRemoved,
		Level:                eventpublisher.PolicyLevelOrganization,
		EntityID:             o.organizationID,
		DistributionContexts: []string{distributionContext},
	})
	return nil
}

func (o *organizationWriter) RemovePackages(ctx context.Context, packages []*proto.PackagePolicy, distributionContext string) error {
	if distributionContext == "" {
		return ErrDistributionContextRequired
	}
	_, err := o.storage.UpsertOrganizationPolicy(ctx, o.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		for _, dp := range newPolicy.DistributionPolicies {
			if dp.Name == distributionContext {
				dp.Packages = removePackagesFromList(dp.Packages, packages)
			}
		}
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	publishPolicyChangedAsync(ctx, o.app, o.publisher, eventpublisher.PolicyChangedEvent{
		Action:               eventpublisher.PolicyActionPackageExemptionRemoved,
		Level:                eventpublisher.PolicyLevelOrganization,
		EntityID:             o.organizationID,
		DistributionContexts: []string{distributionContext},
	})
	return nil
}

type enterpriseWriter struct {
	app          *application.Application
	storage      *storage.Storage
	publisher    *eventpublisher.Publisher
	enterpriseID uint64
}

func (e *enterpriseWriter) AddLicenses(ctx context.Context, licenses, distributionContexts []string) error {
	result, err := e.storage.UpsertEnterprisePolicy(ctx, e.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		distributionPolicies := models.AddLicensesToPolicy(newPolicy, licenses, distributionContexts)
		newPolicy.DistributionPolicies = distributionPolicies
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	action := eventpublisher.PolicyActionLicenseAdded
	if result.WasCreated {
		action = eventpublisher.PolicyActionPolicyCreated
	}
	publishPolicyChangedAsync(ctx, e.app, e.publisher, eventpublisher.PolicyChangedEvent{
		Action:               action,
		Level:                eventpublisher.PolicyLevelEnterprise,
		EntityID:             e.enterpriseID,
		DistributionContexts: distributionContexts,
	})
	return nil
}

func (e *enterpriseWriter) AddPackage(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error {
	result, err := e.storage.UpsertEnterprisePolicy(ctx, e.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		newPolicy.DistributionPolicies = models.AddPackageToPolicy(newPolicy, packagePolicy, distributionContexts)
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	action := eventpublisher.PolicyActionPackageExemptionAdded
	if result.WasCreated {
		action = eventpublisher.PolicyActionPolicyCreated
	}
	publishPolicyChangedAsync(ctx, e.app, e.publisher, eventpublisher.PolicyChangedEvent{
		Action:               action,
		Level:                eventpublisher.PolicyLevelEnterprise,
		EntityID:             e.enterpriseID,
		DistributionContexts: distributionContexts,
	})
	return nil
}

func (e *enterpriseWriter) RemoveLicenses(ctx context.Context, spdxIDs []string, distributionContext string) error {
	if distributionContext == "" {
		return ErrDistributionContextRequired
	}
	_, err := e.storage.UpsertEnterprisePolicy(ctx, e.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		for _, dp := range newPolicy.DistributionPolicies {
			if dp.Name == distributionContext {
				dp.Licenses = removeLicensesFromPolicyLicenses(dp.Licenses, spdxIDs)
			}
		}
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	publishPolicyChangedAsync(ctx, e.app, e.publisher, eventpublisher.PolicyChangedEvent{
		Action:               eventpublisher.PolicyActionLicenseRemoved,
		Level:                eventpublisher.PolicyLevelEnterprise,
		EntityID:             e.enterpriseID,
		DistributionContexts: []string{distributionContext},
	})
	return nil
}

func (e *enterpriseWriter) RemovePackages(ctx context.Context, packages []*proto.PackagePolicy, distributionContext string) error {
	if distributionContext == "" {
		return ErrDistributionContextRequired
	}
	_, err := e.storage.UpsertEnterprisePolicy(ctx, e.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		newPolicy := storage.ProtoCopy(policy)
		for _, dp := range newPolicy.DistributionPolicies {
			if dp.Name == distributionContext {
				dp.Packages = removePackagesFromList(dp.Packages, packages)
			}
		}
		return newPolicy, nil
	})
	if err != nil {
		return err
	}

	publishPolicyChangedAsync(ctx, e.app, e.publisher, eventpublisher.PolicyChangedEvent{
		Action:               eventpublisher.PolicyActionPackageExemptionRemoved,
		Level:                eventpublisher.PolicyLevelEnterprise,
		EntityID:             e.enterpriseID,
		DistributionContexts: []string{distributionContext},
	})
	return nil
}

func removeLicensesFromPolicyLicenses(policyLicenses *proto.PolicyLicenses, spdxIDsToRemove []string) *proto.PolicyLicenses {
	if policyLicenses == nil || policyLicenses.Allowed == nil {
		return policyLicenses
	}

	spdxToRemoveMap := make(map[string]bool)
	for _, spdxID := range spdxIDsToRemove {
		spdxToRemoveMap[spdxID] = true
	}

	var updatedAllowed []*proto.LicenseEntry
	for _, existing := range policyLicenses.Allowed {
		if !spdxToRemoveMap[existing.SpdxId] {
			updatedAllowed = append(updatedAllowed, existing)
		}
	}

	return &proto.PolicyLicenses{
		Allowed: updatedAllowed,
	}
}

func removePackagesFromList(existing, toRemove []*proto.PackagePolicy) []*proto.PackagePolicy {
	result := make([]*proto.PackagePolicy, 0, len(existing))
	for _, existingPkg := range existing {
		shouldRemove := false
		for _, pkg := range toRemove {
			if existingPkg.PackageManager == pkg.PackageManager && existingPkg.Name == pkg.Name {
				shouldRemove = true
				break
			}
		}
		if !shouldRemove {
			result = append(result, existingPkg)
		}
	}
	return result
}
