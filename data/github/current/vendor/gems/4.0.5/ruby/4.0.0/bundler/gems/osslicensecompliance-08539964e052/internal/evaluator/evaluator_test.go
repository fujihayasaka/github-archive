package evaluator_test

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIsPackageAllowedWithAllowLists(t *testing.T) {
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"}, nil, testhelpers.AllDistributionContexts),
		},
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"BSD-2-Clause"}, nil, testhelpers.AllDistributionContexts),
		},
		&proto.RepositoryPolicy{
			Licenses: &proto.PolicyLicenses{
				Allowed: testhelpers.CreateLicenseEntries([]string{"BSD-3-Clause"}),
			},
		},
	)

	// Test that we're evaluating with licenses at all levels and using
	// proper SPDX comparisons.

	testCases := []struct {
		license string
		allowed bool
	}{
		{"MIT", true},
		{"BSD-2-Clause", true},
		{"BSD-3-Clause AND MIT", true},
		{"MIT AND GPL-2.0", false},
		{"GPL-2.0 OR MIT", true},
	}

	for _, tc := range testCases {
		t.Run(tc.license, func(t *testing.T) {
			packageInfo := models.Package{License: tc.license}
			result, err := evaluator.PolicyResultForPackage(packageInfo, policy, "distributed", log.Named("test"))
			require.NoError(t, err)
			if tc.allowed {
				assert.Nil(t, result)
				return
			}
			assert.Equal(t, evaluator.LicenseNotAllowed, result.Reason)
		})
	}
}

func TestPolicyResultForPackage_WithPackageSettings(t *testing.T) {
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"},
				[]*proto.PackagePolicy{
					{
						PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
						Name:           "lodash",
						Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
					},
					{
						PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
						Name:           "react",
						Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
					},
				},
				testhelpers.AllDistributionContexts,
			),
		},
		nil,
		&proto.RepositoryPolicy{
			Packages: []*proto.PackagePolicy{
				{
					PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
					Name:           "lodash",
					Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
				},
			},
		},
	)

	p := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		License:        "GPL-2.0",
	}
	result, err := evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Nil(t, result, "Allowed because of repository policy")

	p = models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "react",
		License:        "MIT",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Nil(t, result, "Allowed because of enterprise package policy")

	p = models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		License:        "MIT",
	}
	policy.RepositoryPolicy = nil
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result, "result should not be nil")
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of enterprise package policy")
	assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, result.Level, "Blocked because of enterprise package policy")

	policy.OrganizationPolicy = models.NewOrganizationPolicy(&proto.OrganizationPolicy{
		DistributionPolicies: testhelpers.CreateDistributionPolicies(nil,
			[]*proto.PackagePolicy{
				{
					PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
					Name:           "react",
					Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
				},
			},
			testhelpers.AllDistributionContexts),
	})
	p = models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "react",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result, "result should not be nil")
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of organization package policy")
	assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, result.Level, "Blocked because of organization package policy")
}

func TestPackageBlockedRegardlessOfExtraAllowedSpdxIDs(t *testing.T) {
	policy := models.NewCompletePolicy(
		nil,
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"},
				[]*proto.PackagePolicy{
					{
						PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
						Name:                "lodash",
						Action:              proto.PackageAction_PACKAGE_ACTION_BLOCKED,
						ExtraAllowedSpdxIds: []string{"MIT"},
					},
				},
				testhelpers.AllDistributionContexts,
			),
		},
		nil,
	)

	p := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		License:        "MIT",
	}
	result, err := evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result, "result should not be nil")
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of organization package policy")
	assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, result.Level, "Blocked because of organization package policy")

	p = models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		License:        "GPL-2.0",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of organization package policy")
	assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, result.Level, "Blocked because of organization package policy")
}

func TestPolicyResultForPackageWithLicenseList(t *testing.T) {
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"}, nil, testhelpers.AllDistributionContexts),
		},
		nil,
		&proto.RepositoryPolicy{
			Packages: []*proto.PackagePolicy{
				{
					PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
					Name:                "lodash",
					Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
					ExtraAllowedSpdxIds: []string{"GPL-2.0"},
				},
			},
		},
	)

	p := models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		License:        "GPL-2.0",
	}
	result, err := evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Nil(t, result, "Allowed because of repository package policy")

	p = models.Package{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
		Name:           "lodash",
		License:        "AGPL-3.0",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, evaluator.LicenseNotAllowed, result.Reason, "Not allowed because of repository package policy")
}

