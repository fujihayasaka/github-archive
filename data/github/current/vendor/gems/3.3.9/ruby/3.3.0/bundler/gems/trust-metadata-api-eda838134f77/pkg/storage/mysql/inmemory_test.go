package mysql

import (
	"context"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/stretchr/testify/assert"
)

func TestInMemoryDatabase_StoreAttestation(t *testing.T) {
	// setup new InMemoryDatabase for test
	db := NewInMemoryDatabase()

	// create new Attestation for test
	//nolint:gosec
	purl := "pkg:github/trust-metadata-api@sha256:00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"
	//nolint:gosec
	subjectDigest := "sha256:00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"

	attestationRecord := attestation.Record{
		SubjectDigest: subjectDigest,
		Purl:          purl,
	}

	// call the StoreAttestation method
	id, err := db.StoreAttestation(context.Background(), &attestationRecord, nil)
	if err != nil {
		t.Fatalf("error storing attestation: %v", err)
	}

	assert.Equal(t, uint64(1), id)

	// check that the attestation was stored
	params := attestation.IdentifiersNPM{
		Purl: purl,
	}
	attestations, err := db.GetAttestationsByPurl(context.Background(), params)
	if err != nil {
		t.Fatalf("error getting attestations: %v", err)
	}

	assert.Len(t, attestations, 1)
	assert.Equal(t, subjectDigest, attestations[0].SubjectDigest)
}

func TestInMemoryDatabase_StoreAttestationSubjects(t *testing.T) {
	db := NewInMemoryDatabase()

	id := uint64(1)
	name := "foo/bar"
	digest := "00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"

	subjects := []attestation.Subject{{
		Name: name, SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: digest}}}

	err := db.StoreAttestationSubjects(context.Background(), id, subjects, nil)
	if err != nil {
		t.Fatalf("error storing attestation subjects: %v", err)
	}

	assert.Len(t, db.subjects, 1)
	assert.Equal(t, subjects[0], db.subjects[0])
}

func TestInMemoryDatabase_Close(t *testing.T) {
	// setup new InMemoryDatabase for test
	db := NewInMemoryDatabase()

	assert.Nil(t, db.Close(), "expected Close to return nil error")
}

func TestInMemoryDatabase_Duplicate(t *testing.T) {
	db := NewInMemoryDatabase()

	attestationRecord := attestation.Record{
		Purl:          "pkg:foo/bar@1.0",
		PredicateType: "https://slsa.dev/provenance/v0.1",
	}

	_, err := db.StoreAttestation(context.Background(), &attestationRecord, nil)
	assert.NoError(t, err)
	_, err = db.StoreAttestation(context.Background(), &attestationRecord, nil)
	assert.ErrorIs(t, err, ErrDuplicateAttestation)
}

func TestInMemoryDatabase_GetAttestationByPurlPredicateType(t *testing.T) {
	db := NewInMemoryDatabase()

	attestationRecord := attestation.Record{
		Purl:          "pkg:foo/bar@1.0",
		PredicateType: "https://slsa.dev/provenance/v0.1",
		DomainID:      1,
	}

	_, err := db.StoreAttestation(context.Background(), &attestationRecord, nil)
	assert.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl:     "pkg:foo/bar@1.0",
		DomainID: 1,
	}

	predicateTypes := []string{"https://slsa.dev/provenance/v0.1"}

	result, err := db.GetAttestationByPurlPredicateType(context.Background(), attestationIdentifier, predicateTypes)
	assert.NoError(t, err)
	assert.Equal(t, &attestationRecord, result)
}

func TestInMemoryDatabase_ListAttestationsByOwnerSubjectDigest(t *testing.T) {
	db := NewInMemoryDatabase()

	ownerID := uint64(1)
	repoID := uint64(2)
	domainID := uint32(1)

	attestationRecord := attestation.Record{
		Purl:          "pkg:foo/bar@1.0",
		PredicateType: "https://slsa.dev/provenance/v0.1",
		DomainID:      domainID,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		SubjectDigest: "digest1",
	}

	_, err := db.StoreAttestation(context.Background(), &attestationRecord, nil)
	assert.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersGitHub{
		DomainID:      domainID,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		SubjectDigest: "digest1",
	}

	attestations, _, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), attestationIdentifier, nil)
	assert.NoError(t, err)
	assert.Equal(t, 1, len(attestations))
	assert.Equal(t, attestationRecord, attestations[0])
}

func TestInMemoryDatabase_GetAttestationsByRepository(t *testing.T) {
	db := NewInMemoryDatabase()

	ownerID := uint64(1)
	repoID := uint64(2)
	domainID := uint32(1)

	attestationRecord := attestation.Record{
		Purl:          "pkg:foo/bar@1.0",
		PredicateType: "https://slsa.dev/provenance/v0.1",
		DomainID:      domainID,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
	}

	_, err := db.StoreAttestation(context.Background(), &attestationRecord, nil)
	assert.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersGitHub{
		DomainID:     domainID,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	attestations, _, err := db.ListAttestationsByRepository(context.Background(), attestationIdentifier, nil)
	assert.NoError(t, err)
	assert.Equal(t, 1, len(attestations))
	assert.Equal(t, attestationRecord, attestations[0])
}
