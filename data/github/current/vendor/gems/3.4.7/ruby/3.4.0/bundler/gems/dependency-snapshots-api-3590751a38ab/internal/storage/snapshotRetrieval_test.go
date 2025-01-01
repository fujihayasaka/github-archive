package storage_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/testutil"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"

	"github.com/maxatome/go-testdeep/td"

	gitMock "github.com/github/dependency-snapshots-api/internal/gitaccess/mock"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/snapshots"
	"github.com/github/dependency-snapshots-api/internal/storage/blob/testutility"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
)

// Define the suite, and absorb the built-in basic suite
// functionality from testify - including a T() method which
// returns the current testing context
type StorageRetrievalTestSuite struct {
	suite.Suite
	Enterprise     bool
	storageAdapter snapshots.StorageAdapter
	testDB         *testutil.TestDB
}

func (s *StorageRetrievalTestSuite) SetupSuite() {
	if s.Enterprise {
		os.Setenv("ENTERPRISE", "TRUE")
	} else {
		os.Unsetenv("ENTERPRISE")
	}

	testDB, err := testutil.NewNamedTestDB(s.T(), testutil.CreateTestConfig(s.T()), log.NewNullLogger(), stats.NullStatter, "snapshot_storage")
	s.Require().NoError(err)
	s.testDB = testDB

	s.storageAdapter = createTestAdapter(s.T(), testDB)
	s.T().Logf("Starting test suite with Enterprise: %v", s.Enterprise)
}

func (s *StorageRetrievalTestSuite) TearDownSuite() {
	s.Require().NoError(s.testDB.Close())
}

func (s *StorageRetrievalTestSuite) BeforeTest() {
	s.Require().NoError(s.testDB.DeleteTables())
}

func (s *StorageRetrievalTestSuite) AfterTest() {
	s.Require().NoError(s.testDB.DeleteTables())
}

// In order for 'go test' to run this suite, we need to create
// a normal test function and pass our suite to suite.Run
func TestStorageRetrievalTestSuite(t *testing.T) {
	// Run w/o blob storage (snapshots in DB)
	blobStorageSuite := new(StorageRetrievalTestSuite)
	blobStorageSuite.Enterprise = true
	suite.Run(t, blobStorageSuite)
	suite.Run(t, new(StorageRetrievalTestSuite))
}

func getExpectedSnapshot(t *testing.T) *interfaces.Snapshot {
	t.Helper()
	return getExpectedSnapshotWithRepoID(t, 10)
}

func getExpectedSnapshotWithRepoID(t *testing.T, repoID uint64) *interfaces.Snapshot {
	t.Helper()

	return &interfaces.Snapshot{
		Version: 0,
		Job: interfaces.Job{
			Correlator: "test-correlator",
			ID:         "job-id",
			HTMLUrl:    "example.com/job",
		},
		SHA: string(gitMock.ExpectedSHA),
		Ref: "refs/heads/main",
		Detector: &interfaces.DetectorMetadata{
			Name:    "test-detector",
			URL:     "example.com/detector",
			Version: "1.1.1",
		},
		Metadata: interfaces.Metadata{
			"push_id": "654321",
		},
		Manifests: interfaces.Manifests{
			"oid1": &interfaces.Manifest{
				Name:     "Path1",
				File:     interfaces.FileInfo{SourceLocation: "Path1"},
				Metadata: interfaces.Metadata{"oid": "oid1"},
				Resolved: interfaces.DependencyGraph{
					"somepack1": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/somepack1@version1",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
						Metadata: interfaces.Metadata{
							"dep": "somepack1",
						},
						Dependencies: []string{"transitiveDep"},
					},
					"transitiveDep": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/transitiveDep@1.2.3",
						Relationship: interfaces.Indirect,
						Scope:        interfaces.Runtime,
						Metadata: interfaces.Metadata{
							"dep": "transitiveDep",
						},
					},
				},
			},
			"oid2": &interfaces.Manifest{
				Name:     "Path2",
				File:     interfaces.FileInfo{SourceLocation: "Path2"},
				Metadata: interfaces.Metadata{"oid": "oid2"},
				Resolved: interfaces.DependencyGraph{
					"somepack2": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/somepack2@version2",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Runtime,
					},
					"testDep": &interfaces.DependencyNode{
						PackageURL:   "pkg:example/testDep@3.2.1",
						Relationship: interfaces.Direct,
						Scope:        interfaces.Development,
					},
				},
			},
		},
		Scanned:      time.Now().Add(-time.Minute).Round(0),
		ID:           5,
		RepositoryID: repoID,
	}
}

