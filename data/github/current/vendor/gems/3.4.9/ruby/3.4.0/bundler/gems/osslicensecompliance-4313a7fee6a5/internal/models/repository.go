package models

import (
	"sync"
	"time"
)

// RepositoryPolicy is the container for the policy for a single repository.
type RepositoryPolicy struct {
	ID        uint64
	CreatedAt time.Time
	// TODO: do we need the organization ID here?
	OrganizationID uint64
	RepositoryID   uint64
	Hash           []byte
	Policy         *RepositoryRefinement
}

// RepositoryRefinement provides license policy information for a single repository.
type RepositoryRefinement struct {
	Licenses        LicenseList     `json:"repositoryLicenses"`
	Packages        []PackagePolicy `json:"packages"`
	fastPackages    map[PackageManager]map[string]PackagePolicy
	mapCreationLock sync.Mutex
}

// GetAllowList returns the list of allowed licenses based on the repository policy.
// It will never return nil, but may return an empty slice.
func (rr *RepositoryRefinement) GetAllowList() []LicenseEntry {
	if rr.Licenses.Allowed == nil {
		return []LicenseEntry{}
	}
	return rr.Licenses.Allowed
}

// GetPackagePolicy returns the policy for a given package.
func (rr *RepositoryRefinement) GetPackagePolicy(packageManager PackageManager, packageName, distributionContext string) *PackagePolicy {
	if rr.Packages == nil {
		return nil
	}

	// This code is called a lot, so we convert the slice to a map for faster lookup.
	// It's stored in the database as a slice so that we can have multiple
	// package policies for a single package, potentially allowing different
	// policies for different versions.
	if rr.fastPackages == nil {
		rr.mapCreationLock.Lock()
		defer rr.mapCreationLock.Unlock()
		rr.fastPackages = mapPackagePolicySliceToMap(rr.Packages)
	}
	return getPackagePolicy(rr.fastPackages, packageManager, packageName, distributionContext)
}
