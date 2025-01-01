// Package models contains models we use in our domain logic
package models

import (
	"sync"
	"time"
)

// OrganizationPolicy represents an organisation level license policy.
type OrganizationPolicy struct {
	ID                        uint64
	CreatedAt                 time.Time
	OrganizationID            uint64
	Policy                    *Policy
	Hash                      []byte
	CustomRemediationGuidance string
}

// Policy is the policy declared for license compliance.
type Policy struct {
	// PolicyLicenses provides the ability to have multiple license lists.
	// The default list is "default" (and that's all that's supported for now).
	PolicyLicenses  LicenseList     `json:"licenseList"`
	Packages        []PackagePolicy `json:"packages"`
	fastPackages    map[PackageManager]map[string]PackagePolicy
	mapCreationLock sync.Mutex
}

// GetAllowList returns the default list of allowed licenses. Will never
// return nil, but may return an empty slice.
func (p *Policy) GetAllowList() []LicenseEntry {
	return p.PolicyLicenses.Allowed
}

// GetPackagePolicy returns the policy for a given package.
func (p *Policy) GetPackagePolicy(packageManager PackageManager, packageName, distributionContext string) *PackagePolicy {
	if p.Packages == nil {
		return nil
	}

	// This code is called a lot, so we convert the slice to a map for faster lookup.
	// It's stored in the database as a slice so that we can have multiple
	// package policies for a single package, potentially allowing different
	// policies for different versions.
	if p.fastPackages == nil {
		p.mapCreationLock.Lock()
		defer p.mapCreationLock.Unlock()
		p.fastPackages = mapPackagePolicySliceToMap(p.Packages)
	}
	return getPackagePolicy(p.fastPackages, packageManager, packageName, distributionContext)
}
