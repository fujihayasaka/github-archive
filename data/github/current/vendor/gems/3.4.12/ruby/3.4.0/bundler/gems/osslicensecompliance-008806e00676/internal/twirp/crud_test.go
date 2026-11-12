package twirp

import (
	"fmt"
	"testing"
	"testing/synctest"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestCreateOrganizationPolicy(t *testing.T) {
	server := newTestServer(t)
	orgID := uint64(1)
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "reason",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            testhelpers.AllDistributionContexts,
		},
	}

	createRequest := &proto.CreateOrganizationPolicyRequest{
		OrganizationId:            orgID,
		Licenses:                  licenses,
		Packages:                  packages,
		CustomRemediationGuidance: "Please ask Kevin to fix any and all problems with this policy, day or night.",
	}

	response, err := server.CreateOrganizationPolicy(t.Context(), createRequest)
	require.NoError(t, err)

	assert.Equal(t, orgID, response.Policy.OrganizationId)
	assert.Len(t, response.Policy.DistributionPolicies, 3)
	licenses.Allowed[0].Contexts = nil //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	packages[0].Contexts = nil         //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	for _, dp := range response.Policy.DistributionPolicies {
		assert.Contains(t, testhelpers.AllDistributionContexts, dp.Name)
		assert.EqualExportedValues(t, licenses, dp.Licenses)
		assert.EqualExportedValues(t, packages, dp.Packages)
	}
	assert.Equal(t, createRequest.CustomRemediationGuidance, response.Policy.CustomRemediationGuidance)
}

func TestGetOrganizationPolicy(t *testing.T) {
	server := newTestServer(t)
	orgID := 1
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
	}

	createResponse, err := server.CreateOrganizationPolicy(
		t.Context(),
		&proto.CreateOrganizationPolicyRequest{
			OrganizationId: uint64(orgID),
			Licenses:       licenses,
			Packages:       packages,
		},
	)
	require.NoError(t, err)
	assert.Len(t, createResponse.Policy.DistributionPolicies, 3)

	getRequest := &proto.GetOrganizationPolicyRequest{OrganizationId: uint64(orgID)}
	response, err := server.GetOrganizationPolicy(t.Context(), getRequest)
	require.NoError(t, err)
	assert.Equal(t, orgID, int(response.Policy.OrganizationId))
	assert.Len(t, response.Policy.DistributionPolicies, 3)
	for _, dp := range response.Policy.DistributionPolicies {
		assert.Contains(t, testhelpers.AllDistributionContexts, dp.Name)
		assert.EqualExportedValues(t, licenses, dp.Licenses)
		if dp.Name == "distributed" {
			assert.EqualExportedValues(t, packages, dp.Packages)
		} else {
			assert.Empty(t, dp.Packages)
		}
	}
	assert.NotNil(t, response.Policy.CreatedAt)
}

func TestGetOrganizationPolicy_NotFound(t *testing.T) {
	server := newTestServer(t)

	req := &proto.GetOrganizationPolicyRequest{OrganizationId: uint64(1)}
	res, err := server.GetOrganizationPolicy(t.Context(), req)
	assert.Nil(t, res)
	assert.Equal(t, twirp.NotFoundError("policy not found"), err)
}

func TestCreateEnterprisePolicy(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := 1
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "reason",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            testhelpers.AllDistributionContexts,
		},
	}

	createRequest := &proto.CreateEnterprisePolicyRequest{
		EnterpriseId:              uint64(enterpriseID),
		Licenses:                  licenses,
		Packages:                  packages,
		CustomRemediationGuidance: "Please ask Thomas to fix any and all problems with this policy, day or night.",
	}

	response, err := server.CreateEnterprisePolicy(t.Context(), createRequest)
	require.NoError(t, err)

	assert.Equal(t, enterpriseID, int(response.Policy.EnterpriseId))
	assert.Len(t, response.Policy.DistributionPolicies, 3)
	licenses.Allowed[0].Contexts = nil //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	packages[0].Contexts = nil         //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	for _, dp := range response.Policy.DistributionPolicies {
		assert.Contains(t, testhelpers.AllDistributionContexts, dp.Name)
		assert.EqualExportedValues(t, licenses, dp.Licenses)
		assert.EqualExportedValues(t, packages, dp.Packages)
	}
	assert.Equal(t, createRequest.CustomRemediationGuidance, response.Policy.CustomRemediationGuidance)

	// Backwards compatibility check to be removed later
	require.NotNil(t, response.Policy.Licenses) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	require.NotNil(t, response.Policy.Packages) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility

	assert.EqualExportedValues(t, licenses, response.Policy.Licenses) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.EqualExportedValues(t, packages, response.Policy.Packages) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

func TestGetEnterprisePolicy(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := 1
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
	}

	createResponse, err := server.CreateEnterprisePolicy(
		t.Context(),
		&proto.CreateEnterprisePolicyRequest{
			EnterpriseId: uint64(enterpriseID),
			Licenses:     licenses,
			Packages:     packages,
		},
	)
	require.NoError(t, err)
	assert.Len(t, createResponse.Policy.DistributionPolicies, 3)

	getRequest := &proto.GetEnterprisePolicyRequest{EnterpriseId: uint64(enterpriseID)}
	response, err := server.GetEnterprisePolicy(t.Context(), getRequest)
	require.NoError(t, err)
	assert.Equal(t, enterpriseID, int(response.Policy.EnterpriseId))
	assert.Len(t, response.Policy.DistributionPolicies, 3)
	for _, dp := range response.Policy.DistributionPolicies {
		assert.Contains(t, testhelpers.AllDistributionContexts, dp.Name)
		assert.EqualExportedValues(t, licenses, dp.Licenses)
		if dp.Name == "distributed" {
			assert.EqualExportedValues(t, packages, dp.Packages)
		} else {
			assert.Empty(t, dp.Packages)
		}
	}
	assert.NotNil(t, response.Policy.CreatedAt)

	// Backwards compatibility check to be removed later
	require.NotNil(t, response.Policy.Licenses) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	require.NotNil(t, response.Policy.Packages) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility

	assert.EqualExportedValues(t, licenses, response.Policy.Licenses) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.EqualExportedValues(t, packages, response.Policy.Packages) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

