package service

import (
	"context"
	"math/rand"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var githubServiceClient = auth.ServiceClient{
	ClientID: "dotcom",
	Domain:   "github",
	DomainID: 2,
}

func createTestRecord(t *testing.T, subjectDigest string, ownerID, repoID *uint64) attestation.Record {
	return attestation.Record{
		ID:            999,
		OwnerID:       ownerID,
		RepositoryID:  repoID,
		SubjectDigest: subjectDigest,
		SubjectName:   SubjectName,
		Bundle:        data.SigstoreBundleFromGenerateBuildProvenance(t),
	}
}

func TestService_CreateAttestationFromGitHub(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.NotZero(t, attestationIdentifier)
	assert.Nil(t, err)
}

func TestService_CreateAttestationNotFromGitHub(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundle(t) // bundle is not from GitHub
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	_, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.Error(t, err)
	assert.EqualError(t, err, "BadRequestError: issuer is not GitHub")
}

func TestService_GetAttestationByRepository(t *testing.T) {
	store := storage.NewInMemoryStore()
	tma := NewTestTMAWithStore(t, store)

	// create new Attestation instance for test
	subjectDigest := SubjectDigest
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, subjectDigest, &ownerID, &repoID)
	bundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	// store attestation
	err = store.StoreGitHubAttestation(context.Background(), &record, bundle)
	assert.NoError(t, err)

	ctx := auth.WithCurrentClient(context.Background(), githubServiceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		ID:           record.ID,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	storedRecord, err := tma.GetAttestationByRepository(ctx, attestationIdentifier)

	assert.NotNil(t, storedRecord)
	assert.Equal(t, subjectDigest, storedRecord.SubjectDigest)
	assert.Equal(t, SubjectName, storedRecord.SubjectName)
	assert.NotZero(t, storedRecord.SASUrl)
	assert.NoError(t, err)
}

func TestService_ListAttestations_By_Repository(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	subjectDigest := SubjectDigest
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, subjectDigest, &ownerID, &repoID)
	bundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	// store attestation
	err = tma.store.StoreGitHubAttestation(context.Background(), &record, bundle)
	assert.NoError(t, err)

	ctx := auth.WithCurrentClient(context.Background(), githubServiceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	cursor := mysql.Cursor{
		PerPage: 30,
	}

	attestationRecords, err := tma.ListAttestationsByRepository(ctx, attestationIdentifier, &cursor)
	attestations := attestationRecords.Attestations

	assert.Len(t, attestations, 1)
	assert.Equal(t, subjectDigest, attestations[0].SubjectDigest)
	assert.Equal(t, SubjectName, attestations[0].SubjectName)
	assert.NoError(t, err)
}

func TestService_ListAttestations_NilCursor(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	subjectDigest := SubjectDigest
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, subjectDigest, &ownerID, &repoID)
	bundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	// store attestation
	err = tma.store.StoreGitHubAttestation(context.Background(), &record, bundle)
	assert.NoError(t, err)

	ctx := auth.WithCurrentClient(context.Background(), githubServiceClient)

	attestationIdentifier := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	records, err := tma.ListAttestationsByRepository(ctx, attestationIdentifier, nil)
	assert.Nil(t, records)
	assert.NoError(t, err)
}

func TestService_GetAttestationSASByRepository(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, SubjectDigest, &ownerID, &repoID)
	sgBundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	err = tma.store.StoreGitHubAttestation(context.Background(), &record, sgBundle)
	require.NoError(t, err)

	ctx := auth.WithCurrentClient(context.Background(), githubServiceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		ID:           record.ID,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	sas, err := tma.GetAttestationSASByRepository(ctx, attestationIdentifier)

	assert.NotZero(t, sas)
	assert.Nil(t, err)
}

func TestService_GetAttestationSASByRepository_FetchSASFail(t *testing.T) {
	tma := NewTestTMAWithStore(t, &storage.SASFailInMemoryStore{})

	// create new Attestation instance for test
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, SubjectDigest, &ownerID, &repoID)
	sgBundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	err = tma.store.StoreGitHubAttestation(context.Background(), &record, sgBundle)
	require.NoError(t, err)

	ctx := auth.WithCurrentClient(context.Background(), githubServiceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		ID:           record.ID,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	sas, err := tma.GetAttestationSASByRepository(ctx, attestationIdentifier)
	assert.Zero(t, sas)
	assert.ErrorContains(t, err, "failed to generate SAS")
}

func TestService_GetAttestationSASByRepository_FetchAttestationFail(t *testing.T) {
	tma := NewTestTMAWithStore(t, &storage.GitHubFetchFailInMemoryStore{})

	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, SubjectDigest, &ownerID, &repoID)
	sgBundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	err = tma.store.StoreGitHubAttestation(context.Background(), &record, sgBundle)
	require.NoError(t, err)

	ctx := auth.WithCurrentClient(context.Background(), githubServiceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		ID:           record.ID,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	sas, err := tma.GetAttestationSASByRepository(ctx, attestationIdentifier)

	assert.Zero(t, sas)
	assert.ErrorIs(t, err, mysql.ErrAttestationNotFound)
}

