package storage

import (
	"context"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

func TestFetchBlobBundlesAndUpdateRecords(t *testing.T) {
	ownerID, repoID := uint64(1), uint64(123)
	record := attestation.Record{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	b := data.SigstoreJs300ProtoBundle(t)
	sgBundle, err := bundle.NewBundle(b)
	assert.NoError(t, err)

	db := mysql.NewInMemoryDatabase()
	_, err = db.StoreAttestation(context.Background(), &record, nil)
	assert.NoError(t, err)

	azBlobClient := azureblob.NewInMemoryClient()
	err = azBlobClient.StoreAttestation(context.Background(), record, sgBundle)
	assert.NoError(t, err)

	store := LiveStore{
		azBlobStorage: azBlobClient,
		db:            &DatabaseEndpoints{Primary: db, Replica: db},
	}

	// fetch the bundle and update the record
	records := []attestation.Record{record, record}
	reportErrDummyFunc := func(context.Context, error) error {
		return nil
	}
	updatedRecords, err := store.updateRecordsWithBundles(context.Background(), records, reportErrDummyFunc)
	assert.Len(t, updatedRecords, 2)
	assert.NoError(t, err)
	assert.Equal(t, b.String(), updatedRecords[0].Bundle.String())
	assert.NotZero(t, updatedRecords[0].SASUrl)
}
