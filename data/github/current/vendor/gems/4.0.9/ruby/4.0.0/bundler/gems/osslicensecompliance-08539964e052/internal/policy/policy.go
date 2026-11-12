// Package policy provides operations for updating license policies across different levels
// (repository, organization, enterprise).
package policy

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// ErrDistributionContextRequired is returned when a remove operation is attempted without a distribution context.
var ErrDistributionContextRequired = errors.New("distributionContext is required for organization/enterprise policies")

// repositoryUpserter implements the policyUpserter interface for repository policies.
type repositoryUpserter struct {
	storage      *storage.Storage
	repositoryID uint64
}

// Upsert performs an upsert operation on a repository policy using the provided update function.
func (u *repositoryUpserter) Upsert(ctx context.Context, updateFunc func(policyUpdater) updateResult) (updateResult, error) {
	var result updateResult
	storageResult, err := u.storage.UpsertRepositoryPolicy(ctx, u.repositoryID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		updater := &repositoryPolicyUpdater{policy: policy}
		result = updateFunc(updater)
		return updater.policy, nil
	})
	if err != nil {
		return updateResult{}, fmt.Errorf("failed to upsert repository policy: %w", err)
	}

	result.WasCreated = storageResult.WasCreated
	return result, nil
}

// organizationUpserter implements the policyUpserter interface for organization policies.
type organizationUpserter struct {
	storage        *storage.Storage
	organizationID uint64
}

// Upsert performs an upsert operation on an organization policy using the provided update function.
func (u *organizationUpserter) Upsert(ctx context.Context, updateFunc func(policyUpdater) updateResult) (updateResult, error) {
	var result updateResult
	storageResult, err := u.storage.UpsertOrganizationPolicy(ctx, u.organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		updater := &organizationPolicyUpdater{policy: policy}
		result = updateFunc(updater)
		return updater.policy, nil
	})
	if err != nil {
		return updateResult{}, fmt.Errorf("failed to upsert organization policy: %w", err)
	}

	result.WasCreated = storageResult.WasCreated
	return result, nil
}

// enterpriseUpserter implements the policyUpserter interface for enterprise policies.
type enterpriseUpserter struct {
	storage      *storage.Storage
	enterpriseID uint64
}

// Upsert performs an upsert operation on an enterprise policy using the provided update function.
func (u *enterpriseUpserter) Upsert(ctx context.Context, updateFunc func(policyUpdater) updateResult) (updateResult, error) {
	var result updateResult
	storageResult, err := u.storage.UpsertEnterprisePolicy(ctx, u.enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		updater := &enterprisePolicyUpdater{policy: policy}
		result = updateFunc(updater)
		return updater.policy, nil
	})
	if err != nil {
		return updateResult{}, fmt.Errorf("failed to upsert enterprise policy: %w", err)
	}

	result.WasCreated = storageResult.WasCreated
	return result, nil
}

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

// repositoryPolicyUpdater implements the policyUpdater interface for repository policies.
type repositoryPolicyUpdater struct {
	policy *proto.RepositoryPolicy
}

// Ensure repositoryPolicyUpdater implements the policyUpdater interface.
var _ policyUpdater = (*repositoryPolicyUpdater)(nil)

// AddLicenses adds licenses to the repository policy, ignoring distribution contexts since they don't apply at the repository level.
func (a *repositoryPolicyUpdater) AddLicenses(licenses, _ []string) {
	a.policy.Licenses = models.AddLicensesToPolicyLicenses(a.policy.Licenses, licenses)
}

// AddPackage adds a package exemption to the repository policy, ignoring distribution contexts since they don't apply at the repository level.
func (a *repositoryPolicyUpdater) AddPackage(packagePolicy *proto.PackagePolicy, distributionContexts []string) {
	a.policy.Packages = models.AddPackageToPackagePolicyList(a.policy.Packages, packagePolicy)
}

