package evaluator_test

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var allDistributionContexts = []string{"distributed", "network", "internal"}

func TestIsPackageAllowedWithAllowLists(t *testing.T) {
	policy := &models.CompletePolicy{
		EnterprisePolicy: &models.EnterprisePolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
				},
			},
		},
		OrganizationPolicy: &models.OrganizationPolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "BSD-2-Clause", Contexts: allDistributionContexts}},
				},
			},
		},
		RepositoryPolicy: &models.RepositoryPolicy{
			Policy: &models.RepositoryRefinement{
				Licenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}},
				},
			},
		},
	}

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
	policy := &models.CompletePolicy{
		EnterprisePolicy: &models.EnterprisePolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
				},
				Packages: []models.PackagePolicy{
					{
						PackageManager: models.PMnpm,
						PackageName:    "lodash",
						Action:         models.PackageActionBlock,
						Contexts:       allDistributionContexts,
					},
					{
						PackageManager: models.PMnpm,
						PackageName:    "react",
						Action:         models.PackageActionAllow,
						Contexts:       allDistributionContexts,
					},
				},
			},
		},
		RepositoryPolicy: &models.RepositoryPolicy{
			Policy: &models.RepositoryRefinement{
				Packages: []models.PackagePolicy{
					{
						PackageManager: models.PMnpm,
						PackageName:    "lodash",
						Action:         models.PackageActionAllow,
						Contexts:       allDistributionContexts,
					},
				},
			},
		},
	}

	p := models.Package{
		PackageManager: models.PMnpm,
		Name:           "lodash",
		License:        "GPL-2.0",
	}
	result, err := evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Nil(t, result, "Allowed because of repository policy")

	p = models.Package{
		PackageManager: models.PMnpm,
		Name:           "react",
		License:        "MIT",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Nil(t, result, "Allowed because of enterprise package policy")

	p = models.Package{
		PackageManager: models.PMnpm,
		Name:           "lodash",
		License:        "MIT",
	}
	policy.RepositoryPolicy = nil
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result, "result should not be nil")
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of enterprise package policy")
	assert.Equal(t, evaluator.EnterpriseLevel, result.Level, "Blocked because of enterprise package policy")

	policy.OrganizationPolicy = &models.OrganizationPolicy{
		Policy: &models.Policy{
			Packages: []models.PackagePolicy{
				{
					PackageManager: models.PMnpm,
					PackageName:    "react",
					Action:         models.PackageActionBlock,
					Contexts:       allDistributionContexts,
				},
			},
		},
	}
	p = models.Package{
		PackageManager: models.PMnpm,
		Name:           "react",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result, "result should not be nil")
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of organization package policy")
	assert.Equal(t, evaluator.OrganizationLevel, result.Level, "Blocked because of organization package policy")
}

func TestPackageBlockedRegardlessOfMatchLicenses(t *testing.T) {
	policy := &models.CompletePolicy{
		OrganizationPolicy: &models.OrganizationPolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
				},
				Packages: []models.PackagePolicy{
					{
						PackageManager: models.PMnpm,
						PackageName:    "lodash",
						Action:         models.PackageActionBlock,
						MatchLicenses:  []string{"MIT"},
						Contexts:       allDistributionContexts,
					},
				},
			},
		},
	}

	p := models.Package{
		PackageManager: models.PMnpm,
		Name:           "lodash",
		License:        "MIT",
	}
	result, err := evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result, "result should not be nil")
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of organization package policy")
	assert.Equal(t, evaluator.OrganizationLevel, result.Level, "Blocked because of organization package policy")

	p = models.Package{
		PackageManager: models.PMnpm,
		Name:           "lodash",
		License:        "GPL-2.0",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Equal(t, evaluator.PackageBlocked, result.Reason, "Blocked because of organization package policy")
	assert.Equal(t, evaluator.OrganizationLevel, result.Level, "Blocked because of organization package policy")
}

func TestPolicyResultForPackageWithLicenseList(t *testing.T) {
	policy := &models.CompletePolicy{
		EnterprisePolicy: &models.EnterprisePolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
				},
			},
		},
		RepositoryPolicy: &models.RepositoryPolicy{
			Policy: &models.RepositoryRefinement{
				Packages: []models.PackagePolicy{
					{
						PackageManager: models.PMnpm,
						PackageName:    "lodash",
						Action:         models.PackageActionAllow,
						MatchLicenses:  []string{"GPL-2.0"},
						Contexts:       allDistributionContexts,
					},
				},
			},
		},
	}

	p := models.Package{
		PackageManager: models.PMnpm,
		Name:           "lodash",
		License:        "GPL-2.0",
	}
	result, err := evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	assert.Nil(t, result, "Allowed because of repository package policy")

	p = models.Package{
		PackageManager: models.PMnpm,
		Name:           "lodash",
		License:        "AGPL-3.0",
	}
	result, err = evaluator.PolicyResultForPackage(p, policy, "distributed", log.Named("test"))
	require.NoError(t, err)
	require.NotNil(t, result)
	assert.Equal(t, evaluator.LicenseNotAllowed, result.Reason, "Not allowed because of repository package policy")
}

