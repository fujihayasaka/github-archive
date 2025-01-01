//go:build integration

package mysql

import (
	"context"
	"fmt"
	"testing"

	"math/rand"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/stretchr/testify/assert"
)

const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

var seededRand = rand.New(rand.NewSource(time.Now().UnixNano()))

func generateRandomString(length int) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[seededRand.Intn(len(charset))]
	}
	return string(b)
}

var predicateTypes = []string{
	attestation.PredicateSLSAProvenance,
	"https://spdx.dev/Document",
	"https://spdx.dev/Document/v2.5",
	"https://cyclonedx.org/bom",
	"https://cyclonedx.org/bom/v1",
	"https://mydev.org/someDocument/v1",
}

type withPredicateTypeFilterTest struct {
	name                 string
	predicateTypePattern string
	expectedRecordNum    int
}

var withPredicateTypeFilterTestCases = []withPredicateTypeFilterTest{
	{
		name:                 "no predicate type",
		predicateTypePattern: "",
		expectedRecordNum:    6,
	},
	{
		name:                 "provenance",
		predicateTypePattern: "https://slsa.dev/provenance/",
		expectedRecordNum:    1,
	},
	{
		name:                 "sbom",
		predicateTypePattern: "^(https://spdx.dev/Document|https://cyclonedx.org/bom)",
		expectedRecordNum:    4,
	},
	{
		name:                 "custom predicate type wildcard pattern",
		predicateTypePattern: "https://mydev.org/someDocument/*",
		expectedRecordNum:    1,
	},
	{
		name:                 "custom predicate type exact match",
		predicateTypePattern: "https://mydev.org/someDocument/v1",
		expectedRecordNum:    1,
	},
	{
		name:                 "predicate type with no matching prefix",
		predicateTypePattern: "fedfdsfsdfds/https://slsa.dev/provenance/",
		expectedRecordNum:    0,
	},
}

type getAttestationsCursorTest struct {
	name                    string
	cursor                  Cursor
	expectedSize            int
	expectedIds             []uint64
	createNumOfAttestations int
}

var listAttestationsWithCursorTestCases = []getAttestationsCursorTest{
	{
		name:                    "cursor with page size 0",
		cursor:                  Cursor{PerPage: 0},
		expectedSize:            0,
		expectedIds:             []uint64{},
		createNumOfAttestations: 1,
	},
	{
		name:                    "cursor with page size 1",
		cursor:                  Cursor{PerPage: 1},
		expectedSize:            1,
		expectedIds:             []uint64{1},
		createNumOfAttestations: 1,
	},
	{
		name:                    "cursor with page size 10",
		cursor:                  Cursor{PerPage: 10},
		expectedSize:            10,
		expectedIds:             []uint64{10, 9, 8, 7, 6, 5, 4, 3, 2, 1},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with page size 10 but only 4 attestations",
		cursor:                  Cursor{PerPage: 10},
		expectedSize:            4,
		expectedIds:             []uint64{4, 3, 2, 1},
		createNumOfAttestations: 4,
	},
	{
		name: "cursor with before which is in range",
		cursor: Cursor{
			PerPage: 4,
			Before:  uint64(4),
		},
		expectedSize:            4,
		expectedIds:             []uint64{8, 7, 6, 5},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with before which is out of range",
		cursor:                  Cursor{PerPage: 10, Before: 10},
		expectedSize:            0,
		expectedIds:             []uint64{},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with after which is in range",
		cursor:                  Cursor{PerPage: 10, After: 5},
		expectedSize:            4,
		expectedIds:             []uint64{4, 3, 2, 1},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with after which is out of range",
		cursor:                  Cursor{PerPage: 10, After: 1},
		expectedSize:            0,
		expectedIds:             []uint64{},
		createNumOfAttestations: 10,
	},
	{
		name: "cursor with before and after which is in range",
		cursor: Cursor{
			PerPage: 10,
			Before:  uint64(2),
			After:   uint64(8),
		},
		expectedSize:            5,
		expectedIds:             []uint64{7, 6, 5, 4, 3},
		createNumOfAttestations: 10,
	},
	{
		name: "cursor with before and after which start is larger than end",
		cursor: Cursor{
			PerPage: 10,
			Before:  uint64(8),
			After:   uint64(2),
		},
		expectedSize:            0,
		expectedIds:             []uint64{},
		createNumOfAttestations: 10,
	},
}

