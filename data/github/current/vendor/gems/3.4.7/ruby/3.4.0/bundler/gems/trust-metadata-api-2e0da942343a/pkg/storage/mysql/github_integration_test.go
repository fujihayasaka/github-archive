package mysql

import (
	"context"
	"fmt"
	"testing"

	"math/rand"
	"time"

	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/test"
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
	expectedIDs             []uint64
	createNumOfAttestations int
}

var listAttestationsWithCursorTestCases = []getAttestationsCursorTest{
	{
		name:                    "cursor with page size 0",
		cursor:                  Cursor{PerPage: 0},
		expectedSize:            0,
		expectedIDs:             []uint64{},
		createNumOfAttestations: 1,
	},
	{
		name:                    "cursor with page size 1",
		cursor:                  Cursor{PerPage: 1},
		expectedSize:            1,
		expectedIDs:             []uint64{1},
		createNumOfAttestations: 1,
	},
	{
		name:                    "cursor with page size 10",
		cursor:                  Cursor{PerPage: 10},
		expectedSize:            10,
		expectedIDs:             []uint64{10, 9, 8, 7, 6, 5, 4, 3, 2, 1},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with page size 10 but only 4 attestations",
		cursor:                  Cursor{PerPage: 10},
		expectedSize:            4,
		expectedIDs:             []uint64{4, 3, 2, 1},
		createNumOfAttestations: 4,
	},
	{
		name: "cursor with before which is in range",
		cursor: Cursor{
			PerPage: 4,
			Before:  uint64(4),
		},
		expectedSize:            4,
		expectedIDs:             []uint64{8, 7, 6, 5},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with before which is out of range",
		cursor:                  Cursor{PerPage: 10, Before: 10},
		expectedSize:            0,
		expectedIDs:             []uint64{},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with after which is in range",
		cursor:                  Cursor{PerPage: 10, After: 5},
		expectedSize:            4,
		expectedIDs:             []uint64{4, 3, 2, 1},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with after which is out of range",
		cursor:                  Cursor{PerPage: 10, After: 1},
		expectedSize:            0,
		expectedIDs:             []uint64{},
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
		expectedIDs:             []uint64{7, 6, 5, 4, 3},
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
		expectedIDs:             []uint64{},
		createNumOfAttestations: 10,
	},
}

type getAttestationsWithSortCursorTest struct {
	name                    string
	cursor                  Cursor
	expectedSize            int
	expectedIDs             []uint64
	createNumOfAttestations int
}

var listAttestationsWithCursorAndCustomSortTestCases = []getAttestationsWithSortCursorTest{
	{
		name:                    "cursor with page size 0",
		cursor:                  Cursor{PerPage: 0},
		expectedSize:            0,
		expectedIDs:             []uint64{},
		createNumOfAttestations: 1,
	},
	{
		name:                    "cursor with page size 1",
		cursor:                  Cursor{PerPage: 1},
		expectedSize:            1,
		expectedIDs:             []uint64{1},
		createNumOfAttestations: 1,
	},
	{
		name:                    "cursor with page size 10",
		cursor:                  Cursor{PerPage: 10},
		expectedSize:            10,
		expectedIDs:             []uint64{10, 9, 8, 7, 6, 5, 4, 3, 2, 1},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with page size 10 but only 4 attestations",
		cursor:                  Cursor{PerPage: 10},
		expectedSize:            4,
		expectedIDs:             []uint64{4, 3, 2, 1},
		createNumOfAttestations: 4,
	},
	{
		name:                    "cursor with before which is out of range",
		cursor:                  Cursor{PerPage: 10, Before: 10},
		expectedSize:            0,
		expectedIDs:             []uint64{},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with after which is in range",
		cursor:                  Cursor{PerPage: 10, After: 5},
		expectedSize:            4,
		expectedIDs:             []uint64{4, 3, 2, 1},
		createNumOfAttestations: 10,
	},
	{
		name:                    "cursor with after which is out of range",
		cursor:                  Cursor{PerPage: 10, After: 1},
		expectedSize:            0,
		expectedIDs:             []uint64{},
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
		expectedIDs:             []uint64{7, 6, 5, 4, 3},
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
		expectedIDs:             []uint64{},
		createNumOfAttestations: 10,
	},
}

func TestListAttestationsByOwnerSubjectDigest(t *testing.T) {
	db, tx := NewTransactionalDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(1234)

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		SubjectDigest: "foo",
	}
	cursor := DescCursor{}
	cursor.PerPage = 10
	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
	assert.Empty(t, pageInfo)
}

func TestListAttestationsByOwnerSubjectDigest_MismatchedDomainID(t *testing.T) {
	db, tx := NewTransactionalDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(1234)
	subjectDigest := "foo" //nolint:goconst

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		SubjectDigest: subjectDigest,
		SubjectName:   "foo/bar",
		DomainID:      1,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	identifiers := attestation.IdentifiersGitHub{
		SubjectDigest: subjectDigest,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		DomainID:      12345,
	}
	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)
	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
	assert.Empty(t, pageInfo)
}

