package models

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestAddIDs(t *testing.T) {
	e := NewCustomerLicenseEnablement(
		ProductEnablementTypeOrg,
		EnablementReasonOrgMembership,
		nil,
	)

	assert.True(t, e.IsEmpty())
	assert.True(t, e.AddIDs(100, 200))
	assert.ElementsMatch(t, []uint64{100, 200}, e.EnablementIDs)
	assert.False(t, e.AddIDs(100))
	assert.ElementsMatch(t, []uint64{100, 200}, e.EnablementIDs)
}

func TestRemoveIDs(t *testing.T) {
	e := NewCustomerLicenseEnablement(
		ProductEnablementTypeOrg,
		EnablementReasonOrgMembership,
		[]uint64{100, 200},
	)

	assert.False(t, e.IsEmpty())
	assert.False(t, e.RemoveIDs(300))
	assert.ElementsMatch(t, []uint64{100, 200}, e.EnablementIDs)
	assert.True(t, e.RemoveIDs(100, 200))
	assert.True(t, e.IsEmpty())
}