func TestListAttestationsByOwnerSubjectDigest(t *testing.T) {
	db, tx := NewTransactionalDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(1234)

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		SubjectDigest: "foo",
	}
	cursor := Cursor{
		PerPage: 10,
	}
	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
	assert.Empty(t, pageInfo)
}

func TestListAttestationsByOwnerSubjectDigest_MismatchedDomainID(t *testing.T) {
	db, tx := NewTransactionalDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(1234)
	subjectDigest := "foo"

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		SubjectDigest: subjectDigest,
		SubjectName:   "foo/bar",
		DomainID:      1,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	identifiers := attestation.IdentifiersGitHub{
		SubjectDigest: subjectDigest,
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      12345,
	}
	cursor := Cursor{
		PerPage: 10,
	}
	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
	assert.Empty(t, pageInfo)
}

func TestListAttestationsByOwnerSubjectDigest_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(1234)
	alg := "sha256"
	digest := "foo"
	subjectName := "pkg:foo/bar"
	domainID := uint32(2)

	// Creating attestation for testing purposes, so we include repository ID
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:      &ownerId,
		RepositoryID: &repoId,
		DomainID:     domainID,
		CreatedAt:    time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          subjectName,
		SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	// Get attestations by owner subject digest without repository ID
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
		OwnerID:       &ownerId,
		DomainID:      domainID,
		RepositoryID:  &repoId,
	}

	attestations, _, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)

	err = db.DeleteAttestationsByID(context.Background(), []uint64{uint64(id)}, time.Now())
	assert.NoError(t, err)

	attestations, _, err = db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
}

func TestGetAttestationByRepository_MismatchedDomainID(t *testing.T) {
	db, tx := NewTransactionalDatabase(t)
	defer tx.Rollback()

	subjectDigest := "foo"

	repoId := uint64(8847)
	ownerId := uint64(3)
	identifiers := attestation.IdentifiersGitHub{
		ID:           888,
		DomainID:     2,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		ID:            identifiers.ID,
		SubjectDigest: subjectDigest,
		SubjectName:   "foo/bar",
		DomainID:      857473,
		RepositoryID:  identifiers.RepositoryID,
		OwnerID:       identifiers.OwnerID,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	attestation, err := db.GetAttestationByRepository(context.Background(), identifiers)
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "no attestation for given (purl, predicateType) exists")
	assert.Empty(t, attestation)
}

func TestStoreListAttestationsByOwnerSubjectDigestWithoutRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(1234)
	alg := "sha256"
	digest := "foo"
	subjectName := "pkg:foo/bar"
	domainID := uint32(2)

	// Creating attestation for testing purposes, so we include repository ID
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:      &ownerId,
		RepositoryID: &repoId,
		DomainID:     domainID,
		CreatedAt:    time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          subjectName,
		SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	// Get attestations by owner subject digest without repository ID
	identifiersForGetAttestationsByOwnerSubjectDigest := attestation.IdentifiersGitHub{
		SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
		OwnerID:       &ownerId,
		DomainID:      domainID,
	}

	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiersForGetAttestationsByOwnerSubjectDigest, &cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, fmt.Sprintf("%s:%s", alg, digest), attestations[0].SubjectDigest)
	assert.Equal(t, subjectName, attestations[0].SubjectName)
	assert.Equal(t, domainID, attestations[0].DomainID)
	assert.Equal(t, pageInfo.EndCursor, uint64(1))
	assert.Equal(t, pageInfo.StartCursor, uint64(1))
}

