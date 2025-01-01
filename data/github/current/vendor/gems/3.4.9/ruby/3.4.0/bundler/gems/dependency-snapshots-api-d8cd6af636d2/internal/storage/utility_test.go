package storage_test

import (
	"context"
	"math/rand"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/db"
	featuresMock "github.com/github/dependency-snapshots-api/internal/features/mock"
	frenoMock "github.com/github/dependency-snapshots-api/internal/freno/mock"
	gitMock "github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/repolocks"
	"github.com/github/dependency-snapshots-api/internal/snapshots"
	"github.com/github/dependency-snapshots-api/internal/storage"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/github/dependency-snapshots-api/internal/storage/blob/testutility"
	"github.com/github/dependency-snapshots-api/internal/testutil"
	"github.com/github/dependency-snapshots-api/internal/util"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/stretchr/testify/require"
)

var usedRepoIDs = util.NewSet[uint64]()

// randomRepositoryID returns a random repository ID that is *probably* unused.
// It will not return the same repo ID twice in the same test run.
// It also checks for existing snapshots in the given StorageAdapter to confirm,
// which is subject to race conditions but better than nothing.
func randomRepositoryID(t *testing.T, stg snapshots.StorageAdapter) uint64 {
	t.Helper()

	id := uint64(rand.Intn(8999999-1000) + 1000)
	if usedRepoIDs.Contains(id) {
		t.Logf("Repository ID %d already used, trying again", id)
		return randomRepositoryID(t, stg)
	}
	usedRepoIDs.Add(id)

	res, err := stg.CanonicalSnapshotsForRepository(context.Background(), id, interfaces.DefaultQueryMode)
	require.NoError(t, err)

	if len(res) > 0 {
		t.Logf("Repository ID %d already has snapshots, trying again", id)
		return randomRepositoryID(t, stg)
	}
	return id
}

func createTestAdapter(t *testing.T, testDB *testutil.TestDB, featuresClient *featuresMock.MockFeaturesClient) snapshots.StorageAdapter {
	t.Helper()

	sqlxDB, err := db.NewSqlxDatabase(testDB.DB.GetRawSQLDBPrimary())
	require.NoError(t, err)

	var blobStorage blob.BlobClient
	if testutility.IsBlobStorageBeingUsedToStoreSnapshots(t) {
		blobStorage = testutility.GetTestBlobStorage(t)
	}

	return storage.NewAdapter(storage.AdapterOptions{
		DB:                             sqlxDB,
		BlobClient:                     blobStorage,
		ShouldStoreBlobsInAzure:        testutility.IsBlobStorageBeingUsedToStoreSnapshots(t),
		Git:                            gitMock.NewClient(0),
		Freno:                          frenoMock.NewMockFrenoClient(),
		RepoLocker:                     repolocks.NewService(testDB.DB, log.NewNullLogger(), stats.NullStatter),
		Features:                       featuresClient,
		Statter:                        stats.NullStatter,
		ShouldStoreHistoricalSnapshots: testutility.AreHistoricalSnapshotsStored(t),
		ShouldStoreBlobsInDatabase:     !testutility.IsBlobStorageBeingUsedToStoreSnapshots(t),
	})
}
