package attestation

import (
	"testing"

	"github.com/github/trust-metadata-api/testing/data"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

func TestNewNPMAttestationRecordWithCertChain(t *testing.T) {
	pbundle := data.SigstoreBundle(t)
	identifiers := IdentifiersNPM{
		DomainID: 1,
		Purl:     "pkg:npm/foo/bar@12.3.4",
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
		record, err := NewNPMAttestationRecord(pbundle, identifiers, subject, statement)
		assert.NoError(t, err)
		assert.Equal(t, "36965687079782928586435860974023896448601983968", record.Certificate.SerialNumber.String())
	})

	t.Run("Invalid VerificationMaterial", func(t *testing.T) {
		bundle.VerificationMaterial.Content = nil
		record, err := NewNPMAttestationRecord(pbundle, identifiers, subject, statement)
		assert.NoError(t, err)
		assert.Nil(t, record.Certificate)
	})
}

func TestNewNPMAttestationRecordWithSingleCert(t *testing.T) {
	pbundle := data.SigstoreJs300ProtoBundle(t)
	identifiers := IdentifiersNPM{
		DomainID: 1,
		Purl:     "pkg:npm/foo/bar@12.3.4",
	}

	bundle, _ := sgbundle.NewBundle(pbundle)
	envelope, err := bundle.Envelope()
	assert.NoError(t, err)
	statement, err := envelope.Statement()
	assert.NoError(t, err)
	subject, _ := ValidateStatement(statement)

	t.Run("valid certificate", func(t *testing.T) {
		record, err := NewNPMAttestationRecord(pbundle, identifiers, subject, statement)
		assert.NoError(t, err)
		assert.Equal(t, "662640022264592389906077087555937040960009710002", record.Certificate.SerialNumber.String())
	})
}
