package twirp

import (
	"fmt"
	"testing"
	"testing/synctest"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/internal/twirp/twcerr/twcerrtesting"
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
}

func TestGetEnterprisePolicy_NotFound(t *testing.T) {
	server := newTestServer(t)

	req := &proto.GetEnterprisePolicyRequest{EnterpriseId: uint64(1)}
	res, err := server.GetEnterprisePolicy(t.Context(), req)
	assert.Nil(t, res)
	assert.Equal(t, twirp.NotFoundError("policy not found"), err)
}

func enterprisePolicyLicenseIDsForContext(policy *proto.EnterprisePolicy, distributionContext string) []string {
	if policy == nil {
		return nil
	}
	for _, dp := range policy.DistributionPolicies {
		if dp.Name == distributionContext && dp.Licenses != nil {
			ids := make([]string, 0, len(dp.Licenses.Allowed))
			for _, entry := range dp.Licenses.Allowed {
				if entry != nil {
					ids = append(ids, entry.SpdxId)
				}
			}
			return ids
		}
	}
	return nil
}

func enterprisePolicyPackageNamesForContext(policy *proto.EnterprisePolicy, distributionContext string) []string {
	if policy == nil {
		return nil
	}
	for _, dp := range policy.DistributionPolicies {
		if dp.Name == distributionContext {
			names := make([]string, 0, len(dp.Packages))
			for _, pkg := range dp.Packages {
				if pkg != nil {
					names = append(names, pkg.Name)
				}
			}
			return names
		}
	}
	return nil
}

func seedEnterprisePolicy(t *testing.T, server *Server, enterpriseID uint64, licenses []string, packages []*proto.PackagePolicy) {
	t.Helper()
	var policyLicenses *proto.PolicyLicenses
	if licenses != nil {
		allowed := make([]*proto.LicenseEntry, 0, len(licenses))
		for _, spdxID := range licenses {
			allowed = append(allowed, &proto.LicenseEntry{SpdxId: spdxID})
		}
		policyLicenses = &proto.PolicyLicenses{Allowed: allowed}
	}

	resp, err := server.CreateEnterprisePolicy(t.Context(), &proto.CreateEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Licenses:     policyLicenses,
		Packages:     packages,
	})
	require.NoError(t, err)
	require.ElementsMatch(t, licenses, enterprisePolicyLicenseIDsForContext(resp.Policy, "distributed"))
	packageNames := make([]string, 0, len(packages))
	for _, pkg := range packages {
		packageNames = append(packageNames, pkg.Name)
	}
	require.ElementsMatch(t, packageNames, enterprisePolicyPackageNamesForContext(resp.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_MissingRequiredArguments(t *testing.T) {
	server := newTestServer(t)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{})
	assert.Nil(t, res)
	assert.Equal(t, twirp.RequiredArgumentError("enterprise_id, context, user_id"), err)

	res, err = server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{EnterpriseId: 1})
	assert.Nil(t, res)
	assert.Equal(t, twirp.RequiredArgumentError("context, user_id"), err)
}

func TestSaveEnterprisePolicy_InvalidArgument_NoUpdates(t *testing.T) {
	server := newTestServer(t)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: 1,
		Context:      "distributed",
		UserId:       123,
	})
	assert.Nil(t, res)
	assert.Equal(t, twirp.InvalidArgumentError("request", "must specify at least one update"), err)
}