func TestGetEnterprisePolicy_NotFound(t *testing.T) {
	server := newTestServer(t)

	req := &proto.GetEnterprisePolicyRequest{EnterpriseId: uint64(1)}
	res, err := server.GetEnterprisePolicy(t.Context(), req)
	assert.Nil(t, res)
	assert.Equal(t, twirp.NotFoundError("policy not found"), err)
}

func TestCreateRepositoryPolicy(t *testing.T) {
	server := newTestServer(t)
	repositoryID := 1
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       testhelpers.AllDistributionContexts,
		},
	}
	repositoryLicenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts}}}
	createRequest := &proto.CreateRepositoryPolicyRequest{
		RepositoryId: uint64(repositoryID),
		Licenses:     repositoryLicenses,
		Packages:     packages,
	}

	response, err := server.CreateRepositoryPolicy(t.Context(), createRequest)
	require.NoError(t, err)

	assert.Equal(t, repositoryID, int(response.Policy.RepositoryId))
	assert.Equal(t, repositoryLicenses, response.Policy.Licenses)
	assert.Equal(t, packages, response.Policy.Packages)
}

func TestGetRepositoryPolicy(t *testing.T) {
	server := newTestServer(t)
	repositoryID := 1
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       testhelpers.AllDistributionContexts,
		},
	}
	repositoryLicenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "GPL-2.0", Contexts: testhelpers.AllDistributionContexts}}}
	createRequest := &proto.CreateRepositoryPolicyRequest{
		RepositoryId: uint64(repositoryID),
		Licenses:     repositoryLicenses,
		Packages:     packages,
	}

	_, err := server.CreateRepositoryPolicy(t.Context(), createRequest)
	require.NoError(t, err)

	getRequest := &proto.GetRepositoryPolicyRequest{RepositoryId: uint64(repositoryID)}
	response, err := server.GetRepositoryPolicy(t.Context(), getRequest)
	require.NoError(t, err)

	assert.Equal(t, repositoryID, int(response.Policy.RepositoryId))
	assert.EqualExportedValues(t, repositoryLicenses, response.Policy.Licenses)
	assert.EqualExportedValues(t, packages, response.Policy.Packages)
}

func TestGetRepositoryPolicy_NotFound(t *testing.T) {
	server := newTestServer(t)

	req := &proto.GetRepositoryPolicyRequest{RepositoryId: 1}
	res, err := server.GetRepositoryPolicy(t.Context(), req)
	assert.Nil(t, res)
	assert.Equal(t, twirp.NotFoundError("policy not found"), err)
}

func TestGetCombinedRepositoryPolicy(t *testing.T) {
	server := newTestServer(t)
	repositoryID := uint64(1)
	organizationID := uint64(2)
	enterpriseID := uint64(3)

	completePolicy := models.NewCompletePolicy(
		&proto.EnterprisePolicy{
			EnterpriseId: enterpriseID,
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
		&proto.OrganizationPolicy{
			OrganizationId: organizationID,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "foo",
							Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
						},
					},
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{
							{
								SpdxId: "GPL-3.0-only",
							},
						},
					},
				},
				{
					Name: "internal",
					Packages: []*proto.PackagePolicy{
						{
							PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
							Name:           "bar",
							Action:         proto.PackageAction_PACKAGE_ACTION_BLOCKED,
						},
					},
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{
							{
								SpdxId: "ISC",
							},
						},
					},
				},
			},
		},
		&proto.RepositoryPolicy{
			RepositoryId: repositoryID,
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
	storageSystem := server.app.Subsystems.Storage
	_, err := storageSystem.CreateRepositoryPolicy(t.Context(), completePolicy.RepositoryPolicy.Data)
	require.NoError(t, err)
	_, err = storageSystem.CreateOrganizationPolicy(t.Context(), completePolicy.OrganizationPolicy.Data)
	require.NoError(t, err)
	_, err = storageSystem.CreateEnterprisePolicy(t.Context(), completePolicy.EnterprisePolicy.Data)
	require.NoError(t, err)
	getRequest := &proto.GetCombinedRepositoryPolicyRequest{
		EnterpriseId:   enterpriseID,
		OrganizationId: organizationID,
		RepositoryId:   repositoryID,
	}
	response, err := server.GetCombinedRepositoryPolicy(t.Context(), getRequest)
	require.NoError(t, err)

	combinedPolicy := response.Policy
	// Check that the combined policy has the expected packages
	for _, pkgPolicy := range combinedPolicy.Packages {
		switch pkgPolicy.Name {
		case "express":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, pkgPolicy.Level)
		case "lodash":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, pkgPolicy.Level)
		case "foo":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, pkgPolicy.Level)
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
		case "MIT":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, licenseEntry.Level)
		case "Apache-2.0":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE, licenseEntry.Level)
		case "GPL-3.0-only":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION, licenseEntry.Level)
		case "AGPL-3.0":
			assert.Equal(t, proto.PolicyLevel_POLICY_LEVEL_REPOSITORY, licenseEntry.Level)
		default:
			t.Errorf("unexpected license ID: %s", licenseEntry.SpdxId)
		}
	}
}

