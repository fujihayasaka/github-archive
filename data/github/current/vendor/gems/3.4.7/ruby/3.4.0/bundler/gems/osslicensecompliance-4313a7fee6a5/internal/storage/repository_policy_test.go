package storage_test

import (
	"crypto/sha256"
	"encoding/json"
	"testing"
	"time"

	"github.com/github/osslicensecompliance/internal/models"
	olcstorage "github.com/github/osslicensecompliance/internal/storage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCreateRepositoryPolicy(t *testing.T) {
	storage := newAzBlobStorage(t)

	policy := &models.RepositoryRefinement{
		Licenses: models.LicenseList{
			Allowed: []models.LicenseEntry{{SpdxID: "GPL", Contexts: []string{"network", "internal"}}},
		},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "reason"},
			{PackageManager: models.PMgomod, PackageName: "github/golinter", Action: models.PackageActionBlock, Reason: "reason"},
			{PackageManager: models.PMrubygems, PackageName: "rubocop", Action: models.PackageActionPrivate, Reason: "reason"},
		},
	}

	repoID := randomIDForDatabase()
	organizationID := randomIDForDatabase()

	policyBytes, err := json.Marshal(policy)
	require.NoError(t, err)
	expectedHash := sha256.New()
	_, err = expectedHash.Write(policyBytes)
	require.NoError(t, err)

	insertedRepoPolicy, err := storage.CreateRepositoryPolicy(t.Context(), repoID, organizationID, policy)
	require.NoError(t, err)

	gotRepoPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
	require.NoError(t, err)

	assert.Equal(t, repoID, gotRepoPolicy.RepositoryID)
	assert.Equal(t, organizationID, gotRepoPolicy.OrganizationID)
	assert.Equal(t, policy, gotRepoPolicy.Policy)
	assert.Equal(t, expectedHash.Sum(nil), gotRepoPolicy.Hash)
	assert.ElementsMatch(t, policy.Licenses.Allowed, gotRepoPolicy.Policy.Licenses.Allowed)
	assert.Equal(t, insertedRepoPolicy.CreatedAt.UTC().UTC().Round(time.Second), gotRepoPolicy.CreatedAt.UTC().Round(time.Second))
}

func TestGetRepositoryPolicyByRepoID_ReturnsLastCreated(t *testing.T) {
	storage := newAzBlobStorage(t)
	repoID := randomIDForDatabase()

	firstPolicy := &models.RepositoryRefinement{
		Licenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}}},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "reason"},
		},
	}
	secondPolicy := &models.RepositoryRefinement{
		Licenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}}},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "react", Action: models.PackageActionAllow, Reason: "reason"},
		},
	}

	_, err := storage.CreateRepositoryPolicy(t.Context(), repoID, uint64(1), firstPolicy)
	require.NoError(t, err)

	_, err = storage.CreateRepositoryPolicy(t.Context(), repoID, uint64(1), secondPolicy)
	require.NoError(t, err)

	gotRepoPolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), repoID)
	require.NoError(t, err)
	assert.Equal(t, secondPolicy, gotRepoPolicy.Policy)
}

func TestGetRepositoryPolicy_NotFound(t *testing.T) {
	storage := newAzBlobStorage(t)

	licensePolicy, err := storage.GetRepositoryPolicyByRepoID(t.Context(), randomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}
