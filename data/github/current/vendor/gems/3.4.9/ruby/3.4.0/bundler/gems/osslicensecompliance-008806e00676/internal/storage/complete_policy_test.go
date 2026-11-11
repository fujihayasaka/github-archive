package storage_test

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/models"
	olcstorage "github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/testhelpers"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetCompletePolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	policy := &proto.EnterprisePolicy{
		EnterpriseId:              testhelpers.RandomIDForDatabase(),
		CustomRemediationGuidance: "Just fix it (Enterprise Edition).",
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name:     "distributed",
				Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}},
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
				},
			},
		},
	}
	insertedEnterprisePolicy, err := storage.CreateEnterprisePolicy(t.Context(), policy)
	require.NoError(t, err)
	require.NotNil(t, insertedEnterprisePolicy)
	require.Equal(t, "Just fix it (Enterprise Edition).", insertedEnterprisePolicy.CustomRemediationGuidance)

	orgPolicy := &proto.OrganizationPolicy{
		OrganizationId:            testhelpers.RandomIDForDatabase(),
		CustomRemediationGuidance: "Just fix it.",
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name:     "distributed",
				Licenses: &proto.PolicyLicenses{Allowed: []*proto.LicenseEntry{{SpdxId: "MIT", Contexts: testhelpers.AllDistributionContexts}}},
				Packages: []*proto.PackagePolicy{
					{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
				},
			},
		},
	}
	insertedOrgPolicy, err := storage.CreateOrganizationPolicy(t.Context(), orgPolicy)
	require.NoError(t, err)
	require.NotNil(t, insertedOrgPolicy)
	require.Equal(t, "Just fix it.", insertedOrgPolicy.CustomRemediationGuidance)

	repoPolicy := &proto.RepositoryPolicy{
		RepositoryId: testhelpers.RandomIDForDatabase(),
		Packages: []*proto.PackagePolicy{
			{PackageManager: proto.PackageManager_PACKAGE_MANAGER_NPM, Name: "lodash", Action: proto.PackageAction_PACKAGE_ACTION_ALLOWED, Reason: "reason", Contexts: []string{"distributed"}},
		},
	}

	insertedRepoPolicy, err := storage.CreateRepositoryPolicy(t.Context(), repoPolicy)
	require.NoError(t, err)
	require.NotNil(t, insertedRepoPolicy)
	require.Nil(t, insertedRepoPolicy.Licenses)

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
			enterpriseID: insertedEnterprisePolicy.EnterpriseId,
			orgID:        insertedOrgPolicy.OrganizationId,
			repoID:       insertedRepoPolicy.RepositoryId,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   &models.EnterprisePolicy{Data: insertedEnterprisePolicy},
				OrganizationPolicy: &models.OrganizationPolicy{Data: insertedOrgPolicy},
				RepositoryPolicy:   &models.RepositoryPolicy{Data: insertedRepoPolicy},
			},
		},
		{
			name:         "complete policy returned with no enterprise policy when no enterpise policy exists",
			enterpriseID: insertedEnterprisePolicy.EnterpriseId + 1,
			orgID:        insertedOrgPolicy.OrganizationId,
			repoID:       insertedRepoPolicy.RepositoryId,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   nil,
				OrganizationPolicy: &models.OrganizationPolicy{Data: insertedOrgPolicy},
				RepositoryPolicy:   &models.RepositoryPolicy{Data: insertedRepoPolicy},
			},
		},
		{
			name:         "complete policy returned with no org policy when no org policy exists",
			enterpriseID: insertedEnterprisePolicy.EnterpriseId,
			orgID:        insertedOrgPolicy.OrganizationId + 1,
			repoID:       insertedRepoPolicy.RepositoryId,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   &models.EnterprisePolicy{Data: insertedEnterprisePolicy},
				OrganizationPolicy: nil,
				RepositoryPolicy:   &models.RepositoryPolicy{Data: insertedRepoPolicy},
			},
		},
		{
			name:         "complete policy returned with no repo policy when no repo policy exists",
			enterpriseID: insertedEnterprisePolicy.EnterpriseId,
			orgID:        insertedOrgPolicy.OrganizationId,
			repoID:       insertedRepoPolicy.RepositoryId + 1,
			expected: &models.CompletePolicy{
				EnterprisePolicy:   &models.EnterprisePolicy{Data: insertedEnterprisePolicy},
				OrganizationPolicy: &models.OrganizationPolicy{Data: insertedOrgPolicy},
				RepositoryPolicy:   nil,
			},
		},
		{
			name:         "not found error returned when no policies exist",
			enterpriseID: insertedEnterprisePolicy.EnterpriseId + 1,
			orgID:        insertedOrgPolicy.OrganizationId + 1,
			repoID:       insertedRepoPolicy.RepositoryId + 1,
			err:          olcstorage.ErrNotFound,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			gotPolicy, err := storage.GetCompletePolicy(t.Context(), tc.enterpriseID, tc.orgID, tc.repoID)
			assert.Equal(t, tc.err, err)
			assert.EqualExportedValues(t, tc.expected, gotPolicy)
		})
	}
}