func (s *StorageRetrievalTestSuite) TestGetSnapshotByIDHappyPath() {
	t := s.Suite.T()

	snapExpected := getExpectedSnapshot(t)
	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	assert.NoError(t, err)
	assert.NotNil(t, snapActual)

	td.Cmp(t, snapActual, snapExpected)
}

func (s *StorageRetrievalTestSuite) TestGetSnapshotByIDAlternateBranch() {
	t := s.Suite.T()

	repoID := randomRepositoryID(t, s.storageAdapter)
	snapExpected := getExpectedSnapshotWithRepoID(t, repoID)
	snapExpected.Ref = "refs/heads/other-branch"
	snapExpected.SHA = "cafe123"
	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	assert.NoError(t, err)

	if testutility.AreHistoricalSnapshotsStored(t) {
		assert.NotNil(t, snapActual)
		td.Cmp(t, snapActual, snapExpected)
	} else {
		assert.Nil(t, snapActual)
	}
}

func (s *StorageRetrievalTestSuite) TestGetInternalSnapshot() {
	t := s.Suite.T()

	repoID := randomRepositoryID(t, s.storageAdapter)
	snapExpected := getExpectedSnapshotWithRepoID(t, repoID)
	snapExpected.Internal = true
	createTestSnapshot(t, s.storageAdapter, snapExpected)
	require.NotZero(t, snapExpected.ID, "newly created snapshot should have an ID")

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	assert.NoError(t, err)

	require.Truef(t, snapActual.Internal, "expected snapshot to be marked internal")
	td.Cmp(t, snapActual, snapExpected)

	// get the external canonical snapshots for the repo
	defaultSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	require.Lenf(t, defaultSnapshots, 0, "expected no external snapshots for repo %d", repoID)

	// get the internal canonical snapshots for the repo
	internalSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.IncludeInternal)
	require.NoError(t, err)
	require.Lenf(t, internalSnapshots, 1, "expected 1 internal snapshot for repo %d", repoID)
	td.Cmp(t, internalSnapshots[0], snapExpected)
}

func (s *StorageRetrievalTestSuite) TestInternalCanonical() {
	t := s.Suite.T()

	earlyTime := time.Unix(200000000, 0) // May 3, 1976
	laterTime := time.Unix(500000000, 0) // Nov 4, 1985

	// Create an internal snapshot and make sure it's considered canonical
	repoID := randomRepositoryID(t, s.storageAdapter)
	snapExpected := getExpectedSnapshotWithRepoID(t, repoID)
	snapExpected.Internal = true
	snapExpected.SHA = "caca" // SHAs should be ignored for internal snapshots
	snapExpected.Scanned = laterTime
	snapExpected.Ref = "refs/heads/whatever" // This should be assumed to be the default branch
	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	assert.NoError(t, err)
	td.Cmp(t, snapActual, snapExpected)

	internalSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.IncludeInternal)
	require.NoError(t, err)
	require.Lenf(t, internalSnapshots, 1, "expected 1 internal snapshot for repo %d", repoID)
	require.Equalf(t, snapExpected.ID, internalSnapshots[0].ID, "expected the first snapshot to be canonical, got snapshot with sha '%s'", internalSnapshots[0].SHA)
	td.Cmp(t, internalSnapshots[0], snapExpected)

	// Create a second snapshot with an older timestamp and make sure it's not canonical
	snapExpected2 := getExpectedSnapshotWithRepoID(t, repoID)
	snapExpected2.Internal = true
	snapExpected2.SHA = "baba"
	snapExpected2.Scanned = earlyTime
	createTestSnapshot(t, s.storageAdapter, snapExpected2)

	internalSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.IncludeInternal)
	require.NoError(t, err)
	require.Lenf(t, internalSnapshots, 1, "expected 1 internal snapshot for repo %d", repoID)
	require.Equalf(t, snapExpected.ID, internalSnapshots[0].ID, "expected the first snapshot to still be canonical, got snapshot with sha '%s'", internalSnapshots[0].SHA)
	td.Cmp(t, internalSnapshots[0], snapExpected)

	// Create a third snapshot with a newer timestamp and make sure it's canonical
	snapExpected3 := getExpectedSnapshotWithRepoID(t, repoID)
	snapExpected3.Internal = true
	snapExpected3.SHA = "aaaa"
	createTestSnapshot(t, s.storageAdapter, snapExpected3)

	internalSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.IncludeInternal)
	require.NoError(t, err)
	require.Lenf(t, internalSnapshots, 1, "expected 1 internal snapshot for repo %d", repoID)
	require.Equalf(t, snapExpected3.ID, internalSnapshots[0].ID, "expected the third snapshot to be canonical, got snapshot with sha '%s'", internalSnapshots[0].SHA)
	td.Cmp(t, internalSnapshots[0], snapExpected3)
}

