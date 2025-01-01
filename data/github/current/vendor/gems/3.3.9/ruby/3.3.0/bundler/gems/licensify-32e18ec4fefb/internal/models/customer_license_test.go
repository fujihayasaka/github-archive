package models

import (
	"encoding/json"
	"fmt"
	"strconv"
	"testing"
	"time"

	"github.com/github/licensify/lib/globalid"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCustomerLicenseToProto(t *testing.T) {
	customerID := uint64(1)
	product := ProductSDLC
	status := LicenseStatusActive
	globalID := &globalid.GlobalID{
		App:       "test-app",
		ModelName: "test-model",
		ModelID:   "1",
	}
	licenseeID := "2"
	suspendedAt := int64(1728675888)

	customerLicense := &CustomerLicense{
		Key:           NewCustomerLicenseKey(customerID, product, LicenseeTypeUser, licenseeID),
		CustomerID:    customerID,
		Product:       product,
		LicenseStatus: status,
		Licensee: &Licensee{
			Type:     LicenseeTypeUser,
			ID:       licenseeID,
			GlobalID: globalID,
		},
		Enablements: []*CustomerLicenseEnablement{
			{
				Type:          ProductEnablementTypeOrg,
				Reason:        EnablementReasonOrgMembership,
				EnablementIDs: []uint64{1, 2, 3},
			},
		},
		ExpiresAt:   time.Now().Add(time.Hour * 24 * 30).Unix(),
		SuspendedAt: &suspendedAt,
	}

	proto := customerLicense.ToProto()

	assert.Equal(t, customerID, proto.CustomerId)
	assert.Equal(t, product.ToProto(), proto.Product)
	assert.Equal(t, LicenseeTypeUser.ToProto(), proto.Licensee.Type)
	//nolint:staticcheck // Use IdDeprecated for backward compatibility
	assert.Equal(t, licenseeID, strconv.FormatUint(proto.Licensee.IdDeprecated, 10))
	assert.Equal(t, globalID.String(), proto.Licensee.GlobalId)
	assert.Equal(t, suspendedAt, proto.SuspendedAt.AsTime().Unix())
	assert.Len(t, proto.Enablements, len(customerLicense.Enablements))
	for i, target := range proto.Enablements {
		assert.Equal(t, customerLicense.Enablements[i].Type.ToProto(), target.Type)
		assert.Equal(t, customerLicense.Enablements[i].Reason.ToProto(), target.Reason)
		assert.ElementsMatch(t, customerLicense.Enablements[i].EnablementIDs, target.EnablementIds)
	}
}

func TestCustomerLicenseMarshalJSONValidInputs(t *testing.T) {
	ttl := int64(100)
	suspendedAt := int64(1728675888)
	tests := []struct {
		name           string
		product        Product
		licenseStatus  LicenseStatus
		licenseeType   LicenseeType
		enablementType ProductEnablementType
		ttl            *int64
	}{
		{
			name:           "no ttl",
			product:        ProductGhas,
			licenseStatus:  LicenseStatusActive,
			licenseeType:   LicenseeTypeUser,
			enablementType: ProductEnablementTypeOrg,
			ttl:            nil,
		},
		{
			name:           "with ttl",
			product:        ProductSDLC,
			licenseStatus:  LicenseStatusDeactivated,
			licenseeType:   LicenseeTypeUser,
			enablementType: ProductEnablementTypeOrg,
			ttl:            &ttl,
		},
		{
			name:           "No status",
			product:        ProductSDLC,
			licenseeType:   LicenseeTypeUser,
			enablementType: ProductEnablementTypeOrg,
			ttl:            &ttl,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			model := &CustomerLicense{
				Key:           NewCustomerLicenseKey(1, tt.product, tt.licenseeType, "2"),
				CustomerID:    1,
				Product:       tt.product,
				LicenseStatus: tt.licenseStatus,
				Licensee: &Licensee{
					Type: tt.licenseeType,
					ID:   "2",
					GlobalID: &globalid.GlobalID{
						App:       "test-app",
						ModelName: "test-model",
						ModelID:   "1",
					},
				},
				Enablements: []*CustomerLicenseEnablement{
					{
						Type:          tt.enablementType,
						Reason:        EnablementReasonOrgMembership,
						EnablementIDs: []uint64{1, 2, 3},
					},
				},
				ExpiresAt:   1611316800,
				SuspendedAt: &suspendedAt,
			}
			if tt.ttl != nil {
				model.TTL = tt.ttl
			}

			marshalled, err := json.Marshal(model)

			require.NoError(t, err)

			var unmarshalled CustomerLicense
			err = json.Unmarshal(marshalled, &unmarshalled)

			require.NoError(t, err)
			assert.Equal(t, model, &unmarshalled)
			assert.Equal(t, tt.ttl, unmarshalled.TTL)
		})
	}
}