func TestGetOrganizationPolicy_WithSubsetContexts(t *testing.T) {
	server := newTestServer(t)
	orgID := 2
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.SubsetContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       []string{"internal"},
		},
	}

	createResponse, err := server.CreateOrganizationPolicy(
		t.Context(),
		&proto.CreateOrganizationPolicyRequest{
			OrganizationId: uint64(orgID),
			Licenses:       licenses,
			Packages:       packages,
		},
	)
	require.NoError(t, err)

	getRequest := &proto.GetOrganizationPolicyRequest{OrganizationId: uint64(orgID)}
	response, err := server.GetOrganizationPolicy(t.Context(), getRequest)
	require.NoError(t, err)
	assert.Equal(t, orgID, int(response.Policy.OrganizationId))
	assert.Len(t, response.Policy.DistributionPolicies, 2)
	assert.EqualExportedValues(t, createResponse.Policy.DistributionPolicies[0].Licenses.Allowed, response.Policy.DistributionPolicies[0].Licenses.Allowed)
	for _, dp := range response.Policy.DistributionPolicies {
		if dp.Name == "internal" {
			assert.EqualExportedValues(t, packages, dp.Packages)
		} else {
			assert.Empty(t, dp.Packages)
		}
	}
	assert.NotNil(t, response.Policy.CreatedAt)
}

// TestAddLicenseToOrganizationPolicy_PolicyExists tests that adding licenses when
// a policy exists, extends the list of allowed licenses.
func TestAddLicenseToOrganizationPolicy_PolicyExists(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	existingLicense := "GPL-2.0"
	newLicense := "Apache-2.0"

	// Start with only GPL-2.0 is allowed by the policy.
	_, err := server.CreateOrganizationPolicy(t.Context(), &proto.CreateOrganizationPolicyRequest{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: existingLicense, Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	// Test
	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        []string{newLicense},
		Context:        testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	assert.NotNil(t, updateResponse.Policy)
	updatedPolicy := updateResponse.Policy

	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updatedPolicy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}
	assert.Len(t, allowedLicenses, 2)
	assert.Equal(t, existingLicense, allowedLicenses[0].SpdxId)
	assert.Equal(t, newLicense, allowedLicenses[1].SpdxId)
}

// TestAddLicenseToEnterprisePolicy_PolicyExists tests that adding licenses when
// a policy exists, extends the list of allowed licenses.
func TestAddLicenseToEnterprisePolicy_PolicyExists(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()
	existingLicense := "GPL-2.0"
	newLicense := "Apache-2.0"

	// Start with only GPL-2.0 is allowed by the policy.
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: existingLicense, Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	// Test
	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      []string{newLicense},
		Context:      testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	assert.NotNil(t, updateResponse.Policy)
	updatedPolicy := updateResponse.Policy

	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updatedPolicy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}
	assert.Len(t, allowedLicenses, 2)
	assert.Equal(t, existingLicense, allowedLicenses[0].SpdxId)
	assert.Equal(t, newLicense, allowedLicenses[1].SpdxId)

	// Backwards compatibility check to be removed later
	require.NotNil(t, updateResponse.Policy.Licenses)        //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.Len(t, updateResponse.Policy.Licenses.Allowed, 2) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

func TestAddLicensesToEnterprisePolicy_ClosesAffectedAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		server := newTestServer(t)
		ctx := t.Context()
		entID := testhelpers.RandomIDForDatabase()
		repositoryID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()

		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlert, err := server.app.Subsystems.Storage.CreateAlert(ctx, alert)
		require.NoError(t, err)

		// Add GPL-3.0 to enterprise policy
		_, err = server.AddLicensesToEnterprisePolicy(ctx, &proto.AddLicensesToEnterprisePolicyRequest{
			EnterpriseId: entID,
			SpdxIds:      []string{"GPL-3.0"},
			Context:      testhelpers.DistributedContext,
		})
		require.NoError(t, err)

		// Wait for async alert closure to complete
		synctest.Wait()

		// Verify alert is closed
		alertAfter, err := server.app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String(), "alert should be closed")
	})
}

func TestAddLicensesToOrganizationPolicy_ClosesAffectedAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		server := newTestServer(t)
		ctx := t.Context()
		entID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()
		repositoryID := testhelpers.RandomIDForDatabase()

		alert := models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		}
		createdAlert, err := server.app.Subsystems.Storage.CreateAlert(ctx, alert)
		require.NoError(t, err)

		// Add GPL-3.0 to organization policy
		_, err = server.AddLicensesToOrganizationPolicy(ctx, &proto.AddLicensesToOrganizationPolicyRequest{
			OrganizationId: orgID,
			SpdxIds:        []string{"GPL-3.0"},
			Context:        testhelpers.DistributedContext,
		})
		require.NoError(t, err)

		// Wait for async alert closure to complete
		synctest.Wait()

		// Verify alert is closed
		alertAfter, err := server.app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.Closed.String(), alertAfter.Status.String(), "alert should be closed")
	})
}