func (s *StorageRetrievalTestSuite) TestGetSnapshotByIDWrongRepo() {
	t := s.Suite.T()

	snapExpected := getExpectedSnapshot(t)
	createTestSnapshot(t, s.storageAdapter, snapExpected)

	wrongRepoID := snapExpected.RepositoryID + 1
	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), wrongRepoID, snapExpected.ID)

	assert.NoError(t, err)
	assert.Nil(t, snapActual)
}

func (s *StorageRetrievalTestSuite) TestGetSnapshotByIDEmptyDependencies() {
	t := s.Suite.T()

	snapExpected := getExpectedSnapshot(t)

	// empty out the dependencies in the snapshot
	snapExpected.Manifests = interfaces.Manifests{
		"oid1": {
			Name:     "Path1",
			File:     interfaces.FileInfo{SourceLocation: "Path1"},
			Metadata: interfaces.Metadata{"oid": "oid1"},
			Resolved: interfaces.DependencyGraph{},
		},
	}

	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	assert.NotNil(t, snapActual)
	assert.NoError(t, err)

	td.Cmp(t, snapActual, snapExpected)
}

func (s *StorageRetrievalTestSuite) TestGetSnapshotByIDEmptyManifests() {
	t := s.Suite.T()

	snapExpected := getExpectedSnapshot(t)
	snapExpected.Manifests = interfaces.Manifests{}

	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	assert.NotNil(t, snapActual)
	assert.NoError(t, err)

	td.Cmp(t, snapActual, snapExpected)
}

func (s *StorageRetrievalTestSuite) TestSnapshotByIDEmptyDetector() {
	t := s.Suite.T()

	snapExpected := getExpectedSnapshot(t)
	snapExpected.Detector = nil

	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	require.NoError(t, err)

	assert.NotNil(t, snapActual)
	assert.Equal(t, "unknown", snapActual.Detector.Name)
}

func (s *StorageRetrievalTestSuite) TestSnapshotPurlEncoding() {
	t := s.Suite.T()

	snapExpected := getExpectedSnapshot(t)
	badPurl := "pkg:hex/plug_crypto@~> 1.1.1 or ~> 1.2"
	snapExpected.Manifests["oid1"] = simpleManifest("oid1", badPurl)

	badPurlEscaped := "pkg:hex/plug_crypto@~%3E%201.1.1%20or%20~%3E%201.2"

	createTestSnapshot(t, s.storageAdapter, snapExpected)

	snapActual, err := s.storageAdapter.SnapshotByID(context.Background(), snapExpected.RepositoryID, snapExpected.ID)
	require.NoError(t, err)
	assert.NotNil(t, snapActual)

	// ensure that the purl was properly escaped
	purlAsRetrieved := snapActual.Manifests["oid1"].Resolved[badPurl].PackageURL
	assert.Equal(t, badPurlEscaped, purlAsRetrieved)
}