func TestSaveEnterprisePolicy_AddValidLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, []string{"ADSL"}, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      "distributed",
		UserId:       123,
		AddSpdxIds:   []string{"Apache-2.0", "MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.Empty(t, res.FailedSpdxIds)

	assert.ElementsMatch(t, []string{"ADSL", "Apache-2.0", "MIT"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddWithSomeInvalidLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, nil, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      "distributed",
		UserId:       123,
		AddSpdxIds:   []string{"Apache-2.0", "not-a-license"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.Equal(t, []string{"not-a-license"}, res.FailedSpdxIds)
	assert.ElementsMatch(t, []string{"Apache-2.0"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddWithDuplicateLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, nil, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      "distributed",
		UserId:       123,
		AddSpdxIds:   []string{"mit", " MIT ", "MIT", "apache-2.0", "Apache-2.0"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.Empty(t, res.FailedSpdxIds)
	assert.ElementsMatch(t, []string{"MIT", "Apache-2.0"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddLicenses_PolicyDoesNotExist(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      "distributed",
		UserId:       123,
		AddSpdxIds:   []string{"MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.Empty(t, res.FailedSpdxIds)
	assert.ElementsMatch(t, []string{"MIT"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))

	getRes, getErr := server.GetEnterprisePolicy(t.Context(), &proto.GetEnterprisePolicyRequest{EnterpriseId: enterpriseID})
	require.NoError(t, getErr)
	require.NotNil(t, getRes)
	require.NotNil(t, getRes.Policy)
	assert.ElementsMatch(t, []string{"MIT"}, enterprisePolicyLicenseIDsForContext(getRes.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_DeleteLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, []string{"MIT", "Apache-2.0"}, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:  enterpriseID,
		Context:       "distributed",
		UserId:        123,
		DeleteSpdxIds: []string{"MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.Empty(t, res.FailedSpdxIds)
	assert.ElementsMatch(t, []string{"Apache-2.0"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_DeleteLicensesNotInPolicy(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, []string{"MIT"}, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:  enterpriseID,
		Context:       "distributed",
		UserId:        123,
		DeleteSpdxIds: []string{"Apache-2.0"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"MIT"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddAndDeleteUniqueLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, []string{"MIT"}, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:  enterpriseID,
		Context:       "distributed",
		UserId:        123,
		AddSpdxIds:    []string{"Apache-2.0"},
		DeleteSpdxIds: []string{"MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"Apache-2.0"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddAndDeleteSameLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, []string{"MIT"}, nil)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:  enterpriseID,
		Context:       "distributed",
		UserId:        123,
		AddSpdxIds:    []string{"mit"},
		DeleteSpdxIds: []string{"MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"MIT"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_DeletePackages(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, nil, []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       []string{"distributed"},
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "react",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       []string{"distributed"},
		},
	})

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:   enterpriseID,
		Context:        "distributed",
		UserId:         123,
		DeletePackages: []*proto.PackagePolicy{{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"}},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"react"}, enterprisePolicyPackageNamesForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_DeletePackageNotInPolicy(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, nil, []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       []string{"distributed"},
		},
	})

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:   enterpriseID,
		Context:        "distributed",
		UserId:         123,
		DeletePackages: []*proto.PackagePolicy{{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react"}},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"lodash"}, enterprisePolicyPackageNamesForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddDeleteLicensesAndDeletePackages(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)
	seedEnterprisePolicy(t, server, enterpriseID, []string{"MIT"}, []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			Contexts:       []string{"distributed"},
		},
	})

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId:   enterpriseID,
		Context:        "distributed",
		UserId:         123,
		AddSpdxIds:     []string{"Apache-2.0"},
		DeleteSpdxIds:  []string{"MIT"},
		DeletePackages: []*proto.PackagePolicy{{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"}},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.Empty(t, res.FailedSpdxIds)
	assert.ElementsMatch(t, []string{"Apache-2.0"}, enterprisePolicyLicenseIDsForContext(res.Policy, "distributed"))
	assert.Empty(t, enterprisePolicyPackageNamesForContext(res.Policy, "distributed"))
}

func TestSaveEnterprisePolicy_AddPackages_Single(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      testhelpers.DistributedContext,
		UserId:       123,
		AddPackages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "some-*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				Reason:         "private package",
			},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"some-*"}, enterprisePolicyPackageNamesForContext(res.Policy, testhelpers.DistributedContext))
}

func TestSaveEnterprisePolicy_AddPackages_Multiple(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      testhelpers.DistributedContext,
		UserId:       123,
		AddPackages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "foo-*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				Reason:         "private package",
			},
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "bar-*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				Reason:         "private package",
			},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"foo-*", "bar-*"}, enterprisePolicyPackageNamesForContext(res.Policy, testhelpers.DistributedContext))
}

func TestSaveEnterprisePolicy_AddPackages_InvalidWildcard(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	// Multiple wildcards — structurally invalid, should be rejected
	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      testhelpers.DistributedContext,
		UserId:       123,
		AddPackages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "*-foo-*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
			},
		},
	})
	require.Error(t, err)
	assert.Nil(t, res)
	assert.Contains(t, err.Error(), "only one wildcard")
}

func TestSaveEnterprisePolicy_AddPackages_TooShortName(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      testhelpers.DistributedContext,
		UserId:       123,
		AddPackages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "a*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
			},
		},
	})
	require.Error(t, err)
	assert.Nil(t, res)
	assert.Contains(t, err.Error(), "must have at least two non-wildcard characters")
}

func TestSaveEnterprisePolicy_AddPackages_PolicyDoesNotExist(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      testhelpers.DistributedContext,
		UserId:       123,
		AddPackages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "private-*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				Reason:         "private package",
			},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"private-*"}, enterprisePolicyPackageNamesForContext(res.Policy, testhelpers.DistributedContext))

	getRes, err := server.GetEnterprisePolicy(t.Context(), &proto.GetEnterprisePolicyRequest{EnterpriseId: enterpriseID})
	require.NoError(t, err)
	require.NotNil(t, getRes)
	require.NotNil(t, getRes.Policy)
	assert.ElementsMatch(t, []string{"private-*"}, enterprisePolicyPackageNamesForContext(getRes.Policy, testhelpers.DistributedContext))
}

