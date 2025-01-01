package attestation

import (
	"testing"

	"github.com/github/trust-metadata-api/test/data"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewNPMAttestationRecord(t *testing.T) {
	domainID := uint32(1)
	purl := "pkg:npm/foo/bar@12.3.4"
	identifiers := IdentifiersNPM{
		DomainID: domainID,
		Purl:     purl,
	}

	pbundle := data.SigstoreBundle(t)
	bundle, err := sgbundle.NewBundle(pbundle)
	require.NoError(t, err)
	statement, subjects := getStatementandSubject(t, bundle)

	record, err := NewNPMAttestationRecord(pbundle, identifiers, subjects, statement)
	assert.NoError(t, err)
	// check that the npm specific fields are set
	assert.Equal(t, domainID, record.DomainID)
	assert.Equal(t, purl, record.Purl)
	assert.Equal(t, subjects[0].String(), record.SubjectDigest)
	assert.Equal(t, subjects[0].Name, record.SubjectName)
	// check that the GitHub specific fields are not set
	assert.Nil(t, record.OwnerID)
	assert.Nil(t, record.RepositoryID)
	assert.Zero(t, record.TenantID)
}
