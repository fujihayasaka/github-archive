package storage

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/test"
	"github.com/github/trust-metadata-api/test/data"
	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/rand"
)

const (
	//nolint:gosec
	SubjectDigest = "sha256:00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"
	SubjectName   = "foo/bar"
)

type failBlobClient struct {
	*azureblob.InMemoryClient
}

func (c failBlobClient) StoreAttestation(context.Context, attestation.Record, *bundle.Bundle) error {
	return &azureblob.ErrBlobUploadFailed{}
}

func createTestRecord(t *testing.T) (attestation.Record, *v1.Bundle) {
	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	return createTestRecordWithCustomOwnerAndRepo(t, ownerID, repoID)
}

func createTestRecordWithCustomOwnerAndRepo(t *testing.T, ownerID, repoID uint64) (attestation.Record, *v1.Bundle) {
	protoBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	return attestation.Record{
		Bundle:       protoBundle,
		CreatedAt:    time.Now().UTC(),
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		Subjects: []attestation.Subject{
			{
				Name:          SubjectName,
				SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: SubjectDigest},
			},
		},
	}, protoBundle
}

func newDBEndpoints(t *testing.T) (DatabaseEndpoints, *sql.Tx) {
	var db DatabaseEndpoints
	var tx *sql.Tx

	db.Primary, tx = mysql.NewTransactionalDatabase(t)
	db.Replica = db.Primary
	return db, tx
}

func TestStoreAttestation(t *testing.T) {
	ctx := context.Background()
	db, tx := newDBEndpoints(t)
	test.Cleanup(t, tx.Rollback)

	// the azure blob client will successfully upload the blob
	azBlobClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)
	test.Cleanup(t, func() error {
		return azBlobClient.DeleteContainer(ctx, "attestations")
	})
	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	store := LiveStore{
		azBlobStorage: azBlobClient,
		db:            &db,
	}

	record, protoBundle := createTestRecord(t)
	testBundle, err := bundle.NewBundle(protoBundle)
	require.NoError(t, err)

	err = store.StoreGitHubAttestation(ctx, &record, testBundle)
	assert.NoError(t, err)

	// Verify the record was stored in the database
	cursor, err := mysql.NewCursor(10, 0, 0)
	require.NoError(t, err)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	records, _, err := db.Replica.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	// TODO: Add test for attestations_subjects table when implemented on GET side

	// Verify the record was stored in blob storage
	downloaded, err := azBlobClient.DownloadAttestation(ctx, record)
	assert.NoError(t, err)
	assert.NotNil(t, downloaded)
	assert.Equal(t, protoBundle, downloaded)
}

func TestStoreReleaseAttestation(t *testing.T) {
	ctx := context.Background()
	db, tx := newDBEndpoints(t)
	test.Cleanup(t, tx.Rollback)

	// the azure blob client will successfully upload the blob
	azBlobClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)
	test.Cleanup(t, func() error {
		return azBlobClient.DeleteContainer(ctx, "attestations")
	})
	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	store := LiveStore{
		azBlobStorage: azBlobClient,
		db:            &db,
	}

	protoBundle := data.SigstoreBundleGitHubRelease(t)
	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	record := attestation.Record{
		Bundle:        protoBundle,
		CreatedAt:     time.Now().UTC(),
		DomainID:      2,
		OwnerID:       &ownerID,
		RepositoryID:  &repoID,
		PredicateType: attestation.PredicateRelease,
		Tag:           "v1.0.0",
		Subjects: []attestation.Subject{
			{
				Name:          SubjectName,
				SubjectDigest: attestation.SubjectDigest{Alg: "sha256", Digest: SubjectDigest},
			},
		},
	}

	testBundle, err := bundle.NewBundle(protoBundle)
	require.NoError(t, err)

	err = store.StoreReleaseAttestation(ctx, &record, testBundle)
	assert.NoError(t, err)

	// Verify the record was stored in the database
	cursor, err := mysql.NewCursor(10, 0, 0)
	require.NoError(t, err)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	records, _, err := db.Replica.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)

	// Verify that the release cannot be duplicated
	err = store.StoreReleaseAttestation(ctx, &record, testBundle)
	assert.Error(t, err)
	assert.ErrorIs(t, err, mysql.ErrReleaseAttestationConstraint)

	// Verify the record was stored in blob storage
	downloaded, err := azBlobClient.DownloadAttestation(ctx, records[0])
	assert.NoError(t, err)
	assert.NotNil(t, downloaded)
	assert.Equal(t, protoBundle, downloaded)
}

func TestStoreAttestation_BlobWriteFail(t *testing.T) {
	ctx := context.Background()
	db, tx := newDBEndpoints(t)
	test.Cleanup(t, tx.Rollback)

	// the azure blob client will fail to upload the blob
	store := LiveStore{
		azBlobStorage: &failBlobClient{},
		db:            &db,
	}

	record, protoBundle := createTestRecord(t)
	testBundle, err := bundle.NewBundle(protoBundle)
	require.NoError(t, err)

	err = store.StoreGitHubAttestation(ctx, &record, testBundle)
	assert.Error(t, err)
	assert.ErrorContains(t, err, "failed to store attestation in blob storage")

	// Verify the record was not stored in the database
	cursor, err := mysql.NewCursor(10, 0, 0)
	require.NoError(t, err)
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      record.OwnerID,
		RepositoryID: record.RepositoryID,
	}
	records, _, err := db.Replica.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 0)
}

func TestListAttestationSummariesByRepository_TotalAttestationCount(t *testing.T) {
	ctx := context.Background()
	db, tx := newDBEndpoints(t)
	test.Cleanup(t, tx.Rollback)

	// the azure blob client will successfully upload the blob
	azBlobClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)
	test.Cleanup(t, func() error {
		return azBlobClient.DeleteContainer(ctx, "attestations")
	})
	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	store := LiveStore{
		azBlobStorage: azBlobClient,
		db:            &db,
	}

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	for range 100 {
		record, protoBundle := createTestRecordWithCustomOwnerAndRepo(t, ownerID, repoID)
		testBundle, err := bundle.NewBundle(protoBundle)
		require.NoError(t, err)

		err = store.StoreGitHubAttestation(ctx, &record, testBundle)
		assert.NoError(t, err)
	}

	cursor, err := mysql.NewCursor(30, 0, 0)
	require.NoError(t, err)

	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}
	records, err := store.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 30)
	assert.Equal(t, int64(100), records.TotalCount)
	assert.Equal(t, 71, int(records.PageInfo.EndCursor))
	assert.Equal(t, 100, int(records.PageInfo.StartCursor))

	// Expect to get the next 30 attestations but still get a total count of 100
	cursor, err = mysql.NewCursor(30, records.PageInfo.EndCursor, 0)
	require.NoError(t, err)
	records, err = store.ListAttestationSummariesByRepository(context.Background(), identifiers, cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 30)
	assert.Equal(t, int64(100), records.TotalCount)
	assert.Equal(t, 41, int(records.PageInfo.EndCursor))
	assert.Equal(t, 70, int(records.PageInfo.StartCursor))
}
