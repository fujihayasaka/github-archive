package storage_test

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"sort"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/storage"
	"github.com/github/dependency-snapshots-api/internal/testutil"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"

	"github.com/maxatome/go-testdeep/td"

	features_mock "github.com/github/dependency-snapshots-api/internal/features/mock"
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
	t := s.Suite.T()
	if s.Enterprise {
		os.Setenv("ENTERPRISE", "TRUE")
	} else {
		os.Unsetenv("ENTERPRISE")
	}

	testDB, err := testutil.NewNamedTestDB(t, testutil.CreateTestConfig(t), log.NewNullLogger(), stats.NullStatter, "snapshot_storage")
	s.Require().NoError(err)
	s.testDB = testDB

	features := features_mock.NewFeaturesClientAllOn()
	s.storageAdapter = createTestAdapter(t, testDB, features)
	t.Logf("Starting test suite with Enterprise: %v", s.Enterprise)
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
	cloudMode := &StorageRetrievalTestSuite{
		Enterprise: false,
	}
	enterpriseMode := &StorageRetrievalTestSuite{
		// Run w/o blob storage (snapshots in DB)
		Enterprise: true,
	}

	suite.Run(t, cloudMode)
	suite.Run(t, enterpriseMode)
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
		Scanned:      time.Now().Add(-time.Minute).Round(time.Second).In(time.UTC),
		CreatedAt:    time.Now().Add(-time.Minute).Round(time.Second).In(time.UTC),
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