func TestListAttestationsByOwnerSubjectDigest_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(1234)
	alg := "sha256" //nolint:goconst
	digest := "foo"
	subjectName := "pkg:foo/bar" //nolint:goconst
	domainID := uint32(2)

	// Creating attestation for testing purposes, so we include repository ID
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     domainID,
		CreatedAt:    time.Now(),
		Certificate:  CreateTestCert(t),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          subjectName,
		SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	// Get attestations by owner subject digest without repository ID
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
		OwnerID:       &ownerID,
		DomainID:      domainID,
		RepositoryID:  &repoID,
	}

	attestations, _, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)

	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		RepositoryID:   &repoID,
		AttestationIDs: []uint64{id},
	}
	deleted, err := db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, deleted, 1)

	attestations, _, err = db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
}

func TestGetAttestationByRepository_MismatchedDomainID(t *testing.T) {
	db, tx := NewTransactionalDatabase(t)
	test.Cleanup(t, tx.Rollback)

	subjectDigest := "foo"

	repoID := uint64(8847)
	ownerID := uint64(3)
	identifiers := attestation.IdentifiersGitHub{
		ID:           888,
		DomainID:     2,
		RepositoryID: &repoID,
		OwnerID:      &ownerID,
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
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(1234)
	alg := "sha256" //nolint:goconst
	digest := "foo"
	subjectName := "pkg:foo/bar" //nolint:goconst
	domainID := uint32(2)
	signer := "https://example.com/"

	// Creating attestation for testing purposes, so we include repository ID
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     domainID,
		CreatedAt:    time.Now(),
		Signer:       signer,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{
		Name:          subjectName,
		SubjectDigest: attestation.SubjectDigest{Alg: alg, Digest: digest},
	}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	// Get attestations by owner subject digest without repository ID
	identifiersForGetAttestationsByOwnerSubjectDigest := attestation.IdentifiersGitHub{
		SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
		OwnerID:       &ownerID,
		DomainID:      domainID,
	}

	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiersForGetAttestationsByOwnerSubjectDigest, cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, fmt.Sprintf("%s:%s", alg, digest), attestations[0].SubjectDigest)
	assert.Equal(t, subjectName, attestations[0].SubjectName)
	assert.Equal(t, domainID, attestations[0].DomainID)
	assert.Equal(t, pageInfo.EndCursor, uint64(1))
	assert.Equal(t, pageInfo.StartCursor, uint64(1))
	assert.Equal(t, signer, attestations[0].Signer)
}

func TestStoreListAttestationsByOwnerSubjectDigest_PredicateType(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(1234)
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
			OwnerID:       &ownerID,
			RepositoryID:  &repoID,
			DomainID:      domainID,
			CreatedAt:     time.Now(),
			PredicateType: pt,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	for _, tc := range withPredicateTypeFilterTestCases {
		// first request attestations without specifying the predicate type
		identifiers := attestation.IdentifiersGitHub{
			SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
			OwnerID:       &ownerID,
			DomainID:      domainID,
			PredicateType: tc.predicateTypePattern,
		}
		attestations, _, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, cursor)
		assert.NoError(t, err, tc.name)
		// we expect all attestations to be returned
		assert.Len(t, attestations, tc.expectedRecordNum, tc.name)
	}
}

// The ListAttestationsByOwnerSubjectDigest tests will be updated to use the new batch method tested here
// see https://github.com/github/package-security/issues/2486
func TestListAttestationsByOwnerSubjectDigests(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	subjectCollections := [][]attestation.Subject{
		{
			attestation.Subject{
				Name:          "pkg:foo/bar",
				SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
			},
		},
		{
			attestation.Subject{
				Name:          "pkg:foo/baz",
				SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
			},
		},
	}

	ownerID := uint64(1)
	repoID := uint64(1234)
	domainID := uint32(2)
	for _, subjects := range subjectCollections {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:       &ownerID,
			RepositoryID:  &repoID,
			DomainID:      domainID,
			CreatedAt:     time.Now(),
			PredicateType: attestation.PredicateSLSAProvenance,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	// check that attestations with different subject digests are both returned
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: []string{"sha256:foo", "sha256:baz"},
		OwnerID:        &ownerID,
		DomainID:       domainID,
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, records[0].SubjectDigest, "sha256:baz")
	assert.Equal(t, records[1].SubjectDigest, "sha256:foo")

	// check that only attestations with the included subject digest is returned
	identifiers.SubjectDigests = []string{"sha256:foo"}
	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, records[0].SubjectDigest, "sha256:foo")
}