func (s *StorageRetrievalTestSuite) TestSearchRepositoriesByDependency() {
	t := s.Suite.T()

	snapshot1 := getExpectedSnapshotWithRepoID(t, 43456)
	snapshot2 := getExpectedSnapshotWithRepoID(t, 43457)
	snapshot3 := getExpectedSnapshotWithRepoID(t, 43458)
	snapshot4 := getExpectedSnapshotWithRepoID(t, 43459)
	snapshot5 := getExpectedSnapshotWithRepoID(t, 43460)

	//snapshot1's purl 										   = "pkg:example/transitiveDep@1.2.3"
	snapshot2.Manifests["oid1"].Resolved["transitiveDep"].PackageURL = "pkg:example/namespace/transitiveDep@5.0.0"
	snapshot3.Manifests["oid1"].Resolved["transitiveDep"].PackageURL = "pkg:example/namespace/transitiveDep@5.0.0"
	snapshot4.Manifests["oid1"].Resolved["transitiveDep"].PackageURL = "pkg:example/namespace/transitiveDep@6.0.0"
	snapshot5.Manifests["oid1"].Resolved["transitiveDep"].PackageURL = "pkg:example/namespace/transitiveDep@7.0.0"

	createTestSnapshots(t, s.storageAdapter, snapshot1, snapshot2, snapshot3, snapshot4, snapshot5)

	actualRepositories, err := s.storageAdapter.SearchForRepositoriesContainingDependency(context.Background(), "pkg:example/namespace/transitiveDep", ">4.0.0,<6.0.0")
	require.NoError(t, err)

	// Tests aren't isolated, so we could pick up other canonical snapshots while running.
	require.GreaterOrEqual(t, len(actualRepositories), 2)
	require.Contains(t, actualRepositories, snapshot2.RepositoryID)
	require.Contains(t, actualRepositories, snapshot3.RepositoryID)
	require.NotContains(t, actualRepositories, snapshot1.RepositoryID)
	require.NotContains(t, actualRepositories, snapshot4.RepositoryID)
	require.NotContains(t, actualRepositories, snapshot5.RepositoryID)
}

func (s *StorageRetrievalTestSuite) TestCanonicalSnapshotsForRepository() {
	t := s.Suite.T()

	repo1 := randomRepositoryID(t, s.storageAdapter)
	repo2 := randomRepositoryID(t, s.storageAdapter)

	// a snapshot that won't be included
	snapshotOld := getExpectedSnapshotWithRepoID(t, repo1)
	snapshotOld.Metadata["name"] = "Old"
	setAge(snapshotOld, 100)

	// two snapshots that should both be included, one with a different job name
	snapshotNew1 := getExpectedSnapshotWithRepoID(t, repo1)
	snapshotNew1.Metadata["name"] = "New1"
	setAge(snapshotNew1, 0)

	snapshotNew1DiffBuild := getExpectedSnapshotWithRepoID(t, repo1)
	snapshotNew1DiffBuild.Metadata["name"] = "New1DiffBuild"
	snapshotNew1DiffBuild.Job.Correlator = "diff-build"
	setAge(snapshotNew1DiffBuild, 0)

	// a snapshot for another repo, which should not be included
	snapshotNew2 := getExpectedSnapshotWithRepoID(t, repo2)
	setAge(snapshotNew2, 0)

	createTestSnapshots(t, s.storageAdapter, snapshotOld, snapshotNew1, snapshotNew1DiffBuild, snapshotNew2)

	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo1, interfaces.DefaultQueryMode)
	require.NoError(t, err)

	// Tests aren't isolated, so we could pick up other canonical snapshots while running.
	require.GreaterOrEqual(t, len(actualSnapshots), 2)
	assertContainsSnapshots(t, actualSnapshots, snapshotNew1, snapshotNew1DiffBuild)
	assertDoesNotContainSnapshots(t, actualSnapshots, snapshotOld, snapshotNew2)
}

// Repro of https://github.com/github/dependency-graph/issues/2733
// based on the idea that ds_canonical_snapshots points to a non-existent snapshot ID
func (s *StorageRetrievalTestSuite) TestWeirdCanonicalCondition() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	snapshot := getExpectedSnapshotWithRepoID(t, repo)

	// 1. Create a normal snapshot
	createTestSnapshot(t, s.storageAdapter, snapshot)
	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	require.Equal(t, 1, len(actualSnapshots))
	require.Equal(t, snapshot.ID, actualSnapshots[0].ID)

	// 2. Make sure the canonical row points to a non-existent snapshot ID
	res, err := s.testDB.DB.PrimaryExecutor.ExecContext(context.Background(), fmt.Sprintf("DELETE FROM ds_snapshots WHERE id = %d", snapshot.ID))
	require.NoError(t, err, "error updating canonical row to bogus ID")
	rowsAffected, err := res.RowsAffected()
	require.NoError(t, err, "error deleting canonical snapshot")
	require.Equal(t, int64(1), rowsAffected, "expected to delete one row")

	// 4. Check the canonical snapshots again
	included, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	require.Len(t, included, 0, "no snapshots should be considered canonical")

	// 5. Creating a new snapshot for that repo should succeed
	snapshot2 := getExpectedSnapshotWithRepoID(t, repo)
	createTestSnapshot(t, s.storageAdapter, snapshot2)

	// 6. Verify that the new snapshot is canonical
	included, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	require.Len(t, included, 1, "one snapshot should be considered canonical")
	require.Equal(t, snapshot2.ID, included[0].ID, "the second snapshot should be considered canonical")
}