func (s *StorageRetrievalTestSuite) TestOnlyCanonicalSnapshotsDenormalize() {
	t := s.Suite.T()

	repo := randomRepositoryID(t, s.storageAdapter)

	snapshotCanonical := getExpectedSnapshotWithRepoID(t, repo)

	snapshotNonCanonical := getExpectedSnapshotWithRepoID(t, repo)
	snapshotNonCanonical.Ref = "refs/heads/dev"

	ctx, buf := newTestLogContext()

	// Create the canonical snapshot
	createTestSnapshotWithContext(t, ctx, s.storageAdapter, snapshotCanonical)
	denormalizationCount := testutil.OperationCallCount(buf, "denormalizeSnapshotDependencies")
	require.Equal(t, 1, denormalizationCount, "expected one denormalization for the canonical snapshot")

	buf.Reset()

	// Create a non-canonical snapshot
	createTestSnapshotWithContext(t, ctx, s.storageAdapter, snapshotNonCanonical)
	denormalizationCount = testutil.OperationCallCount(buf, "denormalizeSnapshotDependencies")
	require.Zero(t, denormalizationCount, "expected no denormalization for the non-canonical snapshot")
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
	// update one of the deps in snapshot1 to make it different from snapshot0
	snapshot1.Manifests["oid1"].Resolved["somepack1"].PackageURL = "pkg:example/somepack1@1.0.0"

	_, _, _, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot0)
	require.NoError(t, err)

	_, _, result, err := s.storageAdapter.StoreSnapshot(context.Background(), snapshot1)
	require.NoError(t, err)

	if testutility.AreHistoricalSnapshotsStored(t) {
		assert.Equal(t, interfaces.AcceptedHistorical, result)
	} else {
		assert.Equal(t, interfaces.SnapshotRemoved, result)
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

func (s *StorageRetrievalTestSuite) TestVolatileFieldsComeFromDatabaseNotBlob() {
	t := s.Suite.T()
	if s.Enterprise {
		// Snapshot blobs are regularly deleted in the enterprise version,
		// which makes deduplication irrelevant.
		t.Skip("Skipping test that is not relevant for enterprise")
	}

	// Step 1: Create two snapshots that will have different volatile fields
	repoID := randomRepositoryID(t, s.storageAdapter)
	snap1 := getExpectedSnapshotWithRepoID(t, repoID)
	snap2 := getExpectedSnapshotWithRepoID(t, repoID)

	// Enable the feature flag for blob deduplication
	features := features_mock.NewFeaturesClientAllOn()
	s.storageAdapter = createTestAdapter(t, s.testDB, features)

	// Make the volatile fields different
	snap1.Job.ID = "job-1"
	snap1.SHA = "sha-111"
	snap1.Scanned = time.Now().Add(-2 * time.Hour).Round(0)

	snap2.Job.ID = "job-2"
	snap2.SHA = "sha-222"
	snap2.Scanned = time.Now().Add(-1 * time.Hour).Round(0)

	createTestSnapshots(t, s.storageAdapter, snap1, snap2)

	// Assert that the blob IDs are the same (deduplication worked)
	blobID1 := getSnapshotBlobID(t, s.testDB, snap1.ID)
	blobID2 := getSnapshotBlobID(t, s.testDB, snap2.ID)
	assert.Equal(t, blobID1, blobID2, "blob IDs should match for deduplicated snapshots")

	// Step 2: Retrieve both snapshots and assert that the volatile fields match the database, not the blob
	got1, err1 := s.storageAdapter.SnapshotByID(context.Background(), repoID, snap1.ID)
	require.NoError(t, err1, "error retrieving snapshot 1")
	got2, err2 := s.storageAdapter.SnapshotByID(context.Background(), repoID, snap2.ID)
	require.NoError(t, err2, "error retrieving snapshot 2")

	// These assertions will fail if the fields are coming from the blob, not the database
	assert.Equal(t, "job-1", got1.Job.ID, "job.id should come from the database")
	assert.Equal(t, "sha-111", got1.SHA, "sha should come from the database")
	assert.WithinDuration(t, snap1.Scanned, got1.Scanned, time.Second, "scanned should come from the database")

	assert.Equal(t, "job-2", got2.Job.ID, "job.id should come from the database")
	assert.Equal(t, "sha-222", got2.SHA, "sha should come from the database")
	assert.WithinDuration(t, snap2.Scanned, got2.Scanned, time.Second, "scanned should come from the database")
}

// Test that volatile fields come from the database, not the blob, for CanonicalSnapshotsForRepository
func (s *StorageRetrievalTestSuite) TestVolatileFieldsComeFromDatabaseNotBlob_CanonicalSnapshotsForRepository() {
	t := s.Suite.T()
	if s.Enterprise {
		t.Skip("Skipping test that is not relevant for enterprise")
	}

	// Step 1: Create a snapshot with a specific repository ID and volatile fields
	repoID := randomRepositoryID(t, s.storageAdapter)
	snap := getExpectedSnapshotWithRepoID(t, repoID)

	features := features_mock.NewFeaturesClientAllOn()
	s.storageAdapter = createTestAdapter(t, s.testDB, features)

	snap.Job.ID = "job-1-blob-value"
	snap.Scanned = time.Now().Round(0)
	// the SHA is "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", and we can't change that or the snapshot will not be canonical

	createTestSnapshots(t, s.storageAdapter, snap)

	// Step 2: Manually update the database so the snapshot has different volatile fields
	//
	// These steps are necessary only because we're not actually deduplicating blobs.
	// They manually change the database to simulate a situation where these values differ
	// between the blob and the database. Once we actually have blob deduplication,
	// this will not be necessary.
	manuallyChangeSnapshotRow(t, s.testDB, snap.ID, "sha", "fake-sha-db-value")
	newScannedTime := time.Now().Add(-8 * time.Hour).Round(0)
	manuallyChangeSnapshotRow(t, s.testDB, snap.ID, "scanned_at", newScannedTime)
	manualSQLUpdate(t, s.testDB, "UPDATE ds_builds SET external_build_id = ? WHERE external_build_id = ?", "job-1-db-value", snap.Job.ID)

	// Step 3: Retrieve canonical snapshots for the repo
	canonical, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.DefaultQueryMode)
	require.NoError(t, err)

	require.Len(t, canonical, 1, "expected one canonical snapshot for the repo")

	// Assert volatile fields come from the database
	assert.Equal(t, "job-1-db-value", canonical[0].Job.ID, "job.id should come from the database")
	assert.Equal(t, "fake-sha-db-value", canonical[0].SHA, "sha should come from the database")
	assert.WithinDuration(t, newScannedTime, canonical[0].Scanned, time.Second, "scanned should come from the database")
}