func TestPolicyResultForRepository(t *testing.T) {
	policy := &models.CompletePolicy{
		EnterprisePolicy: &models.EnterprisePolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
				},
				Packages: []models.PackagePolicy{
					{
						PackageManager: models.PMgomod,
						PackageName:    "github.com/github/go-linter",
						Action:         models.PackageActionPrivate,
						Contexts:       allDistributionContexts,
					},
				},
			},
		},
		RepositoryPolicy: &models.RepositoryPolicy{
			Policy: &models.RepositoryRefinement{
				Licenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "LGPL-3.0", Contexts: allDistributionContexts}},
				},
			},
		},
	}

	repositoryPackages := map[string]models.Package{
		"7:github.com/github/go-linter@v1.2.1": {
			PackageManager: models.PMgomod,
			Name:           "github.com/github/go-linter",
			Version:        "1.2.1",
			License:        "",
			Manifests:      []string{"go.mod", "go.sum"},
		},
		"7:golang.org/x/sync@v0.0.0-20201020160332-670669b29e9b": {
			PackageManager: models.PMgomod,
			Name:           "golang.org/x/sync",
			Version:        "v0.0.0-20201020160332-670669b29e9b",
			License:        "MIT",
			Manifests:      []string{"go.mod", "go.sum"},
		},
		"7:foobar.foofoo/foo@v2.2.2": {
			PackageManager: models.PMgomod,
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

func TestExpectedInvalidSPDXIsOkay(t *testing.T) {
	policy := &models.CompletePolicy{
		OrganizationPolicy: &models.OrganizationPolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{
						{SpdxID: "LicenseRef-clearlydefined-OTHER", Contexts: allDistributionContexts},
						{SpdxID: "LicenseRef-clearlydefined-NOASSERTION", Contexts: allDistributionContexts},
						{SpdxID: evaluator.LicenseRefEmpty, Contexts: allDistributionContexts},
					},
				},
			},
		},
	}
	repositoryPackages := map[string]models.Package{
		"7:github.com/github/go-linter@v1.2.1": {
			PackageManager: models.PMgomod,
			Name:           "github.com/github/go-linter",
			Version:        "1.2.1",
			License:        "",
			Manifests:      []string{"go.mod", "go.sum"},
		},
		"7:golang.org/x/sync@v0.0.0-20201020160332-670669b29e9b": {
			PackageManager: models.PMgomod,
			Name:           "golang.org/x/sync",
			Version:        "v0.0.0-20201020160332-670669b29e9b",
			License:        "OTHER",
			Manifests:      []string{"go.mod", "go.sum"},
		},
		"7:foobar.foofoo/foo@v2.2.2": {
			PackageManager: models.PMgomod,
			Name:           "foobar.foofoo/foo",
			Version:        "v2.2.2",
			License:        "NOASSERTION",
			Manifests:      []string{"go.mod", "go.sum"},
		},
	}
	results := evaluator.PolicyResultsForRepository(repositoryPackages, policy, "distributed", log.Named("test"))
	assert.Equal(t, 3, results.SuccessCount)
	assert.Equal(t, 0, results.FailureCount)
	assert.Equal(t, 0, results.ErrorCount)
	require.NoError(t, results.LastError)
	assert.Len(t, results.Failures, 0)
}

func TestLicenseReplacements(t *testing.T) {
	policy := &models.CompletePolicy{
		OrganizationPolicy: &models.OrganizationPolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{
						{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts},
						{SpdxID: "LicenseRef-github-google-patent-license-golang", Contexts: allDistributionContexts},
					},
				},
			},
		},
	}
	repositoryPackages := map[string]models.Package{
		"7:golang.org/x/net/v0.0.0-20210503060351-7fd8e65b6420": {
			PackageManager: models.PMgomod,
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
	policy := &models.CompletePolicy{
		EnterprisePolicy: &models.EnterprisePolicy{
			Policy: &models.Policy{
				PolicyLicenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
				},
				Packages: []models.PackagePolicy{
					{
						PackageManager: models.PMnpm,
						PackageName:    "foo",
						Action:         models.PackageActionBlock,
						Contexts:       []string{"distributed"},
					},
					{
						PackageManager: models.PMnpm,
						PackageName:    "bar",
						Action:         models.PackageActionAllow,
						Contexts:       []string{"network"},
					},
					{
						PackageManager: models.PMnpm,
						PackageName:    "baz",
						Action:         models.PackageActionBlock,
						Contexts:       []string{"internal"},
					},
				},
			},
		},
	}

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
				PackageManager: models.PMnpm,
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