func TestPolicyResultForRepository(t *testing.T) {
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"}, []*proto.PackagePolicy{
				{
					PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
					Name:           "github.com/github/go-linter",
					Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				},
			},
				testhelpers.AllDistributionContexts,
			),
		},
		nil,
		&proto.RepositoryPolicy{
			Licenses: &proto.PolicyLicenses{
				Allowed: []*proto.LicenseEntry{{SpdxId: "LGPL-3.0"}},
			},
		},
	)

	repositoryPackages := map[string]models.Package{
		"7:github.com/github/go-linter@v1.2.1": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "github.com/github/go-linter",
			Version:        "1.2.1",
			License:        "",
			Manifests:      []string{"go.mod", "go.sum"},
		},
		"7:golang.org/x/sync@v0.0.0-20201020160332-670669b29e9b": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "golang.org/x/sync",
			Version:        "v0.0.0-20201020160332-670669b29e9b",
			License:        "MIT",
			Manifests:      []string{"go.mod", "go.sum"},
		},
		"7:foobar.foofoo/foo@v2.2.2": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "foobar.foofoo/foo",
			Version:        "v2.2.2",
			License:        "GPL-3.0",
			Manifests:      []string{"go.mod", "go.sum"},
		},
	}
	results := evaluator.PolicyResultsForRepository(repositoryPackages, policy, "distributed", log.Named("test"))
	assert.Equal(t, 2, results.SuccessCount)
	assert.Equal(t, 1, results.FailureCount)
	assert.Equal(t, 0, results.ErrorCount)
	require.NoError(t, results.LastError)
	assert.Len(t, results.Failures, 1)
	assert.Equal(t, evaluator.LicenseNotAllowed, results.Failures[0].Reason)
	assert.Equal(t, "foobar.foofoo/foo", results.Failures[0].Package.Name)
}

func TestEmptyLicenseStringFailsIfNotInPolicy(t *testing.T) {
	policy := models.NewCompletePolicy(
		nil,
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"}, nil, testhelpers.AllDistributionContexts),
		},
		nil,
	)
	repositoryPackages := map[string]models.Package{
		"7:github.com/github/go-linter@v1.2.1": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "github.com/github/go-linter",
			Version:        "1.2.1",
			License:        "",
			Manifests:      []string{"go.mod", "go.sum"},
		},
	}
	results := evaluator.PolicyResultsForRepository(repositoryPackages, policy, "distributed", log.Named("test"))
	assert.Equal(t, 0, results.SuccessCount)
	assert.Equal(t, 1, results.FailureCount)
	assert.Len(t, results.Failures, 1)
	assert.Equal(t, "", results.Failures[0].Package.License, "Our LicenseRef doesn't leak out in failures")
}

func TestEmptyLicenseStringCanBeAllowedInPackagePolicy(t *testing.T) {
	policy := models.NewCompletePolicy(
		nil,
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"},
				[]*proto.PackagePolicy{
					{
						PackageManager:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
						Name:                "github.com/github/go-linter",
						Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						ExtraAllowedSpdxIds: []string{evaluator.LicenseRefEmpty},
					},
				},
				[]string{"distributed"},
			),
		},
		nil,
	)
	repositoryPackages := map[string]models.Package{
		"7:github.com/github/go-linter@v1.2.1": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "github.com/github/go-linter",
			Version:        "1.2.1",
			License:        "",
			Manifests:      []string{"go.mod", "go.sum"},
		},
	}
	results := evaluator.PolicyResultsForRepository(repositoryPackages, policy, "distributed", log.Named("test"))
	assert.Equal(t, 1, results.SuccessCount)
	assert.Equal(t, 0, results.FailureCount)
	assert.Len(t, results.Failures, 0)
}

func TestPrivatePackageAllowed(t *testing.T) {
	policy := models.NewCompletePolicy(
		nil,
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"},
				[]*proto.PackagePolicy{
					{
						PackageManager:      proto.PackageManager_PACKAGE_MANAGER_GOMOD,
						Name:                "github.com/github/*",
						Action:              proto.PackageAction_PACKAGE_ACTION_PRIVATE,
						ExtraAllowedSpdxIds: []string{evaluator.LicenseRefEmpty},
					},
				},
				[]string{"distributed"},
			),
		},
		nil,
	)
	repositoryPackages := map[string]models.Package{
		"7:github.com/github/go-linter@v1.2.1": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "github.com/github/go-linter",
			Version:        "1.2.1",
			License:        "",
			Manifests:      []string{"go.mod", "go.sum"},
		},
	}
	results := evaluator.PolicyResultsForRepository(repositoryPackages, policy, "distributed", log.Named("test"))
	assert.Equal(t, 1, results.SuccessCount)
	assert.Equal(t, 0, results.FailureCount)
	assert.Len(t, results.Failures, 0)
}

