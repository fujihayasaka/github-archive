package testutility

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/stretchr/testify/require"
)

func GetTestBlobStorage(t *testing.T) blob.BlobClient {
	t.Helper()
	cfg := GetTestConfig(t)
	ctx := context.Background()
	innerClient, err := blob.CreateDevelopmentAzureBlobClient(ctx, cfg.AzureStorageBlobEndpoint, "samplecontainer")
	require.NoError(t, err)
	client := &SpyBlobClient{
		Inner: innerClient,
	}
	return client
}

func GetTestConfig(t *testing.T) *config.Config {
	t.Helper()
	cfg, err := config.Load("notused")
	require.NoError(t, err)
	return cfg
}

func AreHistoricalSnapshotsStored(t *testing.T) bool {
	t.Helper()
	return !GetTestConfig(t).Enterprise
}

func IsBlobStorageBeingUsedToStoreSnapshots(t *testing.T) bool {
	t.Helper()
	return !GetTestConfig(t).Enterprise
}

// SpyBlobClient wraps a BlobClient and counts CreateBlob calls for testing.
type SpyBlobClient struct {
	Inner           blob.BlobClient
	CreateBlobCalls int
}

func (s *SpyBlobClient) CreateBlob(ctx context.Context, parentDirectory string, contents []byte) (string, error) {
	s.CreateBlobCalls++
	return s.Inner.CreateBlob(ctx, parentDirectory, contents)
}

func (s *SpyBlobClient) GetBlob(ctx context.Context, blobURL string) ([]byte, error) {
	return s.Inner.GetBlob(ctx, blobURL)
}
