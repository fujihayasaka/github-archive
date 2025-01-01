package models_test

import (
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/stretchr/testify/assert"
)

var allDistributionContexts = []string{"distributed", "network", "internal"}

func policyWithLicenses(licenses []string) *models.Policy {
	allowed := make([]models.LicenseEntry, 0, len(licenses))
	for _, license := range licenses {
		allowed = append(allowed, models.LicenseEntry{SpdxID: license, Contexts: allDistributionContexts})
	}
	return &models.Policy{
		PolicyLicenses: models.LicenseList{
			Allowed: allowed,
		},
	}
}

func TestGetAllowList(t *testing.T) {
	policy := models.CompletePolicy{
		EnterprisePolicy: &models.EnterprisePolicy{
			Policy: policyWithLicenses([]string{"MIT"}),
		},
		OrganizationPolicy: &models.OrganizationPolicy{
			Policy: policyWithLicenses([]string{"BSD-2-Clause"}),
		},
		RepositoryPolicy: &models.RepositoryPolicy{
			Policy: &models.RepositoryRefinement{
				Licenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}},
				},
			},
		},
	}
	allowList := policy.GetAllowList("distributed")
	assert.Len(t, allowList, 3)
	assert.ElementsMatch(t, allowList, []string{"MIT", "BSD-2-Clause", "BSD-3-Clause"})

	// Test that the list is cached
	policy.OrganizationPolicy = nil
	allowList = policy.GetAllowList("distributed")
	assert.Len(t, allowList, 3, "expected the same number of elements despite changing it because of caching")

	policy = models.CompletePolicy{
		RepositoryPolicy: &models.RepositoryPolicy{
			Policy: &models.RepositoryRefinement{
				Licenses: models.LicenseList{
					Allowed: []models.LicenseEntry{{SpdxID: "BSD-3-Clause", Contexts: allDistributionContexts}},
				},
			},
		},
	}
	allowList = policy.GetAllowList("distributed")
	assert.Len(t, allowList, 1)
	assert.ElementsMatch(t, allowList, []string{"BSD-3-Clause"})
}
