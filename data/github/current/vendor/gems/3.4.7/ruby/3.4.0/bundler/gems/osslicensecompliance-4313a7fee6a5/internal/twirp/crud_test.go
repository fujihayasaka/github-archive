package twirp

import (
	"testing"

	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

var allDistributionContexts = []string{"distributed", "network", "internal"}

func TestCreateOrganizationPolicy(t *testing.T) {
	server := newTestServer(t)
	orgID := uint64(1)
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			MatchLicenses:  []string{"MIT"},
			Contexts:       allDistributionContexts,
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
	assert.Equal(t, licenses, response.Policy.Licenses)
	assert.Equal(t, packages, response.Policy.Packages)
	assert.Equal(t, createRequest.CustomRemediationGuidance, response.Policy.CustomRemediationGuidance)
}

func TestCreateOrganizationPolicy_DefaultUnspecifiedActionToBlocked(t *testing.T) {
	server := newTestServer(t)
	createRequest := &proto.CreateOrganizationPolicyRequest{
		OrganizationId: uint64(1),
		Licenses:       &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}}},
		Packages: []*proto.PackagePolicy{
			{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "lodash",
				Action:         proto.PackageAction_PACKAGE_ACTION_UNKNOWN,
				Reason:         "reason",
			},
		},
	}
	response, err := server.CreateOrganizationPolicy(t.Context(), createRequest)
	require.NoError(t, err)
	assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_BLOCKED, response.Policy.Packages[0].Action)
}

func TestGetOrganizationPolicy(t *testing.T) {
	server := newTestServer(t)
	orgID := 1
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}}}
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

	getRequest := &proto.GetOrganizationPolicyRequest{OrganizationId: uint64(orgID)}
	response, err := server.GetOrganizationPolicy(t.Context(), getRequest)
	require.NoError(t, err)
	assert.Equal(t, orgID, int(response.Policy.OrganizationId))
	assert.Equal(t, licenses, response.Policy.Licenses)
	assert.ElementsMatch(t, createResponse.Policy.Packages, response.Policy.Packages)
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
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}}}
	packages := []*proto.PackagePolicy{
		{
			PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
			Name:           "lodash",
			Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			Reason:         "reason",
			MatchLicenses:  []string{"MIT"},
			Contexts:       allDistributionContexts,
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
	assert.Equal(t, licenses, response.Policy.Licenses)
	assert.Equal(t, packages, response.Policy.Packages)
	assert.Equal(t, createRequest.CustomRemediationGuidance, response.Policy.CustomRemediationGuidance)
}

func TestGetEnterprisePolicy(t *testing.T) {
	server := newTestServer(t)
	enterpriseID := 1
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: allDistributionContexts}}}
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

	getRequest := &proto.GetEnterprisePolicyRequest{EnterpriseId: uint64(enterpriseID)}
	response, err := server.GetEnterprisePolicy(t.Context(), getRequest)
	require.NoError(t, err)
	assert.Equal(t, enterpriseID, int(response.Policy.EnterpriseId))
	assert.Equal(t, licenses, response.Policy.Licenses)
	assert.ElementsMatch(t, createResponse.Policy.Packages, response.Policy.Packages)
	assert.NotNil(t, response.Policy.CreatedAt)
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
			Contexts:       allDistributionContexts,
		},
	}
	repositoryLicenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "GPL-2.0", Contexts: allDistributionContexts}}}
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
			Contexts:       allDistributionContexts,
		},
	}
	repositoryLicenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "GPL-2.0", Contexts: allDistributionContexts}}}
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
	assert.Equal(t, repositoryLicenses, response.Policy.Licenses)
	assert.Equal(t, packages, response.Policy.Packages)
}

func TestGetRepositoryPolicy_NotFound(t *testing.T) {
	server := newTestServer(t)

	req := &proto.GetRepositoryPolicyRequest{RepositoryId: 1}
	res, err := server.GetRepositoryPolicy(t.Context(), req)
	assert.Nil(t, res)
	assert.Equal(t, twirp.NotFoundError("policy not found"), err)
}

func TestGetOrganizationPolicy_WithSubsetContexts(t *testing.T) {
	server := newTestServer(t)
	orgID := 2
	subsetContexts := []string{"network", "internal"}
	licenses := &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: subsetContexts}}}
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

	getRequest := &proto.GetOrganizationPolicyRequest{OrganizationId: uint64(orgID)}
	response, err := server.GetOrganizationPolicy(t.Context(), getRequest)
	require.NoError(t, err)
	assert.Equal(t, orgID, int(response.Policy.OrganizationId))
	assert.Equal(t, licenses, response.Policy.Licenses)
	assert.ElementsMatch(t, createResponse.Policy.Packages, response.Policy.Packages)
	assert.NotNil(t, response.Policy.CreatedAt)
}
