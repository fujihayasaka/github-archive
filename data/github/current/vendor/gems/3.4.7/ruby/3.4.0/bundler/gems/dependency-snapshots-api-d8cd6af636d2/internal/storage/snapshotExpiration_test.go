package storage_test

import (
	"context"
	"database/sql"
	"time"

	gitMock "github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/stretchr/testify/require"
)

func (s *StorageRetrievalTestSuite) TestSnapshotExpiration() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	newestSHA := string(gitMock.HistoricalSHAs[0])
	newerSHA := string(gitMock.HistoricalSHAs[1])
	olderSHA := string(gitMock.HistoricalSHAs[3])

	// create a snapshot to be orphaned in the past and expired
	// later, we'll set the stale_since time on this to be > 2 hours
	snapshotExpired := getExpectedSnapshotWithRepoID(t, repo)
	snapshotExpired.SHA = olderSHA
	snapshotExpired.Detector.Name = "expired"
	snapshotExpired.Manifests = map[string]*interfaces.Manifest{
		"oidExpired": simpleManifest("oid1", "pkg:example/expired@1.0.0"),
	}
	createTestSnapshot(t, s.storageAdapter, snapshotExpired)
	s.assertNotStale(snapshotExpired.ID, "snapshotExpired should not be stale yet")

	// create a sibling snasphot to be orphaned in the past, but this one
	// will not have been stale for as long, so it will not be expired
	snapshotOrphaned := getExpectedSnapshotWithRepoID(t, repo)
	snapshotOrphaned.SHA = olderSHA
	snapshotOrphaned.Detector.Name = "orphaned"
	snapshotOrphaned.Manifests = map[string]*interfaces.Manifest{
		"oid1": simpleManifest("oid1", "pkg:example/orphaned@1.0.0"),
	}
	createTestSnapshot(t, s.storageAdapter, snapshotOrphaned)
	s.assertNotStale(snapshotOrphaned.ID, "snapshotOrphaned should not be stale yet")
	s.assertNotStale(snapshotExpired.ID, "snapshotExpired should still not be stale yet")

	// the purpose of this snapshot is to introduce a new commit SHA and mark the previous two as stale
	snapshotNewer := getExpectedSnapshotWithRepoID(t, repo)
	snapshotNewer.SHA = newerSHA
	snapshotNewer.Detector.Name = "newer"
	snapshotNewer.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/detector2@1.0.0"),
	}
	createTestSnapshot(t, s.storageAdapter, snapshotNewer)

	// at this point, snapshotExpired and snapshot1 should both be considered stale
	s.assertStale(snapshotExpired.ID, "snapshotExpired should be stale now")
	s.assertStale(snapshotOrphaned.ID, "snapshotOrphaned should be stale now")
	s.assertNotStale(snapshotNewer.ID, "snapshot2 should not be stale yet")

	// modify the stale_since times to fit our scenario
	s.setCanonicalStaleSince(snapshotExpired.ID, 121*60)
	s.setCanonicalStaleSince(snapshotOrphaned.ID, 60)

	// one more snapshot to trigger the expiration
	snapshotNewest := getExpectedSnapshotWithRepoID(t, repo)
	snapshotNewest.SHA = newestSHA
	snapshotNewest.Detector.Name = "newest"
	createTestSnapshot(t, s.storageAdapter, snapshotNewest)

	// check the canonical snapshots at this point to verify expiration
	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertContainsSnapshots(t, actualSnapshots, snapshotOrphaned, snapshotNewer, snapshotNewest)
	assertDoesNotContainSnapshots(t, actualSnapshots, snapshotExpired)

	// now, make sure we can un-stalify a snapshot
	snapshotOrphanedRefresh := getExpectedSnapshotWithRepoID(t, repo)
	snapshotOrphanedRefresh.SHA = newestSHA
	snapshotOrphanedRefresh.Detector.Name = snapshotOrphaned.Detector.Name
	createTestSnapshot(t, s.storageAdapter, snapshotOrphanedRefresh)
	s.assertNotStale(snapshotOrphanedRefresh.ID, "snapshotOrphanedRefresh should not be stale")
}

func (s *StorageRetrievalTestSuite) setCanonicalStaleSince(snapshotID uint64, seconds int64) {
	s.T().Helper()
	s.assertStale(snapshotID, "snapshot is not yet stale!")

	newTime := time.Now().Add(-time.Duration(seconds) * time.Second)
	updateAgeQuery := `
		update ds_canonical_snapshots
		set stale_since = ?
		where snapshot_id = ?
	`
	_, err := s.testDB.DB.PrimaryExecutor.ExecContext(context.Background(), updateAgeQuery, newTime, snapshotID)
	s.Require().NoError(err)
}

func (s *StorageRetrievalTestSuite) getStaleness(snapshotID uint64) sql.NullTime {
	s.T().Helper()

	query := `
		select stale_since
		from ds_canonical_snapshots
		where snapshot_id = ?
	`
	var staleSince sql.NullTime
	err := s.testDB.DB.PrimaryExecutor.QueryRowContext(context.Background(), query, snapshotID).Scan(&staleSince)
	s.Require().NoError(err)
	return staleSince
}

func (s *StorageRetrievalTestSuite) assertStale(snapshotID uint64, msg string) {
	s.T().Helper()
	staleness := s.getStaleness(snapshotID)
	s.Require().Truef(staleness.Valid, msg)
}

func (s *StorageRetrievalTestSuite) assertNotStale(snapshotID uint64, msg string) {
	s.T().Helper()
	staleness := s.getStaleness(snapshotID)
	s.Require().Falsef(staleness.Valid, msg)
}
