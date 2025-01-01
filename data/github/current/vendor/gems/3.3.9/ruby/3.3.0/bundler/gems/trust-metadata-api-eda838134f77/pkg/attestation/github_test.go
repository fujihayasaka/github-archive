package attestation

import (
	"errors"
	"testing"

	"github.com/github/trust-metadata-api/testing/data"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
	"github.com/stretchr/testify/assert"
)

func TestNewGitHubAttestationRecordWithCertChain(t *testing.T) {
	ownerID := uint64(1)
	repoID := uint64(2)

	pbundle := data.SigstoreBundle(t)
	identifiers := IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	bundle, err := sgbundle.NewBundle(pbundle)
	if err != nil {
		t.Error(err)
		return
	}
	envelope, err := bundle.Envelope()
	assert.NoError(t, err)
	statement, err := envelope.Statement()
	assert.NoError(t, err)
	subject, _ := ValidateStatement(statement)

	t.Run("valid certificate chain", func(t *testing.T) {
		record, err := NewGitHubAttestationRecord(pbundle, identifiers, subject, statement)
		assert.NoError(t, err)
		assert.Equal(t, "36965687079782928586435860974023896448601983968", record.Certificate.SerialNumber.String())
	})

	t.Run("Invalid VerificationMaterial", func(t *testing.T) {
		bundle.VerificationMaterial.Content = nil
		record, err := NewGitHubAttestationRecord(pbundle, identifiers, subject, statement)
		assert.NoError(t, err)
		assert.Nil(t, record.Certificate)
	})
}

func TestNewGitHubAttestationRecordWithSingleCert(t *testing.T) {
	ownerID := uint64(1)
	repoID := uint64(2)

	pbundle := data.SigstoreJs300ProtoBundle(t)
	identifiers := IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	bundle, _ := sgbundle.NewBundle(pbundle)
	envelope, err := bundle.Envelope()
	assert.NoError(t, err)
	statement, err := envelope.Statement()
	assert.NoError(t, err)
	subject, _ := ValidateStatement(statement)

	t.Run("valid certificate", func(t *testing.T) {
		record, err := NewGitHubAttestationRecord(pbundle, identifiers, subject, statement)
		assert.NoError(t, err)
		assert.Equal(t, "662640022264592389906077087555937040960009710002", record.Certificate.SerialNumber.String())
	})
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