func (s *StorageRetrievalTestSuite) TestCanonicalSnapshotsMultipleDetectors() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	// a snapshot that won't be included
	newerSHA := string(gitMock.HistoricalSHAs[1])
	olderSHA := string(gitMock.HistoricalSHAs[3])

	// snapshot1 should be returned
	snapshot1 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1.SHA = newerSHA
	snapshot1.Detector.Name = "detector1"
	snapshot1.Manifests = map[string]*interfaces.Manifest{
		"oid1": simpleManifest("oid1", "pkg:example/detector1@1.0.0"),
	}
	// make sure this is the newest snapshot for the repo, sha, and detector
	setAge(snapshot1, 0)

	// a snapshot that should not be returned because it is superseded by snapshot1
	snapshotSuperseded := getExpectedSnapshotWithRepoID(t, repo)
	snapshotSuperseded.SHA = newerSHA
	snapshotSuperseded.Detector.Name = "detector1"
	snapshotSuperseded.Manifests = map[string]*interfaces.Manifest{
		"oidSuperseded": simpleManifest("oid1", "pkg:example/superseded@1.0.0"),
	}
	// if not for its old age, this would be a canonical commit
	setAge(snapshotSuperseded, 200)

	// snapshot2 should also be returned, because it has the same commit SHA and a different detector
	snapshot2 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot2.SHA = newerSHA
	snapshot2.Detector.Name = "detector2"
	snapshot2.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/detector2@1.0.0"),
	}
	// make this snapshot extra old to make sure time is not all that determines canonicity
	setAge(snapshot2, 300)

	// a snapshot with an older commit SHA, which should never appear in the results
	snapshotOldCommit := getExpectedSnapshotWithRepoID(t, repo)
	snapshotOldCommit.SHA = olderSHA
	snapshotOldCommit.Detector.Name = "detector1"
	snapshotOldCommit.Manifests = map[string]*interfaces.Manifest{
		"oidOld": simpleManifest("oidOld", "pkg:example/should_not_appear@1.0.0"),
	}

	createTestSnapshots(t, s.storageAdapter, snapshot1, snapshotSuperseded, snapshot2, snapshotOldCommit)

	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)

	// Tests aren't isolated, so we could pick up other canonical snapshots while running.
	require.GreaterOrEqual(t, len(actualSnapshots), 2)
	assertContainsSnapshots(t, actualSnapshots, snapshot1, snapshot2)
	assertDoesNotContainSnapshots(t, actualSnapshots, snapshotSuperseded, snapshotOldCommit)
}

func (s *StorageRetrievalTestSuite) TestQuerySnapshotsEmpty() {
	t := s.Suite.T()
	if !testutility.AreHistoricalSnapshotsStored(t) {
		// This test requires historical snapshot storage
		return
	}

	repo := randomRepositoryID(t, s.storageAdapter)

	query := interfaces.SnapshotsQuery{
		SHA: string(gitMock.ExpectedSHA),
	}

	snapshots, err := s.storageAdapter.QuerySnapshots(context.Background(), repo, query)
	require.NoError(t, err)
	require.Empty(t, snapshots)
}