func TestCustomerLicenseUnmarshalJSONwithInvalidInputs(t *testing.T) {
	tests := []struct {
		name             string
		product          string
		status           string
		licenseeType     string
		enablementType   string
		enablementReason string
		licenseeGID      string
	}{
		{
			name:             "invalid Licensee",
			product:          ProductSDLC.String(),
			status:           LicenseStatusActive.String(),
			licenseeType:     "invalid",
			enablementType:   ProductEnablementTypeOrg.String(),
			enablementReason: EnablementReasonOrgMembership.String(),
			licenseeGID:      "gid://git-hub/User/2",
		},
		{
			name:             "invalid EnablementReason",
			product:          ProductSDLC.String(),
			status:           LicenseStatusActive.String(),
			licenseeType:     LicenseeTypeUser.String(),
			enablementType:   ProductEnablementTypeOrg.String(),
			enablementReason: "invalid",
			licenseeGID:      "gid://git-hub/User/2",
		},
		{
			name:             "globalId scheme requires an app name",
			product:          ProductSDLC.String(),
			status:           LicenseStatusActive.String(),
			licenseeType:     LicenseeTypeUser.String(),
			enablementType:   ProductEnablementTypeOrg.String(),
			enablementReason: "invalid",
			licenseeGID:      "gid:///User/2",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := []byte(`{"type":"CustomerLicense","id":"sdlc:user:2","customerId":1,"product":"` + tt.product + `","licensee":{"type":"` + tt.licenseeType + `","id":2,"globalId":"` + tt.licenseeGID + `"},"enablements":[{"type":"` + tt.enablementType + `","reason":"` + tt.enablementReason + `","enablementIds":[1,2]}],"expiresAt":1611316800}`)

			var customerLicense CustomerLicense
			err := json.Unmarshal(data, &customerLicense)

			require.Error(t, err)
			assert.ErrorContains(t, err, tt.name)
		})
	}
}

func TestNewCustomerLicenseSetsCorrectKey(t *testing.T) {
	proto := stubs.NewCustomerLicenseProto()
	cl := NewCustomerLicenseFromProto(proto)

	//nolint:staticcheck // Use IdDeprecated for backward compatibility
	wantID := fmt.Sprintf("%s:%d", LicenseeType(proto.Licensee.Type), proto.Licensee.IdDeprecated)
	wantPK := fmt.Sprintf("%d/%s/%s", proto.GetCustomerId(), "CustomerLicense", Product(proto.Product))

	assert.Equal(t, wantID, cl.ID)
	assert.Equal(t, wantPK, cl.PartitionKey)
}

func TestNewLicenseeSetsCorrectFields(t *testing.T) {
	licesee := NewLicensee(LicenseeTypeUser, "1")

	assert.Equal(t, LicenseeTypeUser, licesee.Type)
	assert.Equal(t, "1", licesee.ID)
	assert.Equal(t, "gid://git-hub/User/1", licesee.GlobalID.String())
}
func TestGetEnablementForReturnsMatchingEnablement(t *testing.T) {
	proto := stubs.NewCustomerLicenseProto()
	cl := NewCustomerLicenseFromProto(proto)
	cl.Enablements = []*CustomerLicenseEnablement{
		{
			Type:          ProductEnablementTypeOrg,
			Reason:        EnablementReasonUnspecified,
			EnablementIDs: []uint64{4, 5, 6},
		},
		{
			Type:          ProductEnablementTypeOrg,
			Reason:        EnablementReasonOrgMembership,
			EnablementIDs: []uint64{1, 2, 3},
		},
	}

	assert.Equal(t, cl.Enablements[1], cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership))
}
func TestGetEnablementForReturnsNilIfNotFound(t *testing.T) {
	cl := NewCustomerLicenseFromProto(stubs.NewCustomerLicenseProto())
	assert.Nil(t, cl.GetEnablementFor(ProductEnablementTypeUnspecified, EnablementReasonUnspecified))
}