// RemoveLicenses removes licenses from the repository policy, ignoring distribution contexts since they don't apply at the repository level.
func (a *repositoryPolicyUpdater) RemoveLicenses(spdxIDs []string, _ string) {
	a.policy.Licenses = removeLicensesFromPolicyLicenses(a.policy.Licenses, spdxIDs)
}

// RemovePackages removes package exemptions from the repository policy, ignoring distribution contexts since they don't apply at the repository level.
func (a *repositoryPolicyUpdater) RemovePackages(packages []*proto.PackagePolicy, _ string) {
	a.policy.Packages = removePackagesFromList(a.policy.Packages, packages)
}

// organizationPolicyUpdater implements the policyUpdater interface for organization policies.
type organizationPolicyUpdater struct {
	policy *proto.OrganizationPolicy
}

var _ policyUpdater = (*organizationPolicyUpdater)(nil)

// AddLicenses adds licenses to the organization policy for the specified distribution contexts.
func (a *organizationPolicyUpdater) AddLicenses(licenses, distributionContexts []string) {
	distributionPolicies := models.AddLicensesToPolicy(a.policy, licenses, distributionContexts)
	a.policy.DistributionPolicies = distributionPolicies
}

// AddPackage adds a package exemption to the organization policy for the specified distribution contexts.
func (a *organizationPolicyUpdater) AddPackage(packagePolicy *proto.PackagePolicy, distributionContexts []string) {
	a.policy.DistributionPolicies = models.AddPackageToPolicy(a.policy, packagePolicy, distributionContexts)
}

// RemoveLicenses removes licenses from the organization policy for the specified distribution context.
func (a *organizationPolicyUpdater) RemoveLicenses(spdxIDs []string, distributionContext string) {
	for _, dp := range a.policy.DistributionPolicies {
		if dp.Name == distributionContext {
			dp.Licenses = removeLicensesFromPolicyLicenses(dp.Licenses, spdxIDs)
		}
	}
}

// RemovePackages removes package exemptions from the organization policy for the specified distribution context.
func (a *organizationPolicyUpdater) RemovePackages(packages []*proto.PackagePolicy, distributionContext string) {
	for _, dp := range a.policy.DistributionPolicies {
		if dp.Name == distributionContext {
			dp.Packages = removePackagesFromList(dp.Packages, packages)
		}
	}
}

// enterprisePolicyUpdater implements the policyUpdater interface for enterprise policies.
type enterprisePolicyUpdater struct {
	policy *proto.EnterprisePolicy
}

var _ policyUpdater = (*enterprisePolicyUpdater)(nil)

// AddLicenses adds licenses to the enterprise policy for the specified distribution contexts.
func (a *enterprisePolicyUpdater) AddLicenses(licenses, distributionContexts []string) {
	distributionPolicies := models.AddLicensesToPolicy(a.policy, licenses, distributionContexts)
	a.policy.DistributionPolicies = distributionPolicies
}

// AddPackage adds a package exemption to the enterprise policy for the specified distribution contexts.
func (a *enterprisePolicyUpdater) AddPackage(packagePolicy *proto.PackagePolicy, distributionContexts []string) {
	a.policy.DistributionPolicies = models.AddPackageToPolicy(a.policy, packagePolicy, distributionContexts)
}

// RemoveLicenses removes licenses from the enterprise policy for the specified distribution context.
func (a *enterprisePolicyUpdater) RemoveLicenses(spdxIDs []string, distributionContext string) {
	for _, dp := range a.policy.DistributionPolicies {
		if dp.Name == distributionContext {
			dp.Licenses = removeLicensesFromPolicyLicenses(dp.Licenses, spdxIDs)
		}
	}
}

// RemovePackages removes package exemptions from the enterprise policy for the specified distribution context.
func (a *enterprisePolicyUpdater) RemovePackages(packages []*proto.PackagePolicy, distributionContext string) {
	for _, dp := range a.policy.DistributionPolicies {
		if dp.Name == distributionContext {
			dp.Packages = removePackagesFromList(dp.Packages, packages)
		}
	}
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
