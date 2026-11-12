package models_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetAllowList(t *testing.T) {
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Licenses: &proto.PolicyLicenses{
						Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
					},
				},
			},
		},
		&proto.OrganizationPolicy{
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Licenses: &proto.PolicyLicenses{
						Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
					},
				},
			},
		},
		&proto.RepositoryPolicy{
			Licenses: &proto.PolicyLicenses{
				Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-3-Clause"}),
			},
		},
	)
	allowList := policy.GetAllowList("distributed")
	assert.Len(t, allowList, 3)
	assert.ElementsMatch(t, allowList, []string{"MIT", "BSD-2-Clause", "BSD-3-Clause"})

	// Test that the list is cached
	policy.OrganizationPolicy = nil
	allowList = policy.GetAllowList("distributed")
	assert.Len(t, allowList, 3, "expected the same number of elements despite changing it because of caching")

	policy = models.NewCompletePolicy(
		nil,
		nil,
		&proto.RepositoryPolicy{
			Licenses: &proto.PolicyLicenses{
				Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-3-Clause"}),
			},
		},
	)
	allowList = policy.GetAllowList("distributed")
	assert.Len(t, allowList, 1)
	assert.ElementsMatch(t, allowList, []string{"BSD-3-Clause"})
}

func TestGetRemediationGuidance(t *testing.T) {
	tests := []struct {
		name           string
		policy         *models.CompletePolicy
		expectedResult string
	}{
		{
			name: "both enterprise and organization guidance present",
			policy: models.NewCompletePolicy(
				&proto.EnterprisePolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
							},
						},
					},
					CustomRemediationGuidance: "enterprise guidance",
				},
				&proto.OrganizationPolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
							},
						},
					},
					CustomRemediationGuidance: "organisation guidance",
				},
				nil,
			),
			expectedResult: "enterprise guidance\n organisation guidance",
		},
		{
			name: "enterprise guidance only",
			policy: models.NewCompletePolicy(
				&proto.EnterprisePolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
							},
						},
					},
					CustomRemediationGuidance: "enterprise guidance",
				},
				nil,
				nil,
			),
			expectedResult: "enterprise guidance",
		},
		{
			name: "organization guidance only",
			policy: models.NewCompletePolicy(
				nil,
				&proto.OrganizationPolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
							},
						},
					},
					CustomRemediationGuidance: "organisation guidance",
				},
				nil,
			),
			expectedResult: "organisation guidance",
		},
		{
			name: "both policies exist but guidance is empty string",
			policy: models.NewCompletePolicy(
				&proto.EnterprisePolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
							},
						},
					},
					CustomRemediationGuidance: "",
				},
				&proto.OrganizationPolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
							},
						},
					},
					CustomRemediationGuidance: "",
				},
				nil,
			),
			expectedResult: "",
		},
		{
			name: "enterprise policy exists but guidance is empty string",
			policy: models.NewCompletePolicy(
				&proto.EnterprisePolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
							},
						},
					},
					CustomRemediationGuidance: "",
				},
				nil,
				nil,
			),
			expectedResult: "",
		},
		{
			name: "organization policy exists but guidance is empty string",
			policy: models.NewCompletePolicy(
				nil,
				&proto.OrganizationPolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
							},
						},
					},
					CustomRemediationGuidance: "",
				},
				nil,
			),
			expectedResult: "",
		},
		{
			name:           "no policies exist",
			policy:         models.NewCompletePolicy(nil, nil, nil),
			expectedResult: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			guidance := tt.policy.GetRemediationGuidance()
			assert.Equal(t, tt.expectedResult, guidance)
		})
	}
}

func TestWildcardNameMatch(t *testing.T) {
	testCases := []struct {
		name        string
		pattern     string
		packageName string
		wantMatch   bool
	}{
		{
			name:        "simple match",
			pattern:     "express*",
			packageName: "express-server",
			wantMatch:   true,
		},
		{
			name:        "simple no match",
			pattern:     "express*",
			packageName: "react-server",
			wantMatch:   false,
		},
		{
			name:        "wildcard in middle match",
			pattern:     "@types/*-server",
			packageName: "@types/node-server",
			wantMatch:   true,
		},
		{
			name:        "wildcard in middle no match",
			pattern:     "@types/*-server",
			packageName: "@types/node-client",
			wantMatch:   false,
		},
		{
			name:        "no wildcard - exact match",
			pattern:     "express",
			packageName: "express",
			wantMatch:   true,
		},
		{
			name:        "no wildcard - no match",
			pattern:     "express",
			packageName: "express-server",
			wantMatch:   false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			gotMatch := models.WildcardNameMatch(tc.pattern, tc.packageName)
			assert.Equal(t, tc.wantMatch, gotMatch)
		})
	}
}