func TestSaveEnterprisePolicy_AddPackagesAndLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := uint64(1)

	res, err := server.SaveEnterprisePolicy(t.Context(), &proto.SaveEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		Context:      testhelpers.DistributedContext,
		UserId:       123,
		AddSpdxIds:   []string{"MIT"},
		AddPackages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "private-*",
				Action:         proto.PackageAction_PACKAGE_ACTION_PRIVATE,
				Reason:         "private package",
			},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	require.NotNil(t, res.Policy)
	assert.ElementsMatch(t, []string{"MIT"}, enterprisePolicyLicenseIDsForContext(res.Policy, testhelpers.DistributedContext))
	assert.ElementsMatch(t, []string{"private-*"}, enterprisePolicyPackageNamesForContext(res.Policy, testhelpers.DistributedContext))
}

func TestSaveEnterprisePolicy_AddPackages_ClosesAffectedAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		server := newTestServer(t)
		ctx := t.Context()
		entID := testhelpers.RandomIDForDatabase()
		repositoryID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()
		editorUserID := uint64(42)

		createdAlert, err := server.app.Subsystems.Storage.CreateAlert(ctx, models.Alert{
			RepositoryID:          repositoryID,
			OrganizationID:        orgID,
			EnterpriseID:          &entID,
			PackageEcosystem:      proto.PackageManager_PACKAGE_MANAGER_NPM,
			PackageName:           "some-package",
			PackageVersion:        "1.0.0",
			SPDXLicenseExpression: "GPL-3.0",
		})
		require.NoError(t, err)

		_, err = server.SaveEnterprisePolicy(ctx, &proto.SaveEnterprisePolicyRequest{
			EnterpriseId: entID,
			Context:      testhelpers.DistributedContext,
			UserId:       editorUserID,
			AddPackages: []*proto.PackagePolicy{
				{
					PackageManager:      proto.PackageManager_PACKAGE_MANAGER_NPM,
					Name:                "some-*",
					Action:              proto.PackageAction_PACKAGE_ACTION_PRIVATE,
					ExtraAllowedSpdxIds: []string{"GPL-3.0"},
				},
			},
		})
		require.NoError(t, err)

		synctest.Wait()

		alertAfter, err := server.app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String(), "alert should be closed by package policy")
	})
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
		case "express", "lodash":
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
		case "MIT", "Apache-2.0":
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
		UserId:         1,
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
		UserId:       1,
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

