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

const (
	SubjectDigest = "sha256:00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"
	SubjectName   = "foo/bar"
)

// This func provides a light sanity check that the toSQLC & fromSQLC funcs
// manage to serialize and deserialize complex values accordingly.
func TestMysql_toSQLCAndFromSQLCRoundTrip(t *testing.T) {
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

	ownerID, repoID := uint64(42), uint64(84)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     1,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	// Actual work begins:
	originalRecord, err := attestation.NewGitHubAttestationRecord(pbundle, identifiers, subjects, statement)
	assert.NoError(t, err, "error creating attestation record for test")

	attParam, err := toSQLC(originalRecord)
	assert.NoError(t, err, "error converting attestation record into sqlc attestation for test")

	sqlcAttestation := &sqlc.Attestation{
		DomainID:      attParam.DomainID,
		OwnerID:       attParam.OwnerID,
		RepositoryID:  attParam.RepositoryID,
		Certificate:   attParam.Certificate,
		MediaType:     attParam.MediaType,
		PredicateType: attParam.PredicateType,
		StatementType: attParam.StatementType,
		Statement:     attParam.Statement,
	}

	newRecord, err := fromSQLC(sqlcAttestation)
	if err != nil {
		t.Fatalf("error converting sqlc attestation into attestation record for test %v", err)
	}

	// The Certificate, Bundle and Statement all get marshaled and unmarshaled
	// into a string and json respectively. When we re-hydrate an Record
	// from the sqlc object, do the resulting objects come back properly?
	assert.NotNil(t, originalRecord.Certificate)
	assert.Equal(t, originalRecord.Certificate, newRecord.Certificate)
	assert.True(t, proto.Equal(originalRecord.Statement, newRecord.Statement))

	// Great. The cert field is nullable, though. What happens if we supply a nil Certificate?
	nilCertRecord := originalRecord
	nilCertRecord.Certificate = nil

	nilCertAttParam, err := toSQLC(nilCertRecord)
	assert.NoError(t, err, "error converting attestation record into sqlc attestation for test")

	nilCertSqlcAttestation := &sqlc.Attestation{
		DomainID:      nilCertAttParam.DomainID,
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