func TestListAttestationsByOwnerSubjectDigests_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	subjects := []attestation.Subject{{
		Name:          "pkg:foo/bar",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	ownerID := uint64(1)
	repoID := uint64(1234)
	domainID := uint32(2)
	activeID, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, activeID)

	err = db.StoreAttestationSubjects(context.Background(), uint64(activeID), subjects, tx)
	assert.NoError(t, err)

	deletedID, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	// check that attestations with different subject digests are both returned
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: []string{"sha256:foo", "sha256:baz"},
		OwnerID:        &ownerID,
		DomainID:       domainID,
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, "sha256:baz", records[0].SubjectDigest)
	assert.Equal(t, "sha256:foo", records[1].SubjectDigest)

	// now delete the last attestation and confirm it's not returned
	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		RepositoryID:   &repoID,
		AttestationIDs: []uint64{deletedID},
	}
	deleted, err := db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, deleted, 1)

	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, "sha256:foo", records[0].SubjectDigest)
}

func TestListAttestationsByOwnerSubjectDigests_PredicateTypeFilter(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	subjects := []attestation.Subject{{
		Name:          "pkg:foo/bar",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	ownerID := uint64(1)
	repoID := uint64(1234)
	domainID := uint32(2)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		DomainID:      domainID,
		CreatedAt:     time.Now(),
		PredicateType: attestation.PredicateSLSAProvenance,
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	id, err = db.StoreAttestation(context.Background(), &attestation.Record{
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	// check that attestations with different subject digests are both returned
	// and apply the predicate type filter
	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: []string{"sha256:foo", "sha256:baz", "sha256:zed"},
		OwnerID:        &ownerID,
		DomainID:       domainID,
		PredicateType:  "^(https://spdx.dev/Document|https://cyclonedx.org/bom)",
	}
	records, _, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, "sha256:zed", records[0].SubjectDigest)
	assert.Equal(t, "sha256:baz", records[1].SubjectDigest)

	// check that only provenance predicate type records returned
	identifiers.PredicateType = attestation.PredicateSLSAProvenance
	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, "sha256:foo", records[0].SubjectDigest)

	// check that only the attestation with the listed subject digest is returned
	identifiers.PredicateType = "^(https://spdx.dev/Document|https://cyclonedx.org/bom)"
	identifiers.SubjectDigests = []string{"sha256:foo"}
	records, _, err = db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 0)
}

func TestListAttestationsByOwnerSubjectDigests_MultiSubjectDigest(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

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

	ownerID := uint64(1)
	repoID := uint64(1234)
	domainID := uint32(2)

	for range 2 {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:       &ownerID,
			RepositoryID:  &repoID,
			DomainID:      domainID,
			CreatedAt:     time.Now(),
			PredicateType: attestation.PredicateSLSAProvenance,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	// List attestations by those same three subject digests and confirm that
	// only one attestation record is returned
	subjectStrings := make([]string, len(subjects))
	for i, s := range subjects {
		subjectStrings[i] = s.String()
	}

	identifiers := attestation.IdentifiersGitHub{
		SubjectDigests: subjectStrings,
		OwnerID:        &ownerID,
		DomainID:       domainID,
		RepositoryID:   &repoID,
	}
	records, pageInfo, err := db.ListAttestationsByOwnerSubjectDigests(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.NotNil(t, pageInfo)
}

func TestListAttestationSummariesByRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(4321)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
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

	subjects := []attestation.Subject{
		{
			Name:          "pkg:foo/bar",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "bar"},
		},
		{
			Name:          "pkg:foo/baz",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
		},
	}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	records, pageInfo, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, 2, int(records[0].SubjectCount))
	assert.Equal(t, "pkg:foo/bar", records[0].Subjects[0].Name)
	assert.Len(t, records[0].Subjects, 1)
	assert.Equal(t, 1, int(pageInfo.EndCursor))
	assert.Equal(t, 1, int(pageInfo.StartCursor))
}

func TestListAttestationSummariesByRepository_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(4321)
	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:  CreateTestCert(t),
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

	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		RepositoryID:   &repoID,
		AttestationIDs: []uint64{id},
	}
	deleted, err := db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, deleted, 1)

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	records, _, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Empty(t, records)
}

func TestGetHydroDeleteRecordInfoByID(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(4321)
	subjects := []attestation.Subject{
		{
			Name:          "mysubjectname",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
		},
		{
			Name:          "anothersubjectname",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha512", Digest: "bar"},
		},
	}
	subjects2 := []attestation.Subject{
		{
			Name:          "mysubjectname3",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "baz"},
		},
		{
			Name:          "anothersubjectname4",
			SubjectDigest: attestation.SubjectDigest{Alg: "sha512", Digest: "boo"},
		},
	}
	allSubjects := [][]attestation.Subject{subjects, subjects2}

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}

	ids := make([]uint64, 0, 2)
	for _, subs := range allSubjects {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			Certificate:  CreateTestCert(t),
			OwnerID:      identifiers.OwnerID,
			RepositoryID: identifiers.RepositoryID,
			DomainID:     identifiers.DomainID,
			CreatedAt:    time.Now(),
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subs, tx)
		assert.NoError(t, err)

		ids = append(ids, uint64(id))
	}

	txc := sqlc.New(tx)
	auditInfo, err := txc.GetHydroDeleteRecordInfoByID(context.Background(), ids)
	assert.NoError(t, err)
	assert.Len(t, auditInfo, 2)

	attSubjects, err := convertJSONRawMessageToSubjects(auditInfo[0].Subjects)
	assert.NoError(t, err)
	assert.Len(t, subjects, 2)
	assert.Equal(t, subjects[0].Name, attSubjects[0].Name)
	assert.Equal(t, subjects[0].String(), attSubjects[0].String())
	assert.Equal(t, subjects[1].Name, attSubjects[1].Name)
	assert.Equal(t, subjects[1].String(), attSubjects[1].String())

	attSubjects2, err := convertJSONRawMessageToSubjects(auditInfo[1].Subjects)
	assert.NoError(t, err)
	assert.NoError(t, err)
	assert.Len(t, attSubjects2, 2)
	assert.Equal(t, subjects2[0].Name, attSubjects2[0].Name)
	assert.Equal(t, subjects2[0].String(), attSubjects2[0].String())
	assert.Equal(t, subjects2[1].Name, attSubjects2[1].Name)
	assert.Equal(t, subjects2[1].String(), attSubjects2[1].String())
}