func TestGetCompletePolicyFromPolicy(t *testing.T) {
	storage, err := olcstorage.NewNullStorage("", log.NewNullLogger())
	require.NoError(t, err)

	entPolicy := &proto.EnterprisePolicy{
		EnterpriseId: 1,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"MIT"}),
				},
			},
		},
	}

	insertedEntPolicy, err := storage.CreateEnterprisePolicy(t.Context(), entPolicy)
	require.NoError(t, err)
	require.NotNil(t, insertedEntPolicy)

	orgPolicy := &proto.OrganizationPolicy{
		OrganizationId: 2,
		DistributionPolicies: []*proto.DistributionPolicy{
			{
				Name: "distributed",
				Licenses: &proto.PolicyLicenses{
					Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-2-Clause"}),
				},
			},
		},
	}
	insertedOrgPolicy, err := storage.CreateOrganizationPolicy(t.Context(), orgPolicy)
	require.NoError(t, err)
	require.NotNil(t, insertedOrgPolicy)

	repoPolicy := &proto.RepositoryPolicy{
		RepositoryId: 3,
		Licenses: &proto.PolicyLicenses{
			Allowed: testhelpers.CreateLicenseEntriesWithAllContexts([]string{"BSD-3-Clause"}),
		},
	}
	insertedRepoPolicy, err := storage.CreateRepositoryPolicy(t.Context(), repoPolicy)
	require.NoError(t, err)
	require.NotNil(t, insertedRepoPolicy)

	completePolicy := models.NewCompletePolicy(insertedEntPolicy, insertedOrgPolicy, insertedRepoPolicy)

	// noPolicyInDatabase is a sentinel value to indicate that a test case should have no policy in the database
	noPolicyInDatabase := []string{"__NO_POLICY__"}

	testCases := []struct {
		name                          string
		newEnterprisePolicyLicenses   []string
		newOrganizationPolicyLicenses []string
		newRepositoryPolicyLicenses   []string
		expectedAllowedLicenses       []string
	}{
		{
			name:                          "all policies unchanged",
			newEnterprisePolicyLicenses:   nil,
			newOrganizationPolicyLicenses: nil,
			newRepositoryPolicyLicenses:   nil,
			expectedAllowedLicenses:       []string{"MIT", "BSD-2-Clause", "BSD-3-Clause"},
		},
		{
			name:                        "enterprise policy changed",
			newEnterprisePolicyLicenses: []string{"Apache-2.0"},
			expectedAllowedLicenses:     []string{"Apache-2.0", "BSD-2-Clause", "BSD-3-Clause"},
		},
		{
			name:                          "empty organization policy",
			newEnterprisePolicyLicenses:   nil,
			newOrganizationPolicyLicenses: []string{},
			newRepositoryPolicyLicenses:   nil,
			expectedAllowedLicenses:       []string{"MIT", "BSD-3-Clause"},
		},
		{
			name:                        "clear enterprise policy",
			newEnterprisePolicyLicenses: []string{},
			expectedAllowedLicenses:     []string{"BSD-2-Clause", "BSD-3-Clause"},
		},
		{
			name:                        "repository policy changed",
			newRepositoryPolicyLicenses: []string{"GPL-3.0"},
			expectedAllowedLicenses:     []string{"MIT", "BSD-2-Clause", "GPL-3.0"},
		},
		{
			name:                        "repository policy does not exist",
			newRepositoryPolicyLicenses: noPolicyInDatabase,
			expectedAllowedLicenses:     []string{"MIT", "BSD-2-Clause"},
		},
		{
			name:                          "all three policies changed",
			newEnterprisePolicyLicenses:   []string{"Apache-2.0"},
			newOrganizationPolicyLicenses: []string{"LGPL-3.0"},
			newRepositoryPolicyLicenses:   []string{"GPL-3.0"},
			expectedAllowedLicenses:       []string{"Apache-2.0", "LGPL-3.0", "GPL-3.0"},
		},
	}
	currentID := uint64(4)

	// getIDForPolicy figures out the entity ID to use for the policy in testing.
	// It returns the appropriate ID and a boolean indicating whether a new policy
	// should be created in the storage.
	getIDForPolicy := func(licenses []string, insertedID uint64) (uint64, bool) {
		if len(licenses) != 0 && licenses[0] == "__NO_POLICY__" {
			newID := currentID
			currentID++
			return newID, false
		}
		if licenses != nil {
			if len(licenses) == 0 {
				return 0, false
			}
			newID := currentID
			currentID++
			return newID, true
		}
		return insertedID, false
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			newEnterpriseID, createPolicy := getIDForPolicy(tc.newEnterprisePolicyLicenses, insertedEntPolicy.EnterpriseId)
			if createPolicy {
				newEnterpriseID = currentID
				currentID++
				newEntPolicy := &proto.EnterprisePolicy{
					EnterpriseId: newEnterpriseID,
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts(tc.newEnterprisePolicyLicenses),
							},
						},
					},
				}
				_, err := storage.CreateEnterprisePolicy(t.Context(), newEntPolicy)
				require.NoError(t, err)
			}

			newOrgID, createPolicy := getIDForPolicy(tc.newOrganizationPolicyLicenses, insertedOrgPolicy.OrganizationId)
			if createPolicy {
				newOrgID = currentID
				currentID++
				newOrgPolicy := &proto.OrganizationPolicy{
					OrganizationId: newOrgID,
					DistributionPolicies: []*proto.DistributionPolicy{
						{
							Name: "distributed",
							Licenses: &proto.PolicyLicenses{
								Allowed: testhelpers.CreateLicenseEntriesWithAllContexts(tc.newOrganizationPolicyLicenses),
							},
						},
					},
				}
				_, err := storage.CreateOrganizationPolicy(t.Context(), newOrgPolicy)
				require.NoError(t, err)
			}

			newRepoID, createPolicy := getIDForPolicy(tc.newRepositoryPolicyLicenses, insertedRepoPolicy.RepositoryId)

			if createPolicy {
				newRepoID = currentID
				currentID++
				newRepoPolicy := &proto.RepositoryPolicy{
					RepositoryId: newRepoID,
					Licenses: &proto.PolicyLicenses{
						Allowed: testhelpers.CreateLicenseEntriesWithAllContexts(tc.newRepositoryPolicyLicenses),
					},
				}
				_, err := storage.CreateRepositoryPolicy(t.Context(), newRepoPolicy)
				require.NoError(t, err)
			}

			gotCompletePolicy, err := storage.GetCompletePolicyFromPolicy(t.Context(), completePolicy, newEnterpriseID, newOrgID, newRepoID)
			require.NoError(t, err)
			assert.ElementsMatch(t, tc.expectedAllowedLicenses, gotCompletePolicy.GetAllowList("distributed"))
		})
	}
}