func (s *StorageRetrievalTestSuite) TestQuerySnapshots() {
	t := s.Suite.T()
	if !testutility.AreHistoricalSnapshotsStored(t) {
		// This test requires historical snapshot storage
		return
	}
	repo := randomRepositoryID(t, s.storageAdapter)

	newerSHA := string(gitMock.HistoricalSHAs[1])
	olderSHA := string(gitMock.HistoricalSHAs[3])

	newerSnap1 := getExpectedSnapshotWithRepoID(t, repo)
	newerSnap1.SHA = newerSHA
	newerSnap1.Detector.Name = "detector1"
	newerSnap1.Manifests = map[string]*interfaces.Manifest{
		"oid1": simpleManifest("oid1", "pkg:example/detector1@1.0.0"),
	}
	newerSnap2 := getExpectedSnapshotWithRepoID(t, repo)
	newerSnap2.SHA = newerSHA
	newerSnap2.Detector.Name = "detector2"
	newerSnap2.Manifests = map[string]*interfaces.Manifest{
		"oid1": simpleManifest("oid1", "pkg:example/blah@1.2.3"),
	}
	newerSnap3 := getExpectedSnapshotWithRepoID(t, repo)
	newerSnap3.SHA = newerSHA
	newerSnap3.Detector.Name = "detector3"
	newerSnap3.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/blorg@1.2.3"),
	}
	createTestSnapshots(t, s.storageAdapter, newerSnap1, newerSnap2, newerSnap3)

	olderSnapSuperseded := getExpectedSnapshotWithRepoID(t, repo)
	olderSnapSuperseded.SHA = olderSHA
	olderSnapSuperseded.Detector.Name = "detector1"
	olderSnapSuperseded.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/crackle@1.0.0"),
	}
	setAge(olderSnapSuperseded, 100)

	olderSnap1 := getExpectedSnapshotWithRepoID(t, repo)
	olderSnap1.SHA = olderSHA
	olderSnap1.Detector.Name = "detector1"
	olderSnap1.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/snap@1.0.0"),
	}

	olderSnap2 := getExpectedSnapshotWithRepoID(t, repo)
	olderSnap2.SHA = olderSHA
	olderSnap2.Detector.Name = "detector2"
	olderSnap2.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/pop@1.0.0"),
	}
	createTestSnapshots(t, s.storageAdapter, olderSnap1, olderSnapSuperseded, olderSnap2)

	newerSnaps, err := s.storageAdapter.QuerySnapshots(context.Background(), repo, interfaces.SnapshotsQuery{SHA: newerSHA})
	require.NoError(t, err)
	assert.Lenf(t, newerSnaps, 3, "expected 3 snapshots, got %d", len(newerSnaps))
	assertContainsSnapshots(t, newerSnaps, newerSnap1, newerSnap2, newerSnap3)

	olderSnaps, err := s.storageAdapter.QuerySnapshots(context.Background(), repo, interfaces.SnapshotsQuery{SHA: olderSHA})
	require.NoError(t, err)
	assert.Lenf(t, olderSnaps, 2, "expected 3 snapshots, got %d", len(olderSnaps))
	assertContainsSnapshots(t, olderSnaps, olderSnap1, olderSnap2)
	assertDoesNotContainSnapshots(t, olderSnaps, olderSnapSuperseded)
}

func (s *StorageRetrievalTestSuite) TestExcludeSnapshotsWithMultipleDetectorsAndCorrelators() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	newerSHA := string(gitMock.HistoricalSHAs[1])

	snapshot1 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1.SHA = newerSHA
	snapshot1.Job.Correlator = "correlator1"
	snapshot1.Detector.Name = "detector1"
	snapshot1.Manifests = map[string]*interfaces.Manifest{
		"oid1": simpleManifest("oid1", "pkg:example/detector1@1.0.0"),
	}

	snapshot2 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot2.SHA = newerSHA
	snapshot2.Job.Correlator = "correlator2"
	snapshot2.Detector.Name = "detector2"
	snapshot2.Manifests = map[string]*interfaces.Manifest{
		"oid2": simpleManifest("oid2", "pkg:example/detector2@1.0.0"),
	}

	createTestSnapshots(t, s.storageAdapter, snapshot1, snapshot2)

	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertContainsSnapshots(t, actualSnapshots, snapshot1, snapshot2)

	removed, err := s.storageAdapter.ExcludeDependencySnapshots(context.Background(), repo, []uint64{snapshot1.ID})
	require.NoError(t, err)
	assert.Contains(t, removed, snapshot1.ID)

	actualSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertDoesNotContainSnapshots(t, actualSnapshots, snapshot1)
	assertContainsSnapshots(t, actualSnapshots, snapshot2)
}

