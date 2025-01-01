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
	"golang.org/x/exp/rand"
)

func TestFetchBlobBundlesAndUpdateRecords(t *testing.T) {
	ownerID, repoID := uint64(1), uint64(123)
	record := attestation.Record{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
	}

	notStored := record
	// nolint:gosec
	notStoredRepoID := uint64(rand.Intn(9999) + 1)
	notStored.RepositoryID = &notStoredRepoID

	testcases := []struct {
		name      string
		records   []attestation.Record
		expectErr bool
	}{
		{
			name:    "success",
			records: []attestation.Record{record, record},
		},
		{
			name:      "blob not found",
			records:   []attestation.Record{record, notStored, record},
			expectErr: true,
		},
	}

	for _, tc := range testcases {
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

		updatedRecords, err := store.updateRecordsWithBundles(context.Background(), tc.records, true)
		if tc.expectErr {
			assert.Nil(t, updatedRecords)
			assert.Error(t, err)
		} else {
			assert.Len(t, updatedRecords, 2)
			assert.NoError(t, err)
			assert.Equal(t, b.String(), updatedRecords[0].Bundle.String())
			assert.NotZero(t, updatedRecords[0].SASUrl)
		}
	}
}