func TestListAttestationSummariesByRepository_PredicateTypeFilter(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(4321)
	subjects := []attestation.Subject{{
		Name:          "name",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	for _, pt := range predicateTypes {
		// Creating attestation for testing purposes, so we include repository ID
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:       &ownerID,
			RepositoryID:  &repoID,
			DomainID:      2,
			CreatedAt:     time.Now(),
			PredicateType: pt,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	for _, tc := range withPredicateTypeFilterTestCases {
		// first request attestations without specifying the predicate type
		identifiers := attestation.IdentifiersGitHub{
			DomainID:      2,
			OwnerID:       &ownerID,
			PredicateType: tc.predicateTypePattern,
			RepositoryID:  &repoID,
		}
		records, _, err := db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
		assert.NoError(t, err, tc.name)
		// we expect all attestations to be returned
		assert.Len(t, records, tc.expectedRecordNum, tc.name)
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
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(4321)
	subjects := []attestation.Subject{{
		Name:          "name",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	for _, cd := range createdAtDates {
		// Creating attestation for testing purposes, so we include repository ID
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			OwnerID:      &ownerID,
			RepositoryID: &repoID,
			DomainID:     2,
			CreatedAt:    cd,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(10, 0, 0)
	assert.NoError(t, err)

	for _, tc := range createdFilterTestCases {
		identifiers := attestation.IdentifiersGitHub{
			DomainID:     2,
			OwnerID:      &ownerID,
			RepositoryID: &repoID,
			Created:      tc.createdFilter,
		}
		records, _, err := db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
		assert.NoError(t, err, tc.name)
		assert.Len(t, records, tc.expectedRecordNum, tc.name)
	}
}

func TestGetAttestationByRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4233)
	ownerID := uint64(7)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: sd.String(),
		SubjectName:   "foo/bar",
		DomainID:      2,
		RepositoryID:  &repoID,
		OwnerID:       &ownerID,
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
		RepositoryID: &repoID,
		OwnerID:      &ownerID,
	}

	attestation, err := db.GetAttestationByRepository(context.Background(), findIdentifiers)
	assert.Nil(t, err)
	assert.Equal(t, sd.String(), attestation.SubjectDigest)
	assert.Equal(t, "foo/bar", attestation.SubjectName)
	assert.Equal(t, 2, int(attestation.DomainID))
}

func TestGetAttestationByRepository_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4233)
	ownerID := uint64(7)
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		SubjectDigest: sd.String(),
		SubjectName:   "foo/bar",
		DomainID:      2,
		RepositoryID:  &repoID,
		OwnerID:       &ownerID,
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
	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		RepositoryID:   &repoID,
		AttestationIDs: []uint64{id},
	}
	deleted, err := db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, deleted, 1)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           id,
		DomainID:     2,
		RepositoryID: &repoID,
		OwnerID:      &ownerID,
	}

	attestation, err := db.GetAttestationByRepository(context.Background(), findIdentifiers)
	assert.Error(t, err)
	assert.Nil(t, attestation)
}

func TestGetAttestationSummaryByRepository(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4235)
	ownerID := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: sd.String(),
		RepositoryID:  &repoID,
		OwnerID:       &ownerID,
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
		RepositoryID: &repoID,
		OwnerID:      &ownerID,
	}

	attestation, err := db.GetAttestationSummaryByRepository(context.Background(), findIdentifiers)
	assert.Nil(t, err)
	assert.Equal(t, sd.String(), attestation.SubjectDigest)
	assert.Equal(t, "foo/bar", attestation.Subjects[0].Name)
	assert.Equal(t, uint64(id), attestation.ID)
}

func TestGetAttestationSummaryByRepository_DontReturnDeletedAttestations(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4235)
	ownerID := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		CreatedAt:     time.Now(),
		DomainID:      2,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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
	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		RepositoryID:   &repoID,
		AttestationIDs: []uint64{id},
	}
	deleted, err := db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, deleted, 1)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           id,
		RepositoryID: &repoID,
		OwnerID:      &ownerID,
	}

	attestation, err := db.GetAttestationSummaryByRepository(context.Background(), findIdentifiers)
	assert.Error(t, err)
	assert.Nil(t, attestation)
}