func TestGetPackagePolicyViaAccessor(t *testing.T) {
	packagePolicy := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "express",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
			Name:           "spring-core",
			Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "private-*",
			Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
		},
	}
	testCases := []struct {
		name                string
		packageManager      proto.PackageManager
		packageName         string
		distributionContext string
		expectedPolicy      *proto.PackagePolicy
	}{
		{
			name:                "found in policy",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:         "express",
			distributionContext: "distributed",
			expectedPolicy:      packagePolicy[0],
		},
		{
			name:                "not found in policy - different package",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:         "react",
			distributionContext: "distributed",
			expectedPolicy:      nil,
		},
		{
			name:                "not found in policy - different package manager",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_PIP,
			packageName:         "express",
			distributionContext: "distributed",
			expectedPolicy:      nil,
		},
		{
			name:                "found in policy - matching context",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:         "lodash",
			distributionContext: "distributed",
			expectedPolicy:      packagePolicy[1],
		},
		{
			name:                "not found in policy - non-matching context",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:         "lodash",
			distributionContext: "internal",
			expectedPolicy:      nil,
		},
		{
			name:                "found in policy - wildcard name match",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:         "private-utils",
			distributionContext: "internal",
			expectedPolicy:      packagePolicy[3],
		},
		{
			name:                "not found in policy - wildcard name no match",
			packageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			packageName:         "private-utils",
			distributionContext: "distributed",
			expectedPolicy:      nil,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			completePolicy := models.NewCompletePolicy(
				&proto.EnterprisePolicy{
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Packages: []*proto.PackagePolicy{
								{
									PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
									Name:           "express",
									Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
								},
								{
									PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
									Name:           "lodash",
									Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
								},
								{
									PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
									Name:           "spring-core",
									Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
								},
							},
						},
						{
							Name: "internal",
							Packages: []*proto.PackagePolicy{
								{
									PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
									Name:           "express",
									Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
								},
								{
									PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
									Name:           "spring-core",
									Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
								},
								{
									PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
									Name:           "private-*",
									Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
								},
							},
						},
					},
				},
				nil,
				nil,
			)
			policy, _ := completePolicy.GetPackagePolicy(tc.packageManager, tc.packageName, tc.distributionContext)
			assert.Equal(t, tc.expectedPolicy, policy)
		})
	}
}

func TestGetCombinedRepositoryPolicy(t *testing.T) {
	completePolicy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "express",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "lodash",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
					},
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{
							{
								SpdxId: "MIT",
							},
							{
								SpdxId: "Apache-2.0",
							},
						},
					},
				},
				{
					Name: "internal",
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "express",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
							Name:           "spring-core",
							Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
						},
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "private-*",
							Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
						},
					},
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{
							{
								SpdxId: "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
		nil,
		&proto.RepositoryPolicy{
			Packages: []*proto.PackagePolicy{
				{
					PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
					Name:           "baz",
					Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
				},
			},
			Licenses: &proto.PolicyLicenses{
				Allowed: []*proto.LicenseEntry{
					{
						SpdxId: "AGPL-3.0",
					},
				},
			},
		},
	)

	combinedPolicy := completePolicy.GetCombinedRepositoryPolicy("distributed")
	require.NotNil(t, combinedPolicy)

	// Check that the combined policy has the expected packages
	for _, pkgPolicy := range combinedPolicy.Packages {
		switch pkgPolicy.Name {
		case "express", "lodash":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, pkgPolicy.Level)
		case "baz":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, pkgPolicy.Level)
		default:
			t.Errorf("unexpected package name: %s", pkgPolicy.Name)
		}
	}

	// Check that the combined policy has the expected licenses
	for _, licenseEntry := range combinedPolicy.Licenses {
		switch licenseEntry.SpdxId {
		case "MIT", "Apache-2.0":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, licenseEntry.Level)
		case "AGPL-3.0":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, licenseEntry.Level)
		default:
			t.Errorf("unexpected license ID: %s", licenseEntry.SpdxId)
		}
	}
}

