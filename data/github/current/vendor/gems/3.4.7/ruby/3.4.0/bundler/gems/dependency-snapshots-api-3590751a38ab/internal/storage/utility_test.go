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
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
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

func createTestAdapter(t *testing.T, testDB *testutil.TestDB) snapshots.StorageAdapter {
	t.Helper()

	sqlxDB, err := db.NewSqlxDatabase(testDB.DB.GetRawSQLDBPrimary())
	require.NoError(t, err)

	featuresClient := featuresMock.NewMockFeaturesClient()
	// the featuresClient mock is awkward to stub for these tests once it
	// is returned nested in a storage.SnapshotsAdapter interface.
	// since it's unused at the moment, other than in this no-op change,
	// let's nerf it (for now!) Yes this is terrible all the way around :(
	featuresClient.On("IsFeatureFlagEnabledForRepository",
		mock.Anything,                 // context
		mock.AnythingOfType("string"), // feature name
		mock.AnythingOfType("uint64"), // repository id
	).Return(false, nil)

	var blobStorage blob.BlobClient
	if testutility.IsBlobStorageBeingUsedToStoreSnapshots(t) {
		blobStorage = testutility.GetTestBlobStorage(t)
	}

	return storage.NewAdapter(storage.AdapterOptions{
		DB:                             sqlxDB,
		BlobClient:                     blobStorage,
		Git:                            gitMock.NewClient(0),
		Freno:                          frenoMock.NewMockFrenoClient(),
		RepoLocker:                     repolocks.NewService(testDB.DB, log.NewNullLogger(), stats.NullStatter),
		Features:                       featuresClient,
		ShouldStoreHistoricalSnapshots: testutility.AreHistoricalSnapshotsStored(t),
		ShouldStoreBlobsInDatabase:     !testutility.IsBlobStorageBeingUsedToStoreSnapshots(t),
	})
}
