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
	client, err := blob.CreateDevelopmentAzureBlobClient(ctx, cfg.AzureStorageBlobEndpoint, "samplecontainer")
	require.NoError(t, err)
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
