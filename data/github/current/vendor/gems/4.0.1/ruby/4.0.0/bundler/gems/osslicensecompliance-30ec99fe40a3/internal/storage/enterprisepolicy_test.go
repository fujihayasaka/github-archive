package storage_test

import (
	"strconv"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/models"
	olcstorage "github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	goproto "google.golang.org/protobuf/proto"
)

func TestCreateEnterprisePolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	enterpriseID := testhelpers.RandomIDForDatabase()

	policy := &proto.EnterprisePolicy{
		EnterpriseId: enterpriseID,
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
		CustomRemediationGuidance: "Just fix it (Enterprise Edition).",
	}

	insertedEnterprisePolicy, err := storage.CreateEnterprisePolicy(t.Context(), policy)
	require.NoError(t, err)
	require.Equal(t, "Just fix it (Enterprise Edition).", insertedEnterprisePolicy.CustomRemediationGuidance)

	gotEnterprisePolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), enterpriseID)
	require.NoError(t, err)

	assert.Equal(t, enterpriseID, gotEnterprisePolicy.EnterpriseId)
	assert.Len(t, gotEnterprisePolicy.DistributionPolicies, 1)
	distributedPolicy := gotEnterprisePolicy.DistributionPolicies[0]
	assert.Equal(t, "distributed", distributedPolicy.Name)
	assert.EqualExportedValues(t, policy.DistributionPolicies[0].Licenses, distributedPolicy.Licenses)
	assert.EqualExportedValues(t, policy.DistributionPolicies[0].Packages, distributedPolicy.Packages)
	insertedTime := insertedEnterprisePolicy.CreatedAt.AsTime().UTC().Round(time.Second)
	gotTime := gotEnterprisePolicy.CreatedAt.AsTime().UTC().Round(time.Second)
	assert.Equal(t, insertedTime, gotTime)
}

func TestGetEnterprisePolicyByEnterpriseID_ReturnsLastCreated(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)
	enterpriseID := testhelpers.RandomIDForDatabase()

	firstPolicy := &proto.EnterprisePolicy{
		EnterpriseId: enterpriseID,
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
		CustomRemediationGuidance: "First policy.",
	}

	secondPolicy := &proto.EnterprisePolicy{
		EnterpriseId: enterpriseID,
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
		CustomRemediationGuidance: "Second policy.",
	}

	_, err = storage.CreateEnterprisePolicy(t.Context(), firstPolicy)
	require.NoError(t, err)

	_, err = storage.CreateEnterprisePolicy(t.Context(), secondPolicy)
	require.NoError(t, err)

	gotEnterprisePolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), enterpriseID)
	require.NoError(t, err)
	assert.EqualExportedValues(t, secondPolicy, gotEnterprisePolicy)
	assert.EqualExportedValues(t, secondPolicy.DistributionPolicies[0].Licenses.Allowed, gotEnterprisePolicy.DistributionPolicies[0].Licenses.Allowed)
	assert.Equal(t, "Second policy.", gotEnterprisePolicy.CustomRemediationGuidance)
}

func TestGetEnterprisePolicyByEnterpriseID_NotFound(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	licensePolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), testhelpers.RandomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}

func TestUpsertEnterprisePolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	t.Run("update existing policy", func(t *testing.T) {
		enterpriseID := testhelpers.RandomIDForDatabase()

		initialPolicy := &proto.EnterprisePolicy{
			EnterpriseId: enterpriseID,
			DistributionPolicies: []*proto.DistributionPolicy{
				{
					Name: "distributed",
					Licenses: &proto.PolicyLicenses{
						Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}},
					},
					Packages: []*proto.PackagePolicy{
						{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
						{PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD, Name: "github/golinter", Action: proto.PackageAction_PACKAGE_ACTION_BLOCKED, Reason: "reason", Contexts: []string{"distributed"}},
						{PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, Name: "rubocop", Action: proto.PackageAction_PACKAGE_ACTION_PRIVATE, Reason: "reason", Contexts: []string{"distributed"}},
					},
				},
			},
			CustomRemediationGuidance: "Just fix it.",
		}

		_, err = storage.CreateEnterprisePolicy(t.Context(), initialPolicy)
		require.NoError(t, err)

		called := false
		result, err := storage.UpsertEnterprisePolicy(t.Context(), enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
			called = true
			assert.Len(t, policy.DistributionPolicies[0].Licenses.Allowed, 1)
			policyCopy := olcstorage.ProtoCopy(policy)
			policyCopy.DistributionPolicies[0].Licenses.Allowed = append(policyCopy.DistributionPolicies[0].Licenses.Allowed, &proto.LicenseEntry{SpdxId: "Apache-2.0", Contexts: testhelpers.AllDistributionContexts})
			return policyCopy, nil
		})
		require.NoError(t, err)
		expectedPolicy := olcstorage.ProtoCopy(initialPolicy)
		expectedPolicy.DistributionPolicies[0].Licenses.Allowed = append(expectedPolicy.DistributionPolicies[0].Licenses.Allowed, &proto.LicenseEntry{SpdxId: "Apache-2.0", Contexts: testhelpers.AllDistributionContexts})

		assert.True(t, called, "update function was not called")

		actualPolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), enterpriseID)
		require.NoError(t, err)
		// Copy the CreatedAt so we can compare the rest of the struct
		expectedPolicy.CreatedAt = actualPolicy.CreatedAt
		assert.EqualExportedValues(t, expectedPolicy, actualPolicy)
		assert.EqualExportedValues(t, result.Policy, actualPolicy)

		allowedLicenses := actualPolicy.DistributionPolicies[0].Licenses.Allowed
		assert.Len(t, allowedLicenses, 2)
		assert.Equal(t, "MIT", allowedLicenses[0].SpdxId)
		assert.Equal(t, "Apache-2.0", allowedLicenses[1].SpdxId)
	})

	t.Run("create new policy when none exists", func(t *testing.T) {
		enterpriseID := testhelpers.RandomIDForDatabase()
		called := false
		result, err := storage.UpsertEnterprisePolicy(t.Context(), enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
			called = true
			policyCopy := olcstorage.ProtoCopy(policy)
			distributionPolicies := models.AddLicensesToPolicy(policyCopy, []string{"MIT", "Apache-2.0"}, []string{"distributed"})
			policyCopy.DistributionPolicies = distributionPolicies

			packagePolicy := &proto.PackagePolicy{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM,
				Name:           "example-package",
				Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
			}
			policyCopy.DistributionPolicies = models.AddPackageToPolicy(policyCopy, packagePolicy, []string{"distributed"})

			return policyCopy, nil
		})

		require.NoError(t, err)
		assert.True(t, called, "update function was not called")

		actualPolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), enterpriseID)
		require.NoError(t, err)
		assert.Equal(t, enterpriseID, actualPolicy.EnterpriseId)
		require.Len(t, actualPolicy.DistributionPolicies, 1)
		assert.Equal(t, "MIT", actualPolicy.DistributionPolicies[0].Licenses.Allowed[0].SpdxId)
		assert.Equal(t, "Apache-2.0", actualPolicy.DistributionPolicies[0].Licenses.Allowed[1].SpdxId)
		assert.Equal(t, "example-package", actualPolicy.DistributionPolicies[0].Packages[0].Name)
		assert.Equal(t, result.Policy.CreatedAt.AsTime(), actualPolicy.CreatedAt.AsTime())
	})
}

func TestUpsertEnterprisePolicy_WasCreatedTrue(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	enterpriseID := testhelpers.RandomIDForDatabase()

	result, err := storage.UpsertEnterprisePolicy(t.Context(), enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		policyCopy := olcstorage.ProtoCopy(policy)
		policyCopy.DistributionPolicies = models.AddLicensesToPolicy(policyCopy, []string{"MIT"}, []string{"distributed"})
		return policyCopy, nil
	})
	require.NoError(t, err)
	assert.True(t, result.WasCreated, "expected WasCreated to be true for new policy")
	assert.Equal(t, enterpriseID, result.Policy.EnterpriseId)
}