func TestStoreListAttestationsByOwnerSubjectDigest_PredicateType(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(1234)
	alg := "sha256"
	digest := "foo"
	subjectName := "pkg:foo/bar"
	domainID := uint32(2)

	subjects := []attestation.Subject{{
		Name:          subjectName,
		SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
	}}

	for _, pt := range predicateTypes {
		// Creating attestation for testing purposes, so we include repository ID
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:       &ownerId,
			RepositoryID:  &repoId,
			DomainID:      domainID,
			CreatedAt:     time.Now(),
			PredicateType: pt,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor := Cursor{
		PerPage: 10,
	}

	for _, tc := range withPredicateTypeFilterTestCases {
		// first request attestations without specifying the predicate type
		identifiers := attestation.IdentifiersGitHub{
			SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
			OwnerID:       &ownerId,
			DomainID:      domainID,
			PredicateType: tc.predicateTypePattern,
		}
		attestations, _, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
		assert.NoError(t, err, tc.name)
		// we expect all attestations to be returned
		assert.Len(t, attestations, tc.expectedRecordNum, tc.name)
	}
}

// The ListAttestationsByOwnerSubjectDigest tests will be updated to use the new batch method tested here
// see https://github.com/github/package-security/issues/2486
func TestListAttestationsByOwnerSubjectDigests(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	subjects := []attestation.Subject{{
		Name:          "pkg:foo/bar",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	ownerId := uint64(1)
	repoId := uint64(1234)
	domainID := uint32(2)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	id, err = db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects = []attestation.Subject{{
		Name:          "pkg:foo/baz",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	// check that attestations with different subject digests are both returned
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: []string{"sha256:foo", "sha256:baz"},
		OwnerID:        &ownerId,
		DomainID:       domainID,
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, records[0].SubjectDigest, "sha256:baz")
	assert.Equal(t, records[1].SubjectDigest, "sha256:foo")

	// check that only the attestation with the listed subject digest is returned
	identifiers.SubjectDigests = []string{"sha256:foo"}
	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, records[0].SubjectDigest, "sha256:foo")
}

func TestListAttestationsByOwnerSubjectDigests_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	subjects := []attestation.Subject{{
		Name:          "pkg:foo/bar",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	ownerId := uint64(1)
	repoId := uint64(1234)
	domainID := uint32(2)
	activeID, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, activeID)

	err = db.StoreAttestationSubjects(context.Background(), uint64(activeID), subjects, tx)
	assert.NoError(t, err)

	deletedID, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, deletedID)

	subjects = []attestation.Subject{{
		Name:          "pkg:foo/baz",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(deletedID), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	// check that attestations with different subject digests are both returned
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: []string{"sha256:foo", "sha256:baz"},
		OwnerID:        &ownerId,
		DomainID:       domainID,
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, records[0].SubjectDigest, "sha256:baz")
	assert.Equal(t, records[1].SubjectDigest, "sha256:foo")

	// now delete the last attestation and confirm it's not returned
	err = db.DeleteAttestationsByID(context.Background(), []uint64{uint64(deletedID)}, time.Now())
	assert.NoError(t, err)

	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, records[0].SubjectDigest, "sha256:foo")
}

func TestListAttestationsByOwnerSubjectDigests_PredicateTypeFilter(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	subjects := []attestation.Subject{{
		Name:          "pkg:foo/bar",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	ownerId := uint64(1)
	repoId := uint64(1234)
	domainID := uint32(2)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	id, err = db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: "https://cyclonedx.org/bom/v1",
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects = []attestation.Subject{{
		Name:          "pkg:foo/baz",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	id, err = db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: "https://cyclonedx.org/bom/v1",
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects = []attestation.Subject{{
		Name:          "pkg:foo/baz",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "zed"},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	// check that attestations with different subject digests are both returned
	// and apply the predicate type filter
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: []string{"sha256:foo", "sha256:baz", "sha256:zed"},
		OwnerID:        &ownerId,
		DomainID:       domainID,
		PredicateType:  "^(https://spdx.dev/Document|https://cyclonedx.org/bom)",
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, "sha256:zed", records[0].SubjectDigest)
	assert.Equal(t, "sha256:baz", records[1].SubjectDigest)

	// check that only provenance predicate type records returned
	identifiers.PredicateType = attestation.PredicateSLSAProvenance
	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, "sha256:foo", records[0].SubjectDigest)

	// check that only the attestation with the listed subject digest is returned
	identifiers.PredicateType = "^(https://spdx.dev/Document|https://cyclonedx.org/bom)"
	identifiers.SubjectDigests = []string{"sha256:foo"}
	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 0)
}

func TestListAttestationsByOwnerSubjectDigests_MultiSubjectDigest(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	// Store an attestation associated with thee subject digests
	subjects := []attestation.Subject{
		{
			Name:          "pkg:foo/bar",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "bar"},
		},
		{
			Name:          "pkg:foo/baz",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
		},
		{
			Name:          "pkg:foo/zed",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "zed"},
		},
	}

	ownerId := uint64(1)
	repoId := uint64(1234)
	domainID := uint32(2)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerId,
		RepositoryID:  &repoId,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	// List attestations by those same three subject digests and confirm that
	// only one attestation record is returned
	subjectStrings := make([]string, len(subjects))
	for i, s := range subjects {
		subjectStrings[i] = s.String()
	}

	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: subjectStrings,
		OwnerID:        &ownerId,
		DomainID:       domainID,
		RepositoryID:   &repoId,
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
}

func TestListAttestationSummariesByRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(4321)
	alg := "sha256"
	digest := "foo"

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerId,
		RepositoryID: &repoId,
		DomainID:     2,
	}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:      identifiers.OwnerID,
		RepositoryID: identifiers.RepositoryID,
		DomainID:     identifiers.DomainID,
		CreatedAt:    time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "name",
		SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	attestations, pageInfo, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, uint64(1), attestations[0].SubjectCount)
	assert.Empty(t, attestations[0].Subjects)
	assert.Equal(t, pageInfo.EndCursor, uint64(1))
	assert.Equal(t, pageInfo.StartCursor, uint64(1))
}