func TestAddAndRemoveOrgMembership(t *testing.T) {
	proto := stubs.NewCustomerLicenseProto()
	cl := NewCustomerLicenseFromProto(proto)
	cl.Enablements = []*CustomerLicenseEnablement{}

	assert.True(t, cl.AddOrgMemberships(100, 200))
	assert.False(t, cl.AddOrgMemberships(200))
	assert.ElementsMatch(t, []uint64{100, 200}, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)

	assert.True(t, cl.RemoveOrgMemberships(200))
	assert.ElementsMatch(t, []uint64{100}, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)
	assert.True(t, cl.RemoveOrgMemberships(100))
	assert.True(t, cl.IsEmpty())
	assert.False(t, cl.RemoveOrgMemberships(500))
	assert.True(t, cl.IsEmpty())
}

func TestReplaceOrgMemberships(t *testing.T) {
	customerID := uint64(1)
	userID := uint64(2)
	cl := NewCustomerLicenseForUserWithOrgMemberships(customerID, userID, 100, 200)

	assert.False(t, cl.ReplaceOrgMemberships(100, 200))
	assert.ElementsMatch(t, []uint64{100, 200}, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)

	assert.True(t, cl.ReplaceOrgMemberships(200, 300))
	assert.ElementsMatch(t, []uint64{200, 300}, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)

	assert.True(t, cl.ReplaceOrgMemberships())
	assert.True(t, cl.IsEmpty())
}

func TestReplaceEnablementIDs(t *testing.T) {
	customerID := uint64(1)
	userID := uint64(2)

	tests := []struct {
		name             string
		enablementType   ProductEnablementType
		enablementReason EnablementReason
	}{
		{
			name:             "org membership",
			enablementType:   ProductEnablementTypeOrg,
			enablementReason: EnablementReasonOrgMembership,
		},
		{
			name:             "repo membership",
			enablementType:   ProductEnablementTypeRepo,
			enablementReason: EnablementReasonRepositoryCollaborator,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cl := NewCustomerLicenseForUserWithMemberships(customerID, userID, []uint64{100, 200}, []uint64{100, 200})

			assert.False(t, cl.ReplaceEnablementIDs(tt.enablementType, tt.enablementReason, 100, 200))
			assert.ElementsMatch(t, []uint64{100, 200}, cl.GetEnablementFor(tt.enablementType, tt.enablementReason).EnablementIDs)

			assert.True(t, cl.ReplaceEnablementIDs(tt.enablementType, tt.enablementReason, 200, 300))
			assert.ElementsMatch(t, []uint64{200, 300}, cl.GetEnablementFor(tt.enablementType, tt.enablementReason).EnablementIDs)

			assert.True(t, cl.ReplaceEnablementIDs(tt.enablementType, tt.enablementReason))
			assert.Nil(t, cl.GetEnablementFor(tt.enablementType, tt.enablementReason))
		})
	}
}

func TestReplaceEnablementIDsRemovesEmptyEnablement(t *testing.T) {
	customerID := uint64(1)
	userID := uint64(2)
	licenseeID := strconv.FormatUint(userID, 10)

	enablements := []*CustomerLicenseEnablement{
		{
			Type:   ProductEnablementTypeOrg,
			Reason: EnablementReasonOrgMembership,
		},
	}
	cl := NewCustomerLicense(
		customerID,
		ProductSDLC,
		LicenseStatusActive,
		NewLicensee(LicenseeTypeUser, licenseeID),
		enablements,
		MaxExpiresAt,
		nil,
	)

	assert.True(t, cl.ReplaceEnablementIDs(ProductEnablementTypeOrg, EnablementReasonOrgMembership))
	assert.True(t, cl.IsEmpty())
}

func TestAddEnablementFor(t *testing.T) {
	cl := NewCustomerLicenseFromProto(stubs.NewCustomerLicenseProto())
	cl.Enablements = []*CustomerLicenseEnablement{}

	assert.False(t, cl.AddEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership))
	assert.Nil(t, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership))
	assert.True(t, cl.AddEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, 100))
	assert.True(t, cl.AddEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, 200))
	assert.False(t, cl.AddEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, 200))
	assert.ElementsMatch(t, []uint64{100, 200}, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)
}

