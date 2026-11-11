package models_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAddLicensesToPolicy(t *testing.T) {
	r := require.New(t)
	a := assert.New(t)
	policy := &proto.EnterprisePolicy{}
	spdxIDs := []string{"MIT", "Apache-2.0"}
	distributionPolicyNames := []string{"distributed", "internal"}

	updatedDPs := models.AddLicensesToPolicy(policy, spdxIDs, distributionPolicyNames)
	policy.DistributionPolicies = updatedDPs
	r.Len(updatedDPs, 2)

	// Check that the licenses were added correctly
	for _, dp := range updatedDPs {
		a.Contains(distributionPolicyNames, dp.Name)
		r.Len(dp.Licenses.Allowed, 2)
		a.Equal("MIT", dp.Licenses.Allowed[0].SpdxId)
		a.NotZero(dp.Licenses.Allowed[0].AddedAt, "AddedAt timestamp should be set")
		a.Equal("Apache-2.0", dp.Licenses.Allowed[1].SpdxId)
	}

	// Add a duplicate license and ensure it is not added again
	spdxIDs = []string{"MIT"}
	updatedDPs = models.AddLicensesToPolicy(policy, spdxIDs, []string{"distributed"})
	r.Len(updatedDPs, 2)                     // Should still be 2 distribution policies
	a.Len(updatedDPs[0].Licenses.Allowed, 2) // Should still be 2, not 3
}

func TestAddPackageToPolicy(t *testing.T) {
	r := require.New(t)
	a := assert.New(t)

	policy := &proto.EnterprisePolicy{}
	packagePolicy := &proto.PackagePolicy{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "example-package",
		Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
	}
	updatedDPs := models.AddPackageToPolicy(policy, packagePolicy, []string{"distributed"})
	policy.DistributionPolicies = updatedDPs
	r.Len(updatedDPs, 1)
	r.Len(updatedDPs[0].Packages, 1)
	a.Equal("example-package", updatedDPs[0].Packages[0].Name)
	a.NotZero(updatedDPs[0].Packages[0].AddedAt, "AddedAt timestamp should be set")

	// Add the same package again and ensure it is not duplicated
	updatedDPs = models.AddPackageToPolicy(policy, packagePolicy, []string{"distributed"})
	r.Len(updatedDPs, 1)
	a.Len(updatedDPs[0].Packages, 1) // Should still be 1, not 2

	// Add another package to the same distribution policy
	anotherPackagePolicy := &proto.PackagePolicy{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "another-package",
		Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
	}
	updatedDPs = models.AddPackageToPolicy(policy, anotherPackagePolicy, []string{"distributed"})
	r.Len(updatedDPs, 1)
	a.Len(updatedDPs[0].Packages, 2)
	a.NotZero(updatedDPs[0].Packages[1].AddedAt, "AddedAt timestamp should be set")
}

func TestContainsLicenseEntry_CaseInsensitive(t *testing.T) {
	testCases := []struct {
		name     string
		entries  []*proto.LicenseEntry
		spdxID   string
		expected bool
	}{
		{
			name: "exact match",
			entries: []*proto.LicenseEntry{
				{SpdxId: "MIT"},
				{SpdxId: "Apache-2.0"},
			},
			spdxID:   "MIT",
			expected: true,
		},
		{
			name: "case insensitive match - lowercase query",
			entries: []*proto.LicenseEntry{
				{SpdxId: "MIT"},
				{SpdxId: "Apache-2.0"},
			},
			spdxID:   "mit",
			expected: true,
		},
		{
			name: "case insensitive match - uppercase query",
			entries: []*proto.LicenseEntry{
				{SpdxId: "Apache-2.0"},
			},
			spdxID:   "APACHE-2.0",
			expected: true,
		},
		{
			name: "case insensitive match - mixed case",
			entries: []*proto.LicenseEntry{
				{SpdxId: "BSD-3-Clause"},
			},
			spdxID:   "bsd-3-clause",
			expected: true,
		},
		{
			name: "expression case insensitive",
			entries: []*proto.LicenseEntry{
				{SpdxId: "MIT OR Apache-2.0"},
			},
			spdxID:   "mit or apache-2.0",
			expected: true,
		},
		{
			name: "no match",
			entries: []*proto.LicenseEntry{
				{SpdxId: "MIT"},
			},
			spdxID:   "Apache-2.0",
			expected: false,
		},
		{
			name:     "empty list",
			entries:  []*proto.LicenseEntry{},
			spdxID:   "MIT",
			expected: false,
		},
		{
			name: "LicenseRef case sensitive",
			entries: []*proto.LicenseEntry{
				{SpdxId: "LicenseRef-Custom"},
			},
			spdxID:   "LicenseRef-Custom",
			expected: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			result := models.ContainsLicenseEntry(tc.entries, tc.spdxID)
			require.Equal(t, tc.expected, result, "ContainsLicenseEntry should return %v for spdxID %q in entries %v", tc.expected, tc.spdxID, tc.entries)
		})
	}
}

func TestAddLicensesToPolicyLicensesHandlesNilLicenses(t *testing.T) {
	policy := &proto.RepositoryPolicy{}
	spdxIDs := []string{"MIT", "Apache-2.0"}

	policy.Licenses = models.AddLicensesToPolicyLicenses(policy.Licenses, spdxIDs)

	require.Len(t, policy.Licenses.Allowed, 2, "Should have 2 licenses")
	assert.Equal(t, "MIT", policy.Licenses.Allowed[0].SpdxId)
	assert.Equal(t, "Apache-2.0", policy.Licenses.Allowed[1].SpdxId)
	assert.NotZero(t, policy.Licenses.Allowed[0].AddedAt, "AddedAt timestamp should be set")
	assert.NotZero(t, policy.Licenses.Allowed[1].AddedAt, "AddedAt timestamp should be set")
}