func TestGetCombinedRepositoryPolicy_WithNoRepositoryPolicy(t *testing.T) {
	completePolicy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "express",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "lodash",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
					},
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{
							{
								SpdxId: "MIT",
							},
							{
								SpdxId: "Apache-2.0",
							},
						},
					},
				},
				{
					Name: "internal",
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "express",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
							Name:           "spring-core",
							Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
						},
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "private-*",
							Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
						},
					},
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{
							{
								SpdxId: "BSD-3-Clause",
							},
						},
					},
				},
			},
		},
		nil,
		nil,
	)

	combinedPolicy := completePolicy.GetCombinedRepositoryPolicy("internal")
	require.NotNil(t, combinedPolicy)

	// Check that the combined policy has the expected packages
	for _, pkgPolicy := range combinedPolicy.Packages {
		switch pkgPolicy.Name {
		case "express":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, pkgPolicy.Level)
		case "private-*":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_PRIVATE, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, pkgPolicy.Level)
		case "spring-core":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_BLOCKED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, pkgPolicy.Level)
		default:
			t.Errorf("unexpected package name: %s", pkgPolicy.Name)
		}
	}

	// Check that the combined policy has the expected licenses
	for _, licenseEntry := range combinedPolicy.Licenses {
		switch licenseEntry.SpdxId {
		case "BSD-3-Clause":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, licenseEntry.Level)
		default:
			t.Errorf("unexpected license ID: %s", licenseEntry.SpdxId)
		}
	}
}

func TestCompletePolicy_PolicyFromExistingPolicy(t *testing.T) {
	basePolicy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			EnterpriseId: 1,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Licenses: &proto.PolicyLicenses{
						Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
					},
				},
			},
		},
		&proto.OrganizationPolicy{
			OrganizationId: 2,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Licenses: &proto.PolicyLicenses{
						Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
					},
				},
			},
		},
		&proto.RepositoryPolicy{
			RepositoryId: 3,
			Licenses: &proto.PolicyLicenses{
				Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-3-Clause"}),
			},
		},
	)

	testCases := []struct {
		name                    string
		enterprisePolicy        *proto.EnterprisePolicy
		organizationPolicy      *proto.OrganizationPolicy
		repositoryPolicy        *proto.RepositoryPolicy
		expectedAllowedLicenses []string
	}{
		{
			name:                    "all policies with same ID - no change",
			enterprisePolicy:        &proto.EnterprisePolicy{EnterpriseId: 1},
			organizationPolicy:      &proto.OrganizationPolicy{OrganizationId: 2},
			repositoryPolicy:        &proto.RepositoryPolicy{RepositoryId: 3},
			expectedAllowedLicenses: []string{"MIT", "BSD-2-Clause", "BSD-3-Clause"},
		},
		{
			name:                    "all empty policies",
			enterprisePolicy:        &proto.EnterprisePolicy{},
			organizationPolicy:      &proto.OrganizationPolicy{},
			repositoryPolicy:        &proto.RepositoryPolicy{},
			expectedAllowedLicenses: []string{},
		},
		{
			name: "only enterprise policy",
			enterprisePolicy: &proto.EnterprisePolicy{
				EnterpriseId: 4,
				DistributionPolicies: []*proto.DistributionPolicy{
					{
						Name: "distributed",
						Licenses: &proto.PolicyLicenses{
							Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"GPL-3.0"}),
						},
					},
				},
			},
			organizationPolicy:      &proto.OrganizationPolicy{OrganizationId: 2},
			repositoryPolicy:        &proto.RepositoryPolicy{RepositoryId: 3},
			expectedAllowedLicenses: []string{"GPL-3.0", "BSD-2-Clause", "BSD-3-Clause"},
		},
		{
			name:             "new organization and repository policies",
			enterprisePolicy: &proto.EnterprisePolicy{EnterpriseId: 1},
			organizationPolicy: &proto.OrganizationPolicy{
				OrganizationId: 5,
				DistributionPolicies: []*proto.DistributionPolicy{
					{
						Name: "distributed",
						Licenses: &proto.PolicyLicenses{
							Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"LGPL-3.0"}),
						},
					},
				},
			},
			repositoryPolicy: &proto.RepositoryPolicy{
				RepositoryId: 6,
				Licenses: &proto.PolicyLicenses{
					Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"AGPL-3.0"}),
				},
			},
			expectedAllowedLicenses: []string{"MIT", "LGPL-3.0", "AGPL-3.0"},
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			policy := basePolicy.PolicyFromExistingPolicy(tc.enterprisePolicy, tc.organizationPolicy, tc.repositoryPolicy)
			allowList := policy.GetAllowList("distributed")
			assert.ElementsMatch(t, tc.expectedAllowedLicenses, allowList)
		})
	}
}