// TestAddLicensesToOrganizationPolicy_PolicyExists tests that adding multiple licenses
// when a policy exists, extends the list of allowed licenses.
func TestAddLicensesToOrganizationPolicy_AddMultipleLicenses(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	existingLicense := "GPL-2.0"
	newLicenses := []string{"Apache-2.0", "ISC"}

	// Start with only GPL-2.0 is allowed by the policy.
	_, err := server.CreateOrganizationPolicy(t.Context(), &proto.CreateOrganizationPolicyRequest{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: existingLicense, Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        newLicenses,
		Context:        testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	assert.NotNil(t, updateResponse.Policy)
	updatedPolicy := updateResponse.Policy

	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updatedPolicy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}
	assert.Len(t, allowedLicenses, 3)
	assert.Equal(t, existingLicense, allowedLicenses[0].SpdxId)
	assert.Equal(t, newLicenses[0], allowedLicenses[1].SpdxId)
	assert.Equal(t, newLicenses[1], allowedLicenses[2].SpdxId)
}

// TestAddLicensesToEnterprisePolicy_PolicyExists tests that adding multiple licenses
// when a policy exists, extends the list of allowed licenses.
func TestAddLicensesToEnterprisePolicy_AddMultipleLicenses(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()
	existingLicense := "GPL-2.0"
	newLicenses := []string{"Apache-2.0", "ISC"}

	// Start with only GPL-2.0 is allowed by the policy.
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: existingLicense, Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      newLicenses,
		Context:      testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	assert.NotNil(t, updateResponse.Policy)
	updatedPolicy := updateResponse.Policy

	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updatedPolicy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}
	assert.Len(t, allowedLicenses, 3)
	assert.Equal(t, existingLicense, allowedLicenses[0].SpdxId)
	assert.Equal(t, newLicenses[0], allowedLicenses[1].SpdxId)
	assert.Equal(t, newLicenses[1], allowedLicenses[2].SpdxId)

	// Backwards compatibility check to be removed later
	require.NotNil(t, updateResponse.Policy.Licenses)        //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.Len(t, updateResponse.Policy.Licenses.Allowed, 3) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

// TestAddLicensesToOrganizationPolicy_NoPolicy tests that adding licenses when
// a policy doesn't exist yet, creates a policy with those licenses.
func TestAddLicensesToOrganizationPolicy_NoPolicy(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	newLicense := "Apache-2.0"

	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        []string{newLicense},
		Context:        testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	assert.NotNil(t, updateResponse.Policy)
	updatedPolicy := updateResponse.Policy

	require.Len(t, updatedPolicy.DistributionPolicies, 1)

	allowedLicenses := updatedPolicy.DistributionPolicies[0].Licenses.Allowed
	assert.Len(t, allowedLicenses, 1)
	assert.Equal(t, newLicense, allowedLicenses[0].SpdxId)
}

// TestAddLicensesToEnterprisePolicy_NoPolicy tests that adding licenses when
// a policy doesn't exist yet, creates a policy with those licenses.
func TestAddLicensesToEnterprisePolicy_NoPolicy(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()
	newLicense := "Apache-2.0"

	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      []string{newLicense},
		Context:      testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	assert.NotNil(t, updateResponse.Policy)
	updatedPolicy := updateResponse.Policy

	require.Len(t, updatedPolicy.DistributionPolicies, 1)

	allowedLicenses := updatedPolicy.DistributionPolicies[0].Licenses.Allowed
	assert.Len(t, allowedLicenses, 1)
	assert.Equal(t, newLicense, allowedLicenses[0].SpdxId)

	// Backwards compatibility check to be removed later
	require.NotNil(t, updateResponse.Policy.Licenses)        //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.Len(t, updateResponse.Policy.Licenses.Allowed, 1) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

// TestAddLicensesToOrganizationPolicy_MissingRequiredParams tests that adding licenses
// without required parameters returns an error.
func TestAddLicensesToOrganizationPolicy_MissingRequiredParams(t *testing.T) {
	server := newTestServer(t)
	newLicense := "Apache-2.0"

	tests := []struct {
		name     string
		request  *proto.AddLicensesToOrganizationPolicyRequest
		errorMsg string
	}{
		{"missing SpdxIDs", &proto.AddLicensesToOrganizationPolicyRequest{
			OrganizationId: 0,
			SpdxIds:        nil,
			Context:        "",
		}, "spdx_ids"},
		{"missing Context", &proto.AddLicensesToOrganizationPolicyRequest{
			OrganizationId: 0,
			SpdxIds:        []string{newLicense},
			Context:        "",
		}, "context"},
		{"missing OrganizationID", &proto.AddLicensesToOrganizationPolicyRequest{
			OrganizationId: 0,
			SpdxIds:        []string{newLicense},
			Context:        testhelpers.DistributedContext,
		}, "organization_id"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), test.request)
			assert.Nil(t, updateResponse)

			// Check that it's specifically a RequiredArgumentError
			expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: %s is required", test.errorMsg)
			var twerr twirp.Error
			require.Error(t, err)
			require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
			assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match RequiredArgumentError format")
		})
	}
}

// TestAddLicensesToEnterprisePolicy_MissingRequiredParams tests that adding licenses
// without required parameters returns an error.
func TestAddLicensesToEnterprisePolicy_MissingRequiredParams(t *testing.T) {
	server := newTestServer(t)
	newLicense := "Apache-2.0"

	tests := []struct {
		name     string
		request  *proto.AddLicensesToEnterprisePolicyRequest
		errorMsg string
	}{
		{"missing SpdxIDs", &proto.AddLicensesToEnterprisePolicyRequest{
			EnterpriseId: 0,
			SpdxIds:      nil,
			Context:      "",
		}, "spdx_ids"},
		{"missing Context", &proto.AddLicensesToEnterprisePolicyRequest{
			EnterpriseId: 0,
			SpdxIds:      []string{newLicense},
			Context:      "",
		}, "context"},
		{"missing EnterpriseID", &proto.AddLicensesToEnterprisePolicyRequest{
			EnterpriseId: 0,
			SpdxIds:      []string{newLicense},
			Context:      testhelpers.DistributedContext,
		}, "enterprise_id"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), test.request)
			assert.Nil(t, updateResponse)

			// Check that it's specifically a RequiredArgumentError
			expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: %s is required", test.errorMsg)
			var twerr twirp.Error
			require.Error(t, err)
			require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
			assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match RequiredArgumentError format")
		})
	}
}

// TestAddLicenseToOrganizationPolicy_InvalidSPDXLicense tests that an invalid SPDX license
// returns an error.
func TestAddLicenseToOrganizationPolicy_InvalidSPDXLicense(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	invalidLicense := "BAD-LICENSE"

	// Test
	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        []string{invalidLicense},
		Context:        testhelpers.DistributedContext,
	})
	assert.Nil(t, updateResponse)

	expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: spdx_ids invalid SPDX license identifiers: [%v]", invalidLicense)
	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match InvalidArgumentError format")
}

// TestAddLicenseToEnterprisePolicy_InvalidSPDXLicense tests that an invalid SPDX license
// returns an error.
func TestAddLicenseToEnterprisePolicy_InvalidSPDXLicense(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := testhelpers.RandomIDForDatabase()
	invalidLicense := "BAD-LICENSE"

	// Test
	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		SpdxIds:      []string{invalidLicense},
		Context:      testhelpers.DistributedContext,
	})
	assert.Nil(t, updateResponse)

	expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: spdx_ids invalid SPDX license identifiers: [%v]", invalidLicense)
	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match InvalidArgumentError format")
}