func TestRemoveEnablementFor(t *testing.T) {
	cl := NewCustomerLicenseFromProto(stubs.NewCustomerLicenseProto())
	cl.Enablements = []*CustomerLicenseEnablement{
		{
			Type:          ProductEnablementTypeOrg,
			Reason:        EnablementReasonOrgMembership,
			EnablementIDs: []uint64{100, 200},
		},
	}

	assert.True(t, cl.RemoveEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, 100))
	assert.ElementsMatch(t, []uint64{200}, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)
	assert.False(t, cl.IsEmpty())
	assert.True(t, cl.RemoveEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, 200))
	assert.Nil(t, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership))
	assert.True(t, cl.IsEmpty())
}

func TestNewCustomerLicenseForUserWithMembershipsAddsOrgs(t *testing.T) {
	customerID := uint64(1)
	userID := uint64(2)
	orgIDs := []uint64{100, 200}

	cl := NewCustomerLicenseForUserWithMemberships(customerID, userID, orgIDs, nil)

	assert.Equal(t, customerID, cl.CustomerID)
	assert.Equal(t, ProductSDLC, cl.Product)
	assert.Equal(t, LicenseeTypeUser, cl.Licensee.Type)
	assert.Equal(t, strconv.FormatUint(userID, 10), cl.Licensee.ID)
	assert.ElementsMatch(t, orgIDs, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership).EnablementIDs)
	assert.Nil(t, cl.GetEnablementFor(ProductEnablementTypeRepo, EnablementReasonRepositoryCollaborator))
}

func TestNewCustomerLicenseForUserWithMembershipsAddsRepos(t *testing.T) {
	customerID := uint64(1)
	userID := uint64(2)
	repoIDs := []uint64{100, 200}

	cl := NewCustomerLicenseForUserWithMemberships(customerID, userID, nil, repoIDs)

	assert.Equal(t, customerID, cl.CustomerID)
	assert.Equal(t, ProductSDLC, cl.Product)
	assert.Equal(t, LicenseeTypeUser, cl.Licensee.Type)
	assert.Equal(t, strconv.FormatUint(userID, 10), cl.Licensee.ID)
	assert.ElementsMatch(t, repoIDs, cl.GetEnablementFor(ProductEnablementTypeRepo, EnablementReasonRepositoryCollaborator).EnablementIDs)
	assert.Nil(t, cl.GetEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership))
}

func TestSetSuspendedAt(t *testing.T) {
	suspendedAt1 := int64(1000)
	suspendedAt2 := int64(2000)
	suspendedAt3 := int64(1000)

	tests := []struct {
		name string
		t1   *int64
		t2   *int64
		want bool
	}{
		{
			name: "both nil",
			t1:   nil,
			t2:   nil,
			want: false,
		},
		{
			name: "same pointer",
			t1:   &suspendedAt1,
			t2:   &suspendedAt1,
			want: false,
		},
		{
			name: "same pointer values",
			t1:   &suspendedAt1,
			t2:   &suspendedAt3,
			want: false,
		},
		{
			name: "nil and non-nil pointers",
			t1:   nil,
			t2:   &suspendedAt1,
			want: true,
		},
		{
			name: "different pointer values",
			t1:   &suspendedAt1,
			t2:   &suspendedAt2,
			want: true,
		},
	}
	for _, tt := range tests {
		cl := NewCustomerLicense(1, ProductSDLC, LicenseStatusActive, NewLicensee(LicenseeTypeUser, "2"), nil, MaxExpiresAt, tt.t1)
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cl.SetSuspendedAt(tt.t2))
			assert.Equal(t, tt.t2, cl.SuspendedAt)
		})
	}
}

func TestSetStatus(t *testing.T) {
	tests := []struct {
		name          string
		initialStatus LicenseStatus
		newStatus     LicenseStatus
		want          bool
	}{
		{
			name:          "same status",
			initialStatus: LicenseStatusActive,
			newStatus:     LicenseStatusActive,
			want:          false,
		},
		{
			name:          "different status",
			initialStatus: LicenseStatusActive,
			newStatus:     LicenseStatusSuspended,
			want:          true,
		},
	}
	for _, tt := range tests {
		cl := NewCustomerLicense(1, ProductSDLC, tt.initialStatus, NewLicensee(LicenseeTypeUser, "2"), nil, MaxExpiresAt, nil)
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cl.SetStatus(tt.newStatus))
			assert.Equal(t, tt.newStatus, cl.LicenseStatus)
		})
	}
}

