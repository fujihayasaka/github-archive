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

func TestCreateRepositoryPolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()

	policy := &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Licenses: &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{{SpdxId: "GPL", Contexts: []string{"network", "internal"}}},
		},
		Packages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD, Name: "github/golinter", Action: proto.PackageAction_PACKAGE_ACTION_BLOCKED, Reason: "reason", Contexts: []string{"distributed"}},
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, Name: "rubocop", Action: proto.PackageAction_PACKAGE_ACTION_PRIVATE, Reason: "reason", Contexts: []string{"distributed"}},
		},
	}

	insertedRepoPolicy, err := storage.CreateRepositoryPolicy(t.Context(), policy)
	require.NoError(t, err)

	gotRepoPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
	require.NoError(t, err)

	assert.Equal(t, repoID, gotRepoPolicy.RepositoryId)
	assert.EqualExportedValues(t, policy.Licenses, gotRepoPolicy.Licenses)
	assert.EqualExportedValues(t, policy.Packages, gotRepoPolicy.Packages)
	insertedTime := insertedRepoPolicy.CreatedAt.AsTime().UTC().Round(time.Second)
	gotTime := gotRepoPolicy.CreatedAt.AsTime().UTC().Round(time.Second)
	assert.Equal(t, insertedTime, gotTime)
}

func TestGetRepositoryPolicyByRepoID_ReturnsLastCreated(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()

	firstPolicy := &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Licenses:     &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}},
		Packages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
		},
	}
	secondPolicy := &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Licenses:     &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "BSD-3-Clause", Contexts: testhelpers.AllDistributionContexts}}},
		Packages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
		},
	}

	_, err = storage.CreateRepositoryPolicy(t.Context(), firstPolicy)
	require.NoError(t, err)

	_, err = storage.CreateRepositoryPolicy(t.Context(), secondPolicy)
	require.NoError(t, err)

	gotRepoPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
	require.NoError(t, err)
	assert.EqualExportedValues(t, secondPolicy, gotRepoPolicy)
}

func TestUpsertRepositoryPolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	t.Run("update existing policy", func(t *testing.T) {
		repoID := testhelpers.RandomIDForDatabase()

		initialPolicy := &proto.RepositoryPolicy{
			RepositoryId: repoID,
			Licenses:     &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "GPL", Contexts: []string{"network", "internal"}}}},
			Packages: []*proto.PackagePolicy{
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_GOMOD, Name: "github/golinter", Action: proto.PackageAction_PACKAGE_ACTION_BLOCKED, Reason: "reason", Contexts: []string{"distributed"}},
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS, Name: "rubocop", Action: proto.PackageAction_PACKAGE_ACTION_PRIVATE, Reason: "reason", Contexts: []string{"distributed"}},
			},
		}

		_, err = storage.CreateRepositoryPolicy(t.Context(), initialPolicy)
		require.NoError(t, err)

		called := false
		result, err := storage.UpsertRepositoryPolicy(t.Context(), repoID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
			called = true
			require.Len(t, policy.Packages, 3)
			policyCopy := olcstorage.ProtoCopy(policy)
			policyCopy.Packages = append(policyCopy.Packages, &proto.PackagePolicy{
				PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
				Name:           "org.apache.commons:commons-lang3",
				Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
				Reason:         "I feel like it",
				Contexts:       []string{"distributed"},
			})
			return policyCopy, nil
		})
		require.NoError(t, err)
		assert.True(t, called, "update function was not called")

		actualPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
		require.NoError(t, err)
		require.Len(t, actualPolicy.Packages, 4)
		assert.Equal(t, "org.apache.commons:commons-lang3", actualPolicy.Packages[3].Name)
		assert.Equal(t, result.Policy.CreatedAt.AsTime(), actualPolicy.CreatedAt.AsTime())
	})

	t.Run("create new policy when none exists", func(t *testing.T) {
		repoID := testhelpers.RandomIDForDatabase()

		called := false
		result, err := storage.UpsertRepositoryPolicy(t.Context(), repoID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
			called = true
			assert.Equal(t, repoID, policy.RepositoryId)
			assert.Nil(t, policy.Licenses)
			assert.Nil(t, policy.Packages)

			policyCopy := olcstorage.ProtoCopy(policy)
			policyCopy.Licenses = &proto.PolicyLicenses{
				Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}},
			}

			policyCopy.Packages = []*proto.PackagePolicy{
				{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "react", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "new policy", Contexts: []string{"distributed"}},
			}
			return policyCopy, nil
		})
		require.NoError(t, err)
		assert.True(t, called, "update function was not called")

		actualPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
		require.NoError(t, err)
		assert.Equal(t, repoID, actualPolicy.RepositoryId)
		require.Len(t, actualPolicy.Licenses.Allowed, 1)
		assert.Equal(t, "MIT", actualPolicy.Licenses.Allowed[0].SpdxId)
		require.Len(t, actualPolicy.Packages, 1)
		assert.Equal(t, "react", actualPolicy.Packages[0].Name)
		assert.Equal(t, result.Policy.CreatedAt.AsTime(), actualPolicy.CreatedAt.AsTime())
	})
}

func TestUpsertRepositoryPolicy_WasCreatedTrue(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()

	result, err := storage.UpsertRepositoryPolicy(t.Context(), repoID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		policyCopy := olcstorage.ProtoCopy(policy)
		policyCopy.Licenses = &proto.PolicyLicenses{
			Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: []string{"distributed"}}},
		}
		return policyCopy, nil
	})
	require.NoError(t, err)
	assert.True(t, result.WasCreated, "expected WasCreated to be true for new policy")
	assert.Equal(t, repoID, result.Policy.RepositoryId)
}

func TestUpsertRepositoryPolicy_WasCreatedFalse(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	repoID := testhelpers.RandomIDForDatabase()

	_, err = storage.CreateRepositoryPolicy(t.Context(), &proto.RepositoryPolicy{
		RepositoryId: repoID,
		Licenses:     &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: []string{"distributed"}}}},
	})
	require.NoError(t, err)

	result, err := storage.UpsertRepositoryPolicy(t.Context(), repoID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		policyCopy := olcstorage.ProtoCopy(policy)
		policyCopy.Licenses.Allowed = append(policyCopy.Licenses.Allowed, &proto.LicenseEntry{SpdxId: "Apache-2.0", Contexts: []string{"distributed"}})
		return policyCopy, nil
	})
	require.NoError(t, err)
	assert.False(t, result.WasCreated, "expected WasCreated to be false for existing policy")
	assert.Equal(t, repoID, result.Policy.RepositoryId)
}

func TestGetRepositoryPolicy_NotFound(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	licensePolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), testhelpers.RandomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}