// TestAddLicenseToOrganizationPolicy_ReturnsInternalError tests that an error coming
// from internal systems (e.g. database) returns an error.
func TestAddLicenseToOrganizationPolicy_ReturnsInternalError(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()
	newLicense := "Apache-2.0"

	// Close DB to force an unexpected error with CreateCheckJob
	err := server.app.Subsystems.Storage.Close()
	require.NoError(t, err)

	// Test
	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        []string{newLicense},
		Context:        testhelpers.DistributedContext,
	})
	assert.Nil(t, updateResponse)

	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

// TestAddLicenseToEnterprisePolicy_ReturnsInternalError tests that an error coming
// from internal systems (e.g. database) returns an error.
func TestAddLicenseToEnterprisePolicy_ReturnsInternalError(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := testhelpers.RandomIDForDatabase()
	newLicense := "Apache-2.0"

	// Close DB to force an unexpected error with CreateCheckJob
	err := server.app.Subsystems.Storage.Close()
	require.NoError(t, err)

	// Test
	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		SpdxIds:      []string{newLicense},
		Context:      testhelpers.DistributedContext,
	})
	assert.Nil(t, updateResponse)

	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

// TestDeleteLicensesFromEnterprisePolicy_Success tests that removing licenses
// from an existing policy removes them from the specified distribution context.
func TestDeleteLicensesFromEnterprisePolicy_Success(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()

	// Create a policy with multiple licenses
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: []string{testhelpers.DistributedContext}},
				{SpdxId: "Apache-2.0", Contexts: []string{testhelpers.DistributedContext}},
				{SpdxId: "MIT", Contexts: []string{testhelpers.DistributedContext}},
			},
		},
	})
	require.NoError(t, err)

	// Remove Apache-2.0 license from distributed context
	removeResponse, err := server.DeleteLicensesFromEnterprisePolicy(t.Context(), &proto.DeleteLicensesFromEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      []string{"Apache-2.0"},
		Context:      testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, removeResponse)

	// Verify the policy was updated correctly
	updatedPolicy := removeResponse.Policy
	assert.NotNil(t, updatedPolicy)
	allowedLicenses := updatedPolicy.DistributionPolicies[0].Licenses.Allowed
	assert.Len(t, allowedLicenses, 2, "should have 2 licenses remaining")

	// Verify Apache-2.0 was removed and GPL-2.0, MIT remain
	remainingLicenseIDs := make([]string, len(allowedLicenses))
	for i, license := range allowedLicenses {
		remainingLicenseIDs[i] = license.SpdxId
	}
	assert.Contains(t, remainingLicenseIDs, "GPL-2.0")
	assert.Contains(t, remainingLicenseIDs, "MIT")
	assert.NotContains(t, remainingLicenseIDs, "Apache-2.0")

	// Backwards compatibility check to be removed later
	require.NotNil(t, removeResponse.Policy.Licenses)        //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.Len(t, removeResponse.Policy.Licenses.Allowed, 2) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

// TestDeleteLicensesFromEnterprisePolicy_NonExistentPolicy tests that removing licenses
// from a non-existent policy returns an error.
func TestDeleteLicensesFromEnterprisePolicy_NonExistentPolicy(t *testing.T) {
	server := newTestServer(t)
	nonExistentEntID := testhelpers.RandomIDForDatabase()

	removeResponse, err := server.DeleteLicensesFromEnterprisePolicy(t.Context(), &proto.DeleteLicensesFromEnterprisePolicyRequest{
		EnterpriseId: nonExistentEntID,
		SpdxIds:      []string{"MIT"},
		Context:      testhelpers.DistributedContext,
	})

	assert.Nil(t, removeResponse)
	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	assert.Equal(t, twirp.Internal, twerr.Code(), "expected error to be a twirp.Internal")
}

// TestDeleteLicensesFromEnterprisePolicy_MissingRequiredParams tests that removing licenses
// with missing required parameters returns appropriate errors.
func TestDeleteLicensesFromEnterprisePolicy_MissingRequiredParams(t *testing.T) {
	server := newTestServer(t)

	tests := []struct {
		name     string
		request  *proto.DeleteLicensesFromEnterprisePolicyRequest
		errorMsg string
	}{
		{"missing SpdxIds", &proto.DeleteLicensesFromEnterprisePolicyRequest{
			EnterpriseId: 123,
			Context:      testhelpers.DistributedContext,
		}, "spdx_ids"},
		{"missing Context", &proto.DeleteLicensesFromEnterprisePolicyRequest{
			EnterpriseId: 123,
			SpdxIds:      []string{"MIT"},
		}, "context"},
		{"missing EnterpriseID", &proto.DeleteLicensesFromEnterprisePolicyRequest{
			SpdxIds: []string{"MIT"},
			Context: testhelpers.DistributedContext,
		}, "enterprise_id"},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			removeResponse, err := server.DeleteLicensesFromEnterprisePolicy(t.Context(), test.request)
			assert.Nil(t, removeResponse)

			// Check that it's specifically a RequiredArgumentError
			expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: %s is required", test.errorMsg)
			var twerr twirp.Error
			require.Error(t, err)
			require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
			assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match RequiredArgumentError format")
		})
	}
}

