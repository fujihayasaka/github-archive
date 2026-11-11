package testutil

import (
	"context"
	"sort"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/util"

	"github.com/pkg/errors"
)

// MockStorage is intended to be a complete and working implementation of the StorageAdapter interface,
// but with based on in-memory storage with zero dependencies. It's also
// woefully inefficient, since it should only be used in tests with relatively
// small amounts of data.
type MockStorage struct {
	snapshotsByID map[uint64]*interfaces.Snapshot
}

func (ms *MockStorage) nextID() uint64 {
	var max uint64
	for k := range ms.snapshotsByID {
		if k > max {
			max = k
		}
	}

	return max + 1
}

func NewMockStorage(t *testing.T) *MockStorage {
	t.Helper()
	return &MockStorage{}
}

func (ms *MockStorage) SnapshotByID(ctx context.Context, repositoryID uint64, snapshotID uint64) (*interfaces.Snapshot, error) {
	if snapshot, ok := ms.snapshotsByID[snapshotID]; ok {
		if snapshot.RepositoryID == repositoryID {
			return snapshot, nil
		}
	}

	return nil, nil
}

func (ms *MockStorage) HasManifests(ctx context.Context, repositoryID uint64) (bool, error) {
	snaps, err := ms.CanonicalSnapshotsForRepository(ctx, repositoryID, interfaces.DefaultQueryMode)
	return len(snaps) > 0, err
}

func (ms *MockStorage) CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	var allForRepo []*interfaces.Snapshot
	for _, snapshot := range ms.snapshotsByID {
		if snapshot.RepositoryID == repositoryID {
			allForRepo = append(allForRepo, snapshot)
		}
	}

	// sort allForRepo by descending scanned time
	sort.Slice(allForRepo, func(i, j int) bool {
		return allForRepo[i].Scanned.After(allForRepo[j].Scanned)
	})

	// get the latest snapshot for the default branch (based on main/master)
	// for each job name
	knownJobs := util.NewSet[string]()
	ret := []*interfaces.Snapshot{}
	for _, snapshot := range allForRepo {
		if isDefaultBranch(snapshot.Ref) {
			identifier := snapshot.Detector.Name + ":" + snapshot.Job.Correlator
			if !knownJobs.Contains(identifier) {
				knownJobs.Add(identifier)
				ret = append(ret, snapshot)
			}
		}
	}

	return ret, nil
}

func isDefaultBranch(ref string) bool {
	return ref == "refs/heads/master" || ref == "refs/heads/main" || ref == "master" || ref == "main"
}

func (ms *MockStorage) StoreSnapshot(ctx context.Context, snapshot *interfaces.Snapshot) (uint64, time.Time, interfaces.SnapshotResult, error) {
	nextID := ms.nextID()
	snapshot.ID = nextID
	ms.snapshotsByID[nextID] = snapshot

	return nextID, time.Now(), interfaces.AcceptedCanonical, nil
}

func (ms *MockStorage) SearchCanonicalSnapshots(_ context.Context, _ string, _ string) ([]*interfaces.Snapshot, error) {
	return nil, errors.Errorf("this method is not yet implemented for MockStorage")
}

func (ms *MockStorage) SnapshotsForCommit(_ context.Context, repositoryID uint64, commitSHA gitaccess.SHA) ([]*interfaces.Snapshot, error) {
	var ret []*interfaces.Snapshot
	for _, snapshot := range ms.snapshotsByID {
		if snapshot.SHA == string(commitSHA) && snapshot.RepositoryID == repositoryID {
			ret = append(ret, snapshot)
		}
	}

	return ret, nil
}

func (ms *MockStorage) SearchForRepositoriesContainingDependency(_ context.Context, _ string, _ string) ([]uint64, error) {
	return nil, errors.Errorf("this method is not yet implemented for MockStorage")
}

func (ms *MockStorage) SearchCanonicalSnapshotsCoarseGrained(_ context.Context, _ string, _ string) ([]*interfaces.Snapshot, error) {
	return nil, errors.Errorf("this method is not yet implemented for MockStorage")
}
