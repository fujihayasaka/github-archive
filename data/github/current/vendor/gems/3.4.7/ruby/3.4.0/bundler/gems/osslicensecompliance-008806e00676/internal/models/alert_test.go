package models_test

import (
	"slices"
	"testing"

	"github.com/github/osslicensecompliance/internal/models"
	"github.com/github/osslicensecompliance/internal/pointers"
	"github.com/stretchr/testify/assert"
)

func TestAlertsByScope(t *testing.T) {
	enterprise1 := uint64(100)
	enterprise2 := uint64(200)

	alerts := []*models.Alert{
		{
			EnterpriseID:   &enterprise2,
			OrganizationID: 300,
			RepositoryID:   500,
		},
		{
			EnterpriseID:   &enterprise1,
			OrganizationID: 200,
			RepositoryID:   400,
		},
		{
			EnterpriseID:   &enterprise1,
			OrganizationID: 200,
			RepositoryID:   300,
		},
		{
			EnterpriseID:   &enterprise1,
			OrganizationID: 100,
			RepositoryID:   200,
		},
		{
			EnterpriseID:   nil,
			OrganizationID: 50,
			RepositoryID:   100,
		},
	}

	slices.SortFunc(alerts, models.CompareAlertsByScope)

	// nil enterprise IDs are treated as 0 and sorted first
	assert.Equal(t, uint64(0), pointers.ValueOrZero(alerts[0].EnterpriseID), "nil enterprise ID should be treated as 0")
	assert.Equal(t, uint64(50), alerts[0].OrganizationID)
	assert.Equal(t, uint64(100), alerts[0].RepositoryID)

	assert.Equal(t, enterprise1, pointers.ValueOrZero(alerts[1].EnterpriseID))
	assert.Equal(t, uint64(100), alerts[1].OrganizationID)
	assert.Equal(t, uint64(200), alerts[1].RepositoryID)

	assert.Equal(t, enterprise1, pointers.ValueOrZero(alerts[2].EnterpriseID))
	assert.Equal(t, uint64(200), alerts[2].OrganizationID)
	assert.Equal(t, uint64(300), alerts[2].RepositoryID)

	assert.Equal(t, enterprise1, pointers.ValueOrZero(alerts[3].EnterpriseID))
	assert.Equal(t, uint64(200), alerts[3].OrganizationID)
	assert.Equal(t, uint64(400), alerts[3].RepositoryID)

	assert.Equal(t, enterprise2, pointers.ValueOrZero(alerts[4].EnterpriseID))
	assert.Equal(t, uint64(300), alerts[4].OrganizationID)
	assert.Equal(t, uint64(500), alerts[4].RepositoryID)
}