func TestAddLicensesToEnterprisePolicy_ClosesAffectedAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		server := newTestServer(t)
		ctx := t.Context()
		entID := testhelpers.RandomIDForDatabase()
		repositoryID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()
		editorUserID := uint64(42)

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
			UserId:       editorUserID,
		})
		require.NoError(t, err)

		// Wait for async alert closure to complete
		synctest.Wait()

		// Verify alert is closed
		alertAfter, err := server.app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String(), "alert should be closed")

		// Verify events have correct user IDs
		events, err := server.app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
		require.NoError(t, err)
		require.Len(t, events, 2)
		assert.Equal(t, models.EventLicensesAdded, events[0].EventType)
		assert.Equal(t, editorUserID, *events[0].UserID, "LicensesAdded should have editor's user ID")
		assert.Equal(t, models.EventClosed, events[1].EventType)
		assert.Nil(t, events[1].UserID, "Closed should be bot (nil)")
	})
}

func TestAddLicensesToOrganizationPolicy_ClosesAffectedAlerts(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		server := newTestServer(t)
		ctx := t.Context()
		entID := testhelpers.RandomIDForDatabase()
		orgID := testhelpers.RandomIDForDatabase()
		repositoryID := testhelpers.RandomIDForDatabase()
		editorUserID := uint64(42)

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
			UserId:         editorUserID,
		})
		require.NoError(t, err)

		// Wait for async alert closure to complete
		synctest.Wait()

		// Verify alert is closed
		alertAfter, err := server.app.Subsystems.Storage.GetAlert(ctx, repositoryID, createdAlert.Number)
		require.NoError(t, err)
		assert.Equal(t, models.AlertStatusClosed.String(), alertAfter.Status.String(), "alert should be closed")

		// Verify events have correct user IDs
		events, err := server.app.Subsystems.Storage.GetAlertEvents(ctx, alertAfter.ID)
		require.NoError(t, err)
		require.Len(t, events, 2)
		assert.Equal(t, models.EventLicensesAdded, events[0].EventType)
		assert.Equal(t, editorUserID, *events[0].UserID, "LicensesAdded should have editor's user ID")
		assert.Equal(t, models.EventClosed, events[1].EventType)
		assert.Nil(t, events[1].UserID, "Closed should be bot (nil)")
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
		UserId:         1,
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
		UserId:       1,
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
		UserId:         1,
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
		UserId:       1,
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
		{"missing UserID", &proto.AddLicensesToOrganizationPolicyRequest{
			OrganizationId: 1,
			SpdxIds:        []string{newLicense},
			Context:        testhelpers.DistributedContext,
			UserId:         0,
		}, "user_id"},
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
		{"missing UserID", &proto.AddLicensesToEnterprisePolicyRequest{
			EnterpriseId: 1,
			SpdxIds:      []string{newLicense},
			Context:      testhelpers.DistributedContext,
			UserId:       0,
		}, "user_id"},
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
		UserId:         1,
	})
	assert.Nil(t, updateResponse)

	argumentName := "req.SpdxIds"
	cause := argumentName + " has invalid SPDX license identifiers"
	twcerrtesting.AssertInvalidSPDXIdentifiersErr(t, err, twirp.InvalidArgument, cause, []string{invalidLicense}, argumentName)
}