func TestListAttestationSummariesByRepository_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(4321)
	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerId,
		RepositoryID: &repoId,
		DomainID:     2,
	}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:      identifiers.OwnerID,
		RepositoryID: identifiers.RepositoryID,
		DomainID:     identifiers.DomainID,
		CreatedAt:    time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "name",
		SubjectDigest: sd,
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	err = db.DeleteAttestationsByID(context.Background(), []uint64{uint64(id)}, time.Now())
	assert.NoError(t, err)

	cursor := Cursor{
		PerPage: 10,
	}

	attestations, _, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
}

func TestListAttestationSummariesByRepository_PredicateTypeFilter(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(4321)
	subjects := []attestation.Subject{{
		Name:          "name",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	for _, pt := range predicateTypes {
		// Creating attestation for testing purposes, so we include repository ID
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:       &ownerId,
			RepositoryID:  &repoId,
			DomainID:      2,
			CreatedAt:     time.Now(),
			PredicateType: pt,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor := Cursor{
		PerPage: 10,
	}

	for _, tc := range withPredicateTypeFilterTestCases {
		// first request attestations without specifying the predicate type
		identifiers := attestation.IdentifiersGitHub{
			DomainID:      2,
			OwnerID:       &ownerId,
			PredicateType: tc.predicateTypePattern,
			RepositoryID:  &repoId,
		}
		attestations, _, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
		assert.NoError(t, err, tc.name)
		// we expect all attestations to be returned
		assert.Len(t, attestations, tc.expectedRecordNum, tc.name)
	}
}

var twenty25 = time.Date(2025, 2, 11, 14, 30, 53, 0, time.UTC)
var twenty24 = time.Date(2024, 2, 11, 9, 17, 13, 35, time.UTC)
var twenty21 = time.Date(2021, 2, 11, 23, 59, 59, 59, time.UTC)
var createdAtDates = []time.Time{
	twenty25,
	twenty24,
	twenty21,
}

type createdFilterTestCase struct {
	name              string
	createdFilter     attestation.CreatedFilter
	expectedRecordNum int
}

var createdFilterTestCases = []createdFilterTestCase{
	{
		name: "created after",
		createdFilter: attestation.CreatedFilter{
			Operator: ">",
			Date:     time.Date(2024, 2, 11, 0, 0, 0, 0, time.UTC),
		},
		expectedRecordNum: 1,
	},
	{
		name: "created before",
		createdFilter: attestation.CreatedFilter{
			Operator: "<",
			Date:     time.Date(2024, 2, 11, 0, 0, 0, 0, time.UTC),
		},
		expectedRecordNum: 1,
	},
	{
		name: "created equals",
		createdFilter: attestation.CreatedFilter{
			Operator: "=",
			Date:     time.Date(2024, 2, 11, 0, 0, 0, 0, time.UTC),
		},
		expectedRecordNum: 1,
	},
	{
		name:              "no filter",
		expectedRecordNum: 3,
	},
}

func TestListAttestationSummariesByRepository_CreatedFilter(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(4321)
	subjects := []attestation.Subject{{
		Name:          "name",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	for _, cd := range createdAtDates {
		// Creating attestation for testing purposes, so we include repository ID
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:      &ownerId,
			RepositoryID: &repoId,
			DomainID:     2,
			CreatedAt:    cd,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor := Cursor{
		PerPage: 10,
	}

	for _, tc := range createdFilterTestCases {
		identifiers := attestation.IdentifiersGitHub{
			DomainID:     2,
			OwnerID:      &ownerId,
			RepositoryID: &repoId,
			Created:      tc.createdFilter,
		}
		attestations, _, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
		assert.NoError(t, err, tc.name)
		assert.Len(t, attestations, tc.expectedRecordNum, tc.name)
	}
}

func TestGetAttestationByRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoId := uint64(4233)
	ownerId := uint64(7)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: sd.String(),
		SubjectName:   "foo/bar",
		DomainID:      2,
		RepositoryID:  &repoId,
		OwnerID:       &ownerId,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "foo/bar",
		SubjectDigest: sd,
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           id,
		DomainID:     2,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}

	attestation, err := db.GetAttestationByRepository(context.Background(), findIdentifiers)
	assert.Nil(t, err)
	assert.Equal(t, sd.String(), attestation.SubjectDigest)
	assert.Equal(t, "foo/bar", attestation.SubjectName)
	assert.Equal(t, 2, int(attestation.DomainID))
}

func TestGetAttestationByRepository_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoId := uint64(4233)
	ownerId := uint64(7)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: sd.String(),
		SubjectName:   "foo/bar",
		DomainID:      2,
		RepositoryID:  &repoId,
		OwnerID:       &ownerId,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "foo/bar",
		SubjectDigest: sd,
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	// now mark the attestation as deleted so it is not returned by the list method
	err = db.DeleteAttestationsByID(context.Background(), []uint64{uint64(id)}, time.Now())
	assert.NoError(t, err)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           id,
		DomainID:     2,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}

	attestation, err := db.GetAttestationByRepository(context.Background(), findIdentifiers)
	assert.Error(t, err)
	assert.Nil(t, attestation)
}

func TestGetAttestationSummaryByRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoId := uint64(4235)
	ownerId := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: sd.String(),
		RepositoryID:  &repoId,
		OwnerID:       &ownerId,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "foo/bar",
		SubjectDigest: sd,
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           id,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}

	attestation, err := db.GetAttestationSummaryByRepository(context.Background(), findIdentifiers)
	assert.Nil(t, err)
	assert.Equal(t, sd.String(), attestation.SubjectDigest)
	assert.Equal(t, "foo/bar", attestation.Subjects[0].Name)
	assert.Equal(t, uint64(id), attestation.ID)
}

