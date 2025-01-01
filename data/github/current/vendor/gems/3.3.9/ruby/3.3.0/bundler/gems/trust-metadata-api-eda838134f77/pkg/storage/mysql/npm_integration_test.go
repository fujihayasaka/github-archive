//go:build integration

package mysql

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/github/trust-metadata-api/db/sqlc"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/stretchr/testify/assert"
)

const (
	testPURL        = "pkg:foo/bar"
	testNPMDomainID = 1
)

/*
  GetAttestationsByPurl
*/

func TestGetAttestationsByPurl(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl: testPURL,
	}
	attestations, err := db.GetAttestationsByPurl(context.Background(), identifiers)
	assert.Nil(t, err)
	assert.Empty(t, attestations)
}

func TestGetAttestationsByPurl_MismatchedDomainID(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:      testPURL,
		DomainID:  testNPMDomainID,
		CreatedAt: time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	subjects := []attestation.Subject{{Name: "name", SubjectDigest: attestation.SubjectDigest{Digest: "digest"}}}
	err = db.StoreAttestationSubjects(context.Background(), uint64(id), subjects, tx)
	assert.NoError(t, err)

	identifiers := attestation.IdentifiersNPM{
		Purl:     testPURL,
		DomainID: 12345,
	}
	attestations, err := db.GetAttestationsByPurl(context.Background(), identifiers)
	assert.NoError(t, err)
	assert.Empty(t, attestations)
}

func TestStoreRetrieveInvalidCert(t *testing.T) {
	ctx := context.Background()
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	storeAttestationParams, err := toSQLCStoreNPMAttestation(&attestation.Record{
		Purl:      testPURL,
		CreatedAt: time.Now(),
	})
	assert.NoError(t, err)

	storeAttestationParams.Certificate = sql.NullString{
		String: "invalid cert",
		Valid:  true,
	}
	q := sqlc.New(db.db)
	result, err := q.StoreNPMAttestation(ctx, storeAttestationParams)
	assert.NoError(t, err)
	assert.NotNil(t, result)

	attestationID, _ := result.LastInsertId()

	q.InsertAttestationSubject(ctx, sqlc.InsertAttestationSubjectParams{
		AttestationID: uint64(attestationID),
		SubjectDigest: "digest",
		SubjectName:   "name"})

	identifiers := attestation.IdentifiersNPM{
		Purl: testPURL,
	}
	attestations, err := db.GetAttestationsByPurl(ctx, identifiers)
	assert.Len(t, attestations, 0)

	var errConvertFromSQLC ErrConvertFromSQLC
	assert.ErrorAs(t, err, &errConvertFromSQLC)
	assert.NotZero(t, errConvertFromSQLC.id)
}

/*
  GetAttestationByPurlPredicateType
*/

func TestGetAttestationByPurlPredicateType(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl: testPURL,
	}
	predicateTypes := []string{
		"https://slsa.dev/provenance/v0.2",
		"https://slsa.dev/provenance/v1",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), identifiers, predicateTypes)

	assert.Error(t, err)
	assert.Equal(t, err.Error(), "no attestation for given (purl, predicateType) exists")
	assert.Empty(t, attestation)
}

func TestStoreGetAttestationByPurlPredicateType_WithSLSA1ProvenanceAttestationWhenHavingBothSLSA1AndSLSA02ReverseOrder(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:     testPURL,
		DomainID: testNPMDomainID,
	}
	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: "https://slsa.dev/provenance/v0.2",
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	id, err = db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: "https://slsa.dev/provenance/v1",
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	predicateTypes := []string{
		"https://slsa.dev/provenance/v0.2",
		"https://slsa.dev/provenance/v1",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), identifiers, predicateTypes)
	assert.NoError(t, err)
	assert.Equal(t, identifiers.Purl, attestation.Purl)
	assert.Equal(t, identifiers.DomainID, attestation.DomainID)
	assert.Equal(t, "https://slsa.dev/provenance/v1", attestation.PredicateType)
}

func TestStoreGetAttestationByPurlPredicateType_WithSLSA1ProvenanceAttestationWhenHavingBothSLSA1AndSLSA02(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:     testPURL,
		DomainID: testNPMDomainID,
	}
	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: "https://slsa.dev/provenance/v1",
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	id, err = db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: "https://slsa.dev/provenance/v0.2",
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	predicateTypes := []string{
		"https://slsa.dev/provenance/v0.2",
		"https://slsa.dev/provenance/v1",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), identifiers, predicateTypes)
	assert.NoError(t, err)
	assert.Equal(t, identifiers.Purl, attestation.Purl)
	assert.Equal(t, identifiers.DomainID, attestation.DomainID)
	assert.Equal(t, "https://slsa.dev/provenance/v1", attestation.PredicateType)
}

