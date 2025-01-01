package attestation

import (
	"errors"
	"testing"
	"time"

	"github.com/github/trust-metadata-api/testing/data"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDeduplicateSubjectDigests(t *testing.T) {
	testcases := []struct {
		name     string
		digests  []string
		expected []string
	}{
		{
			name:     "no duplicates",
			digests:  []string{"a", "b", "c"},
			expected: []string{"a", "b", "c"},
		},
		{
			name:     "duplicates",
			digests:  []string{"a", "b", "a", "c", "b", "c"},
			expected: []string{"a", "b", "c"},
		},
	}

	for _, tc := range testcases {
		assert.Equal(t, tc.expected, deduplicateSlice[string](tc.digests), tc.name)
	}
}

func TestNewGitHubAttestationRecord(t *testing.T) {
	ownerID := uint64(1)
	repoID := uint64(2)
	domainID := uint32(2)

	identifiers := IdentifiersGitHub{
		DomainID:     domainID,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	pbundle := data.SigstoreBundle(t)
	bundle, err := sgbundle.NewBundle(pbundle)
	require.NoError(t, err)
	statement, subject := getStatementandSubject(t, bundle)

	record, err := NewGitHubAttestationRecord(pbundle, identifiers, subject, statement)
	assert.NoError(t, err)
	// check that the github specific fields are set
	assert.Equal(t, ownerID, *record.OwnerID)
	assert.Equal(t, repoID, *record.RepositoryID)
	assert.Equal(t, domainID, record.DomainID)
	assert.Equal(t, uint64(0), record.TenantID)
	assert.Equal(t, "", record.Tag)
	// check that the npm specific fields are not set
	assert.Zero(t, record.Purl)

	// Also check releases
	record, err = NewGitHubReleaseAttestationRecord(pbundle, identifiers, subject, statement, "v1.0.0")
	assert.NoError(t, err)
	assert.Equal(t, ownerID, *record.OwnerID)
	assert.Equal(t, repoID, *record.RepositoryID)
	assert.Equal(t, domainID, record.DomainID)
	assert.Equal(t, uint64(0), record.TenantID)
	assert.Equal(t, "v1.0.0", record.Tag)
	assert.Zero(t, record.Purl)
}

func TestValidateCertificateIssuerIsFromGitHub(t *testing.T) {
	tests := []struct {
		name        string
		certSummary *certificate.Summary
		wantErr     error
	}{
		{
			name: "Valid GitHub Issuer",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.githubusercontent.com",
				},
			},
			wantErr: nil,
		},
		{
			name: "Valid GitHub Issuer w/ enterprise slug",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.githubusercontent.com/foo-bar",
				},
			},
			wantErr: nil,
		},
		{
			name: "Invalid Issuer",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "OtherIssuer",
				},
			},
			wantErr: errors.New("issuer is not GitHub"),
		},
		{
			name: "Invalid Issuer w/ bad enterprise slug",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.githubusercontent.com/foo!bar",
				},
			},
			wantErr: errors.New("issuer is not GitHub"),
		},
		{
			name: "Valid Proxima Issuer",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.tenant.ghe.com",
				},
			},
			wantErr: nil,
		},
		{
			name: "Valid Proxima Issuer with dash and number",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.tenant-2.ghe.com",
				},
			},
			wantErr: nil,
		},
		{
			name: "Valid Proxima Issuer w/ enterprise slug",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.tenant-2.ghe.com/tenant-2",
				},
			},
			wantErr: nil,
		},
		{
			name: "Invalid Proxima Issuer without ghe",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.random.com",
				},
			},
			wantErr: errors.New("issuer is not GitHub"),
		},
		{
			name: "Invalid Proxima Issuer without tenant name ",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.ghe.com",
				},
			},
			wantErr: errors.New("issuer is not GitHub"),
		},
		{
			name: "Invalid Proxima Issuer with special characters for tenant name",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.1_2.ghe.com",
				},
			},
			wantErr: errors.New("issuer is not GitHub"),
		},
		{
			name: "Invalid Proxima Issuer w/ bad enterprise slug",
			certSummary: &certificate.Summary{
				Extensions: certificate.Extensions{
					Issuer: "https://token.actions.tenant-2.ghe.com/foo!bar",
				},
			},
			wantErr: errors.New("issuer is not GitHub"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateCertificateIssuerIsFromGitHub(tt.certSummary)
			assert.Equal(t, tt.wantErr, err)
		})
	}
}

func TestValidateCreateArg(t *testing.T) {
	tests := []struct {
		name    string
		created string
		want    CreatedFilter
		wantErr error
	}{
		{
			name:    "no created filter",
			created: "",
			want:    CreatedFilter{},
			wantErr: nil,
		},
		{
			name:    "greater than filter",
			created: ">2023-01-01",
			want: CreatedFilter{
				Operator: ">",
				Date:     time.Date(2023, 01, 01, 0, 0, 0, 0, time.UTC),
			},
			wantErr: nil,
		},
		{
			name:    "less than filter",
			created: "<2023-01-01",
			want: CreatedFilter{
				Operator: "<",
				Date:     time.Date(2023, 01, 01, 0, 0, 0, 0, time.UTC),
			},
			wantErr: nil,
		},
		{
			name:    "equal to filter",
			created: "=2023-01-01",
			want: CreatedFilter{
				Operator: "=",
				Date:     time.Date(2023, 01, 01, 0, 0, 0, 0, time.UTC),
			},
			wantErr: nil,
		},
		{
			name:    "invalid prefix",
			created: "!2023-01-01",
			want:    CreatedFilter{},
			wantErr: ErrInvalidCreatedPrefix,
		},
		{
			name:    "invalid date",
			created: ">2023-01-0",
			want:    CreatedFilter{},
			wantErr: ErrInvalidDateFormat,
		},
		{
			name:    "invalid date",
			created: ">2023-01-02T00:30:00+00:00",
			want:    CreatedFilter{},
			wantErr: ErrInvalidDateFormat,
		},
	}

	for _, tc := range tests {
		got, err := ValidateCreateArg(tc.created)
		if tc.wantErr != nil {
			assert.Error(t, err, tc.name)
		} else {
			assert.Equal(t, tc.want.Operator, got.Operator, tc.name)
			assert.True(t, tc.want.Date.Equal(got.Date), tc.name, tc.want.Date, got.Date)
		}
	}
}
