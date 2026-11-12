package models

import (
	"strings"

	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// policyWithDistributions is a common type between OrganizationPolicy and EnterprisePolicy
type policyWithDistributions interface {
	GetDistributionPolicies() []*proto.DistributionPolicy
}

// newDistributionPolicy creates an empty distribution policy with the given name.
func newDistributionPolicy(distributionName string) *proto.DistributionPolicy {
	return &proto.DistributionPolicy{
		Name: distributionName,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{},
		},
		Packages: []*proto.PackagePolicy{},
	}
}

// containsLicenseEntry checks if the given SPDX ID is present in the list of `LicenseEntry`s
// using case-insensitive comparison.
func containsLicenseEntry(entries []*proto.LicenseEntry, spdxID string) bool {
	// Normalize the search ID for case-insensitive comparison
	normalizedSearch := strings.ToLower(spdxID)

	for _, entry := range entries {
		// Compare normalized versions for case-insensitive matching
		if strings.EqualFold(entry.SpdxId, normalizedSearch) {
			return true
		}
	}
	return false
}

// ContainsLicenseEntry checks if the given SPDX ID is present in the list of `LicenseEntry`s
// using case-insensitive comparison. This is exported for testing purposes.
func ContainsLicenseEntry(entries []*proto.LicenseEntry, spdxID string) bool {
	return containsLicenseEntry(entries, spdxID)
}

// AddLicensesToPolicyLicenses adds the given SPDX IDs to the PolicyLicenses Allowed list and returns it.
// It sets the AddedAt timestamp to the current time for each added license.
// If a given SPDX ID is already present in the list, it will not be added a second time.
func AddLicensesToPolicyLicenses(licenses *proto.PolicyLicenses, spdxIDs []string) *proto.PolicyLicenses {
	var updatedLicenses *proto.PolicyLicenses
	if licenses == nil {
		updatedLicenses = &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{},
		}
	} else {
		updatedLicenses = licenses
	}

	// Get the current time for AddedAt timestamps
	now := timestamppb.Now()

	for _, spdxID := range spdxIDs {
		if !containsLicenseEntry(updatedLicenses.Allowed, spdxID) {
			updatedLicenses.Allowed = append(updatedLicenses.Allowed, &proto.LicenseEntry{SpdxId: spdxID, AddedAt: now})
		}
	}
	return updatedLicenses
}

// AddLicensesToPolicy adds the given SPDX IDs to the specified distribution policies.
// If a distribution policy does not exist, it is created. If a given SPDX ID is
// already present in the list, it will not be added a second time.
// This returns the updated list of DistributionPolicies that were modified.
func AddLicensesToPolicy(policy policyWithDistributions, spdxIDs, distributionNames []string) []*proto.DistributionPolicy {
	updatedPolicies := policy.GetDistributionPolicies()
	for _, distName := range distributionNames {
		var distPolicy *proto.DistributionPolicy
		for _, dp := range updatedPolicies {
			if dp.Name == distName {
				distPolicy = dp
			}
		}
		if distPolicy == nil {
			distPolicy = newDistributionPolicy(distName)
			updatedPolicies = append(updatedPolicies, distPolicy)
		}
		distPolicy.Licenses = AddLicensesToPolicyLicenses(distPolicy.Licenses, spdxIDs)
	}
	return updatedPolicies
}

// AddPackageToPackagePolicyList adds the given PackagePolicy to the existing list.
// If a PackagePolicy with the same PackageManager and Name already exists, it is replaced.
// Otherwise, the new PackagePolicy is appended to the list.
func AddPackageToPackagePolicyList(existing []*proto.PackagePolicy, newPolicy *proto.PackagePolicy) []*proto.PackagePolicy {
	newPolicy.AddedAt = timestamppb.Now()
	for i, p := range existing {
		if p.PackageManager == newPolicy.PackageManager && p.Name == newPolicy.Name {
			// Replace existing policy
			existing[i] = newPolicy
			return existing
		}
	}
	// Add new policy
	return append(existing, newPolicy)
}

// AddPackageToPolicy adds the given PackagePolicy to the specified distribution policies.
// If a distribution policy does not exist, it is created.
// This returns the updated list of DistributionPolicies that were modified.
func AddPackageToPolicy(policy policyWithDistributions, packagePolicy *proto.PackagePolicy, distributionPolicyNames []string) []*proto.DistributionPolicy {
	distributionPolicies := policy.GetDistributionPolicies()
	for _, contextName := range distributionPolicyNames {
		dpFound := false
		for _, dp := range distributionPolicies {
			if dp.Name == contextName {
				dpFound = true
				dp.Packages = AddPackageToPackagePolicyList(dp.Packages, packagePolicy)
				break
			}
		}
		if !dpFound {
			packagePolicy.AddedAt = timestamppb.Now()
			distributionPolicies = append(distributionPolicies, &proto.DistributionPolicy{
				Name:     contextName,
				Packages: []*proto.PackagePolicy{packagePolicy},
			})
		}
	}
	return distributionPolicies
}