// TestCanonicalSnapshotDeduplication verifies that snapshots with identical dependencies
// but different volatile fields share the same snapshot_blob_id when deduplication is enabled,
// and have different blob IDs when deduplication is disabled.
func (s *StorageRetrievalTestSuite) TestCanonicalSnapshotDeduplication() {
	t := s.Suite.T()
	if s.Enterprise {
		t.Skip("Skipping deduplication test for enterprise mode")
	}

	repoID := randomRepositoryID(t, s.storageAdapter)
	snap1 := getExpectedSnapshotWithRepoID(t, repoID)
	snap2 := getExpectedSnapshotWithRepoID(t, repoID)

	// Snapshots 1 and 2 should be identical except that snapshot 2 is newer.
	snap1.Scanned = time.Now().Add(-2 * time.Hour).Round(0)
	snap2.Scanned = time.Now().Add(-1 * time.Hour).Round(0)

	// --- Deduplication enabled ---
	ctx, logBuf := newTestLogContext()
	results := createTestSnapshotsWithContext(t, ctx, s.storageAdapter, snap1, snap2)
	require.Equal(t,
		[]interfaces.SnapshotResult{interfaces.AcceptedCanonical, interfaces.AcceptedCanonical},
		results, "expected both snapshots to be canonical")
	blobID1 := getSnapshotBlobID(t, s.testDB, snap1.ID)
	blobID2 := getSnapshotBlobID(t, s.testDB, snap2.ID)
	assert.Equal(t, blobID1, blobID2, "With deduplication enabled, blob IDs should match for identical dependencies")

	// only one snapshot should be considered canonical now: the second one (since it's newer).
	canonicalSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.DefaultQueryMode)
	require.NoError(t, err, "error retrieving canonical snapshots")
	require.Len(t, canonicalSnapshots, 1, "expected one canonical snapshot for the repo")
	canonicalSnapshotID := canonicalSnapshots[0].ID
	assert.Equal(t, snap2.ID, canonicalSnapshotID, "the second snapshot should be considered canonical")
	assert.WithinDuration(t, snap2.Scanned, canonicalSnapshots[0].Scanned, time.Second, "scanned should match the second snapshot's scanned time")

	// Assert that denormalization was only performed once (should not be called redundantly for deduplicated canonical snapshots)
	denormCount := testutil.OperationCallCount(logBuf, "denormalizeSnapshotDependencies")
	assert.Equal(t, 1, denormCount, "denormalizeSnapshotDependencies should be called only once for deduplicated canonical snapshots")
	logBuf.Reset()

	// if we re-submit snap1 at this point, nothing much should change. it's old and the blob is already canonical.
	res := createTestSnapshotWithContext(t, ctx, s.storageAdapter, snap1)
	assert.Equal(t, interfaces.AcceptedHistorical, res, "re-submitting an old snapshot should not change the canonical snapshot")
	// snap1 re-submission: doesn't affect canonical snapshots
	canonicalSnapshots, err = s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.DefaultQueryMode)
	require.NoError(t, err, "error retrieving canonical snapshots after re-submitting snap1")
	require.Len(t, canonicalSnapshots, 1, "expected one canonical snapshot for the repo after re-submitting snap1")
	assert.Equal(t, canonicalSnapshotID, canonicalSnapshots[0].ID, "the canonical snapshot should not change after re-submitting an old snapshot")
	// snap1 re-submission: should not change the blob ID
	blobID1AfterResubmit := getSnapshotBlobID(t, s.testDB, snap1.ID)
	assert.Equal(t, blobID1, blobID1AfterResubmit, "re-submitting an old snapshot should not change the blob ID")
	// snap1 re-submission: should not trigger denormalizeSnapshotDependencies
	denormCount = testutil.OperationCallCount(logBuf, "denormalizeSnapshotDependencies")
	assert.Zero(t, denormCount, "denormalizeSnapshotDependencies should not be called again after re-submitting an old snapshot")
}