// TestAddLicenseToEnterprisePolicy_InvalidSPDXLicense tests that an invalid SPDX license
// is returned in failed_spdx_ids and a successful response is still returned.
func TestAddLicenseToEnterprisePolicy_InvalidSPDXLicense(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := testhelpers.RandomIDForDatabase()
	invalidLicense := "BAD-LICENSE"

	// Test
	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		SpdxIds:      []string{invalidLicense},
		Context:      testhelpers.DistributedContext,
		UserId:       1,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)
	assert.Equal(t, []string{invalidLicense}, updateResponse.FailedSpdxIds)
	assert.Nil(t, updateResponse.Policy)
}

// TestAddLicenseToEnterprisePolicy_MixedSPDXLicenses tests that valid SPDX IDs are added
// to the policy and invalid ones are returned in failed_spdx_ids.
func TestAddLicenseToEnterprisePolicy_MixedSPDXLicenses(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := testhelpers.RandomIDForDatabase()
	validLicense := "Apache-2.0"
	anotherValidLicense := "AAL"
	invalidLicense := "BAD-LICENSE"
	anotherInvalidLicense := "ANOTHER-BAD-LICENSE"

	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: enterpriseID,
		SpdxIds:      []string{validLicense, invalidLicense, anotherValidLicense, anotherInvalidLicense},
		Context:      testhelpers.DistributedContext,
		UserId:       1,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)
	require.Len(t, updateResponse.FailedSpdxIds, 2)
	assert.Equal(t, invalidLicense, updateResponse.FailedSpdxIds[0])
	assert.Equal(t, anotherInvalidLicense, updateResponse.FailedSpdxIds[1])
	require.NotNil(t, updateResponse.Policy)
	allowedLicenses := updateResponse.Policy.DistributionPolicies[0].Licenses.Allowed
	require.Len(t, allowedLicenses, 2)
	assert.Equal(t, validLicense, allowedLicenses[0].SpdxId)
	assert.Equal(t, anotherValidLicense, allowedLicenses[1].SpdxId)
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
		UserId:         1,
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
		UserId:       1,
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
	_, updateErr := server.app.Subsystems.Storage.UpsertEnterprisePolicy(t.Context(), enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
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
		default:
			t.Errorf("unexpected distribution context: %s", dp.Name)
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

func repositoryPolicyLicenseIDs(policy *proto.RepositoryPolicy) []string {
	if policy == nil || policy.Licenses == nil {
		return nil
	}
	ids := make([]string, 0, len(policy.Licenses.Allowed))
	for _, entry := range policy.Licenses.Allowed {
		if entry != nil {
			ids = append(ids, entry.SpdxId)
		}
	}
	return ids
}

func repositoryPolicyPackageNames(policy *proto.RepositoryPolicy) []string {
	if policy == nil {
		return nil
	}
	names := make([]string, 0, len(policy.Packages))
	for _, pkg := range policy.Packages {
		if pkg != nil {
			names = append(names, pkg.Name)
		}
	}
	return names
}

func seedRepositoryPolicy(t *testing.T, server *Server, repoID uint64, licenses []string, packages []*proto.PackagePolicy) {
	t.Helper()
	var policyLicenses *proto.PolicyLicenses
	if licenses != nil {
		allowed := make([]*proto.LicenseEntry, 0, len(licenses))
		for _, spdxID := range licenses {
			allowed = append(allowed, &proto.LicenseEntry{SpdxId: spdxID})
		}
		policyLicenses = &proto.PolicyLicenses{Allowed: allowed}
	}

	_, err := server.CreateRepositoryPolicy(t.Context(), &proto.CreateRepositoryPolicyRequest{
		RepositoryId: repoID,
		Licenses:     policyLicenses,
		Packages:     packages,
	})
	require.NoError(t, err)
}

func TestSaveRepositoryPolicy_MissingRequiredArguments(t *testing.T) {
	server := newTestServer(t)

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{})
	assert.Nil(t, res)
	assert.Equal(t, twirp.RequiredArgumentError("repository_id"), err)
}