func TestListAttestationsByOwnerSubjectDigestWithCursor(t *testing.T) {
	for _, tt := range listAttestationsWithCursorTestCases {
		t.Run(tt.name, func(t *testing.T) {
			db, tx := newTxDatabase(t)
			test.Cleanup(t, tx.Rollback)
			descCursor := &DescCursor{
				tt.cursor,
			}
			ownerID := uint64(1)
			repoID := uint64(1234)
			alg := "sha256"
			digest := "foo"

			identifiers := attestation.IdentifiersGitHub{
				SubjectDigest: fmt.Sprintf("%s:%s", alg, digest),
				OwnerID:       &ownerID,
				RepositoryID:  &repoID,
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

			attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, descCursor)
			assert.NoError(t, err, tt.name)
			assert.Equal(t, len(attestations), tt.expectedSize, tt.name)

			if len(tt.expectedIDs) > 0 {
				assert.Equal(t, pageInfo.StartCursor, tt.expectedIDs[0])
				assert.Equal(t, pageInfo.EndCursor, tt.expectedIDs[len(tt.expectedIDs)-1])
			} else {
				assert.Nil(t, pageInfo)
			}

			// Check the order of the attestations match the expected order
			for i, id := range tt.expectedIDs {
				assert.Equal(t, id, attestations[i].ID, tt.name)
			}
		})
	}
}

func TestListAttestationSummariesByRepositoryWithCursor(t *testing.T) {
	for _, tt := range listAttestationsWithCursorAndCustomSortTestCases {
		t.Run(tt.name, func(t *testing.T) {
			db, tx := newTxDatabase(t)
			test.Cleanup(t, tx.Rollback)

			descCursor := &DescCursor{
				tt.cursor,
			}
			ownerID := uint64(1)
			repoID := uint64(1234)
			alg := "sha256"
			digest := "foo"

			identifiers := attestation.IdentifiersGitHub{
				DomainID:     2,
				OwnerID:      &ownerID,
				RepositoryID: &repoID,
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

			records, pageInfo, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, descCursor)
			assert.NoError(t, err, tt.name)
			assert.Equal(t, tt.expectedSize, len(records), tt.name)
			if len(tt.expectedIDs) > 0 {
				if len(tt.expectedIDs) > 1 {
					assert.Greater(t, records[0].ID, records[1].ID, tt.name)
				}

				assert.Equal(t, int(tt.expectedIDs[0]), int(pageInfo.StartCursor), tt.name)
				assert.Equal(t, int(tt.expectedIDs[len(tt.expectedIDs)-1]), int(pageInfo.EndCursor), tt.name)
			} else {
				assert.Nil(t, pageInfo, tt.name)
			}

			// Check the order of the attestations match the expected order
			for i, id := range tt.expectedIDs {
				assert.Equal(t, id, records[i].ID, tt.name)
			}
		})
	}
}

func TestListAttestationSummariesByRepository_CursorAndSort(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	ownerID := uint64(1)
	repoID := uint64(1234)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	subjects := []attestation.Subject{{
		Name:          "foo",
		SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: "foo"},
	}}

	// Create N attestations for testing
	for i := range 23 {
		// generate subject digest as random string by library
		subjectDigest := generateRandomString(10)

		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:     time.Now(),
			DomainID:      2,
			OwnerID:       identifiers.OwnerID,
			RepositoryID:  identifiers.RepositoryID,
			SubjectDigest: subjectDigest,
		}, tx)
		assert.NoError(t, err)
		assert.Equal(t, i+1, int(id))

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(20, 0, 0)
	assert.NoError(t, err)

	// load results defaulting with descending sort order
	// expect list to begin with ID 23 and end with ID 4
	records, pageInfo, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 20)
	assert.Equal(t, 23, int(records[0].ID))
	assert.Equal(t, 4, int(records[len(records)-1].ID))
	for i := range len(records) - 1 {
		assert.Greater(t, records[i].ID, records[i+1].ID)
	}
	assert.Equal(t, 23, int(pageInfo.StartCursor))
	assert.Equal(t, 4, int(pageInfo.EndCursor))
	assert.True(t, pageInfo.HasNextPage)
	assert.False(t, pageInfo.HasPreviousPage)

	// load results with ascending sort order
	// expect list to begin with ID 1 and end with ID 20
	ascCursor, err := NewCursorWithCustomSort(attestation.SortDirectionAsc, 20, 0, 0)
	assert.NoError(t, err)

	records, pageInfo, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, ascCursor)
	assert.NoError(t, err)
	assert.Len(t, records, 20)
	assert.Equal(t, 1, int(records[0].ID))
	assert.Equal(t, 20, int(records[len(records)-1].ID))
	for i := range len(records) - 1 {
		assert.Less(t, records[i].ID, records[i+1].ID)
	}
	assert.Equal(t, 1, int(pageInfo.StartCursor))
	assert.Equal(t, 20, int(pageInfo.EndCursor))
	assert.True(t, pageInfo.HasNextPage)
	assert.False(t, pageInfo.HasPreviousPage)

	// does the code handle ascending sort order with an after cursor?
	ascCursor, err = NewCursorWithCustomSort(attestation.SortDirectionAsc, 20, 4, 0)
	assert.NoError(t, err)

	records, pageInfo, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, ascCursor)
	assert.NoError(t, err)
	assert.Len(t, records, 19)
	assert.Equal(t, 5, int(records[0].ID))
	assert.Equal(t, 23, int(records[len(records)-1].ID))
	for i := range len(records) - 1 {
		assert.Less(t, records[i].ID, records[i+1].ID)
	}
	assert.Equal(t, 5, int(pageInfo.StartCursor))
	assert.Equal(t, 23, int(pageInfo.EndCursor))
	assert.False(t, pageInfo.HasNextPage)
	assert.False(t, pageInfo.HasPreviousPage)

	// does the code handle ascending sort order with an before cursor?
	ascCursor, err = NewCursorWithCustomSort(attestation.SortDirectionAsc, 15, 0, 4)
	assert.NoError(t, err)

	records, pageInfo, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, ascCursor)
	assert.NoError(t, err)
	assert.Len(t, records, 3)
	assert.Equal(t, 1, int(records[0].ID))
	assert.Equal(t, 3, int(records[len(records)-1].ID))
	for i := range len(records) - 1 {
		assert.Less(t, records[i].ID, records[i+1].ID)
	}
	assert.Equal(t, 1, int(pageInfo.StartCursor))
	assert.Equal(t, 3, int(pageInfo.EndCursor))
	assert.False(t, pageInfo.HasNextPage)
	assert.False(t, pageInfo.HasPreviousPage)
}