func (s *StorageRetrievalTestSuite) TestSnapshotBlobDeduplicationDoesNotBreakAnything() {
	// Note: unlike the other tests for this feature, this test WILL run on Enterprise.
	// We don't necessarily expect this flag to be enabled there, but it should not break anything if it is.
	t := s.Suite.T()
	features := features_mock.NewFeaturesClientAllOn()
	s.storageAdapter = createTestAdapter(t, s.testDB, features)

	repoID := randomRepositoryID(t, s.storageAdapter)
	snap1 := getExpectedSnapshotWithRepoID(t, repoID)
	snap2 := getExpectedSnapshotWithRepoID(t, repoID)
	scannedTime1 := time.Now().Add(-2 * time.Hour).Round(0)
	scannedTime2 := time.Now().Add(-1 * time.Hour).Round(0)

	// Make the volatile fields different
	snap1.Job.ID = "job-1"
	snap1.Scanned = scannedTime1
	snap2.Job.ID = "job-2"
	snap2.Scanned = scannedTime2
	createTestSnapshots(t, s.storageAdapter, snap1, snap2)

	canonicalSnapshots, err := s.storageAdapter.CanonicalSnapshotsForRepository(context.Background(), repoID, interfaces.DefaultQueryMode)
	require.NoError(t, err, "error retrieving canonical snapshots")
	require.Len(t, canonicalSnapshots, 1, "expected one canonical snapshot for the repo")
	snapID := canonicalSnapshots[0].ID
	snapAsRetrieved, err := s.storageAdapter.SnapshotByID(context.Background(), repoID, snapID)
	require.NoError(t, err, "error retrieving snapshot by ID")

	// Assert that the snapshots have the right values for volatile fields
	assert.Equal(t, "job-2", snapAsRetrieved.Job.ID, "job.id should have the correct value")
	assert.WithinDuration(t, scannedTime2, snapAsRetrieved.Scanned, time.Second, "scanned should have the correct value")

	// Assert that the dependencies are the same
	snapExpectedDeps := getPackageURLsFromSnapshot(t, snap1)
	snapDepsAsRetrieved := getPackageURLsFromSnapshot(t, snapAsRetrieved)
	assert.Len(t, snapExpectedDeps, 4)
	assert.ElementsMatch(t, snapExpectedDeps, snapDepsAsRetrieved, "dependencies of snapshot should match")
}

