package storage_test

import (
	"encoding/json"
	"fmt"
	"sort"
	"sync"
	"testing"
	"time"

	azsdk "github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/sequence"
	"github.com/github/osslicensecompliance/internal/storage/sqlite"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gocloud.dev/blob"
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

	s, err := storage.NewStorage(db, nil, nil, nil, sequence.NewNullGenerator(), stats.NullStatter, log.NewNullLogger())
	require.NoError(t, err)
	return s
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

	store, err := storage.NewStorage(nil, repoBucket, orgBucket, entBucket, nil, stats.NullStatter, nil)
	require.NoError(t, err)

	t.Cleanup(func() {
		store.Close()
		repoBucket.Close()
		orgBucket.Close()
		serviceClient.DeleteContainer(ctx, containerName, nil)
	})

	return store
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

// helper that creates a temporary Azure container and returns an Opened Go CDK bucket
func createAzureTestBucket(t *testing.T) (*blob.Bucket, func()) {
	ctx := t.Context()
	connectionString := getAzuriteConnectionString()

	serviceClient, err := azsdk.NewClientFromConnectionString(connectionString, nil)
	require.NoError(t, err)

	containerName := fmt.Sprintf("test-%d", time.Now().UnixNano())
	_, err = serviceClient.CreateContainer(ctx, containerName, nil)
	require.NoError(t, err)

	containerClient := serviceClient.ServiceClient().NewContainerClient(containerName)
	bucket, err := azureblob.OpenBucket(ctx, containerClient, nil)
	require.NoError(t, err)

	cleanup := func() {
		_ = bucket.Close()
		_, _ = serviceClient.DeleteContainer(ctx, containerName, nil)
	}

	return bucket, cleanup
}

func TestSwap_CreateNewBlob(t *testing.T) {
	bucket, cleanup := createAzureTestBucket(t)
	defer cleanup()

	ctx := t.Context()
	key := "policy.json"
	err := storage.Swap(ctx, bucket, key, func(oldBlob []byte) (newBlob []byte, err error) {
		// Since this is a new blob there should be no prior contents.
		require.Nil(t, oldBlob)
		return []byte(`{"exceptions":[{"name":"foo"}]}`), nil
	}, nil)
	require.NoError(t, err)

	// Verify blob was written.
	data, err := bucket.ReadAll(ctx, key)
	require.NoError(t, err)
	assert.JSONEq(t, `{"exceptions":[{"name":"foo"}]}`, string(data))
}

func TestSwap_UpdateExistingBlob(t *testing.T) {
	bucket, cleanup := createAzureTestBucket(t)
	defer cleanup()

	ctx := t.Context()
	key := "policy.json"

	// Write initial contents
	require.NoError(t, bucket.WriteAll(ctx, key, []byte("{\"exceptions\":[{\"name\":\"old\"}] }"), nil))

	// Now swap: verify old content and return updated content
	err := storage.Swap(ctx, bucket, key, func(oldBlob []byte) (newBlob []byte, err error) {
		require.NotNil(t, oldBlob)
		assert.Contains(t, string(oldBlob), "old")
		return []byte(`{"exceptions":[{"name":"new"}]}`), nil
	}, nil)
	require.NoError(t, err)

	data, err := bucket.ReadAll(ctx, key)
	require.NoError(t, err)
	assert.Contains(t, string(data), "new")
}

func TestSwap_ConcurrentUpdates(t *testing.T) {
	bucket, cleanup := createAzureTestBucket(t)
	defer cleanup()

	ctx := t.Context()
	key := "concurrent.json"
	const concurrentUpdates = 20

	var wg sync.WaitGroup
	errs := make(chan error, concurrentUpdates)

	for i := 0; i < concurrentUpdates; i++ {
		wg.Add(1)
		id := i
		go func() {
			defer wg.Done()
			err := storage.Swap(ctx, bucket, key, func(oldBlob []byte) (newBlob []byte, err error) {
				var arr []int
				if oldBlob != nil {
					if err := json.Unmarshal(oldBlob, &arr); err != nil {
						return nil, err
					}
				}
				// If our id is already present, do nothing (idempotent); this
				// protects against the transform being re-run during retries.
				for _, v := range arr {
					if v == id {
						return oldBlob, nil
					}
				}
				arr = append(arr, id)
				sort.Ints(arr)
				return json.Marshal(arr)
			}, nil)
			errs <- err
		}()
	}

	wg.Wait()
	close(errs)

	for err := range errs {
		require.NoError(t, err)
	}

	data, err := bucket.ReadAll(ctx, key)
	require.NoError(t, err)

	var final []int
	require.NoError(t, json.Unmarshal(data, &final))
	sort.Ints(final)
	require.Equal(t, concurrentUpdates, len(final), "expected %d entries, got %d", concurrentUpdates, len(final))
	for i := 0; i < concurrentUpdates; i++ {
		assert.Equal(t, i, final[i])
	}
}

func TestSwap_NullBucketBasicCreateAndUpdate(t *testing.T) {
	bucket := storage.NewNullBucket()
	defer bucket.Close()

	ctx := t.Context()
	key := "policy.json"

	// Create
	err := storage.Swap(ctx, bucket, key, func(oldBlob []byte) (newBlob []byte, err error) {
		require.Nil(t, oldBlob)
		return []byte(`{"exceptions":[{"name":"foo"}]}`), nil
	}, nil)
	require.NoError(t, err)

	data, err := bucket.ReadAll(ctx, key)
	require.NoError(t, err)
	assert.Contains(t, string(data), "foo")

	// Update
	err = storage.Swap(ctx, bucket, key, func(oldBlob []byte) (newBlob []byte, err error) {
		require.NotNil(t, oldBlob)
		return []byte(`{"exceptions":[{"name":"bar"}]}`), nil
	}, nil)
	require.NoError(t, err)

	data2, err := bucket.ReadAll(ctx, key)
	require.NoError(t, err)
	assert.Contains(t, string(data2), "bar")
}
