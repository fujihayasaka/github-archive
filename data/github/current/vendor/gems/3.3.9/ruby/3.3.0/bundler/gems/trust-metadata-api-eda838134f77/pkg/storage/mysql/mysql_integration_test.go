//go:build integration

package mysql

import (
	"context"
	"database/sql"
	"fmt"
	"testing"

	"math/rand"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/stretchr/testify/assert"
)

const (
	charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	DBURI   = "tma:TMAdevP4ssw0rd!@tcp(127.0.0.1:3337)/tma_dev?parseTime=true"
)

var seededRand = rand.New(rand.NewSource(time.Now().UnixNano()))

func generateRandomString(length int) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[seededRand.Intn(len(charset))]
	}
	return string(b)
}

// newTransactionalDatabase creates a LiveDatabase with a cancellable transaction.
// Note that you must explicitly call cancel() to rollback the transaction.
func newTransactionalDatabase(t *testing.T, uri string) (*LiveDatabase, *sql.Tx) {
	db, err := sql.Open("mysql", uri)
	// Reset database every time we run tests
	_, err = db.Exec("TRUNCATE TABLE attestations")
	assert.Nil(t, err)
	_, err = db.Exec("TRUNCATE TABLE attestations_subjects")
	assert.Nil(t, err)
	tx, err := db.Begin()
	assert.Nil(t, err)
	// TODO: fail if database is not empty (select(count) on all tables)
	return NewLiveDatabaseFromConn(tx, log.NewNullLogger(), stats.NullStatter), tx
}

func TestListAttestationsByOwnerSubjectDigest(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
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
	db, tx := newTransactionalDatabase(t, DBURI)
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

func TestGetAttestationByRepository_MismatchedDomainID(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
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

func TestStoreListAttestationsByOwnerSubjectDigest(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
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

	attestations, pageInfo, err := db.ListAttestationsByOwnerSubjectDigest(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, identifiers.SubjectDigest, attestations[0].SubjectDigest)
	assert.Equal(t, identifiers.DomainID, attestations[0].DomainID)
	assert.Equal(t, pageInfo.EndCursor, uint64(1))
	assert.Equal(t, pageInfo.StartCursor, uint64(1))
}

func TestStoreListAttestationsByOwnerSubjectDigestWithoutRepository(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
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

func TestListAttestationsByRepository(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
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

	attestations, pageInfo, err := db.ListAttestationsByRepository(context.Background(), identifiers, &cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, fmt.Sprintf("%s:%s", alg, digest), attestations[0].SubjectDigest)
	assert.Equal(t, pageInfo.EndCursor, uint64(1))
	assert.Equal(t, pageInfo.StartCursor, uint64(1))
}

func TestListAttestationsByRepositoryNoResults(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	ownerId := uint64(1)
	repoId := uint64(1234)

	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerId,
		RepositoryID: &repoId,
	}

	cursor := Cursor{
		PerPage: 10,
	}
	attestations, pageInfo, err := db.ListAttestationsByRepository(context.Background(), identifiers, &cursor)
	assert.Nil(t, err)
	assert.Empty(t, attestations)
	assert.Empty(t, pageInfo)
}

func TestListAttestationSummariesByRepository(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
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
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, uint64(1), attestations[0].SubjectCount)
	assert.Equal(t, pageInfo.EndCursor, uint64(1))
	assert.Equal(t, pageInfo.StartCursor, uint64(1))
}

func TestGetAttestationByRepository(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	alg := "sha256"
	digest := "foo"
	subjectDigest := fmt.Sprintf("%s:%s", alg, digest)
	subjectName := "foo/bar"

	repoId := uint64(4233)
	ownerId := uint64(7)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: subjectDigest,
		SubjectName:   subjectName,
		DomainID:      identifiers.DomainID,
		RepositoryID:  identifiers.RepositoryID,
		OwnerID:       identifiers.OwnerID,
		CreatedAt:     time.Now(),
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
		PerPage: 1,
	}
	// Get the first attestation so we can get its ID
	attestations, _, err := db.ListAttestationsByRepository(context.Background(), identifiers, &cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           attestations[0].ID,
		DomainID:     identifiers.DomainID,
		RepositoryID: identifiers.RepositoryID,
		OwnerID:      identifiers.OwnerID,
	}

	attestation, err := db.GetAttestationByRepository(context.Background(), findIdentifiers)
	assert.Nil(t, err)
	assert.Equal(t, subjectDigest, attestation.SubjectDigest)
	assert.Equal(t, subjectName, attestation.SubjectName)
	assert.Equal(t, identifiers.DomainID, attestation.DomainID)
}

func TestGetAttestationSummaryByRepository(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	alg := "sha256"
	digest := "foo"
	subjectDigest := fmt.Sprintf("%s:%s", alg, digest)
	subjectName := "foo/bar"

	repoId := uint64(4235)
	ownerId := uint64(77)
	identifiers := attestation.IdentifiersGitHub{
		RepositoryID: &repoId,
		OwnerID:      &ownerId,
	}
	id, err := db.StoreAttestation(context.Background(), &attestation.Record{
		SubjectDigest: subjectDigest,
		RepositoryID:  identifiers.RepositoryID,
		OwnerID:       identifiers.OwnerID,
		CreatedAt:     time.Now(),
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
		PerPage: 1,
	}
	// Get the first attestation so we can get its ID
	attestations, _, err := db.ListAttestationsByRepository(context.Background(), identifiers, &cursor)
	assert.Nil(t, err)
	assert.Len(t, attestations, 1)

	findIdentifiers := attestation.IdentifiersGitHub{
		ID:           attestations[0].ID,
		RepositoryID: identifiers.RepositoryID,
		OwnerID:      identifiers.OwnerID,
	}

	attestation, err := db.GetAttestationSummaryByRepository(context.Background(), findIdentifiers)
	assert.Nil(t, err)
	assert.Equal(t, subjectDigest, attestation.SubjectDigest)
	fmt.Println(attestation.ID)
	assert.Equal(t, uint64(id), attestation.ID)
}

type getAttestationsCursorTest struct {
	name                    string
	cursor                  Cursor
	expectedSize            int
	expectedIds             []uint64
	createNumOfAttestations int
}

func TestListAttestationsByOwnerSubjectDigestWithCursor(t *testing.T) {
	tests := []getAttestationsCursorTest{
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

	for _, tt := range tests {
		db, tx := newTransactionalDatabase(t, DBURI)
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
		for i := 0; i < tt.createNumOfAttestations; i++ {
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
	tests := []getAttestationsCursorTest{
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

	for _, tt := range tests {
		db, tx := newTransactionalDatabase(t, DBURI)
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
		for i := 0; i < tt.createNumOfAttestations; i++ {
			// genrate subject digest as random string by library
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

		attestations, pageInfo, err := db.ListAttestationsByRepository(context.Background(), identifiers, &tt.cursor)
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