func TestService_CreateAttestation(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	ownerID, repoID := uint64(1), uint64(123)
	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.NotZero(t, attestationIdentifier)
	assert.NoError(t, err)
}

func TestService_CreateAttestationDuplicate(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	ownerID, repoID := uint64(1), uint64(123)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, identifiers)
	assert.NotZero(t, attestationIdentifier)
	assert.NoError(t, err)

	attestationIdentifier, err = tma.CreateAttestation(context.Background(), bundle, identifiers)
	assert.Nil(t, attestationIdentifier)
	assert.ErrorAs(t, err, &ConflictError{})
	assert.Contains(t, clientFacingError(err), "attestation for given (purl, predicateType) already exists")
	assert.Equal(t, err.Error(), "ConflictError: attestation for given (purl, predicateType) already exists")
}

func TestService_CreateAttestation_DatabaseError(t *testing.T) {
	tma := NewTestTMAWithStore(t, &storage.FailInMemoryStore{})

	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	ownerID, repoID := uint64(1), uint64(123)
	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.Nil(t, attestationIdentifier)
	assert.ErrorAs(t, err, &mysql.ErrStoreRecord{})
	assert.Equal(t, "internal error", clientFacingError(err))
}

func TestService_CreateAttestation_InvalidParams(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	bundle.MediaType = "invalid media type"
	ownerID, repoID := uint64(1), uint64(123)
	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.Zero(t, attestationIdentifier)
	assert.ErrorAs(t, err, &BadRequestError{})
	assert.ErrorIs(t, err, sgbundle.ErrValidation)
	assert.Contains(t, clientFacingError(err), "validation error: unsupported media type")
	assert.Equal(t, err.Error(), "BadRequestError: error getting bundle version: validation error: unsupported media type: invalid media type")
}

func TestService_CreateAttestation_VerifySignatureFail(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	ownerID, repoID := uint64(1), uint64(123)
	bundle.Content.(*protobundle.Bundle_DsseEnvelope).DsseEnvelope.Signatures[0].Sig = []byte("invalid signature")
	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.Zero(t, attestationIdentifier)
	assert.ErrorAs(t, err, &BadRequestError{})
}

func TestService_CreateAttestation_ParseSignatureEnvelopeFail(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	bundle.Content.(*protobundle.Bundle_DsseEnvelope).DsseEnvelope.Payload = []byte("invalid payload")
	ownerID, repoID := uint64(1), uint64(123)
	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	})
	assert.Zero(t, attestationIdentifier)
	assert.ErrorAs(t, err, &BadRequestError{})
}

func TestService_ListAttestations_By_SubjectDigest(t *testing.T) {
	store := storage.NewInMemoryStore()
	tma := NewTestTMAWithStore(t, store)

	// create new Attestation instance for test
	subjectDigest := SubjectDigest
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, subjectDigest, &ownerID, &repoID)
	bundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	// store attestation
	err = store.StoreGitHubAttestation(context.Background(), &record, bundle)
	assert.NoError(t, err)

	serviceClient := auth.ServiceClient{
		ClientID: "dotcom",
		Domain:   "github",
		DomainID: 2,
	}
	ctx := auth.WithCurrentClient(context.Background(), serviceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		SubjectDigest: subjectDigest,
		OwnerID:       record.OwnerID,
		RepositoryID:  record.RepositoryID,
	}

	cursor := mysql.Cursor{
		PerPage: 30,
	}

	attestationRecords, err := tma.ListAttestationsBySubjectDigest(ctx, attestationIdentifier, &cursor)
	attestations := attestationRecords.Attestations

	assert.Len(t, attestations, 1)
	assert.Equal(t, subjectDigest, attestations[0].SubjectDigest)
	assert.Equal(t, SubjectName, attestations[0].SubjectName)
	assert.NoError(t, err)
}

func TestService_ListAttestationSummariesByRepository(t *testing.T) {
	store := storage.NewInMemoryStore()
	tma := NewTestTMAWithStore(t, store)

	// create new Attestation instance for test
	subjectDigest := SubjectDigest
	ownerID, repoID := rand.Uint64(), rand.Uint64()
	record := createTestRecord(t, subjectDigest, &ownerID, &repoID)
	bundle, err := sgbundle.NewBundle(record.Bundle)
	require.NoError(t, err)

	// store attestation
	err = store.StoreGitHubAttestation(context.Background(), &record, bundle)
	assert.NoError(t, err)

	serviceClient := auth.ServiceClient{
		ClientID: "dotcom",
		Domain:   "github",
		DomainID: 2,
	}
	ctx := auth.WithCurrentClient(context.Background(), serviceClient)
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestationIdentifier := attestation.IdentifiersGitHub{
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}

	cursor := mysql.Cursor{
		PerPage: 30,
	}

	attestationRecords, err := tma.ListAttestationSummariesByRepository(ctx, attestationIdentifier, &cursor)
	attestations := attestationRecords.Attestations

	assert.Len(t, attestations, 1)
	assert.NoError(t, err)
}