func TestDeleteAttestationsByID(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4235)
	ownerID := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		CreatedAt:     time.Now(),
		DomainID:      2,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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
		DomainID:     2,
		ID:           id,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}
	record, err := db.GetAttestationSummaryByRepository(context.Background(), identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	// now mark the attestation as deleted so it is not returned by the list method
	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		RepositoryID:   &repoID,
		AttestationIDs: []uint64{id},
	}
	deleted, err := db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, deleted, 1)

	// confirm the attestation is no longer returned
	record, err = db.GetAttestationSummaryByRepository(context.Background(), identifiers)
	assert.Error(t, err)
	assert.Nil(t, record)

	// confirm the attestation is no longer found
	deleted, err = db.DeleteAttestationsByID(context.Background(), deleteIdentifiers, time.Now())
	assert.Equal(t, ErrAttestationNotFound, err)
	assert.Nil(t, deleted)
}

func TestDeleteAttestationsByID_NoMatchingIdentifiers(t *testing.T) {
	repoID := uint64(4235)
	ownerID := uint64(77)

	badRepoID := uint64(123)
	testcases := []struct {
		name      string
		ownerID   uint64
		repoID    *uint64
		expectErr bool
	}{
		{
			name:      "no matching owner ID",
			ownerID:   uint64(123),
			repoID:    &repoID,
			expectErr: true,
		},
		{
			name:      "no matching repo ID",
			ownerID:   ownerID,
			repoID:    &badRepoID,
			expectErr: true,
		},
		{
			name:      "no matching owner or repo ID",
			ownerID:   uint64(123),
			repoID:    &badRepoID,
			expectErr: true,
		},
		{
			name:    "no repo ID provided",
			ownerID: ownerID,
		},
	}

	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		CreatedAt:     time.Now(),
		DomainID:      2,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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

	for _, tc := range testcases {
		identifiers := attestation.IdentifiersGitHubDelete{
			DomainID:       2,
			OwnerID:        tc.ownerID,
			RepositoryID:   tc.repoID,
			AttestationIDs: []uint64{id},
		}
		deleted, err := db.DeleteAttestationsByID(context.Background(), identifiers, time.Now())
		if tc.expectErr {
			assert.Error(t, err, tc.name)
			assert.Nil(t, deleted, tc.name)
		} else {
			assert.NoError(t, err, tc.name)
			assert.Len(t, deleted, 1, tc.name)
		}
	}
}

func TestDeleteAttestationsBySubjectDigest(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4235)
	ownerID := uint64(77)

	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		DomainID:      2,
		CreatedAt:     time.Now(),
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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

	getIdentifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		ID:           id,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}
	record, err := db.GetAttestationSummaryByRepository(context.Background(), getIdentifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	// now mark the attestation as deleted so it is not returned by the list method
	deleteIdentifiers := attestation.IdentifiersGitHubDelete{
		DomainID:       2,
		OwnerID:        ownerID,
		SubjectDigests: []string{sd.String()},
	}
	records, err := db.DeleteAttestationsBySubjectDigest(context.Background(), deleteIdentifiers, time.Now())
	assert.NoError(t, err)
	assert.Len(t, records, 1)

	// confirm the attestation is no longer returned
	record, err = db.GetAttestationSummaryByRepository(context.Background(), getIdentifiers)
	assert.Error(t, err)
	assert.Nil(t, record)

	// confirm the attestation is no longer found
	records, err = db.DeleteAttestationsBySubjectDigest(context.Background(), deleteIdentifiers, time.Now())
	assert.Equal(t, ErrAttestationNotFound, err)
	assert.Nil(t, records)
}