func (s *StorageRetrievalTestSuite) TestExcludeSnapshotsWithResubmission() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	// a snapshot that won't be included
	newerSHA := string(gitMock.HistoricalSHAs[1])

	// snapshot1 should be returned
	snapshot1 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1.SHA = newerSHA
	snapshot1.Detector.Name = "detector1"
	snapshot1.Manifests = map[string]*interfaces.Manifest{
		"oid1": simpleManifest("oid1", "pkg:example/detector1@1.0.0"),
	}
	// make sure this is the newest snapshot for the repo, sha, and detector
	setAge(snapshot1, 0)

	// a snapshot that should not be returned because it is superseded by snapshot1
	snapshotSuperseded := getExpectedSnapshotWithRepoID(t, repo)
	snapshotSuperseded.SHA = newerSHA
	snapshotSuperseded.Detector.Name = "detector1"
	snapshotSuperseded.Manifests = map[string]*interfaces.Manifest{
		"oidSuperseded": simpleManifest("oid1", "pkg:example/superseded@1.0.0"),
	}
	// if not for its old age, this would be a canonical commit
	setAge(snapshotSuperseded, 200)
	createTestSnapshots(t, s.storageAdapter, snapshotSuperseded)

	// Superseded should be there
	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertContainsSnapshots(t, actualSnapshots, snapshotSuperseded)

	// Excluding superseded should result in its absence
	removed, err := s.storageAdapter.ExcludeDependencySnapshots(context.Background(), repo, []uint64{snapshotSuperseded.ID})
	require.NoError(t, err)
	assert.Contains(t, removed, snapshotSuperseded.ID)
	actualSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertDoesNotContainSnapshots(t, actualSnapshots, snapshotSuperseded)

	// Readding superseded should work
	createTestSnapshots(t, s.storageAdapter, snapshotSuperseded)
	actualSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertContainsSnapshots(t, actualSnapshots, snapshotSuperseded)

	// Creating something that superses superseded should work
	createTestSnapshots(t, s.storageAdapter, snapshot1)
	actualSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertContainsSnapshots(t, actualSnapshots, snapshot1)

	// Excluding snapshot1 should result in its absence
	removed, err = s.storageAdapter.ExcludeDependencySnapshots(context.Background(), repo, []uint64{snapshot1.ID})
	require.NoError(t, err)
	assert.Contains(t, removed, snapshot1.ID)
	actualSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	assertDoesNotContainSnapshots(t, actualSnapshots, snapshot1)
}

// Simulates a situation in which a snapshot is submitted for an old commit
func (s *StorageRetrievalTestSuite) TestCanonicalSnapshotsForRepositoryCIRerun() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	snapshotNew := getExpectedSnapshotWithRepoID(t, repo)
	// use the newest commit SHA for this snapshot
	snapshotNew.SHA = string(gitMock.HistoricalSHAs[0])
	setAge(snapshotNew, 50)

	snapshotRerun := getExpectedSnapshotWithRepoID(t, repo)
	// use an older commit SHA for this snapshot
	snapshotRerun.SHA = string(gitMock.HistoricalSHAs[1])
	// the SHA is old, but the snapshot is new
	setAge(snapshotRerun, 0)

	// Create the new snapshot and make sure it can be retrieved successfully
	createTestSnapshot(t, s.storageAdapter, snapshotNew)
	res, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	require.GreaterOrEqual(t, len(res), 1)
	assertContainsSnapshots(t, res, snapshotNew)

	// Submit the old snapshot and make sure it does not get retrieved
	createTestSnapshot(t, s.storageAdapter, snapshotRerun)
	res, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)
	require.GreaterOrEqual(t, len(res), 1)
	assertDoesNotContainSnapshots(t, res, snapshotRerun)
}

func (s *StorageRetrievalTestSuite) TestCanonicalSnapshotsForRepositoryEmpty() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	actualSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repo, interfaces.DefaultQueryMode)
	require.NoError(t, err)

	assert.Empty(t, actualSnapshots)
}

func (s *StorageRetrievalTestSuite) TestStoreSnapshotNonDefaultBranch() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)
	snapshot := getExpectedSnapshotWithRepoID(t, repo)
	snapshot.Ref = "refs/heads/non-main"

	_, _, result, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot)
	require.NoError(t, err)

	if testutility.AreHistoricalSnapshotsStored(t) {
		assert.Equal(t, result, interfaces.AcceptedNonDefaultBranch)
	} else {
		assert.Equal(t, result, interfaces.SnapshotRemoved)
	}
}

