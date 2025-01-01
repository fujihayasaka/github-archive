package storage_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	olcstorage "github.com/github/osslicensecompliance/internal/storage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var allDistributionContexts = []string{"distributed", "network", "internal"}

func TestGetCompletePolicy(t *testing.T) {
	storage := newAzBlobStorage(t)
	policy := &models.Policy{
		PolicyLicenses: models.LicenseList{Allowed: []models.LicenseEntry{{SpdxID: "MIT", Contexts: allDistributionContexts}}},
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "reason"},
		},
	}
	insertedEnterprisePolicy, err := storage.CreateEnterprisePolicy(t.Context(), randomIDForDatabase(), policy, "Just fix it (Enterprise Edition).")
	require.NoError(t, err)
	require.NotNil(t, insertedEnterprisePolicy)
	require.Equal(t, "Just fix it (Enterprise Edition).", insertedEnterprisePolicy.CustomRemediationGuidance)

	insertedOrgPolicy, err := storage.CreateOrganizationPolicy(t.Context(), randomIDForDatabase(), policy, "Just fix it.")
	require.NoError(t, err)
	require.NotNil(t, insertedOrgPolicy)
	require.Equal(t, "Just fix it.", insertedOrgPolicy.CustomRemediationGuidance)

	refinement := &models.RepositoryRefinement{
		Packages: []models.PackagePolicy{
			{PackageManager: models.PMnpm, PackageName: "lodash", Action: models.PackageActionAllow, Reason: "reason"},
		},
	}

	insertedRepoPolicy, err := storage.CreateRepositoryPolicy(t.Context(), randomIDForDatabase(), randomIDForDatabase(), refinement)
	require.NoError(t, err)
	require.NotNil(t, insertedRepoPolicy)

	testCases := []struct {
		name         string
		enterpriseID uint64
		orgID        uint64
		repoID       uint64
		expected     *models.CompletePolicy
		err          error
	}{
		{
			name:         "complete policy returned when all policies exist",
			enterpriseID: insertedEnterprisePolicy.EnterpriseID,
			orgID:        insertedOrgPolicy.OrganizationID,
			repoID:       insertedRepoPolicy.RepositoryID,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   insertedEnterprisePolicy,
				RepositoryPolicy:   insertedRepoPolicy,
				OrganizationPolicy: insertedOrgPolicy,
			},
		},
		{
			name:         "complete policy returned with no enterprise policy when no enterpise policy exists",
			enterpriseID: insertedEnterprisePolicy.EnterpriseID + 1,
			orgID:        insertedOrgPolicy.OrganizationID,
			repoID:       insertedRepoPolicy.RepositoryID,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   nil,
				OrganizationPolicy: insertedOrgPolicy,
				RepositoryPolicy:   insertedRepoPolicy,
			},
		},
		{
			name:         "complete policy returned with no org policy when no org policy exists",
			enterpriseID: insertedEnterprisePolicy.EnterpriseID,
			orgID:        insertedOrgPolicy.OrganizationID + 1,
			repoID:       insertedRepoPolicy.RepositoryID,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   insertedEnterprisePolicy,
				OrganizationPolicy: nil,
				RepositoryPolicy:   insertedRepoPolicy,
			},
		},
		{
			name:         "complete policy returned with no repo policy when no repo policy exists",
			enterpriseID: insertedEnterprisePolicy.EnterpriseID,
			orgID:        insertedOrgPolicy.OrganizationID,
			repoID:       insertedRepoPolicy.RepositoryID + 1,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   insertedEnterprisePolicy,
				OrganizationPolicy: insertedOrgPolicy,
				RepositoryPolicy:   nil,
			},
		},
		{
			name:         "not found error returned when no policies exist",
			enterpriseID: insertedEnterprisePolicy.EnterpriseID + 1,
			orgID:        insertedOrgPolicy.OrganizationID + 1,
			repoID:       insertedRepoPolicy.RepositoryID + 1,
			err:          olcstorage.ErrNotFound,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			gotPolicy, err := storage.GetCompletePolicy(t.Context(), tc.enterpriseID, tc.orgID, tc.repoID)
			assert.Equal(t, tc.err, err)
			assert.Equal(t, tc.expected, gotPolicy)
		})
	}
}
