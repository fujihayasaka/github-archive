package storage_test

import (
	"context"
	"fmt"
	"time"

	"github.com/github/dependency-snapshots-api/internal/storage/blob/testutility"
	"github.com/stretchr/testify/require"
)

func (s *StorageRetrievalTestSuite) TestTotalUniqueRepos() {
	t := s.Suite.T()
	initialCount, err := s.storageAdapter.UniqueRepositoryCounts(context.Background())
	require.NoError(t, err)

	repo1 := randomRepositoryID(t, s.storageAdapter)
	repo2 := randomRepositoryID(t, s.storageAdapter)

	r1s1 := getExpectedSnapshotWithRepoID(t, repo1)
	r2s1 := getExpectedSnapshotWithRepoID(t, repo2)
	r2s2 := getExpectedSnapshotWithRepoID(t, repo2)

	createTestSnapshots(t, s.storageAdapter, r1s1, r2s1, r2s2)
	afterCount, err := s.storageAdapter.UniqueRepositoryCounts(context.Background())
	require.NoError(t, err)

	require.True(t, afterCount.Total > initialCount.Total, "We expect at least one repository to be new (statistically speaking, since they are random ids).")

	// All of repo1 < 1 day ago
	s.setSnapshotCreatedAt(time.Now().Add(time.Hour*-12), fmt.Sprintf("WHERE repository_id = %v", repo1))
	// All of repo2 > 1 day ago
	s.setSnapshotCreatedAt(time.Now().Add(time.Hour*24*-2), fmt.Sprintf("WHERE repository_id = %v", repo2))
	// Everything else > 1 week
	s.setSnapshotCreatedAt(time.Now().Add(time.Hour*24*-8), fmt.Sprintf("WHERE repository_id != %v AND repository_id != %v ", repo1, repo2))

	afterDateUpdate, err := s.storageAdapter.UniqueRepositoryCounts(context.Background())
	require.NoError(t, err)

	require.Equal(t, uint64(1), afterDateUpdate.InLastDay)
	require.Equal(t, uint64(2), afterDateUpdate.InLastWeek)
	require.True(t, afterDateUpdate.Total > initialCount.Total)
}

func (s *StorageRetrievalTestSuite) TestTotalSnapshots() {
	t := s.Suite.T()

	initialCount, err := s.storageAdapter.TotalSnapshotCounts(context.Background())
	require.NoError(t, err)

	repo1 := randomRepositoryID(t, s.storageAdapter)
	repo2 := randomRepositoryID(t, s.storageAdapter)

	r1s1 := getExpectedSnapshotWithRepoID(t, repo1)
	r2s1 := getExpectedSnapshotWithRepoID(t, repo2)
	r2s2 := getExpectedSnapshotWithRepoID(t, repo2)

	createTestSnapshots(t, s.storageAdapter, r1s1, r2s1, r2s2)
	afterCount, err := s.storageAdapter.TotalSnapshotCounts(context.Background())
	s.Require().NoError(err)

	s.Require().True(afterCount.Total > initialCount.Total, "We expect at least one snapshot to be new (statistically speaking, since repository_ids are random).")

	// All of repo1 < 1 day ago
	s.setSnapshotCreatedAt(time.Now().Add(time.Hour*-12), fmt.Sprintf("WHERE repository_id = %v", repo1))
	// All of repo2 > 1 day ago
	s.setSnapshotCreatedAt(time.Now().Add(time.Hour*24*-2), fmt.Sprintf("WHERE repository_id = %v", repo2))
	// Everything else > 1 week
	s.setSnapshotCreatedAt(time.Now().Add(time.Hour*24*-8), fmt.Sprintf("WHERE repository_id != %v AND repository_id != %v ", repo1, repo2))

	afterDateUpdate, err := s.storageAdapter.TotalSnapshotCounts(context.Background())
	s.Require().NoError(err)

	s.Require().Equal(uint64(1), afterDateUpdate.InLastDay)
	if testutility.AreHistoricalSnapshotsStored(t) {
		s.Require().Equal(uint64(3), afterDateUpdate.InLastWeek)
	} else {
		s.Require().Equal(uint64(2), afterDateUpdate.InLastWeek)
	}
	s.Require().True(afterDateUpdate.Total > initialCount.Total)
}

func (s *StorageRetrievalTestSuite) setSnapshotCreatedAt(newCreatedAt time.Time, whereClause string) {
	s.T().Helper()

	query := `
		update ds_snapshots
		set created_at = ?
	` + whereClause
	_, err := s.testDB.DB.PrimaryExecutor.ExecContext(context.Background(), query, newCreatedAt)
	s.Require().NoError(err)
}