func TestUpsertEnterprisePolicy_WasCreatedFalse(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	enterpriseID := testhelpers.RandomIDForDatabase()

	_, err = storage.CreateEnterprisePolicy(t.Context(), &proto.EnterprisePolicy{
		EnterpriseId: enterpriseID,
		DistributionPolicies: []*proto.DistributionPolicy{
			{Name: "distributed", Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT"}}}},
		},
	})
	require.NoError(t, err)

	result, err := storage.UpsertEnterprisePolicy(t.Context(), enterpriseID, func(policy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		policyCopy := olcstorage.ProtoCopy(policy)
		policyCopy.DistributionPolicies = models.AddLicensesToPolicy(policyCopy, []string{"Apache-2.0"}, []string{"distributed"})
		return policyCopy, nil
	})
	require.NoError(t, err)
	assert.False(t, result.WasCreated, "expected WasCreated to be false for existing policy")
	assert.Equal(t, enterpriseID, result.Policy.EnterpriseId)
}

func getOldStylePolicy() *proto.EnterprisePolicy {
	enterpriseID := testhelpers.RandomIDForDatabase()
	return &proto.EnterprisePolicy{
		EnterpriseId: enterpriseID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}},
		},
		Packages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed", "network"}},
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD, Name: "github/golinter", Action: proto.PackageAction_PACKAGE_ACTION_BLOCKED, Reason: "reason", Contexts: testhelpers.AllDistributionContexts},
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, Name: "rubocop", Action: proto.PackageAction_PACKAGE_ACTION_PRIVATE, Reason: "reason", Contexts: testhelpers.AllDistributionContexts},
		},
		CustomRemediationGuidance: "Just fix it (Enterprise Edition).",
	}
}

func TestUpgradeEnterprisePolicyInCreate(t *testing.T) {
	r := require.New(t)
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	r.NoError(err)

	policy := getOldStylePolicy()

	insertedEnterprisePolicy, err := storage.CreateEnterprisePolicy(t.Context(), policy)
	r.NoError(err)

	r.NotNil(insertedEnterprisePolicy.Licenses, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	r.NotNil(insertedEnterprisePolicy.Packages, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	r.NotNil(insertedEnterprisePolicy.DistributionPolicies)
	distributionPolicy := insertedEnterprisePolicy.DistributionPolicies[0]
	r.Len(distributionPolicy.Licenses.Allowed, 1)
	r.Len(distributionPolicy.Packages, 3)
}

func TestUpgradeEnterprisePolicyInGet(t *testing.T) {
	r := require.New(t)
	entBucket := olcstorage.NewNullBucket()
	storage, err := olcstorage.NewNullStorageWithBuckets("", nil, nil, entBucket, log.NewNullLogger())
	r.NoError(err)

	policy := getOldStylePolicy()

	key := strconv.FormatUint(policy.EnterpriseId, 10)
	data, err := goproto.Marshal(policy)
	r.NoError(err)

	err = entBucket.WriteAll(t.Context(), key, data, nil)
	r.NoError(err)

	gotPolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), policy.EnterpriseId)
	r.NoError(err)

	r.NotNil(gotPolicy.Licenses, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	r.NotNil(gotPolicy.Packages, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	r.NotNil(gotPolicy.DistributionPolicies)
	distributionPolicy := gotPolicy.DistributionPolicies[0]
	r.Len(distributionPolicy.Licenses.Allowed, 1)
	r.Len(distributionPolicy.Packages, 3)
}

func TestUpgradeEnterprisePolicyInUpdate(t *testing.T) {
	r := require.New(t)
	entBucket := olcstorage.NewNullBucket()
	storage, err := olcstorage.NewNullStorageWithBuckets("", nil, nil, entBucket, log.NewNullLogger())
	r.NoError(err)

	policy := getOldStylePolicy()

	key := strconv.FormatUint(policy.EnterpriseId, 10)
	data, err := goproto.Marshal(policy)
	r.NoError(err)

	err = entBucket.WriteAll(t.Context(), key, data, nil)
	r.NoError(err)

	result, err := storage.UpsertEnterprisePolicy(t.Context(), policy.EnterpriseId, func(oldPolicy *proto.EnterprisePolicy) (*proto.EnterprisePolicy, error) {
		r.NotNil(oldPolicy.Licenses, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
		r.NotNil(oldPolicy.Packages, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
		r.NotNil(oldPolicy.DistributionPolicies)
		distributionPolicy := oldPolicy.DistributionPolicies[0]
		r.Len(distributionPolicy.Licenses.Allowed, 1)
		r.Len(distributionPolicy.Packages, 3)
		return oldPolicy, nil
	})
	r.NoError(err)
	r.NotNil(result.Policy.Licenses, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	r.NotNil(result.Policy.Packages, "old field kept in case we need to roll back") //nolint:staticcheck // SA1019: accessing deprecated field during upgrade
	r.NotNil(result.Policy.DistributionPolicies)
	distributionPolicy := result.Policy.DistributionPolicies[0]
	r.Len(distributionPolicy.Licenses.Allowed, 1)
	r.Len(distributionPolicy.Packages, 3)
}
