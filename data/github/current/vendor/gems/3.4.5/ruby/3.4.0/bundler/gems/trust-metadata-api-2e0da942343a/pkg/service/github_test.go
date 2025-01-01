package service

import (
	"context"
	"math/rand"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/test/data"
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

func TestService_CreateReleaseAttestation(t *testing.T) {
	store := storage.NewInMemoryStore()
	tma := NewTestTMAWithStore(t, store)
	bundle := data.SigstoreBundleGitHubRelease(t)
	ownerID, repoID := uint64(1), uint64(123)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:                 2,
		OwnerID:                  &ownerID,
		RepositoryID:             &repoID,
		ExpectReleaseAttestation: true,
	}

	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, identifiers)
	assert.NotZero(t, attestationIdentifier)
	assert.NoError(t, err)

	// Ensure that the release record was created
	assert.Equal(t, store.ReleaseCount(), 1)
}

func TestService_CreateReleaseAttestationWrongType(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	ownerID, repoID := uint64(1), uint64(123)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:                 2,
		OwnerID:                  &ownerID,
		RepositoryID:             &repoID,
		ExpectReleaseAttestation: true,
	}

	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, identifiers)
	assert.Zero(t, attestationIdentifier)
	assert.ErrorContains(t, err, "this endpoint only supports release attestations with predicate type \"https://in-toto.io/attestation/release/v0.1\"")
}

func TestService_CreateUserSubmittedReleaseAttestation(t *testing.T) {
	store := storage.NewInMemoryStore()
	tma := NewTestTMAWithStore(t, store)
	bundle := data.SigstoreBundleGitHubRelease(t)
	ownerID, repoID := uint64(1), uint64(123)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:                 2,
		OwnerID:                  &ownerID,
		RepositoryID:             &repoID,
		ExpectReleaseAttestation: false,
	}

	attestationIdentifier, err := tma.CreateAttestation(context.Background(), bundle, identifiers)
	assert.NotZero(t, attestationIdentifier)
	assert.NoError(t, err)

	// User-submitted release attestations should not be stored in the release table
	assert.Equal(t, store.ReleaseCount(), 0)
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
	assert.ErrorAs(t, err, new(*mysql.ErrStoreRecord))
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
	assert.ErrorAs(t, err, new(*BadRequestError))
	assert.ErrorIs(t, err, sgbundle.ErrValidation)
	assert.Contains(t, clientFacingError(err), "validation error: unsupported media type")
	assert.ErrorContains(t, err, "BadRequestError: error getting bundle version: validation error: unsupported media type: invalid media type")
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
	assert.ErrorAs(t, err, new(*BadRequestError))
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
	assert.ErrorAs(t, err, new(*BadRequestError))
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

	attestationIdentifier := attestation.IdentifiersGitHub{
		SubjectDigest: subjectDigest,
		OwnerID:       record.OwnerID,
		RepositoryID:  record.RepositoryID,
	}

	cursor, err := mysql.NewCursor(30, 0, 0)
	require.NoError(t, err)

	attestationRecords, err := tma.ListAttestationsBySubjectDigest(ctx, attestationIdentifier, cursor)
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

	attestationIdentifier := attestation.IdentifiersGitHub{
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}

	cursor, err := mysql.NewCursor(30, 0, 0)
	require.NoError(t, err)

	attestationRecords, err := tma.ListAttestationSummariesByRepository(ctx, attestationIdentifier, cursor)
	attestations := attestationRecords.Attestations

	assert.Len(t, attestations, 1)
	assert.NoError(t, err)
}

func TestService_GetAttestationSummaryByRepository(t *testing.T) {
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

	// retrieve attestation summary
	attestationIdentifier := attestation.IdentifiersGitHub{
		ID:           record.ID,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	attestationRecord, err := tma.GetAttestationSummaryByRepository(ctx, attestationIdentifier)

	assert.NotNil(t, attestationRecord)
	assert.NoError(t, err)
}
