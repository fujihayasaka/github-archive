package models

import (
	"maps"
	"slices"

	"strings"

	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// CompletePolicy holds the policies at all levels. These are needed collectively
// in order to evaluate if a package meets the requirements of the policy.
// Any one of the policies can be missing. In general, the more specific
// the policy, the higher priority its contents.
type CompletePolicy struct {
	EnterprisePolicy   *EnterprisePolicy
	OrganizationPolicy *OrganizationPolicy
	RepositoryPolicy   *RepositoryPolicy

	allowList []string
}

// NewCompletePolicy creates a CompletePolicy from the provided protos. Use this
// constructor to ensure that internal accessors are created.
func NewCompletePolicy(enterprise *proto.EnterprisePolicy, organization *proto.OrganizationPolicy, repository *proto.RepositoryPolicy) *CompletePolicy {
	return &CompletePolicy{
		EnterprisePolicy:   NewEnterprisePolicy(enterprise),
		OrganizationPolicy: NewOrganizationPolicy(organization),
		RepositoryPolicy:   NewRepositoryPolicy(repository),
	}
}

// GetEnterpriseID returns the Enterprise ID from the complete policy, or 0 if there is no enterprise policy.
func (cp *CompletePolicy) GetEnterpriseID() uint64 {
	if cp.EnterprisePolicy != nil && cp.EnterprisePolicy.Data != nil {
		return cp.EnterprisePolicy.Data.EnterpriseId
	}
	return 0
}

// GetOrganizationID returns the Organization ID from the complete policy, or 0 if there is no organization policy.
func (cp *CompletePolicy) GetOrganizationID() uint64 {
	if cp.OrganizationPolicy != nil && cp.OrganizationPolicy.Data != nil {
		return cp.OrganizationPolicy.Data.OrganizationId
	}
	return 0
}

// GetRepositoryID returns the Repository ID from the complete policy, or 0 if there is no repository policy.
func (cp *CompletePolicy) GetRepositoryID() uint64 {
	if cp.RepositoryPolicy != nil && cp.RepositoryPolicy.Data != nil {
		return cp.RepositoryPolicy.Data.RepositoryId
	}
	return 0
}

// PolicyFromExistingPolicy creates a CompletePolicy from an existing CompletePolicy.
// For each policy that is provided, if its ID differs from the existing policy, a new policy
// is created from the provided proto. If the provided policy is nil, the corresponding
// policy in the new CompletePolicy is set to nil.
func (cp *CompletePolicy) PolicyFromExistingPolicy(enterprise *proto.EnterprisePolicy, organization *proto.OrganizationPolicy, repository *proto.RepositoryPolicy) *CompletePolicy {
	newEnterprise := cp.EnterprisePolicy
	if enterprise == nil || enterprise.EnterpriseId == 0 {
		newEnterprise = nil
	} else if enterprise.EnterpriseId != cp.GetEnterpriseID() {
		newEnterprise = NewEnterprisePolicy(enterprise)
	}
	newOrganization := cp.OrganizationPolicy
	if organization == nil || organization.OrganizationId == 0 {
		newOrganization = nil
	} else if organization.OrganizationId != cp.GetOrganizationID() {
		newOrganization = NewOrganizationPolicy(organization)
	}
	newRepository := cp.RepositoryPolicy
	if repository == nil || repository.RepositoryId == 0 {
		newRepository = nil
	} else if repository.RepositoryId != cp.GetRepositoryID() {
		newRepository = NewRepositoryPolicy(repository)
	}
	return &CompletePolicy{
		EnterprisePolicy:   newEnterprise,
		OrganizationPolicy: newOrganization,
		RepositoryPolicy:   newRepository,
	}
}

// GetAllowList returns the list of allowed licenses based on the complete policy.
// The list is computed once and cached.
func (cp *CompletePolicy) GetAllowList(distributionContext string) []string {
	if cp.allowList != nil {
		return cp.allowList
	}

	// The allow list is the union of all the allow lists in the policy.
	allowList := map[string]struct{}{}
	addToAllowList := func(licenses []*proto.LicenseEntry) {
		for _, l := range licenses {
			allowList[l.SpdxId] = struct{}{}
		}
	}
	if cp.EnterprisePolicy != nil && cp.EnterprisePolicy.Data.DistributionPolicies != nil {
		for _, dp := range cp.EnterprisePolicy.Data.DistributionPolicies {
			if dp.Name == distributionContext && dp.Licenses != nil {
				addToAllowList(dp.Licenses.Allowed)
			}
		}
	}
	if cp.OrganizationPolicy != nil && cp.OrganizationPolicy.Data.DistributionPolicies != nil {
		for _, dp := range cp.OrganizationPolicy.Data.DistributionPolicies {
			if dp.Name == distributionContext && dp.Licenses != nil {
				addToAllowList(dp.Licenses.Allowed)
			}
		}
	}
	if cp.RepositoryPolicy != nil && cp.RepositoryPolicy.Data.Licenses != nil {
		addToAllowList(cp.RepositoryPolicy.Data.Licenses.Allowed)
	}
	cp.allowList = slices.Collect(maps.Keys(allowList))
	return cp.allowList
}

// GetPackagePolicy returns the most specific package policy for the given package manager,
// package name, and distribution context. The return value is the policy and the level
// at which it was found (repository, organization, or enterprise). If no policy is found,
// nil and POLICY_LEVEL_UNKNOWN are returned.
func (cp *CompletePolicy) GetPackagePolicy(packageManager proto.PackageManager, name, distributionContext string) (*proto.PackagePolicy, proto.PolicyLevel) {
	if cp.RepositoryPolicy != nil {
		if policy := cp.RepositoryPolicy.packageAccessor.GetPackagePolicy(packageManager, name, distributionContext); policy != nil {
			return policy, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY
		}
	}
	if cp.OrganizationPolicy != nil {
		packageAccessor := cp.OrganizationPolicy.packageAccessors[distributionContext]
		if packageAccessor != nil {
			if policy := packageAccessor.GetPackagePolicy(packageManager, name, distributionContext); policy != nil {
				return policy, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION
			}
		}
	}
	if cp.EnterprisePolicy != nil {
		packageAccessor := cp.EnterprisePolicy.packageAccessors[distributionContext]
		if packageAccessor != nil {
			if policy := packageAccessor.GetPackagePolicy(packageManager, name, distributionContext); policy != nil {
				return policy, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE
			}
		}
	}
	return nil, proto.PolicyLevel_POLICY_LEVEL_UNKNOWN
}

// packagePolicyAccessor provides fast access to package policies by package manager and name.
type packagePolicyAccessor struct {
	fastPackages     map[proto.PackageManager]map[string]*proto.PackagePolicy
	wildcardPolicies map[proto.PackageManager][]*proto.PackagePolicy
}

// GetPackagePolicy returns the package policy for the given package manager, package name,
// and distribution context. If no policy is found, nil is returned.
func (ppa *packagePolicyAccessor) GetPackagePolicy(packageManager proto.PackageManager, packageName, distributionContext string) *proto.PackagePolicy {
	// First try the fast lookup for exact package matches.
	if packagePolicy := ppa.getFastPackagePolicy(packageManager, packageName, distributionContext); packagePolicy != nil {
		return packagePolicy
	}

	// Next try the wildcard policies.
	return ppa.getWildcardPackagePolicy(packageManager, packageName, distributionContext)
}

func (ppa *packagePolicyAccessor) getFastPackagePolicy(packageManager proto.PackageManager, packageName, distributionContext string) *proto.PackagePolicy {
	// This should be initialized by calling newPackagePolicyAccessor.
	if ppa.fastPackages == nil {
		return nil
	}
	if _, ok := ppa.fastPackages[packageManager]; !ok {
		return nil
	}
	if packagePolicy, ok := ppa.fastPackages[packageManager][packageName]; ok {
		return packagePolicy
	}

	return nil
}

func (ppa *packagePolicyAccessor) getWildcardPackagePolicy(packageManager proto.PackageManager, packageName, distributionContext string) *proto.PackagePolicy {
	// This should be initialized by calling newPackagePolicyAccessor.
	if ppa.wildcardPolicies == nil {
		return nil
	}
	if _, ok := ppa.wildcardPolicies[packageManager]; !ok {
		return nil
	}
	for _, packagePolicy := range ppa.wildcardPolicies[packageManager] {
		if WildcardNameMatch(packagePolicy.Name, packageName) {
			return packagePolicy
		}
	}
	return nil
}

func newPackagePolicyAccessor(policy []*proto.PackagePolicy) *packagePolicyAccessor {
	fastPackages := make(map[proto.PackageManager]map[string]*proto.PackagePolicy)
	wildcardPolicies := make(map[proto.PackageManager][]*proto.PackagePolicy)
	for _, packagePolicy := range policy {
		if _, ok := fastPackages[packagePolicy.PackageManager]; !ok {
			fastPackages[packagePolicy.PackageManager] = make(map[string]*proto.PackagePolicy)
		}
		if strings.Contains(packagePolicy.Name, "*") {
			wildcardPolicies[packagePolicy.PackageManager] = append(wildcardPolicies[packagePolicy.PackageManager], packagePolicy)
		} else {
			fastPackages[packagePolicy.PackageManager][packagePolicy.Name] = packagePolicy
		}
	}
	return &packagePolicyAccessor{fastPackages: fastPackages, wildcardPolicies: wildcardPolicies}
}

// WildcardNameMatch returns true if the package name matches the pattern with wildcards.
// It supports only a single wildcard '*' in the pattern and won't behave as expected if there are multiple wildcards.
func WildcardNameMatch(pattern, packageName string) bool {
	parts := strings.Split(pattern, "*")
	if len(parts) == 1 {
		// No wildcard, must match exactly
		return pattern == packageName
	}
	prefix := parts[0]
	suffix := parts[1]

	if !strings.HasPrefix(packageName, prefix) || !strings.HasSuffix(packageName, suffix) {
		return false
	}

	return true
}

// GetRemediationGuidance returns the custom remediation guidance from enterprise and organization policies
func (cp *CompletePolicy) GetRemediationGuidance() string {
	var builder strings.Builder

	if cp.EnterprisePolicy != nil && cp.EnterprisePolicy.Data.CustomRemediationGuidance != "" {
		_, _ = builder.WriteString(cp.EnterprisePolicy.Data.CustomRemediationGuidance)
	}

	if cp.OrganizationPolicy != nil && cp.OrganizationPolicy.Data.CustomRemediationGuidance != "" {
		if builder.Len() > 0 {
			_, _ = builder.WriteString("\n ")
		}
		_, _ = builder.WriteString(cp.OrganizationPolicy.Data.CustomRemediationGuidance)
	}

	return builder.String()
}

func addPackagesToCombinedPolicy(combinedPolicy *proto.CombinedRepositoryPolicy, policyLevel proto.PolicyLevel, packagePolicies []*proto.PackagePolicy) {
	for _, pkgPolicy := range packagePolicies {
		combinedPkgPolicy := &proto.CombinedPackage{
			PackageManager:      pkgPolicy.PackageManager,
			Name:                pkgPolicy.Name,
			Action:              pkgPolicy.Action,
			Reason:              pkgPolicy.Reason,
			ExtraAllowedSpdxIds: pkgPolicy.ExtraAllowedSpdxIds,
			AddedAt:             pkgPolicy.AddedAt,
			Level:               policyLevel,
		}
		combinedPolicy.Packages = append(combinedPolicy.Packages, combinedPkgPolicy)
	}
}

func addLicensesToCombinedPolicy(combinedPolicy *proto.CombinedRepositoryPolicy, policyLevel proto.PolicyLevel, licenses *proto.PolicyLicenses) {
	if licenses == nil {
		return
	}
	for _, allowed := range licenses.Allowed {
		combinedLicense := &proto.CombinedLicense{
			SpdxId:  allowed.SpdxId,
			AddedAt: allowed.AddedAt,
			Level:   policyLevel,
		}
		combinedPolicy.Licenses = append(combinedPolicy.Licenses, combinedLicense)
	}
}

// GetCombinedRepositoryPolicy returns a combined repository policy based on this complete policy
// and the provided distribution policy name.
func (cp *CompletePolicy) GetCombinedRepositoryPolicy(distributionPolicyName string) *proto.CombinedRepositoryPolicy {
	combinedPolicy := &proto.CombinedRepositoryPolicy{}

	if cp.EnterprisePolicy != nil && cp.EnterprisePolicy.Data.DistributionPolicies != nil {
		for _, dp := range cp.EnterprisePolicy.Data.DistributionPolicies {
			if dp.Name == distributionPolicyName {
				addPackagesToCombinedPolicy(combinedPolicy, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, dp.Packages)
				addLicensesToCombinedPolicy(combinedPolicy, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, dp.Licenses)
			}
		}
	}

	if cp.OrganizationPolicy != nil && cp.OrganizationPolicy.Data.DistributionPolicies != nil {
		for _, dp := range cp.OrganizationPolicy.Data.DistributionPolicies {
			if dp.Name == distributionPolicyName {
				addPackagesToCombinedPolicy(combinedPolicy, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, dp.Packages)
				addLicensesToCombinedPolicy(combinedPolicy, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, dp.Licenses)
			}
		}
	}

	if cp.RepositoryPolicy != nil {
		addPackagesToCombinedPolicy(combinedPolicy, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, cp.RepositoryPolicy.Data.Packages)
		addLicensesToCombinedPolicy(combinedPolicy, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, cp.RepositoryPolicy.Data.Licenses)
	}
	return combinedPolicy
}
