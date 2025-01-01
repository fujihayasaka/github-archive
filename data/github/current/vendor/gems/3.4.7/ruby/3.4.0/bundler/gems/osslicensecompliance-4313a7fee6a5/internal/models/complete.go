package models

import (
	"maps"
	"slices"
)

// CompletePolicy holds the policies at all levels. These are needed collectively
// in order to evaluate if a package meets the requirements of the policy.
// Any one of the policies can be missing. In general, the more specific
// the policy, the higher priority its contents.
type CompletePolicy struct {
	EnterprisePolicy   *EnterprisePolicy
	OrganizationPolicy *OrganizationPolicy
	RepositoryPolicy   *RepositoryPolicy
	allowList          []string
}

// GetAllowList returns the list of allowed licenses based on the complete policy.
// The list is computed once and cached.
func (cp *CompletePolicy) GetAllowList(distributionContext string) []string {
	if cp.allowList != nil {
		return cp.allowList
	}

	// The allow list is the union of all the allow lists in the policy.
	allowList := map[string]struct{}{}
	addToAllowList := func(licenses []LicenseEntry) {
		for _, l := range licenses {
			if slices.Contains(l.Contexts, distributionContext) {
				allowList[l.SpdxID] = struct{}{}
			}
		}
	}
	if cp.EnterprisePolicy != nil {
		addToAllowList(cp.EnterprisePolicy.Policy.GetAllowList())
	}
	if cp.OrganizationPolicy != nil {
		addToAllowList(cp.OrganizationPolicy.Policy.GetAllowList())
	}
	if cp.RepositoryPolicy != nil {
		addToAllowList(cp.RepositoryPolicy.Policy.GetAllowList())
	}
	cp.allowList = slices.Collect(maps.Keys(allowList))
	return cp.allowList
}
