package storage_test

import (
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	olcstorage "github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCreateOrganizationPolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	organizationID := testhelpers.RandomIDForDatabase()

	policy := &proto.OrganizationPolicy{
		OrganizationId: organizationID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
				},
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason"},
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD, Name: "github/golinter", Action: proto.PackageAction_PACKAGE_ACTION_BLOCKED, Reason: "reason"},
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, Name: "rubocop", Action: proto.PackageAction_PACKAGE_ACTION_PRIVATE, Reason: "reason"},
				},
			},
		},
		CustomRemediationGuidance: "Just fix it.",
	}

	insertedOrgPolicy, err := storage.CreateOrganizationPolicy(t.Context(), policy)
	require.NoError(t, err)
	require.Equal(t, "Just fix it.", insertedOrgPolicy.CustomRemediationGuidance)

	gotOrganizationPolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), organizationID)
	require.NoError(t, err)

	assert.Equal(t, organizationID, gotOrganizationPolicy.OrganizationId)

	require.Len(t, gotOrganizationPolicy.DistributionPolicies, 1)
	distributionPolicy := gotOrganizationPolicy.DistributionPolicies[0]
	assert.Equal(t, "distributed", distributionPolicy.Name)
	require.Len(t, distributionPolicy.Licenses.Allowed, 1)
	assert.Equal(t, "MIT", distributionPolicy.Licenses.Allowed[0].SpdxId)
	for _, pkgPolicy := range distributionPolicy.Packages {
		switch pkgPolicy.Name {
		case "lodash":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_ALLOWED, pkgPolicy.Action)
		case "github/golinter":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_BLOCKED, pkgPolicy.Action)
		case "rubocop":
			assert.Equal(t, proto.PackageAction_PACKAGE_ACTION_PRIVATE, pkgPolicy.Action)
		default:
			t.Errorf("unexpected package policy name: %s", pkgPolicy.Name)
		}
	}

	insertedTime := insertedOrgPolicy.CreatedAt.AsTime().UTC().Round(time.Second)
	gotTime := gotOrganizationPolicy.CreatedAt.AsTime().UTC().Round(time.Second)
	assert.Equal(t, insertedTime, gotTime)
}

func TestGetOrganizationPolicyByOrgID_ReturnsLastCreated(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)
	organizationID := testhelpers.RandomIDForDatabase()

	firstPolicy := &proto.OrganizationPolicy{
		OrganizationId: organizationID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
				},
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason"},
				},
			},
		},
		CustomRemediationGuidance: "First policy",
	}

	secondPolicy := &proto.OrganizationPolicy{
		OrganizationId: organizationID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{{SpdxId: "BSD-3-Clause"}},
				},
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason"},
				},
			},
		},
		CustomRemediationGuidance: "Second policy",
	}

	_, err = storage.CreateOrganizationPolicy(t.Context(), firstPolicy)
	require.NoError(t, err)

	_, err = storage.CreateOrganizationPolicy(t.Context(), secondPolicy)
	require.NoError(t, err)

	gotOrganizationPolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), organizationID)
	require.NoError(t, err)
	require.Len(t, gotOrganizationPolicy.DistributionPolicies, 1)
	assert.EqualExportedValues(t, secondPolicy, gotOrganizationPolicy)
	assert.Equal(t, "Second policy", gotOrganizationPolicy.CustomRemediationGuidance)
}

func TestGetOrganizationPolicy_NotFound(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	licensePolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), testhelpers.RandomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}

func TestUpdateOrganizationPolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	organizationID := testhelpers.RandomIDForDatabase()

	initialPolicy := &proto.OrganizationPolicy{
		OrganizationId: organizationID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}},
				},
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason"},
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD, Name: "github/golinter", Action: proto.PackageAction_PACKAGE_ACTION_BLOCKED, Reason: "reason"},
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, Name: "rubocop", Action: proto.PackageAction_PACKAGE_ACTION_PRIVATE, Reason: "reason"},
				},
			},
		},
	}

	_, err = storage.CreateOrganizationPolicy(t.Context(), initialPolicy)
	require.NoError(t, err)

	called := false
	updatedPolicy, err := storage.UpdateOrganizationPolicy(t.Context(), organizationID, func(policy *proto.OrganizationPolicy) (*proto.OrganizationPolicy, error) {
		called = true
		dp := policy.DistributionPolicies[0]
		assert.Len(t, dp.Licenses.Allowed, 1)
		policyCopy := olcstorage.ProtoCopy(policy)
		dp = policyCopy.DistributionPolicies[0]
		dp.Licenses.Allowed = append(dp.Licenses.Allowed, &proto.LicenseEntry{SpdxId: "Apache-2.0"})
		return policyCopy, nil
	})
	require.NoError(t, err)
	expectedPolicy := olcstorage.ProtoCopy(initialPolicy)
	dp := expectedPolicy.DistributionPolicies[0]
	dp.Licenses.Allowed = append(dp.Licenses.Allowed, &proto.LicenseEntry{SpdxId: "Apache-2.0"})

	assert.True(t, called, "update function was not called")

	actualPolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), organizationID)
	require.NoError(t, err)
	// Copy the CreatedAt so we can compare the rest of the struct
	expectedPolicy.CreatedAt = actualPolicy.CreatedAt
	assert.EqualExportedValues(t, expectedPolicy, actualPolicy)
	assert.EqualExportedValues(t, updatedPolicy, actualPolicy)

	dp = actualPolicy.DistributionPolicies[0]
	allowedLicenses := dp.Licenses.Allowed
	assert.Len(t, allowedLicenses, 2)
	assert.Equal(t, "MIT", allowedLicenses[0].SpdxId)
	assert.Equal(t, "Apache-2.0", allowedLicenses[1].SpdxId)
}
