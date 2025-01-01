package models

import (
	"encoding/json"
	"testing"

	"github.com/github/licensify/lib/globalid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLicenseeLicenseMarshalJSONValidInputs(t *testing.T) {
	ttl := int64(100)
	suspendedAt := int64(1728675888)
	tests := []struct {
		name          string
		licenseeType  LicenseeType
		product       Product
		licensestatus LicenseStatus
		ttl           *int64
	}{
		{
			name:          "user target type",
			licenseeType:  LicenseeTypeUser,
			product:       ProductSDLC,
			licensestatus: LicenseStatusActive,
			ttl:           nil,
		},
		{
			name:          "with ttl",
			licenseeType:  LicenseeTypeUser,
			product:       ProductSDLC,
			licensestatus: LicenseStatusDeactivated,
			ttl:           &ttl,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			model := &LicenseeLicense{
				Key: NewLicenseeLicenseKey("2", tt.licenseeType, tt.product, 1),
				Licensee: &Licensee{
					Type: tt.licenseeType,
					ID:   "2",
					GlobalID: &globalid.GlobalID{
						App:       "test-app",
						ModelName: "test-model",
						ModelID:   "2",
					},
				},
				Product:       tt.product,
				LicenseStatus: tt.licensestatus,
				CustomerID:    1,
				ExpiresAt:     1620000000,
				SuspendedAt:   &suspendedAt,
			}
			if tt.ttl != nil {
				model.TTL = tt.ttl
			}

			marshalled, err := json.Marshal(model)

			require.NoError(t, err)

			var unmarshalled LicenseeLicense
			err = json.Unmarshal(marshalled, &unmarshalled)

			require.NoError(t, err)
			assert.Equal(t, model, &unmarshalled)
			assert.Equal(t, tt.ttl, unmarshalled.TTL)
		})
	}
}

func TestLicenseeLicenseUnmarshalJSONwithInvalidInputs(t *testing.T) {
	tests := []struct {
		name         string
		licenseeType string
		licenseeGID  string
		product      string
	}{
		{
			name:         "invalid Licensee",
			licenseeType: "invalid",
			licenseeGID:  "gid://git-hub/User/2",
			product:      ProductSDLC.String(),
		},
		{
			name:         "globalId scheme requires an app name",
			licenseeType: LicenseeTypeUser.String(),
			licenseeGID:  "gid:///User/2",
			product:      ProductSDLC.String(),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := []byte(`{"type":"LicenseeLicense","id":"sdlc:1","licensee":{"type":"` + tt.licenseeType + `","id":"2","globalId":"` + tt.licenseeGID + `"},"product":"` + tt.product + `","customerId":1,"expiresAt":1620000000}`)

			var licenseeLicense LicenseeLicense
			err := json.Unmarshal(data, &licenseeLicense)

			require.Error(t, err)
			assert.ErrorContains(t, err, tt.name)
		})
	}
}

func TestEqual(t *testing.T) {
	license := NewLicenseeLicense(
		NewLicensee(LicenseeTypeUser, "2"),
		ProductSDLC,
		LicenseStatusActive,
		1,
		MaxExpiresAt,
		nil,
	)
	suspendedAt := int64(1000)
	suspendedAt2 := int64(1000)
	tests := []struct {
		name     string
		license1 *LicenseeLicense
		license2 *LicenseeLicense
		want     bool
	}{
		{
			name:     "different customer id",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 2, 0, nil),
			want:     false,
		},
		{
			name:     "different licensee id",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "3"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			want:     false,
		},
		{
			name:     "different licensee type",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUnspecified, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			want:     false,
		},
		{
			name:     "different license status",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusDeactivated, 1, 0, nil),
			want:     false,
		},
		{
			name:     "different product",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductGhas, LicenseStatusActive, 1, 0, nil),
			want:     false,
		},
		{
			name:     "different suspended at",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, &suspendedAt),
			want:     false,
		},
		{
			name:     "different ExpiresAt",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 100, nil),
			want:     false,
		},
		{
			name:     "not equal to nil",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, nil),
			license2: nil,
			want:     false,
		},
		{
			name:     "equal active licenses",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, MaxExpiresAt, nil),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, MaxExpiresAt, nil),
			want:     true,
		},
		{
			name:     "equal suspended licenses with same SuspendedAt pointer",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, &suspendedAt),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, &suspendedAt),
			want:     true,
		},
		{
			name:     "equal suspended licenses with same SuspendedAt values",
			license1: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, &suspendedAt),
			license2: NewLicenseeLicense(NewLicensee(LicenseeTypeUser, "2"), ProductSDLC, LicenseStatusActive, 1, 0, &suspendedAt2),
			want:     true,
		},
		{
			name:     "equal to self",
			license1: license,
			license2: license,
			want:     true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, tt.license1.Equal(tt.license2))
		})
	}
}