// TestDeleteLicensesFromEnterprisePolicy_InvalidSPDXLicense tests that an invalid SPDX license
// can be successfully deleted (validation should not block cleanup).
func TestDeleteLicensesFromEnterprisePolicy_InvalidSPDXLicense(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := testhelpers.RandomIDForDatabase()
	invalidLicense := "asdasdasdasd"

	// Create a policy with a valid license first
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: []string{testhelpers.DistributedContext}},
			},
		},
	})
	require.NoError(t, err)

	// Manually inject the invalid license into the policy to simulate legacy data
	_, updateErr := server.app.Subsystems.Storage.UpdateEnterprisePolicy(t.Context(), enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		for _, dp := range policy.DistributionPolicies {
			if dp.Name == testhelpers.DistributedContext {
				dp.Licenses.Allowed = append(dp.Licenses.Allowed, &proto.LicenseEntry{
					SpdxId: invalidLicense,
				})
			}
		}
		return storage.ProtoCopy(policy), nil
	})
	require.NoError(t, updateErr)

	// Now attempt to delete the invalid license - this should succeed
	removeResponse, err := server.DeleteLicensesFromEnterprisePolicy(t.Context(), &proto.DeleteLicensesFromEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		SpdxIds:      []string{invalidLicense},
		Context:      testhelpers.DistributedContext,
	})
	require.NoError(t, err, "deleting invalid license should succeed to allow cleanup")
	require.NotNil(t, removeResponse)

	// Verify the invalid license was removed and MIT remains
	allowedLicenses := removeResponse.Policy.DistributionPolicies[0].Licenses.Allowed
	assert.Len(t, allowedLicenses, 1, "should have 1 license remaining")
	assert.Equal(t, "MIT", allowedLicenses[0].SpdxId, "MIT should remain in the policy")
}

// TestDeleteLicensesFromEnterprisePolicy_ExactMatching tests that the
// exact matching requirement works correctly with context matching.
func TestDeleteLicensesFromEnterprisePolicy_ContextSpecificRemoval(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()

	// Create a policy with MIT license in multiple contexts
	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "MIT", Contexts: []string{testhelpers.DistributedContext, "network"}},
			},
		},
	})
	require.NoError(t, err)

	// Remove MIT license only from network context
	removeResponse, err := server.DeleteLicensesFromEnterprisePolicy(t.Context(), &proto.DeleteLicensesFromEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      []string{"MIT"},
		Context:      "network",
	})
	require.NoError(t, err)
	require.NotNil(t, removeResponse)

	// Verify MIT license still exists but only in distributed context
	updatedPolicy := removeResponse.Policy
	assert.NotNil(t, updatedPolicy)
	for _, dp := range updatedPolicy.DistributionPolicies {
		switch dp.Name {
		case "network":
			assert.Len(t, dp.Licenses.Allowed, 0, "MIT license should be removed from network context")
		case testhelpers.DistributedContext:
			assert.Len(t, dp.Licenses.Allowed, 1, "MIT license should still exist in distributed context")
		}
	}
}

func TestDeletePackageExceptionsFromEnterprisePolicy_Success(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()

	// Create an enterprise policy with some package exceptions
	existingPackages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT", "BSD-2-Clause"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "react",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_PIP,
			Name:                "django",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"BSD-3-Clause"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
	}

	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Packages:     existingPackages,
	})
	require.NoError(t, err)

	// Delete the lodash and django packages
	packagesToDelete := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			ExtraAllowedSpdxIds: []string{"BSD-2-Clause", "MIT"}, // Order should not matter
		},
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_PIP,
			Name:                "django",
			ExtraAllowedSpdxIds: []string{"BSD-3-Clause"},
		},
	}

	req := &proto.DeletePackageExceptionsFromEnterprisePolicyRequest{
		EnterpriseId: entID,
		Packages:     packagesToDelete,
	}

	resp, err := server.DeletePackageExceptionsFromEnterprisePolicy(t.Context(), req)
	require.NoError(t, err)
	require.Len(t, resp.Policy.DistributionPolicies, 1)

	packages := resp.Policy.DistributionPolicies[0].Packages

	// Should only have the react package left
	assert.Len(t, packages, 1)
	assert.Equal(t, proto.PackageManager_PACKAGE_MANAGER_NPM, packages[0].PackageManager)
	assert.Equal(t, "react", packages[0].Name)
	assert.Equal(t, []string{"MIT"}, packages[0].ExtraAllowedSpdxIds)

	// Backwards compatibility check to be removed later
	require.NotNil(t, resp.Policy.Packages) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.Len(t, resp.Policy.Packages, 1)  //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

func TestDeletePackageExceptionsFromEnterprisePolicy_NoMatch(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()

	// Create an enterprise policy with some packages
	existingPackages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
	}

	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Packages:     existingPackages,
	})
	require.NoError(t, err)

	// Try to delete a package that doesn't match
	packagesToDelete := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodasher",
			ExtraAllowedSpdxIds: []string{"MIT", "Apache-2.0"},
		},
	}

	req := &proto.DeletePackageExceptionsFromEnterprisePolicyRequest{
		EnterpriseId: entID,
		Packages:     packagesToDelete,
	}

	resp, err := server.DeletePackageExceptionsFromEnterprisePolicy(t.Context(), req)
	require.NoError(t, err)
	require.Len(t, resp.Policy.DistributionPolicies, 1)

	packages := resp.Policy.DistributionPolicies[0].Packages

	// Should still have the package (no match, so nothing deleted)
	assert.Len(t, packages, 1)
	assert.Equal(t, "lodash", packages[0].Name)
	assert.Equal(t, []string{"MIT"}, packages[0].ExtraAllowedSpdxIds)

	// Backwards compatibility check to be removed later
	require.NotNil(t, resp.Policy.Packages) //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
	assert.Len(t, resp.Policy.Packages, 1)  //nolint:staticcheck // SA1019: accessing deprecated field for backwards compatibility
}

