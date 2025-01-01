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

func TestCreateEnterprisePolicy(t *testing.T) {
	storage := newAzBlobStorage(t)

	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{
			Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
		},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "reason"},
			{PackageManager: models.PMgomod, PackageName: "github/golinter", Action: models.PackageActionBlock, Reason: "reason"},
			{PackageManager: models.PMrubygems, PackageName: "rubocop", Action: models.PackageActionPrivate, Reason: "reason"},
		},
	}

	enterpriseID := randomIDForDatabase()

	policyBytes, err := json.Marshal(policy)
	require.NoError(t, err)
	expectedHash := sha256.New()
	_, err = expectedHash.Write(policyBytes)
	require.NoError(t, err)

	insertedEnterprisePolicy, err := storage.CreateEnterprisePolicy(t.Context(), enterpriseID, policy, "Just fix it (Enterprise Edition).")
	require.NoError(t, err)
	require.Equal(t, "Just fix it (Enterprise Edition).", insertedEnterprisePolicy.CustomRemediationGuidance)

	gotEnterprisePolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), enterpriseID)
	require.NoError(t, err)

	assert.Equal(t, enterpriseID, gotEnterprisePolicy.EnterpriseID)
	assert.Equal(t, policy, gotEnterprisePolicy.Policy)
	assert.Equal(t, expectedHash.Sum(nil), gotEnterprisePolicy.Hash)
	assert.ElementsMatch(t, policy.PolicyLicenses.Allowed, gotEnterprisePolicy.Policy.PolicyLicenses.Allowed)
	assert.Equal(t, insertedEnterprisePolicy.CreatedAt.UTC().UTC().Round(time.Second), gotEnterprisePolicy.CreatedAt.UTC().Round(time.Second))
}

func TestGetEnterprisePolicyByEnterpriseID_ReturnsLastCreated(t *testing.T) {
	storage := newAzBlobStorage(t)
	enterpriseID := randomIDForDatabase()

	firstPolicy := &models.Policy{
		PolicyLicenses: models.LicenseList{
			Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}},
		},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "reason"},
		},
	}

	secondPolicy := &models.Policy{
		PolicyLicenses: models.LicenseList{
			Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}},
		},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "react", Action: models.PackageActionAllow, Reason: "reason"},
		},
	}

	_, err := storage.CreateEnterprisePolicy(t.Context(), enterpriseID, firstPolicy, "First policy.")
	require.NoError(t, err)

	_, err = storage.CreateEnterprisePolicy(t.Context(), enterpriseID, secondPolicy, "Second policy.")
	require.NoError(t, err)

	gotEnterprisePolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), enterpriseID)
	require.NoError(t, err)
	assert.Equal(t, secondPolicy, gotEnterprisePolicy.Policy)
	assert.ElementsMatch(t, secondPolicy.PolicyLicenses.Allowed, gotEnterprisePolicy.Policy.PolicyLicenses.Allowed)
	assert.Equal(t, "Second policy.", gotEnterprisePolicy.CustomRemediationGuidance)
}

func TestGetEnterprisePolicyByEnterpriseID_NotFound(t *testing.T) {
	storage := newAzBlobStorage(t)

	licensePolicy, err := storage.GetEnterprisePolicyByEnterpriseID(t.Context(), randomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}