func TestSaveRepositoryPolicy_InvalidArgument_NoUpdates(t *testing.T) {
	server := newTestServer(t)

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId: 1,
	})
	assert.Nil(t, res)
	assert.Equal(t, twirp.InvalidArgumentError("request", "must specify at least one update"), err)
}

func TestSaveRepositoryPolicy_PolicyDoesNotExist(t *testing.T) {
	server := newTestServer(t)

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId:  1,
		DeleteSpdxIds: []string{"MIT"},
	})
	assert.Nil(t, res)
	assert.Equal(t, twirp.NotFoundError("policy not found"), err)
}

func TestSaveRepositoryPolicy_DeleteLicenses(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()
	seedRepositoryPolicy(t, server, repoID, []string{"MIT", "Apache-2.0"}, nil)

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId:  repoID,
		DeleteSpdxIds: []string{"MIT"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.True(t, res.Success)

	getRes, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repoID})
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"Apache-2.0"}, repositoryPolicyLicenseIDs(getRes.Policy))
}

func TestSaveRepositoryPolicy_DeleteLicensesNotInPolicy(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()
	seedRepositoryPolicy(t, server, repoID, []string{"MIT"}, nil)

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId:  repoID,
		DeleteSpdxIds: []string{"Apache-2.0"},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.True(t, res.Success)

	getRes, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repoID})
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"MIT"}, repositoryPolicyLicenseIDs(getRes.Policy))
}

func TestSaveRepositoryPolicy_DeletePackages(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()
	seedRepositoryPolicy(t, server, repoID, nil, []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "react",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
	})

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId: repoID,
		DeletePackages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.True(t, res.Success)

	getRes, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repoID})
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"react"}, repositoryPolicyPackageNames(getRes.Policy))
}

func TestSaveRepositoryPolicy_DeletePackageNotInPolicy(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()
	seedRepositoryPolicy(t, server, repoID, nil, []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
	})

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId: repoID,
		DeletePackages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react"},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.True(t, res.Success)

	getRes, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repoID})
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"lodash"}, repositoryPolicyPackageNames(getRes.Policy))
}

func TestSaveRepositoryPolicy_DeleteLicensesAndPackages(t *testing.T) {
	server := newTestServer(t)
	repoID := testhelpers.RandomIDForDatabase()
	seedRepositoryPolicy(t, server, repoID, []string{"MIT", "Apache-2.0"}, []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "react",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
		},
	})

	res, err := server.SaveRepositoryPolicy(t.Context(), &proto.SaveRepositoryPolicyRequest{
		RepositoryId:  repoID,
		DeleteSpdxIds: []string{"MIT"},
		DeletePackages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash"},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.True(t, res.Success)

	getRes, err := server.GetRepositoryPolicy(t.Context(), &proto.GetRepositoryPolicyRequest{RepositoryId: repoID})
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"Apache-2.0"}, repositoryPolicyLicenseIDs(getRes.Policy))
	assert.ElementsMatch(t, []string{"react"}, repositoryPolicyPackageNames(getRes.Policy))
}

