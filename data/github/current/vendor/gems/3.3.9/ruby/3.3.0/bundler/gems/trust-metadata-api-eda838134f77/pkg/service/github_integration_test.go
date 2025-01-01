//go:build integration

package service

import (
	"context"
	"database/sql"
	"math/rand"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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
	assert.Nil(t, err)
	return mysql.NewLiveDatabaseFromConn(db, log.NewNullLogger(), stats.NullStatter), tx
}

func ServiceWithLocalDockerStorage(t *testing.T) (*TMA, *storage.DatabaseEndpoints, azureblob.Client, *sql.Tx, error) {
	var db storage.DatabaseEndpoints
	var tx *sql.Tx

	db.Primary, tx = newTransactionalDatabase(t, DBURI)
	db.Replica = db.Primary

	azBlobClient, err := azureblob.NewLocalClient("attestations")
	if err != nil {
		return nil, nil, nil, nil, err
	}

	store := storage.NewLiveStore(azBlobClient, &db)

	return NewTestTMAWithStore(t, store), &db, azBlobClient, tx, nil
}

func TestStoreGetAttestationsByRepository(t *testing.T) {
	ctx := context.Background()
	tmaService, db, azBlobClient, tx, err := ServiceWithLocalDockerStorage(t)
	require.NoError(t, err)
	defer tx.Rollback()
	defer azBlobClient.DeleteContainer(ctx, "attestations")

	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	testBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	year, month, day := time.Now().UTC().Date()
	assert.Equal(t, year, record.CreatedAt.Year())
	assert.Equal(t, month, record.CreatedAt.Month())
	assert.Equal(t, day, record.CreatedAt.Day())

	cursor := mysql.Cursor{
		PerPage: 10,
	}

	// check that the bundle is not stored in the database
	attestations, _, err := db.Replica.ListAttestationsByRepository(context.Background(), identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Zero(t, attestations[0].Bundle.GetMediaType())
	assert.Nil(t, attestations[0].Bundle.GetVerificationMaterial())
	assert.Nil(t, attestations[0].Bundle.GetContent())

	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	downloadedBundle, err := azBlobClient.DownloadAttestation(ctx, *record)
	assert.NoError(t, err)
	assert.NotNil(t, downloadedBundle)

	assert.Equal(t, testBundle, downloadedBundle)

	// check that the GetAttestationByRepository method returns the bundle and
	// record metadata as expected
	identifiers.ID = record.ID
	record, err = tmaService.GetAttestationByRepository(ctx, identifiers)
	assert.NoError(t, err)
	assert.Equal(t, testBundle, record.Bundle)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)
	assert.NotZero(t, record.SASUrl)
}

func TestStoreListAttestationsByRepository(t *testing.T) {
	ctx := context.Background()
	tmaService, db, azBlobClient, tx, err := ServiceWithLocalDockerStorage(t)
	require.NoError(t, err)
	defer tx.Rollback()
	defer azBlobClient.DeleteContainer(ctx, "attestations")

	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	testBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	year, month, day := time.Now().UTC().Date()
	assert.Equal(t, year, record.CreatedAt.Year())
	assert.Equal(t, month, record.CreatedAt.Month())
	assert.Equal(t, day, record.CreatedAt.Day())

	cursor := mysql.Cursor{
		PerPage: 10,
	}

	// check that the bundle is not stored in the database
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestations, _, err := db.Replica.ListAttestationsByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Zero(t, attestations[0].Bundle.GetMediaType())
	assert.Nil(t, attestations[0].Bundle.GetVerificationMaterial())
	assert.Nil(t, attestations[0].Bundle.GetContent())

	// check that the bundle is stored in the blob storage
	downloadedBundle, err := azBlobClient.DownloadAttestation(ctx, *record)
	assert.NoError(t, err)
	assert.NotNil(t, downloadedBundle)

	assert.Equal(t, testBundle, downloadedBundle)

	// check that the ListAttestationsByRepository method returns the record metadata as expected
	records, err := tmaService.ListAttestationsByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 1)
	assert.Equal(t, identifiers.OwnerID, records.Attestations[0].OwnerID)
	assert.Equal(t, identifiers.RepositoryID, records.Attestations[0].RepositoryID)
}

func TestStoreListAttestationSummariesByRepository(t *testing.T) {
	ctx := context.Background()
	tmaService, db, azBlobClient, tx, err := ServiceWithLocalDockerStorage(t)
	require.NoError(t, err)
	defer tx.Rollback()
	defer azBlobClient.DeleteContainer(ctx, "attestations")

	err = azBlobClient.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	testBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	year, month, day := time.Now().UTC().Date()
	assert.Equal(t, year, record.CreatedAt.Year())
	assert.Equal(t, month, record.CreatedAt.Month())
	assert.Equal(t, day, record.CreatedAt.Day())

	cursor := mysql.Cursor{
		PerPage: 10,
	}

	// check that the bundle is not stored in the database
	ctx = context.WithValue(ctx, azureblob.ClientIPAddrCtxKeyName, "127.0.0.1")

	attestations, _, err := db.Replica.ListAttestationSummariesByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, attestations, 1)
	assert.Zero(t, attestations[0].Bundle.GetMediaType())
	assert.Nil(t, attestations[0].Bundle.GetVerificationMaterial())
	assert.Nil(t, attestations[0].Bundle.GetContent())

	// check that the bundle is stored in the blob storage
	downloadedBundle, err := azBlobClient.DownloadAttestation(ctx, *record)
	assert.NoError(t, err)
	assert.NotNil(t, downloadedBundle)

	assert.Equal(t, testBundle, downloadedBundle)

	// check that the ListAttestationSummariesByRepository method returns the record metadata as expected
	records, err := tmaService.ListAttestationSummariesByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 1)
	assert.Equal(t, identifiers.OwnerID, records.Attestations[0].OwnerID)
	assert.Equal(t, identifiers.RepositoryID, records.Attestations[0].RepositoryID)
	assert.Equal(t, uint64(1), records.Attestations[0].SubjectCount)
}