func (s *StorageRetrievalTestSuite) TestBlobUploadDeduplicationWithVolatileFields() {
	t := s.Suite.T()
	if !testutility.IsBlobStorageBeingUsedToStoreSnapshots(t) {
		t.Skip("Skipping test because blob storage is not being used")
	}
	features := features_mock.NewFeaturesClientAllOn()
	testDB, err := testutil.NewNamedTestDB(t, testutil.CreateTestConfig(t), log.NewNullLogger(), stats.NullStatter, "snapshot_storage")
	require.NoError(t, err, "error creating test database")
	adapter := createTestAdapter(t, testDB, features)
	blobClientSpy := getSpyBlobClient(t, adapter)

	repoID := randomRepositoryID(t, adapter)
	snap1 := getExpectedSnapshotWithRepoID(t, repoID)
	snap2 := getExpectedSnapshotWithRepoID(t, repoID)

	// Make the volatile fields different
	snap1.Job.ID = "job-1"
	snap1.Scanned = time.Now().Add(-2 * time.Hour).Round(0)
	snap2.Job.ID = "job-2"
	snap2.Scanned = time.Now().Add(-1 * time.Hour).Round(0)

	createTestSnapshots(t, adapter, snap1, snap2)

	// Assert that only one blob was uploaded
	require.Equal(t, 1, blobClientSpy.CreateBlobCalls, "expected only 1 blob upload when deduplication is on")

	// Retrieve the snapshots from storage for verification
	snap1AsRetrieved, err := adapter.SnapshotByID(context.Background(), repoID, snap1.ID)
	require.NoError(t, err, "error retrieving snapshot 1")
	snap2AsRetrieved, err := adapter.SnapshotByID(context.Background(), repoID, snap2.ID)
	require.NoError(t, err, "error retrieving snapshot 2")

	// Assert that the retrieved snapshots use the same blob ID
	sna1blobID := getSnapshotBlobID(t, testDB, snap1.ID)
	sna2blobID := getSnapshotBlobID(t, testDB, snap2.ID)
	assert.Equal(t, sna1blobID, sna2blobID, "retrieved snapshots should share the same blob ID due to deduplication")

	// Assert that the volatile fields are as expected
	assert.Equal(t, "job-1", snap1AsRetrieved.Job.ID, "job.id should come from the database")
	assert.Equal(t, "job-2", snap2AsRetrieved.Job.ID, "job.id should come from the database")
	assert.WithinDuration(t, snap1.Scanned, snap1AsRetrieved.Scanned, time.Second, "scanned should come from the database")
	assert.WithinDuration(t, snap2.Scanned, snap2AsRetrieved.Scanned, time.Second, "scanned should come from the database")

	// Assert that the dependencies are the same
	snap1ExpectedDeps := getPackageURLsFromSnapshot(t, snap1)
	snap1DepsAsRetrieved := getPackageURLsFromSnapshot(t, snap1AsRetrieved)
	assert.Len(t, snap1ExpectedDeps, 4)
	assert.ElementsMatch(t, snap1ExpectedDeps, snap1DepsAsRetrieved, "dependencies of snapshot 1 should match")
	snap2ExpectedDeps := getPackageURLsFromSnapshot(t, snap2)
	snap2DepsAsRetrieved := getPackageURLsFromSnapshot(t, snap2AsRetrieved)
	assert.Len(t, snap2ExpectedDeps, 4)
	assert.ElementsMatch(t, snap2ExpectedDeps, snap2DepsAsRetrieved, "dependencies of snapshot 2 should match")
}

// createTestSnapshot creates a test snapshot with the submitted adapter,
// updating the snapshot pointer to a retrieved instance from the DB.

// newTestLogContext returns a context with a buffer-backed logger and the buffer for inspection.
func newTestLogContext() (context.Context, *bytes.Buffer) {
	logger := testutil.NewTestLogger()
	buf := logger.Buffer
	ctx := contextlogger.Set(context.Background(), logger)
	return ctx, buf
}

// createTestSnapshotWithContext creates a test snapshot using the provided context.
func createTestSnapshotWithContext(t *testing.T, ctx context.Context, adapter snapshots.StorageAdapter, snapshot *interfaces.Snapshot) interfaces.SnapshotResult {
	t.Helper()

	snapshotID, _, res, err := adapter.StoreSnapshot(ctx, snapshot)
	require.NoError(t, err)

	historical := testutility.AreHistoricalSnapshotsStored(t)
	if snapshotID != 0 {
		createdSnapshot, err := adapter.SnapshotByID(ctx, snapshot.RepositoryID, snapshotID)
		require.NoError(t, err)
		require.NotNilf(t, createdSnapshot, "Could not find the test snapshot with ID %d right after creating it. This is not something that should ever happen. Historical snapshot storage: %v", snapshotID, historical)
		*snapshot = *createdSnapshot
	} else if res == interfaces.SnapshotRemoved {
		*snapshot = *new(interfaces.Snapshot)
	} else {
		t.Errorf("Snapshot was not removed but the ID was not returned. This is not something that should ever happen. Result was %v", res)
	}
	return res
}