func TestAddLicensesToOrganizationPolicy_CaseInsensitiveDuplicates(t *testing.T) {
	server := newTestServer(t)
	orgID := testhelpers.RandomIDForDatabase()

	// Create policy with lowercase "mit"
	// NOTE: Even though this is added lowercase, it is saved uppercase by createDistributionPoliciesFromRequest
	// called from CreateOrganizationPolicy.  When AddLicensesToOrganizationPolicy is called later with "MIT",
	// it is a direct match because "mit" has already been normalized.
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
		UserId:         1,
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
		UserId:         1,
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

func TestAddLicensesToEnterprisePolicy_ComplexExpressionRejected(t *testing.T) {
	server := newTestServer(t)
	entID := testhelpers.RandomIDForDatabase()
	expLicenses := []string{"mit OR apache-2.0", "MIT OR Apache-2.0"}

	// Add complex expression with mixed case
	updateResponse, err := server.AddLicensesToEnterprisePolicy(t.Context(), &proto.AddLicensesToEnterprisePolicyRequest{
		EnterpriseId: entID,
		SpdxIds:      expLicenses,
		Context:      testhelpers.DistributedContext,
		UserId:       1,
	})
	require.NoError(t, err)
	require.NotNil(t, updateResponse)
	assert.ElementsMatch(t, expLicenses, updateResponse.FailedSpdxIds)
	assert.Nil(t, updateResponse.Policy)
}

func TestValidateLicenses(t *testing.T) {
	server := newTestServer(t)

	testCases := []struct {
		name       string
		input      []string
		normalized []string
		invalid    []string
	}{
		{
			name:       "already canonical case",
			input:      []string{"MIT"},
			normalized: []string{"MIT"},
			invalid:    []string{},
		},
		{
			name:       "lowercase license",
			input:      []string{"mit"},
			normalized: []string{"MIT"},
			invalid:    []string{},
		},
		{
			name:       "uppercase license",
			input:      []string{"MIT"},
			normalized: []string{"MIT"},
			invalid:    []string{},
		},
		{
			name:       "mixed case license",
			input:      []string{"MiT"},
			normalized: []string{"MIT"},
			invalid:    []string{},
		},
		{
			name:       "returns invalid ids",
			input:      []string{"MIT", "not-a-license"},
			normalized: []string{"MIT"},
			invalid:    []string{"not-a-license"},
		},
		{
			name:       "normalizes and dedups",
			input:      []string{"mit", "MIT", " Mit ", "bsd-3-clause"},
			normalized: []string{"MIT", "BSD-3-Clause"},
			invalid:    []string{},
		},
		{
			name:       "apache with version",
			input:      []string{"apache-2.0"},
			normalized: []string{"Apache-2.0"},
			invalid:    []string{},
		},
		{
			name:       "GPL with version",
			input:      []string{"gpl-3.0-only"},
			normalized: []string{"GPL-3.0-only"},
			invalid:    []string{},
		},
		{
			name:       "allows WITH exception",
			input:      []string{"apache-2.0 WITH llvm-exception"},
			normalized: []string{"Apache-2.0 WITH LLVM-exception"},
			invalid:    []string{},
		},
		{
			name:       "rejects complex expressions",
			input:      []string{"MIT OR Apache-2.0"},
			normalized: []string{},
			invalid:    []string{"MIT OR Apache-2.0"},
		},
		{
			name:       "allows LicenseRef",
			input:      []string{"LicenseRef-My-Custom-License"},
			normalized: []string{"LicenseRef-My-Custom-License"},
			invalid:    []string{},
		},
		{
			name:       "rejects invalid case for LicenseRef",
			input:      []string{"licenseref-custom"},
			normalized: []string{},
			invalid:    []string{"licenseref-custom"},
		},
		{
			name:       "rejects LicenseRef missing hyphen",
			input:      []string{"LicenseRefCustom"},
			normalized: []string{},
			invalid:    []string{"LicenseRefCustom"},
		},
		{
			name:       "should ignore, but rejects empty string",
			input:      []string{""},
			normalized: []string{},
			invalid:    []string{""},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			resp, err := server.ValidateLicenses(t.Context(), &proto.ValidateLicensesRequest{SpdxIds: tc.input})
			require.NoError(t, err)
			require.NotNil(t, resp)

			require.Equal(t, tc.normalized, resp.ValidSpdxIds, "Validation of %q should return as normalized %q but got %q", tc.input, tc.normalized, resp.ValidSpdxIds)
			require.Equal(t, tc.invalid, resp.InvalidSpdxIds, "Validation of %q should return as invalid %q but got %q", tc.input, tc.invalid, resp.InvalidSpdxIds)
		})
	}
}