func TestDeletePackageExceptionsFromEnterprisePolicy_EmptyPackagesList(t *testing.T) {
	server := newTestServer(t)
	entID := uint64(126)

	// Create an enterprise policy with some packages
	existingPackages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            testhelpers.AllDistributionContexts,
		},
	}

	_, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: entID,
		Packages:     existingPackages,
	})
	require.NoError(t, err)

	// Try to delete with empty packages list
	req := &proto.DeletePackageExceptionsFromEnterprisePolicyRequest{
		EnterpriseId: entID,
		Packages:     []*proto.PackagePolicy{},
	}

	resp, err := server.DeletePackageExceptionsFromEnterprisePolicy(t.Context(), req)
	require.Error(t, err)
	require.Nil(t, resp)
	assert.Equal(t, twirp.RequiredArgumentError("packages"), err)
}

func TestDeletePackageExceptionsFromEnterprisePolicy_MissingEnterpriseId(t *testing.T) {
	server := newTestServer(t)

	req := &proto.DeletePackageExceptionsFromEnterprisePolicyRequest{
		EnterpriseId: 0, // Missing
		Packages: []*proto.PackagePolicy{
			{
				PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:                "lodash",
				ExtraAllowedSpdxIds: []string{"MIT"},
			},
		},
	}

	resp, err := server.DeletePackageExceptionsFromEnterprisePolicy(t.Context(), req)
	require.Error(t, err)
	require.Nil(t, resp)
	assert.Equal(t, twirp.RequiredArgumentError("enterprise_id"), err)
}

func TestDeletePackageExceptionsFromEnterprisePolicy_PolicyNotFound(t *testing.T) {
	server := newTestServer(t)
	nonExistentEntID := uint64(999)

	req := &proto.DeletePackageExceptionsFromEnterprisePolicyRequest{
		EnterpriseId: nonExistentEntID,
		Packages: []*proto.PackagePolicy{
			{
				PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:                "lodash",
				ExtraAllowedSpdxIds: []string{"MIT"},
			},
		},
	}

	resp, err := server.DeletePackageExceptionsFromEnterprisePolicy(t.Context(), req)
	require.Error(t, err)
	require.Nil(t, resp)
	assert.Contains(t, err.Error(), "not found")
}

func TestDeleteLicensesFromRepositoryPolicy_Success(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()

	// Create a policy with multiple licenses
	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repoID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: []string{testhelpers.DistributedContext}},
				{SpdxId: "Apache-2.0", Contexts: []string{testhelpers.DistributedContext}},
				{SpdxId: "MIT", Contexts: []string{testhelpers.DistributedContext}},
			},
		},
	})
	require.NoError(t, err)

	// Remove GPL-2.0, MIT licenses from distributed context
	removeResponse, err := server.DeleteLicensesFromRepositoryPolicy(t.Context(), &proto.DeleteLicensesFromRepositoryPolicyRequest{
		RepositoryId: repoID,
		SpdxIds:      []string{"GPL-2.0", "MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, removeResponse)
	assert.True(t, removeResponse.Success)
}

func TestDeleteLicensesFromRepositoryPolicy_NoMatch(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()

	// Create a policy with some licenses
	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repoID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "GPL-2.0", Contexts: []string{testhelpers.DistributedContext}},
				{SpdxId: "MIT", Contexts: []string{testhelpers.DistributedContext}},
			},
		},
	})
	require.NoError(t, err)

	// Attempt to remove a license that doesn't exist in the policy
	removeResponse, err := server.DeleteLicensesFromRepositoryPolicy(t.Context(), &proto.DeleteLicensesFromRepositoryPolicyRequest{
		RepositoryId: repoID,
		SpdxIds:      []string{"Apache-2.0"},
	})
	require.NoError(t, err)
	require.NotNil(t, removeResponse)
	assert.True(t, removeResponse.Success)
}

func TestDeleteLicensesFromRepositoryPolicy_NoPolicy(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()

	// Attempt to remove a license from a non-existent policy
	removeResponse, err := server.DeleteLicensesFromRepositoryPolicy(t.Context(), &proto.DeleteLicensesFromRepositoryPolicyRequest{
		RepositoryId: repoID,
		SpdxIds:      []string{"Apache-2.0"},
	})
	require.Error(t, err)
	require.Nil(t, removeResponse)
}

func TestDeleteLicensesFromRepositoryPolicy_MissingParams(t *testing.T) {
	server := newTestServer(t)

	tests := []struct {
		name     string
		request  *proto.DeleteLicensesFromRepositoryPolicyRequest
		errorMsg string
	}{
		{
			"missing SpdxIds",
			&proto.DeleteLicensesFromRepositoryPolicyRequest{
				RepositoryId: 123,
				SpdxIds:      []string{},
			},
			"spdx_ids",
		},
		{
			"missing RepositoryID", &proto.DeleteLicensesFromRepositoryPolicyRequest{
				SpdxIds: []string{"MIT"},
			},
			"repository_id",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			removeResponse, err := server.DeleteLicensesFromRepositoryPolicy(t.Context(), test.request)
			assert.Nil(t, removeResponse)

			// Check that it's specifically a RequiredArgumentError
			expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: %s is required", test.errorMsg)
			var twerr twirp.Error
			require.Error(t, err)
			require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
			assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match RequiredArgumentError format")
		})
	}
}

func TestDeletePackageExceptionsFromRepositoryPolicy_Success(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()

	// Create a repository policy with some package exceptions
	existingPackages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT", "BSD-2-Clause"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "react",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_PIP,
			Name:                "django",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"BSD-3-Clause"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
	}

	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repoID,
		Packages:     existingPackages,
	})
	require.NoError(t, err)

	// Delete the lodash and django packages
	packagesToDelete := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			ExtraAllowedSpdxIds: []string{"BSD-2-Clause", "MIT"},
		},
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_PIP,
			Name:                "django",
			ExtraAllowedSpdxIds: []string{"BSD-3-Clause"},
		},
	}

	req := &proto.DeletePackageExceptionsFromRepositoryPolicyRequest{
		RepositoryId: repoID,
		Packages:     packagesToDelete,
	}

	resp, err := server.DeletePackageExceptionsFromRepositoryPolicy(t.Context(), req)
	require.NoError(t, err)
	require.True(t, resp.Success)
}