func (s *StorageRetrievalTestSuite) TestStoreSnapshotHistorical() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)
	snapshot0 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1.SHA = string(gitMock.HistoricalSHAs[1])

	_, _, _, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot0)
	require.NoError(t, err)

	_, _, result, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot1)
	require.NoError(t, err)

	if testutility.AreHistoricalSnapshotsStored(t) {
		assert.Equal(t, result, interfaces.AcceptedHistorical)
	} else {
		assert.Equal(t, result, interfaces.SnapshotRemoved)
	}
}

func (s *StorageRetrievalTestSuite) TestStoreSnapshotCanonical() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)
	snapshot := getExpectedSnapshotWithRepoID(t, repo)

	_, _, result, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot)
	require.NoError(t, err)
	assert.Equal(t, result, interfaces.AcceptedCanonical)
}

func (s *StorageRetrievalTestSuite) TestStoreSnapshotError() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)
	snapshot := getExpectedSnapshotWithRepoID(t, repo)
	snapshot.Manifests["oid1"].Resolved["somepack1"].PackageURL = "wrongurl"

	_, _, result, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot)
	require.Error(t, err)
	assert.Equal(t, result, interfaces.Error)
}

// createTestSnapshot creates a test snapshot with the submitted adapter,
// updating the snapshot pointer to a retrieved instance from the DB.
func createTestSnapshot(t *testing.T, adapter snapshots.StorageAdapter, snapshot *interfaces.Snapshot) {
	t.Helper()

	snapshotID, _, res, err := adapter.StoreSnapshot(context.Background(), snapshot)
	require.NoError(t, err)

	historical := testutility.AreHistoricalSnapshotsStored(t)
	if snapshotID != 0 {
		createdSnapshot, err := adapter.SnapshotByID(context.Background(), snapshot.RepositoryID, snapshotID)
		require.NoError(t, err)
		require.NotNilf(t, createdSnapshot, "Could not find the test snapshot with ID %d right after creating it. This is not something that should ever happen. Historical snapshot storage: %v", snapshotID, historical)
		*snapshot = *createdSnapshot
	} else if res == interfaces.SnapshotRemoved {
		// This is expected when running with historical snapshots disabled. The snapshot was "accepted" but not
		// actually stored.
		*snapshot = *new(interfaces.Snapshot)
	} else {
		t.Errorf("Snapshot was not removed but the ID was not returned. This is not something that should ever happen. Result was %v", res)
	}
}

func createTestSnapshots(t *testing.T, adapter snapshots.StorageAdapter, snapshots ...*interfaces.Snapshot) {
	t.Helper()
	for _, snapshot := range snapshots {
		createTestSnapshot(t, adapter, snapshot)
	}
}

func assertContainsSnapshots(t *testing.T, actualSnapshots []*interfaces.Snapshot, snapshotsThatShouldBePresent ...*interfaces.Snapshot) {
	t.Helper()
	for _, expected := range snapshotsThatShouldBePresent {
		foundMatch := false
		for _, actual := range actualSnapshots {
			if actual.ID == expected.ID {
				foundMatch = td.Cmp(t, actual, expected)
				break
			}
		}

		if !foundMatch {
			require.Fail(t, fmt.Sprintf("Could not find the snapshot with ID %v in actualSnapshots", expected.ID))
		}
	}
}

func assertDoesNotContainSnapshots(t *testing.T, actualSnapshots []*interfaces.Snapshot, snapshotsThatShouldNotBePresent ...*interfaces.Snapshot) {
	t.Helper()
	for _, expected := range snapshotsThatShouldNotBePresent {
		foundMatch := false
		for _, actual := range actualSnapshots {
			if actual.ID == expected.ID {
				foundMatch = true
				break
			}
		}

		if foundMatch {
			require.Fail(t, fmt.Sprintf("Found a snapshot we expected to be absent (ID: %v) in actualSnapshots", expected.ID))
		}
	}
}

// setAge should be used in cases where the Scanned time of a snapshot will be compared to other snapshots
func setAge(snapshot *interfaces.Snapshot, seconds int64) {
	snapshot.Scanned = time.Now().Add(-time.Duration(seconds) * time.Second)
}

// simpleManifest returns a manifest object with the given name and purl
func simpleManifest(name string, purl string) *interfaces.Manifest {
	return &interfaces.Manifest{
		Name: name,
		Resolved: map[string]*interfaces.DependencyNode{
			purl: {
				PackageURL:   purl,
				Relationship: interfaces.Direct,
				Scope:        interfaces.Runtime,
			},
		},
	}
}