func TestLicenseReplacements(t *testing.T) {
	policy := models.NewCompletePolicy(
		nil,
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{
				"BSD-3-Clause",
				"LicenseRef-github-google-patent-license-golang",
			}, nil, testhelpers.AllDistributionContexts),
		},
		nil,
	)
	repositoryPackages := map[string]models.Package{
		"7:golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420": {
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD,
			Name:           "golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420",
			Version:        "1.2.1",
			License:        "BSD-3-Clause AND OTHER",
			Manifests:      []string{"go.mod", "go.sum"},
		},
	}
	results := evaluator.PolicyResultsForRepository(repositoryPackages, policy, "distributed", log.Named("test"))
	assert.Equal(t, 1, results.SuccessCount)
	assert.Equal(t, 0, results.FailureCount)
	assert.Equal(t, 0, results.ErrorCount)
	require.NoError(t, results.LastError)
}

func TestPackagePolicyDistributionContexts(t *testing.T) {
	// we need at least one license to be allowed in general
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
					},
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "foo",
							Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
						},
					},
				},
				{
					Name: "network",
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
					},
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "bar",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
					},
				},
				{
					Name: "internal",
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
					},
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "baz",
							Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
						},
					},
				},
			},
		},
		nil,
		nil,
	)

	licenseAllowed := "MIT"
	licenseForbidden := "GPL-2.0"

	testCases := []struct {
		name    string
		pkgName string
		context string
		license string
		allowed bool
	}{
		{"foo blocked in distributed despite license", "foo", "distributed", licenseAllowed, false},
		{"foo allowed in network by license", "foo", "network", licenseAllowed, true},
		{"bar allowed in network despite license", "bar", "network", licenseForbidden, true},
		{"bar forbidden in distributed due to license", "bar", "distributed", licenseForbidden, false},
		{"baz blocked in internal despite license", "baz", "internal", licenseAllowed, false},
		{"baz allowed in distributed by license", "baz", "distributed", licenseAllowed, true},
	}

	for i, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			p := models.Package{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           tc.pkgName,
				License:        tc.license,
			}
			result, err := evaluator.PolicyResultForPackage(p, policy, tc.context, log.Named("test"))
			require.NoErrorf(t, err, "Error evaluating package %s in context %s: %v (test case %d)", tc.pkgName, tc.context, err, i)
			if tc.allowed {
				assert.Nilf(t, result, "Expected allowed, got blocked %v (test case %d)", result, i)
			} else {
				require.NotNilf(t, result, "Expected blocked, got allowed (test case %d)", i)
				if tc.license == licenseForbidden {
					assert.Equalf(t, evaluator.LicenseNotAllowed, result.Reason, "Blocked because of license (test case %d)", i)
				} else {
					assert.Equalf(t, evaluator.PackageBlocked, result.Reason, "Blocked because of package policy (test case %d)", i)
				}
			}
		})
	}
}

func TestAlertSatisfiesPolicy(t *testing.T) {
	policy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies([]string{"MIT"}, nil, testhelpers.AllDistributionContexts),
		},
		&proto.OrganizationPolicy{
			DistributionPolicies: testhelpers.CreateDistributionPolicies(nil,
				[]*proto.PackagePolicy{
					{
						PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
						Name:                "extra-allowed-licenses-package",
						Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						ExtraAllowedSpdxIds: []string{"BSD-3-Clause"},
					},
				},
				testhelpers.AllDistributionContexts),
		},
		&proto.RepositoryPolicy{
			Packages: []*proto.PackagePolicy{
				{
					PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
					Name:           "allowed-package",
					Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
				},
			},
		},
	)

	testCases := []struct {
		name       string
		alert      models.Alert
		shouldPass bool
	}{
		{
			name: "license allowed by policy",
			alert: models.Alert{
				SPDXLicenseExpression: "MIT",
			},
			shouldPass: true,
		},
		{
			name: "license not allowed by policy",
			alert: models.Alert{
				SPDXLicenseExpression: "GPL-3.0",
			},
			shouldPass: false,
		},
		{
			name: "package explicitly allowed via package exception",
			alert: models.Alert{
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "allowed-package",
				SPDXLicenseExpression: "GPL-3.0",
			},
			shouldPass: true,
		},
		{
			name: "package with extra allowed licenses",
			alert: models.Alert{
				PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				PackageName:           "extra-allowed-licenses-package",
				SPDXLicenseExpression: "BSD-3-Clause",
			},
			shouldPass: true,
		},
		{
			name: "empty policy returns false",
			alert: models.Alert{
				SPDXLicenseExpression: "MIT",
			},
			shouldPass: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			testPolicy := policy
			if tc.name == "empty policy returns false" {
				testPolicy = models.NewCompletePolicy(nil, nil, nil)
			}
			passes, err := evaluator.AlertSatisfiesPolicy(&tc.alert, testPolicy, "distributed")
			require.NoError(t, err)
			assert.Equal(t, tc.shouldPass, passes)
		})
	}
}