// createTestSnapshotsWithContext creates multiple test snapshots using the provided context.
func createTestSnapshotsWithContext(t *testing.T, ctx context.Context, adapter snapshots.StorageAdapter, snapshots ...*interfaces.Snapshot) []interfaces.SnapshotResult {
	t.Helper()
	results := make([]interfaces.SnapshotResult, len(snapshots))
	for i, snapshot := range snapshots {
		results[i] = createTestSnapshotWithContext(t, ctx, adapter, snapshot)
	}
	return results
}

// Existing version for backward compatibility
func createTestSnapshot(t *testing.T, adapter snapshots.StorageAdapter, snapshot *interfaces.Snapshot) interfaces.SnapshotResult {
	return createTestSnapshotWithContext(t, context.Background(), adapter, snapshot)
}

func createTestSnapshots(t *testing.T, adapter snapshots.StorageAdapter, snapshots ...*interfaces.Snapshot) []interfaces.SnapshotResult {
	return createTestSnapshotsWithContext(t, context.Background(), adapter, snapshots...)
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
	snapshot.Scanned = time.Now().Add(-time.Duration(seconds) * time.Second).Round(time.Second).In(time.UTC)
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

// getSnapshotBlobID retrieves the snapshot blob ID for a given snapshot ID from the database.
func getSnapshotBlobID(t *testing.T, db *testutil.TestDB, snapshotID uint64) string {
	t.Helper()
	var blobID string
	err := db.DB.PrimaryExecutor.QueryRowContext(context.Background(),
		"SELECT snapshot_blob_id FROM ds_snapshots WHERE id = ?", snapshotID).Scan(&blobID)
	require.NoError(t, err, "error retrieving snapshot blob ID from the database")
	return blobID
}

// manualSQLUpdate executes a raw SQL update query against the database.
// This helper is a huge code smell, but it's necessary for testing deduplication
// while we slowly implement that feature. In the long run, it would be great if this didn't exist
// (along with the specific helpers below that use it).
func manualSQLUpdate(t *testing.T, db *testutil.TestDB, query string, args ...interface{}) {
	t.Helper()
	_, err := db.DB.PrimaryExecutor.ExecContext(context.Background(), query, args...)
	require.NoError(t, err, "error executing manual SQL update")
}

// setSnapshotBlobID updates the snapshot blob ID for a given snapshot ID in the database.
func setSnapshotBlobID(t *testing.T, db *testutil.TestDB, snapshotID uint64, blobID string) {
	t.Helper()
	manualSQLUpdate(t, db, "UPDATE ds_snapshots SET snapshot_blob_id = ? WHERE id = ?", blobID, snapshotID)
}

func manuallyChangeSnapshotRow(t *testing.T, db *testutil.TestDB, snapshotID uint64, column string, value interface{}) {
	t.Helper()
	query := fmt.Sprintf("UPDATE ds_snapshots SET %s = ? WHERE id = ?", column)
	manualSQLUpdate(t, db, query, value, snapshotID)
}

func getSpyBlobClient(t *testing.T, stg snapshots.StorageAdapter) *testutility.SpyBlobClient {
	t.Helper()
	mysqladapter, ok := stg.(*storage.MySQLSnapshotsAdapter)
	require.True(t, ok, "StorageAdapter is not a MySQLStorageAdapter")
	spyClient, ok := mysqladapter.AdapterOptions.BlobClient.(*testutility.SpyBlobClient)
	require.Truef(t, ok, "BlobClient is not a SpyBlobClient: %T", mysqladapter.AdapterOptions.BlobClient)
	return spyClient
}

// getPackageURLsFromSnapshot extracts and returns a sorted list of package URLs from the snapshot.
// This is useful for testing purposes, to ensure that the package URLs in the snapshot match expected values.
func getPackageURLsFromSnapshot(t *testing.T, snapshot *interfaces.Snapshot) []string {
	t.Helper()
	var urls []string
	for _, manifest := range snapshot.Manifests {
		for purl := range manifest.Resolved {
			urls = append(urls, purl)
		}
	}
	sort.Strings(urls)
	return urls
}

func (s *StorageRetrievalTestSuite) TestCountSnapshotsForSHA() {
	t := s.Suite.T()
	repo := randomRepositoryID(t, s.storageAdapter)

	sha := string(gitMock.ExpectedSHA)

	// Create multiple snapshots with different detectors
	snapshot1 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1.SHA = sha
	snapshot1.Detector.Name = "detector1"
	snapshot1.Job.Correlator = "correlator1"

	snapshot2 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot2.SHA = sha
	snapshot2.Detector.Name = "detector2"
	snapshot2.Job.Correlator = "correlator2"

	snapshot3 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot3.SHA = sha
	snapshot3.Detector.Name = "detector3"
	snapshot3.Job.Correlator = "correlator3"

	// Create an internal snapshot (should not be counted)
	internalSnapshot := getExpectedSnapshotWithRepoID(t, repo)
	internalSnapshot.SHA = sha
	internalSnapshot.Internal = true
	internalSnapshot.Detector.Name = "internal-detector"
	internalSnapshot.Job.Correlator = "internal-correlator"

	// Create a snapshot with different SHA (should not be counted)
	differentSHASnapshot := getExpectedSnapshotWithRepoID(t, repo)
	differentSHASnapshot.SHA = string(gitMock.HistoricalSHAs[1])
	differentSHASnapshot.Detector.Name = "detector1"
	differentSHASnapshot.Job.Correlator = "correlator1"

	createTestSnapshots(t, s.storageAdapter, snapshot1, snapshot2, snapshot3, internalSnapshot, differentSHASnapshot)

	// Test counting snapshots for the SHA
	query := interfaces.SnapshotsQuery{SHA: sha}
	count, err := s.storageAdapter.CountSnapshotsForSHA(context.Background(), repo, query)
	require.NoError(t, err)
	assert.Equal(t, 3, count, "expected 3 non-internal snapshots for SHA %s", sha)
}

func (s *StorageRetrievalTestSuite) TestCountSnapshotsForSHADuplicateDetectorCorrelator() {
	t := s.Suite.T()
	repo := randomRepositoryID(t, s.storageAdapter)

	sha := string(gitMock.ExpectedSHA)

	// Create multiple snapshots with the same detector and correlator combination
	snapshot1 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot1.SHA = sha
	snapshot1.Detector.Name = "same-detector"
	snapshot1.Job.Correlator = "same-correlator"

	snapshot2 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot2.SHA = sha
	snapshot2.Detector.Name = "same-detector"
	snapshot2.Job.Correlator = "same-correlator"

	// Create one with different detector
	snapshot3 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot3.SHA = sha
	snapshot3.Detector.Name = "different-detector"
	snapshot3.Job.Correlator = "same-correlator"

	// Create one with different correlator
	snapshot4 := getExpectedSnapshotWithRepoID(t, repo)
	snapshot4.SHA = sha
	snapshot4.Detector.Name = "same-detector"
	snapshot4.Job.Correlator = "different-correlator"

	createTestSnapshots(t, s.storageAdapter, snapshot1, snapshot2, snapshot3, snapshot4)

	// Test counting snapshots - should count unique (detector_name, external_type_id) combinations
	query := interfaces.SnapshotsQuery{SHA: sha}
	count, err := s.storageAdapter.CountSnapshotsForSHA(context.Background(), repo, query)
	require.NoError(t, err)
	assert.Equal(t, 3, count, "expected 3 distinct detector/correlator combinations")
}