func TestDeletePackageExceptionsFromRepositoryPolicy_NoMatch(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()

	// Create a repository policy with some packages
	existingPackages := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodash",
			Action:              proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:              "Exception created via API",
			ExtraAllowedSpdxIds: []string{"MIT"},
			Contexts:            []string{testhelpers.DistributedContext},
		},
	}

	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repoID,
		Packages:     existingPackages,
	})
	require.NoError(t, err)

	// Try to delete a package that doesn't match
	packagesToDelete := []*proto.PackagePolicy{
		{
			PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:                "lodasher",
			ExtraAllowedSpdxIds: []string{"MIT", "Apache-2.0"},
		},
	}

	req := &proto.DeletePackageExceptionsFromRepositoryPolicyRequest{
		RepositoryId: repoID,
		Packages:     packagesToDelete,
	}

	resp, err := server.DeletePackageExceptionsFromRepositoryPolicy(t.Context(), req)
	require.NoError(t, err)
	require.True(t, resp.Success)
}

func TestDeletePackageExceptionsFromRepositoryPolicy_NoPolicy(t *testing.T) {
	server := newTestServer(t)
	nonExistentRepoID := uint64(999)

	req := &proto.DeletePackageExceptionsFromRepositoryPolicyRequest{
		RepositoryId: nonExistentRepoID,
		Packages: []*proto.PackagePolicy{
			{
				PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:                "lodash",
				ExtraAllowedSpdxIds: []string{"MIT"},
			},
		},
	}

	resp, err := server.DeletePackageExceptionsFromRepositoryPolicy(t.Context(), req)
	var twerr twirp.Error
	require.Error(t, err)
	require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
	require.Nil(t, resp)
}

func TestDeletePackageExceptionsFromRepositoryPolicy_MissingParams(t *testing.T) {
	server := newTestServer(t)

	tests := []struct {
		name     string
		request  *proto.DeletePackageExceptionsFromRepositoryPolicyRequest
		errorMsg string
	}{
		{
			"missing Packages",
			&proto.DeletePackageExceptionsFromRepositoryPolicyRequest{
				RepositoryId: 123,
			},
			"packages",
		},
		{
			"empty Packages",
			&proto.DeletePackageExceptionsFromRepositoryPolicyRequest{
				RepositoryId: 123,
				Packages:     []*proto.PackagePolicy{},
			},
			"packages",
		},
		{
			"missing RepositoryID",
			&proto.DeletePackageExceptionsFromRepositoryPolicyRequest{
				Packages: []*proto.PackagePolicy{
					{
						PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
						Name:                "lodash",
						ExtraAllowedSpdxIds: []string{"MIT"},
					},
				},
			},
			"repository_id",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			removeResponse, err := server.DeletePackageExceptionsFromRepositoryPolicy(t.Context(), test.request)
			assert.Nil(t, removeResponse)

			// Check that it's specifically a RequiredArgumentError
			expectedErrorMsg := fmt.Sprintf("twirp error invalid_argument: %s is required", test.errorMsg)
			var twerr twirp.Error
			require.Error(t, err)
			require.ErrorAs(t, err, &twerr, "error should be of type twirp.Error")
			assert.Equal(t, expectedErrorMsg, err.Error(), "error message should match RequiredArgumentError format")
		})
	}
}

func TestAddLicensesToOrganizationPolicy_CaseInsensitiveDuplicates(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()

	// Create policy with lowercase "mit"
	_, err := server.CreateOrganizationPolicy(t.Context(), &proto.CreateOrganizationPolicyRequest{
		OrganizationId: orgID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{
				{SpdxId: "mit", Contexts: testhelpers.AllDistributionContexts},
			},
		},
	})
	require.NoError(t, err)

	// Try to add "MIT" (uppercase) - should be treated as duplicate
	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        []string{"MIT"},
		Context:        testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	// Should only have one license, normalized to canonical "MIT"
	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updateResponse.Policy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}
	require.Len(t, allowedLicenses, 1, "should only have one license, not duplicates")
	assert.Equal(t, "MIT", allowedLicenses[0].SpdxId, "license should be normalized to canonical case 'MIT'")
}

func TestAddLicensesToOrganizationPolicy_MultipleVariantsNormalized(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()

	// Add multiple case variants of the same licenses at once
	updateResponse, err := server.AddLicensesToOrganizationPolicy(t.Context(), &proto.AddLicensesToOrganizationPolicyRequest{
		OrganizationId: orgID,
		SpdxIds:        []string{"mit", "MIT", "apache-2.0", "APACHE-2.0", "bsd-3-clause"},
		Context:        testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updateResponse.Policy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}

	// Should only have 3 unique licenses (MIT, Apache-2.0, BSD-3-Clause)
	require.Len(t, allowedLicenses, 3, "should deduplicate case variants")

	// All should be in canonical case
	assert.Equal(t, "MIT", allowedLicenses[0].SpdxId)
	assert.Equal(t, "Apache-2.0", allowedLicenses[1].SpdxId)
	assert.Equal(t, "BSD-3-Clause", allowedLicenses[2].SpdxId)
}

func TestAddLicensesToEnterprisePolicy_ComplexExpressionNormalized(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()

	// Add complex expression with mixed case
	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      []string{"mit OR apache-2.0", "MIT OR Apache-2.0"},
		Context:      testhelpers.DistributedContext,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)

	var allowedLicenses []*proto.LicenseEntry
	for _, dp := range updateResponse.Policy.DistributionPolicies {
		if dp.Name == testhelpers.DistributedContext {
			allowedLicenses = dp.Licenses.Allowed
			break
		}
	}

	// Should only have 1 license (deduplicated)
	require.Len(t, allowedLicenses, 1, "should treat different case variants of same expression as duplicates")

	// Should be normalized to canonical case
	assert.Equal(t, "MIT OR Apache-2.0", allowedLicenses[0].SpdxId)
}
