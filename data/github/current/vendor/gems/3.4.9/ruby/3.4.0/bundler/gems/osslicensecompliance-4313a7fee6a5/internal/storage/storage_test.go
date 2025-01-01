package storage_test

import (
	"fmt"
	"math"
	"math/rand/v2"
	"testing"
	"time"

	azsdk "github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/sqlite"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gocloud.dev/blob/azureblob"
)

func newSqliteStorage(t *testing.T) *storage.Storage {
	t.Helper()
	db, err := sqlite.New(":memory:")
	require.NoError(t, err)

	t.Cleanup(func() {
		err = db.Close()
		if err != nil {
			t.Errorf("failed to close test db: %v", err)
		}
	})

	s, err := storage.NewStorage(db, nil, nil, nil, nil)
	require.NoError(t, err)
	return s
}

// This test is here to appease the linter by using the func above
// We will want to use  newSqliteStorage() for our tests when we use SQL DB again
// Which we will do when we add license alerts
func TestSetupSqliteStorage(t *testing.T) {
	s := newSqliteStorage(t)
	assert.NotNil(t, s)
}

func getAzuriteConnectionString() string {
	const (
		azuriteAccountName = "devstoreaccount1"
		azuriteAccountKey  = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
		azuriteBlobURL     = "http://127.0.0.1:10100"
	)

	return fmt.Sprintf("DefaultEndpointsProtocol=http;AccountName=%s;AccountKey=%s;BlobEndpoint=%s/%s",
		azuriteAccountName, azuriteAccountKey, azuriteBlobURL, azuriteAccountName)
}

func newAzBlobStorage(t *testing.T) *storage.Storage {
	ctx := t.Context()
	t.Helper()
	connectionString := getAzuriteConnectionString()

	serviceClient, err := azsdk.NewClientFromConnectionString(connectionString, nil)
	require.NoError(t, err)

	containerName := fmt.Sprintf("test%d", time.Now().UnixNano())
	_, err = serviceClient.CreateContainer(ctx, containerName, nil)
	require.NoError(t, err)

	containerClient := serviceClient.ServiceClient().NewContainerClient(containerName)

	repoBucket, err := azureblob.OpenBucket(ctx, containerClient, nil)
	require.NoError(t, err)

	orgBucket, err := azureblob.OpenBucket(ctx, containerClient, nil)
	require.NoError(t, err)

	entBucket, err := azureblob.OpenBucket(ctx, containerClient, nil)
	require.NoError(t, err)

	store, err := storage.NewStorage(nil, repoBucket, orgBucket, entBucket, stats.NullStatter)
	require.NoError(t, err)

	t.Cleanup(func() {
		store.Close()
		repoBucket.Close()
		orgBucket.Close()
		serviceClient.DeleteContainer(ctx, containerName, nil)
	})

	return store
}

func randomIDForDatabase() uint64 {
	// The database drivers don't like it if they get a uint64 with the high
	// bit set. So, this returns random IDs that we're sure are in the clear.
	return rand.Uint64N(math.MaxInt32)
}

func TestStorageHealthCheckPass(t *testing.T) {
	s := newAzBlobStorage(t)

	err := s.HealthCheck(t.Context())

	assert.NoError(t, err, "Storage health check should pass with azure storage")
}

func TestStorageHealthCheckFail(t *testing.T) {
	s := newAzBlobStorage(t)

	// Close the storage to simulate failure
	err := s.Close()
	require.NoError(t, err, "Should be able to close storage")

	err = s.HealthCheck(t.Context())

	require.Error(t, err, "Storage health check should fail after storage is closed")
	assert.Contains(t, err.Error(), "bucket health check failed", "Error should indicate database ping failure")
}