func TestDeleteAttestationsBySubjectDigest_NoMatchingIdentifiers(t *testing.T) {
	repoID := uint64(4235)
	ownerID := uint64(77)

	badRepoID := uint64(123)
	testcases := []struct {
		name      string
		ownerID   uint64
		repoID    *uint64
		expectErr bool
	}{
		{
			name:      "no matching owner ID",
			ownerID:   uint64(123),
			repoID:    &repoID,
			expectErr: true,
		},
		{
			name:      "no matching repo ID",
			ownerID:   ownerID,
			repoID:    &badRepoID,
			expectErr: true,
		},
		{
			name:      "no matching owner or repo ID",
			ownerID:   uint64(123),
			repoID:    &badRepoID,
			expectErr: true,
		},
		{
			name:    "no repo ID provided",
			ownerID: ownerID,
		},
	}

	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		Certificate:   CreateTestCert(t),
		CreatedAt:     time.Now(),
		DomainID:      2,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
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

	for _, tc := range testcases {
		identifiers := attestation.IdentifiersGitHubDelete{
			DomainID:       2,
			OwnerID:        tc.ownerID,
			RepositoryID:   tc.repoID,
			SubjectDigests: []string{sd.String()},
		}
		deleted, err := db.DeleteAttestationsBySubjectDigest(context.Background(), identifiers, time.Now())
		if tc.expectErr {
			assert.Error(t, err, tc.name)
			assert.Nil(t, deleted, tc.name)
		} else {
			assert.NoError(t, err, tc.name)
			assert.Len(t, deleted, 1, tc.name)
		}
	}
}

func TestListAttestationSummariesByRepository_PartialSubjectNameMatch(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	subjectDigest := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4235)
	ownerID := uint64(77)

	subjectNameCollections := [][]string{
		{"fo%o/bar", "foo/baz", "foo/zed"},
		{"boo/bar", "boo/baz", "boo/zed"},
	}

	// Create two attestations, each associated with a distinct set of subject names
	for _, subjectNames := range subjectNameCollections {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:    time.Now(),
			DomainID:     2,
			OwnerID:      &ownerID,
			RepositoryID: &repoID,
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

	cursor, err := NewCursor(30, 0, 0)
	assert.NoError(t, err)

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}

	// Fetch attestations without any subject name filtering
	records, _, err := db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)

	// Fetch attestations with 'foo' prefix matching
	identifiers.SubjectName = "%fo\\%o%"
	records, _, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, 3, int(records[0].SubjectCount))

	// Fetch attestations with boo prefix matching
	identifiers.SubjectName = "%boo%"
	records, _, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, 3, int(records[0].SubjectCount))

	// Fetch attestations with 'o/ze' substring matching
	identifiers.SubjectName = "%o/ze%"
	records, _, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, 3, int(records[0].SubjectCount))
	assert.Equal(t, 3, int(records[1].SubjectCount))

	// Fetch attestations with 'zed' suffix matching
	identifiers.SubjectName = "%zed%"
	records, _, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 2)
	assert.Equal(t, 3, int(records[0].SubjectCount))
	assert.Equal(t, 3, int(records[1].SubjectCount))

	// Fetch attestations with full 'foo/bar' subject name matching
	identifiers.SubjectName = "%fo\\%o/bar%"
	records, _, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	assert.Equal(t, 3, int(records[0].SubjectCount))

	// Fail to fetch any attestations with subject name matching
	identifiers.SubjectName = "%no/subject%"
	records, _, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Empty(t, records)
}

