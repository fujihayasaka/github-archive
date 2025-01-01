package mysql

import (
	"testing"

	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/test/data"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

// This func provides a light sanity check that the toSQLCStoreNPMAttestation
// & fromSQLC funcs manage to serialize and deserialize complex values accordingly.
func TestMysql_toSQLCStoreNPMAttestation(t *testing.T) {
	// Setup:
	pbundle := data.SigstoreBundle(t)
	b, err := bundle.NewBundle(pbundle)
	require.NoError(t, err)

	envelope, err := b.Envelope()
	require.NoError(t, err)

	statement, err := envelope.Statement()
	require.NoError(t, err)

	slsaDigest := statement.Subject[0].Digest
	var alg, digest string
	// nolint:revive
	for alg, digest = range slsaDigest {
	}
	subjectDigest := attestation.SubjectDigest{Alg: alg, Digest: digest}
	subjects := []attestation.Subject{
		{
			Name:          "test",
			SubjectDigest: subjectDigest,
		},
	}

	identifiers := attestation.IdentifiersNPM{
		Purl:     "pkg:npm/foo/bar@12.3.1",
		DomainID: 1,
	}

	// Actual work begins:
	originalRecord, err := attestation.NewNPMAttestationRecord(pbundle, identifiers, subjects, statement)
	assert.NoError(t, err)

	attParam, err := toSQLCStoreNPMAttestation(originalRecord)
	assert.NoError(t, err)

	sqlcAttestation := &sqlc.Attestation{
		DomainID:      attParam.DomainID,
		Purl:          attParam.Purl,
		Certificate:   attParam.Certificate,
		MediaType:     attParam.MediaType,
		PredicateType: attParam.PredicateType,
		StatementType: attParam.StatementType,
		Statement:     attParam.Statement,
	}

	newRecord, err := fromSQLC(sqlcAttestation)
	assert.NoError(t, err, "error converting sqlc attestation into attestation record for test")

	// The Certificate and Statement all get marshaled and unmarshaled
	// into a string and json respectively. When we re-hydrate an Record
	// from the sqlc object, do the resulting objects come back properly?
	assert.NotNil(t, originalRecord.Certificate)
	assert.Equal(t, originalRecord.Certificate, newRecord.Certificate)
	assert.True(t, proto.Equal(originalRecord.Statement, newRecord.Statement))

	// Great. The cert field is nullable, though. What happens if we supply a nil Certificate?
	nilCertRecord := originalRecord
	nilCertRecord.Certificate = nil

	nilCertAttParam, err := toSQLCStoreNPMAttestation(nilCertRecord)
	if err != nil {
		t.Fatalf("error converting attestation record into sqlc attestation for toSQLCStoreNPMAttestation test %v", err)
	}

	nilCertSqlcAttestation := &sqlc.Attestation{
		DomainID:      nilCertAttParam.DomainID,
		Purl:          nilCertAttParam.Purl,
		Certificate:   nilCertAttParam.Certificate,
		MediaType:     nilCertAttParam.MediaType,
		PredicateType: nilCertAttParam.PredicateType,
		StatementType: nilCertAttParam.StatementType,
		Statement:     nilCertAttParam.Statement,
	}

	newNilCertRecord, err := fromSQLC(nilCertSqlcAttestation)
	assert.NoError(t, err, "error converting sqlc attestation into attestation record for test")

	// The Certificate and Statement all get marshaled and unmarshaled
	// into a string and json respectively. When we re-hydrate an Record
	// from the sqlc object, do the resulting objects come back properly?
	assert.Nil(t, nilCertRecord.Certificate)
	assert.Equal(t, nilCertRecord.Certificate, newNilCertRecord.Certificate)
	assert.True(t, proto.Equal(nilCertRecord.Statement, newNilCertRecord.Statement))
}
