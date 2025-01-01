//go:build integration

package storage

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
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
	return azureblob.ErrBlobUploadFailed{}
}

const DBURI = "tma:TMAdevP4ssw0rd!@tcp(127.0.0.1:3337)/tma_dev?parseTime=true"

// newTransactionalDatabase creates a LiveDatabase with a cancellable transaction.
// Note that you must explicitly call cancel() to rollback the transaction.
func newTransactionalDatabase(t *testing.T, uri string) (*mysql.LiveDatabase, *sql.Tx) {
	db, err := sql.Open("mysql", uri)
	assert.NoError(t, err)
	// Reset database every time we run tests
	_, err = db.Exec("TRUNCATE TABLE attestations")
	assert.Nil(t, err)
	_, err = db.Exec("TRUNCATE TABLE attestations_subjects")
	assert.Nil(t, err)
	tx, err := db.Begin()
	assert.NoError(t, err)
	// TODO: fail if database is not empty (select(count) on all tables)
	return mysql.NewLiveDatabaseFromConn(db, log.NewNullLogger(), stats.NullStatter), tx
}

func TestStoreAttestation(t *testing.T) {
	ctx := context.Background()
	var db DatabaseEndpoints
	var tx *sql.Tx

	db.Primary, tx = newTransactionalDatabase(t, DBURI)
	db.Replica = db.Primary
	defer tx.Rollback()

	// the azure blob client will successfully upload the blob
	azBlobClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)
	defer azBlobClient.DeleteContainer(ctx, "attestations")
	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	store := LiveStore{
		azBlobStorage: azBlobClient,
		db:            &db,
	}

	protoBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	testBundle, err := bundle.NewBundle(protoBundle)
	require.NoError(t, err)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	record := attestation.Record{
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
	}

	err = store.StoreGitHubAttestation(ctx, &record, testBundle)
	assert.NoError(t, err)

	// Verify the record was stored in the database
	cursor := mysql.Cursor{
		PerPage: 10,
	}
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}
	records, _, err := db.Replica.ListAttestationsByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 1)
	// TODO: Add test for attestations_subjects table when implemented on GET side

	// Verify the record was stored in blob storage
	downloaded, err := azBlobClient.DownloadAttestation(ctx, record)
	assert.NoError(t, err)
	assert.NotNil(t, downloaded)
	assert.Equal(t, protoBundle, downloaded)
}

func TestStoreAttestation_BlobWriteFail(t *testing.T) {
	ctx := context.Background()
	var db DatabaseEndpoints
	var tx *sql.Tx

	db.Primary, tx = newTransactionalDatabase(t, DBURI)
	db.Replica = db.Primary
	defer tx.Rollback()

	// the azure blob client will fail to upload the blob
	azBlobClient := failBlobClient{}
	defer azBlobClient.DeleteContainer(ctx, "attestations")
	err := azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	store := LiveStore{
		azBlobStorage: &azBlobClient,
		db:            &db,
	}

	protoBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)
	testBundle, err := bundle.NewBundle(protoBundle)
	require.NoError(t, err)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	record := attestation.Record{
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
	}

	err = store.StoreGitHubAttestation(ctx, &record, testBundle)
	assert.Error(t, err)
	assert.ErrorContains(t, err, "failed to store attestation in blob storage")

	// Verify the record was not stored in the database
	cursor := mysql.Cursor{
		PerPage: 10,
	}
	identifiers := attestation.IdentifiersGitHub{
		DomainID:     2,
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}
	records, _, err := db.Replica.ListAttestationsByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records, 0)
}