func TestGetAttestationSummaryByRepository_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoId := uint64(4235)
	ownerId := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		RepositoryID:  &repoId,
		OwnerID:       &ownerId,
		CreatedAt:     time.Now(),
		SubjectDigest: sd.String(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "foo/bar",
		SubjectDigest: sd,
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	// now mark the attestation as deleted so it is not returned by the list method
	err = db.DeleteAttestationsByID(context.Background(), []uint64{uint64(id)}, time.Now())
	assert.NoError(t, err)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           id,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}

	attestation, err := db.GetAttestationSummaryByRepository(context.Background(), findIdentifiers)
	assert.Error(t, err)
	assert.Nil(t, attestation)
}

func TestListAttestationsByOwnerSubjectDigestWithCursor(t *testing.T) {
	for _, tt := range listAttestationsWithCursorTestCases {
		db, tx := newTxDatabase(t)
		defer tx.Rollback()

		ownerId := uint64(1)
		repoId := uint64(1234)
		alg := "sha256"
		digest := "foo"

		identifiers := attestation.IdentifiersGitHub{
			SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
			OwnerID:       &ownerId,
			RepositoryID:  &repoId,
			DomainID:      2,
		}

		subjects := []attestation.Subject{{
			Name:          "foo",
			SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
		}}

		// Create N attestations for testing
		for range tt.createNumOfAttestations {
			id, err := db.StoreAttestation(context.Background(), &attestation.Record{
				OwnerID:      identifiers.OwnerID,
				RepositoryID: identifiers.RepositoryID,
				DomainID:     identifiers.DomainID,
				CreatedAt:    time.Now(),
			}, tx)
			assert.NoError(t, err)

			err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
			assert.NoError(t, err)
		}

		attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &tt.cursor)
		assert.NoError(t, err, tt.name)
		assert.Equal(t, len(attestations), tt.expectedSize, tt.name)

		if len(tt.expectedIds) > 0 {
			assert.Equal(t, pageInfo.StartCursor, tt.expectedIds[0])
			assert.Equal(t, pageInfo.EndCursor, tt.expectedIds[len(tt.expectedIds)-1])
		} else {
			assert.Nil(t, pageInfo)
		}

		// Check the order of the attestations match the expected order
		for i, id := range tt.expectedIds {
			assert.Equal(t, id, attestations[i].ID, tt.name)
		}

		tx.Rollback()
	}
}