func TestSuspend(t *testing.T) {
	suspendedAt := int64(1000)
	tests := []struct {
		name               string
		initialStatus      LicenseStatus
		initialSuspendedAt *int64
		suspendedAt        int64
		want               bool
	}{
		{
			name:               "same status and timestamp",
			initialStatus:      LicenseStatusSuspended,
			initialSuspendedAt: &suspendedAt,
			suspendedAt:        suspendedAt,
			want:               false,
		},
		{
			name:               "active to suspended with same timestamp",
			initialStatus:      LicenseStatusActive,
			initialSuspendedAt: &suspendedAt,
			suspendedAt:        suspendedAt,
			want:               true,
		},
		{
			name:               "suspended to suspended with different timestamp",
			initialStatus:      LicenseStatusSuspended,
			initialSuspendedAt: &suspendedAt,
			suspendedAt:        suspendedAt + 1,
			want:               true,
		},
	}
	for _, tt := range tests {
		cl := NewCustomerLicense(1, ProductSDLC, tt.initialStatus, NewLicensee(LicenseeTypeUser, "2"), nil, MaxExpiresAt, tt.initialSuspendedAt)
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cl.Suspend(tt.suspendedAt))
			assert.Equal(t, LicenseStatusSuspended, cl.LicenseStatus)
		})
	}
}

func TestSetExpiresAt(t *testing.T) {
	cl := NewCustomerLicense(1, ProductSDLC, LicenseStatusActive, NewLicensee(LicenseeTypeUser, "2"), nil, MaxExpiresAt, nil)
	assert.False(t, cl.SetExpiresAt(MaxExpiresAt))
	assert.Equal(t, MaxExpiresAt, cl.ExpiresAt)

	newExpiresAt := MaxExpiresAt - 1
	assert.True(t, cl.SetExpiresAt(newExpiresAt))
	assert.Equal(t, newExpiresAt, cl.ExpiresAt)
}

func TestActivate(t *testing.T) {
	suspendedAt := int64(1000)
	tests := []struct {
		name              string
		initialStatus     LicenseStatus
		initialExpiresAt  int64
		intialSuspendedAt *int64
		want              bool
	}{
		{
			name:              "active to active",
			initialStatus:     LicenseStatusActive,
			initialExpiresAt:  MaxExpiresAt,
			intialSuspendedAt: nil,
			want:              false,
		},
		{
			name:              "deactivated to active",
			initialStatus:     LicenseStatusDeactivated,
			initialExpiresAt:  EndOfMonth(),
			intialSuspendedAt: nil,
			want:              true,
		},
		{
			name:              "suspended to active",
			initialStatus:     LicenseStatusSuspended,
			initialExpiresAt:  MaxExpiresAt,
			intialSuspendedAt: &suspendedAt,
			want:              true,
		},
	}
	for _, tt := range tests {
		cl := NewCustomerLicense(1, ProductSDLC, tt.initialStatus, NewLicensee(LicenseeTypeUser, "2"), nil, tt.initialExpiresAt, tt.intialSuspendedAt)
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cl.Activate())
			assert.Equal(t, LicenseStatusActive, cl.LicenseStatus)
			assert.Equal(t, MaxExpiresAt, cl.ExpiresAt)
		})
	}
}

func TestDeactivate(t *testing.T) {
	suspendedAt := int64(1000)
	tests := []struct {
		name              string
		initialStatus     LicenseStatus
		initialExpiresAt  int64
		intialSuspendedAt *int64
		want              bool
	}{
		{
			name:              "active to deactivated",
			initialStatus:     LicenseStatusActive,
			initialExpiresAt:  MaxExpiresAt,
			intialSuspendedAt: nil,
			want:              true,
		},
		{
			name:              "deactivated to deactivated",
			initialStatus:     LicenseStatusDeactivated,
			initialExpiresAt:  EndOfMonth(),
			intialSuspendedAt: nil,
			want:              false,
		},
		{
			name:              "suspended to deactivated",
			initialStatus:     LicenseStatusSuspended,
			initialExpiresAt:  MaxExpiresAt,
			intialSuspendedAt: &suspendedAt,
			want:              true,
		},
	}
	for _, tt := range tests {
		cl := NewCustomerLicense(1, ProductSDLC, tt.initialStatus, NewLicensee(LicenseeTypeUser, "2"), nil, tt.initialExpiresAt, tt.intialSuspendedAt)
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cl.Deactivate())
			assert.Equal(t, LicenseStatusDeactivated, cl.LicenseStatus)
			assert.Equal(t, EndOfMonth(), cl.ExpiresAt)
		})
	}
}