func TestListAttestationSummariesByRepository_TotalAttestationCount(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	repoID := uint64(4235)
	ownerID := uint64(77)
	subjects := []attestation.Subject{
		{
			Name: "foo/bar",
			SubjectDigest: attestation.SubjectDigest{
				Alg:    "sha256",
				Digest: "foo",
			},
		},
		{
			Name: "foo/baz",
			SubjectDigest: attestation.SubjectDigest{
				Alg:    "sha256",
				Digest: "baz",
			},
		},
	}
	for range 100 {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:     time.Now(),
			DomainID:      2,
			OwnerID:       &ownerID,
			PredicateType: attestation.PredicateSLSAProvenance,
			RepositoryID:  &repoID,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(30, 0, 0)
	assert.NoError(t, err)

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	// Expect to get 30 attestations but a total count of 100
	records, pageInfo, err := db.ListAttestationSummariesByRepository(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 30)
	assert.Equal(t, 100, int(records[0].TotalCount))
	assert.Equal(t, 71, int(pageInfo.EndCursor))
	assert.Equal(t, 100, int(pageInfo.StartCursor))

	// Expect to get the next 30 attestations but still get a total count of 100
	cursor, err = NewCursor(30, pageInfo.EndCursor, 0)
	assert.NoError(t, err)
	records, pageInfo, err = db.ListAttestationSummariesByRepository(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 30)
	assert.Equal(t, 100, int(records[0].TotalCount))
	assert.Equal(t, 41, int(pageInfo.EndCursor))
	assert.Equal(t, 70, int(pageInfo.StartCursor))
}

func TestListAttestationSummariesByRepositoryWithFilters_TotalAttestationCount(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	repoID := uint64(4235)
	ownerID := uint64(77)
	subjects := []attestation.Subject{
		{
			Name: "foo/bar",
			SubjectDigest: attestation.SubjectDigest{
				Alg:    "sha256",
				Digest: "foo",
			},
		},
		{
			Name: "foo/baz",
			SubjectDigest: attestation.SubjectDigest{
				Alg:    "sha256",
				Digest: "baz",
			},
		},
	}
	for range 100 {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:     time.Now(),
			DomainID:      2,
			OwnerID:       &ownerID,
			RepositoryID:  &repoID,
			PredicateType: attestation.PredicateSLSAProvenance,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)

		err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
		assert.NoError(t, err)
	}

	cursor, err := NewCursor(30, 0, 0)
	assert.NoError(t, err)

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		DomainID:      2,
		PredicateType: "https://slsa.dev/provenance/",
	}
	// Expect to get 30 attestations but a total count of 100
	records, pageInfo, err := db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 30)
	assert.Equal(t, 100, int(records[0].TotalCount))
	assert.Equal(t, 71, int(pageInfo.EndCursor))
	assert.Equal(t, 100, int(pageInfo.StartCursor))

	// Expect to get the next 30 attestations but still get a total count of 100
	cursor, err = NewCursor(30, pageInfo.EndCursor, 0)
	assert.NoError(t, err)
	records, pageInfo, err = db.ListAttestationSummariesByRepositoryWithFilters(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 30)
	assert.Equal(t, 100, int(records[0].TotalCount))
	assert.Equal(t, 41, int(pageInfo.EndCursor))
	assert.Equal(t, 70, int(pageInfo.StartCursor))
}

func TestGetBundleIdentifiersByAttestationID(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	attestationIDs := []uint64{}
	sd := attestation.SubjectDigest{Alg: "sha256", Digest: "foo"}
	repoID := uint64(4233)
	ownerID := uint64(7)
	for range 3 {
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:    time.Now().Truncate(time.Second),
			DomainID:     2,
			RepositoryID: &repoID,
			OwnerID:      &ownerID,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)
		attestationIDs = append(attestationIDs, id)

		subjects := []attestation.Subject{{
			Name:          "foo/bar",
			SubjectDigest: sd,
		}}
		err = db.StoreAttestationSubjects(context.Background(), id, subjects, tx)
		assert.NoError(t, err)
	}

	identifiers := attestation.IdentifiersGitHubGet{
		AttestationIDs: attestationIDs,
		DomainID:       2,
		OwnerID:        ownerID,
	}

	records, err := db.ListBundleIdentifiersByAttestationID(context.Background(), identifiers)
	assert.NoError(t, err)
	assert.Len(t, records, 3)
	for i, r := range records {
		assert.Equal(t, attestationIDs[i], r.ID)
		assert.Equal(t, ownerID, *r.OwnerID)
		assert.Equal(t, repoID, *r.RepositoryID)
	}
}

func TestGetBundleIdentifiersBySubjectDigest(t *testing.T) {
	db, tx := newTxDatabase(t)
	test.Cleanup(t, tx.Rollback)

	subjectDigests := []string{}
	repoID := uint64(4233)
	ownerID := uint64(7)
	for i := range 3 {
		sd := attestation.SubjectDigest{Alg: "sha256", Digest: fmt.Sprintf("foo%d", i)}
		id, err := db.StoreAttestation(context.Background(), &attestation.Record{
			CreatedAt:    time.Now().Truncate(time.Second),
			DomainID:     2,
			RepositoryID: &repoID,
			OwnerID:      &ownerID,
		}, tx)
		assert.NoError(t, err)
		assert.NotNil(t, id)
		subjectDigests = append(subjectDigests, sd.String())

		subjects := []attestation.Subject{{
			Name:          "foo/bar",
			SubjectDigest: sd,
		}}
		err = db.StoreAttestationSubjects(context.Background(), id, subjects, tx)
		assert.NoError(t, err)
	}

	identifiers := attestation.IdentifiersGitHubGet{
		DomainID:       2,
		OwnerID:        ownerID,
		SubjectDigests: subjectDigests,
	}

	records, err := db.ListBundleIdentifiersBySubjectDigest(context.Background(), identifiers)
	assert.NoError(t, err)
	assert.Len(t, records, 3)
	for i, r := range records {
		assert.Equal(t, subjectDigests[i], r.SubjectDigest)
		assert.Equal(t, ownerID, *r.OwnerID)
		assert.Equal(t, repoID, *r.RepositoryID)
	}
}
