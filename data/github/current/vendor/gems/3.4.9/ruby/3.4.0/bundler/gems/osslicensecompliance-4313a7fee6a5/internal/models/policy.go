package models

import "slices"

// This file contains structs and code common between the different types
// of policies (repository, organization, and enterprise).

// LicenseEntry represents a license entry in the policy.
type LicenseEntry struct {
	SpdxID   string   `json:"spdxID"`
	Contexts []string `json:"contexts"`
}

// LicenseList holds the allow, blocked an approvalRequired lists.
type LicenseList struct {
	Allowed []LicenseEntry `json:"allowed"`
}

// PackagePolicy is the policy for an individual package.
type PackagePolicy struct {
	PackageManager PackageManager `json:"packageManager"`
	PackageName    string         `json:"packageName"`
	Action         PackageAction  `json:"action"`
	Reason         string         `json:"reason"`
	MatchLicenses  []string       `json:"matchLicenses"`
	Contexts       []string       `json:"contexts"`
}

// PackageAction is enum to constrain the actions.
type PackageAction int

const (
	// PackageActionAllow means that the package is allowed (given a match in the licenses).
	PackageActionAllow PackageAction = iota
	// PackageActionBlock means that the package is blocked from use.
	PackageActionBlock
	// PackageActionPrivate means that the package is a private one and we do not perform license checks.
	PackageActionPrivate
)

// String returns the string representation of the PackageAction.
func (pa PackageAction) String() string {
	return [...]string{"allow", "blocked", "private"}[pa]
}

// mapPackagePolicySliceToMap converts a slice of PackagePolicy to a map for faster lookup.
// We do this because we store the slice in the database to allow multiple package policies
// per package, but we'll eventually want to allow different policies for different versions.
// Using a slice for access would be too slow because we call this code a lot while evaluating
// the policy.
func mapPackagePolicySliceToMap(packages []PackagePolicy) map[PackageManager]map[string]PackagePolicy {
	fastPackages := make(map[PackageManager]map[string]PackagePolicy)
	for _, packagePolicy := range packages {
		if _, ok := fastPackages[packagePolicy.PackageManager]; !ok {
			fastPackages[packagePolicy.PackageManager] = make(map[string]PackagePolicy)
		}
		fastPackages[packagePolicy.PackageManager][packagePolicy.PackageName] = packagePolicy
	}
	return fastPackages
}

// getPackagePolicy returns the package policy for the given package or nil
// if there isn't one. This is designed to be called with the `Packages` map
// on a policy at any level.
func getPackagePolicy(packagesMap map[PackageManager]map[string]PackagePolicy, packageManager PackageManager, name, distributionContext string) *PackagePolicy {
	packageManagerPolicies, ok := packagesMap[packageManager]
	if !ok {
		return nil
	}
	packagePolicy, ok := packageManagerPolicies[name]
	if !ok {
		return nil
	}
	if !slices.Contains(packagePolicy.Contexts, distributionContext) {
		return nil
	}
	return &packagePolicy
}