func TestListAttestationsByRepositoryWithCursor(t *testing.T) {
	for _, tt := range listAttestationsWithCursorTestCases {
		db, tx := newTxDatabase(t)
		defer tx.Rollback()

		ownerId := uint64(1)
		repoId := uint64(1234)
		alg := "sha256"
		digest := "foo"

		identifiers := attestation.IdentifiersGitHub{
			OwnerID:      &ownerId,
			RepositoryID: &repoId,
			DomainID:     2,
		}

		subjects := []attestation.Subject{{
			Name:          "foo",
			SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
		}}

		// Create N attestations for testing
		for range tt.createNumOfAttestations {
			// generate subject digest as random string by library
			subjectDigest := generateRandomString(10)

			id, err := db.StoreAttestation(context.Background(), &attestation.Record{
				SubjectDigest: subjectDigest,
				OwnerID:       identifiers.OwnerID,
				RepositoryID:  identifiers.RepositoryID,
				DomainID:      identifiers.DomainID,
				CreatedAt:     time.Now(),
			}, tx)
			assert.NoError(t, err)

			err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
			assert.NoError(t, err)
		}

		attestations, pageInfo, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, &tt.cursor)
		assert.NoError(t, err, tt.name)
		assert.Equal(t, len(attestations), tt.expectedSize, tt.name)
		if len(tt.expectedIds) > 0 {
			assert.Equal(t, pageInfo.StartCursor, tt.expectedIds[0])
			assert.Equal(t, pageInfo.EndCursor, tt.expectedIds[len(tt.expectedIds)-1])
		} else {
			assert.Nil(t, pageInfo)
		}

		// Check the order of the attestations match the expected order
		for i, id := range tt.expectedIds {
			assert.Equal(t, id, attestations[i].ID, tt.name)
		}

		tx.Rollback()
	}
}

