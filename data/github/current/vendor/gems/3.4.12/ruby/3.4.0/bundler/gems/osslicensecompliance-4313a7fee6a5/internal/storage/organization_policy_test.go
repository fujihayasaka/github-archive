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

func TestCreateOrganizationPolicy(t *testing.T) {
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

	organizationID := randomIDForDatabase()

	policyBytes, err := json.Marshal(policy)
	require.NoError(t, err)
	expectedHash := sha256.New()
	_, err = expectedHash.Write(policyBytes)
	require.NoError(t, err)

	insertedOrgPolicy, err := storage.CreateOrganizationPolicy(t.Context(), organizationID, policy, "Just fix it.")
	require.NoError(t, err)
	require.Equal(t, "Just fix it.", insertedOrgPolicy.CustomRemediationGuidance)

	gotOrganizationPolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), organizationID)
	require.NoError(t, err)

	assert.Equal(t, organizationID, gotOrganizationPolicy.OrganizationID)
	assert.Equal(t, policy, gotOrganizationPolicy.Policy)
	assert.Equal(t, expectedHash.Sum(nil), gotOrganizationPolicy.Hash)
	assert.ElementsMatch(t, policy.PolicyLicenses.Allowed, gotOrganizationPolicy.Policy.PolicyLicenses.Allowed)
	assert.Equal(t, insertedOrgPolicy.CreatedAt.UTC().UTC().Round(time.Second), gotOrganizationPolicy.CreatedAt.UTC().Round(time.Second))
}

func TestGetOrganizationPolicyByOrgID_ReturnsLastCreated(t *testing.T) {
	storage := newAzBlobStorage(t)
	organizationID := randomIDForDatabase()

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

	_, err := storage.CreateOrganizationPolicy(t.Context(), organizationID, firstPolicy, "First policy")
	require.NoError(t, err)

	_, err = storage.CreateOrganizationPolicy(t.Context(), organizationID, secondPolicy, "Second policy")
	require.NoError(t, err)

	gotOrganizationPolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), organizationID)
	require.NoError(t, err)
	assert.Equal(t, secondPolicy, gotOrganizationPolicy.Policy)
	assert.ElementsMatch(t, secondPolicy.PolicyLicenses.Allowed, gotOrganizationPolicy.Policy.PolicyLicenses.Allowed)
	assert.Equal(t, "Second policy", gotOrganizationPolicy.CustomRemediationGuidance)
}

func TestGetOrganizationPolicy_NotFound(t *testing.T) {
	storage := newAzBlobStorage(t)

	licensePolicy, err := storage.GetOrganizationPolicyByOrgID(t.Context(), randomIDForDatabase())

	assert.Nil(t, licensePolicy)
	assert.ErrorIs(t, err, olcstorage.ErrNotFound)
}
