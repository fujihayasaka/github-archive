package storage_test

import (
	"fmt"
	"testing"
	"time"

	azsdk "github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gocloud.dev/blob/azureblob"
)

// createAzureBlobWrapper creates a test Azure blob bucket wrapper with an Azurite container
func createAzureBlobWrapper(t *testing.T) (*storage.AzureBlobWrapper, func()) {
	t.Helper()
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

	wrapper := storage.NewAzureBlobWrapper(bucket)

	cleanup := func() {
		_ = bucket.Close()
		_, _ = serviceClient.DeleteContainer(ctx, containerName, nil)
	}

	return wrapper, cleanup
}

func TestGetLastModified_BlobExists(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()
	key := "test-blob.txt"
	content := []byte("test content")

	// Write a blob
	err := wrapper.WriteAll(ctx, key, content, nil)
	require.NoError(t, err)

	// Get the Last-Modified timestamp
	timestamp, err := wrapper.GetLastModified(ctx, key)
	require.NoError(t, err)
	require.NotNil(t, timestamp)

	// Verify timestamp is recent (within last 5 seconds)
	now := time.Now()
	timeDiff := now.Sub(*timestamp)
	assert.GreaterOrEqual(t, timeDiff, time.Duration(0), "timestamp should be in the past")
	assert.Less(t, timeDiff, 5*time.Second, "timestamp should be very recent")
}

func TestGetLastModified_BlobDoesNotExist(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()
	key := "non-existent-blob.txt"

	// Try to get timestamp for non-existent blob
	timestamp, err := wrapper.GetLastModified(ctx, key)
	require.NoError(t, err)
	assert.Nil(t, timestamp, "timestamp should be nil for non-existent blob")
}

func TestGetLastModified_UpdatedBlob(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()
	key := "updated-blob.txt"

	// Write initial blob
	err := wrapper.WriteAll(ctx, key, []byte("initial content"), nil)
	require.NoError(t, err)

	// Get first timestamp
	firstTimestamp, err := wrapper.GetLastModified(ctx, key)
	require.NoError(t, err)
	require.NotNil(t, firstTimestamp)

	// Wait to ensure timestamp difference (Azure timestamps have second granularity)
	time.Sleep(1100 * time.Millisecond)

	// Update the blob
	err = wrapper.WriteAll(ctx, key, []byte("updated content"), nil)
	require.NoError(t, err)

	// Get second timestamp
	secondTimestamp, err := wrapper.GetLastModified(ctx, key)
	require.NoError(t, err)
	require.NotNil(t, secondTimestamp)

	// Verify second timestamp is at or after first timestamp
	assert.False(t, secondTimestamp.Before(*firstTimestamp),
		"updated blob timestamp should not be before original timestamp")
}

func TestGetLastModified_DeletedBlob(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()
	key := "deleted-blob.txt"

	// Write a blob
	err := wrapper.WriteAll(ctx, key, []byte("temporary content"), nil)
	require.NoError(t, err)

	// Verify it exists and has a timestamp
	timestamp, err := wrapper.GetLastModified(ctx, key)
	require.NoError(t, err)
	require.NotNil(t, timestamp)

	// Delete the blob
	err = wrapper.Delete(ctx, key)
	require.NoError(t, err)

	// Verify GetLastModified returns nil for deleted blob
	timestamp, err = wrapper.GetLastModified(ctx, key)
	require.NoError(t, err)
	assert.Nil(t, timestamp, "timestamp should be nil for deleted blob")
}

func TestGetLastModified_MultipleBlobs(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()

	// Create multiple blobs
	blobs := map[string][]byte{
		"blob1.txt": []byte("content 1"),
		"blob2.txt": []byte("content 2"),
		"blob3.txt": []byte("content 3"),
	}

	timestamps := make(map[string]*time.Time)

	for key, content := range blobs {
		err := wrapper.WriteAll(ctx, key, content, nil)
		require.NoError(t, err)

		timestamp, err := wrapper.GetLastModified(ctx, key)
		require.NoError(t, err)
		require.NotNil(t, timestamp)

		timestamps[key] = timestamp
	}

	// Verify each blob has its own timestamp
	for key, timestamp := range timestamps {
		assert.NotNil(t, timestamp, "blob %s should have a timestamp", key)

		// Verify timestamp is recent
		now := time.Now()
		timeDiff := now.Sub(*timestamp)
		assert.GreaterOrEqual(t, timeDiff, time.Duration(0), "timestamp for %s should be in the past", key)
		assert.Less(t, timeDiff, 5*time.Second, "timestamp for %s should be very recent", key)
	}
}

func TestGetLastModified_EmptyKey(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()

	// Try to get timestamp with empty key
	timestamp, err := wrapper.GetLastModified(ctx, "")

	// Empty key should return an error from Azure
	require.Error(t, err, "empty key should result in an error")
	assert.Nil(t, timestamp)
}
func TestReadAllWithMetadata_BlobExists(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()
	key := "test-blob-with-metadata.txt"
	expectedContent := []byte("test content with metadata")

	// Write a blob
	err := wrapper.WriteAll(ctx, key, expectedContent, nil)
	require.NoError(t, err)

	// Read with metadata
	data, timestamp, err := wrapper.ReadAllWithMetadata(ctx, key)
	require.NoError(t, err)
	require.NotNil(t, timestamp)
	assert.Equal(t, expectedContent, data)

	// Verify timestamp is recent
	now := time.Now()
	timeDiff := now.Sub(*timestamp)
	assert.GreaterOrEqual(t, timeDiff, time.Duration(0), "timestamp should be in the past")
	assert.Less(t, timeDiff, 5*time.Second, "timestamp should be very recent")
}

func TestReadAllWithMetadata_BlobDoesNotExist(t *testing.T) {
	wrapper, cleanup := createAzureBlobWrapper(t)
	defer cleanup()

	ctx := t.Context()
	key := "non-existent-blob-metadata.txt"

	// Try to read non-existent blob
	data, timestamp, err := wrapper.ReadAllWithMetadata(ctx, key)
	require.Error(t, err)
	assert.Nil(t, data)
	assert.Nil(t, timestamp)
}