func TestStoreGetAttestationByPurlPredicateType_WithSLSA1ProvenanceAttestation(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:          testPURL,
		DomainID:      testNPMDomainID,
		PredicateType: "https://slsa.dev/provenance/v1",
	}
	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: identifiers.PredicateType,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	predicateTypes := []string{
		"https://slsa.dev/provenance/v0.2",
		"https://slsa.dev/provenance/v1",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), identifiers, predicateTypes)
	assert.NoError(t, err)
	assert.Equal(t, identifiers.Purl, attestation.Purl)
	assert.Equal(t, identifiers.DomainID, attestation.DomainID)
	assert.Equal(t, "https://slsa.dev/provenance/v1", attestation.PredicateType)
}

func TestStoreGetAttestationByPurlPredicateType_WithSLSA02ProvenanceAttestation_WithoutPredicateType(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:          testPURL,
		DomainID:      testNPMDomainID,
		PredicateType: "https://slsa.dev/provenance/v0.2",
	}
	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: identifiers.PredicateType,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	predicateTypes := []string{
		"",
		"",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), attestation.IdentifiersNPM{
		Purl:     identifiers.Purl,
		DomainID: identifiers.DomainID,
	}, predicateTypes)

	assert.Error(t, err)
	assert.Equal(t, err.Error(), "no attestation for given (purl, predicateType) exists")
	assert.Empty(t, attestation)
}

func TestStoreGetAttestationByPurlPredicateType_WithSLSA02ProvenanceAttestation(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:          testPURL,
		DomainID:      testNPMDomainID,
		PredicateType: "https://slsa.dev/provenance/v0.2",
	}
	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:          identifiers.Purl,
		DomainID:      identifiers.DomainID,
		PredicateType: identifiers.PredicateType,
		CreatedAt:     time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	predicateTypes := []string{
		"https://slsa.dev/provenance/v0.2",
		"https://slsa.dev/provenance/v1",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), identifiers, predicateTypes)
	assert.NoError(t, err)
	assert.Equal(t, identifiers.Purl, attestation.Purl)
	assert.Equal(t, identifiers.DomainID, attestation.DomainID)
	assert.Equal(t, "https://slsa.dev/provenance/v0.2", attestation.PredicateType)
}

func TestStoreGetAttestationByPurlPredicateType_WithoutAnyProvenanceAttestation(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:          testPURL,
		DomainID:      testNPMDomainID,
		PredicateType: "https://slsa.dev/provenance/v0.2",
	}
	id, err := db.StoreNPMAttestation(context.Background(), &attestation.Record{
		Purl:      identifiers.Purl,
		DomainID:  identifiers.DomainID,
		CreatedAt: time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	predicateTypes := []string{
		"https://slsa.dev/provenance/v0.2",
		"https://slsa.dev/provenance/v1",
	}

	attestation, err := db.GetAttestationByPurlPredicateType(context.Background(), identifiers, predicateTypes)
	assert.Error(t, err)
	// TODO: Customize this error message
	assert.Equal(t, err.Error(), "no attestation for given (purl, predicateType) exists")
	assert.Empty(t, attestation)
}

/*
  StoreNPMAttestation
*/

func TestStoreGetAttestationsByPurl(t *testing.T) {
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	identifiers := attestation.IdentifiersNPM{
		Purl:     testPURL,
		DomainID: testNPMDomainID,
	}
	record := &attestation.Record{
		Purl:      identifiers.Purl,
		DomainID:  identifiers.DomainID,
		CreatedAt: time.Now(),
	}
	subjects := []attestation.Subject{{Name: "name", SubjectDigest: attestation.SubjectDigest{Digest: "digest"}}}

	id, err := db.StoreNPMAttestation(context.Background(), record, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	err = db.StoreAttestationSubjects(context.Background(), id, subjects, tx)
	assert.NoError(t, err)

	attestations, err := db.GetAttestationsByPurl(context.Background(), identifiers)

	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Equal(t, identifiers.Purl, attestations[0].Purl)
	assert.Equal(t, identifiers.DomainID, attestations[0].DomainID)
	assert.Equal(t, subjects[0].Name, attestations[0].SubjectName)
	assert.Equal(t, subjects[0].SubjectDigest.String(), attestations[0].SubjectDigest)
}

func TestUniquePurlPredicateType(t *testing.T) {
	// We allow to insert duplicate attestation with the same purl and domain id
	// https://github.com/github/trust-metadata-api/pull/278#discussion_r123679375
	ctx := context.Background()
	db, tx := newTransactionalDatabase(t, DBURI)
	defer tx.Rollback()

	id, err := db.StoreNPMAttestation(ctx, &attestation.Record{
		Purl:      testPURL,
		DomainID:  testNPMDomainID,
		CreatedAt: time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)

	// insert same record again
	id, err = db.StoreNPMAttestation(ctx, &attestation.Record{
		Purl:      testPURL,
		DomainID:  testNPMDomainID,
		CreatedAt: time.Now(),
	}, tx)
	assert.NoError(t, err)
	assert.NotNil(t, id)
}
