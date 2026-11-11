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

func TestUpdateRepositoryPolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

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
	updatedPolicy, err := storage.UpdateRepositoryPolicy(t.Context(), repoID, func(policy *proto.RepositoryPolicy) (*proto.RepositoryPolicy, error) {
		called = true
		assert.EqualExportedValues(t, initialPolicy, policy)
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
	expectedPolicy := olcstorage.ProtoCopy(initialPolicy)

	expectedPolicy.Packages = append(expectedPolicy.Packages, &proto.PackagePolicy{
		PackageManager: proto.PackageManager_PACKAGE_MANAGER_MAVEN,
		Name:           "org.apache.commons:commons-lang3",
		Action:         proto.PackageAction_PACKAGE_ACTION_ALLOWED,
		Reason:         "I feel like it",
		Contexts:       []string{"distributed"},
	})
	assert.True(t, called, "update function was not called")

	actualPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
	require.NoError(t, err)
	// Copy the CreatedAt so we can compare the rest of the struct
	expectedPolicy.CreatedAt = actualPolicy.CreatedAt
	assert.EqualExportedValues(t, expectedPolicy, actualPolicy)
	assert.EqualExportedValues(t, updatedPolicy, actualPolicy)
}

func TestGetRepositoryPolicy_NotFound(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	licensePolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), testhelpers.RandomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}