func TestDeleteAttestationsByID(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoId := uint64(4235)
	ownerId := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		RepositoryID:  &repoId,
		OwnerID:       &ownerId,
		CreatedAt:     time.Now(),
		SubjectDigest: sd.String(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          "foo/bar",
		SubjectDigest: sd,
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	identifiers := attestation.IdentifiersGitHub{
		ID:           id,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}
	record, err := db.GetAttestationSummaryByRepository(context.Background(), identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	// now mark the attestation as deleted so it is not returned by the list method
	err = db.DeleteAttestationsByID(context.Background(), []uint64{uint64(id)}, time.Now())
	assert.NoError(t, err)

	record, err = db.GetAttestationSummaryByRepository(context.Background(), identifiers)
	assert.Error(t, err)
	assert.Nil(t, record)
}

func TestListAttestationSummariesByRepository_PartialSubjectNameMatch(t *testing.T) {
	db, tx := newTxDatabase(t)
	defer tx.Rollback()

	subjectDigest := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoId := uint64(4235)
	ownerId := uint64(77)

	subjectNameCollections := [][]string{
		{"fo%o/bar", "foo/baz", "foo/zed"},
		{"boo/bar", "boo/baz", "boo/zed"},
	}

	// Create two attestations, each associated with a distinct set of subject names
	for _, subjectNames := range subjectNameCollections {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:    time.Now(),
			DomainID:     2,
			OwnerID:      &ownerId,
			RepositoryID: &repoId,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		for _, subjectName := range subjectNames {
			subjects := []attestation.Subject{{
				Name:          subjectName,
				SubjectDigest: subjectDigest,
			}}
			err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
			assert.NoError(t, err)
		}
	}

	cursor := Cursor{
		PerPage: 30,
	}

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerId,
		RepositoryID: &repoId,
		DomainID:     2,
	}
	// Fetch attestations without any subject name filtering
	attestations, _, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 2)

	// Fetch attestations with 'foo' prefix matching
	identifiers.SubjectName = "%fo\\%o%"
	attestations, _, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, uint64(3), attestations[0].SubjectCount)

	// Fetch attestations with boo prefix matching
	identifiers.SubjectName = "%boo%"
	attestations, _, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, uint64(3), attestations[0].SubjectCount)

	// Fetch attestations with 'o/ze' substring matching
	identifiers.SubjectName = "%o/ze%"
	attestations, _, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 2)
	assert.Equal(t, uint64(3), attestations[0].SubjectCount)
	assert.Equal(t, uint64(3), attestations[1].SubjectCount)

	// Fetch attestations with 'zed' suffix matching
	identifiers.SubjectName = "%zed%"
	attestations, _, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 2)
	assert.Equal(t, uint64(3), attestations[0].SubjectCount)
	assert.Equal(t, uint64(3), attestations[1].SubjectCount)

	// Fetch attestations with full 'foo/bar' subject name matching
	identifiers.SubjectName = "%fo\\%o/bar%"
	attestations, _, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, uint64(3), attestations[0].SubjectCount)

	// Fail to fetch any attestations with subject name matching
	identifiers.SubjectName = "%no/subject%"
	attestations, _, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
}
