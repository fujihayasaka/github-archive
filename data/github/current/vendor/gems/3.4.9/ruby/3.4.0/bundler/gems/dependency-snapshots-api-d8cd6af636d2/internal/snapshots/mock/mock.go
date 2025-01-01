package mock

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/stretchr/testify/mock"
)

type MockedSnapshotsService struct {
	mock.Mock
}

func (m *MockedSnapshotsService) SnapshotByID(ctx context.Context, repositoryID uint64, snapshotID uint64) (*interfaces.Snapshot, error) {
	args := m.Called(ctx, snapshotID)
	return args.Get(0).(*interfaces.Snapshot), args.Error(1)
}

func (m *MockedSnapshotsService) CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	args := m.Called(ctx, repositoryID, mode)
	return args.Get(0).([]*interfaces.Snapshot), args.Error(1)
}

func (m *MockedSnapshotsService) QuerySnapshots(ctx context.Context, repositoryID uint64, query interfaces.SnapshotsQuery) ([]*interfaces.Snapshot, error) {
	args := m.Called(ctx, repositoryID, query)
	return args.Get(0).([]*interfaces.Snapshot), args.Error(1)
}

func (m *MockedSnapshotsService) StoreSnapshot(ctx context.Context, snapshot *interfaces.Snapshot) (uint64, time.Time, interfaces.SnapshotResult, error) {
	args := m.Called(ctx, snapshot)
	return args.Get(0).(uint64), args.Get(1).(time.Time), args.Get(2).(interfaces.SnapshotResult), args.Error(3)
}

func (m *MockedSnapshotsService) RepositoriesContainingDependency(ctx context.Context, purl, versionRange string) ([]uint64, error) {
	args := m.Called(ctx, purl, versionRange)
	return args.Get(0).([]uint64), args.Error(1)
}

func (m *MockedSnapshotsService) HasManifests(ctx context.Context, repositoryID uint64) (bool, error) {
	args := m.Called(ctx, repositoryID)
	return args.Get(0).(bool), args.Error(1)
}

func (m *MockedSnapshotsService) ExcludeDependencySnapshots(ctx context.Context, repositoryID uint64, snapshotIDs []uint64) ([]uint64, error) {
	args := m.Called(ctx, repositoryID, snapshotIDs)
	return args.Get(0).([]uint64), args.Error(1)
}

func (m *MockedSnapshotsService) UniqueRepositoryCounts(ctx context.Context) (*interfaces.ActivityCounts, error) {
	args := m.Called(ctx)
	return args.Get(0).(*interfaces.ActivityCounts), args.Error(1)
}

func (m *MockedSnapshotsService) TotalSnapshotCounts(ctx context.Context) (*interfaces.ActivityCounts, error) {
	args := m.Called(ctx)
	return args.Get(0).(*interfaces.ActivityCounts), args.Error(1)
}

func (m *MockedSnapshotsService) CountSnapshotsForSHA(ctx context.Context, repositoryID uint64, query interfaces.SnapshotsQuery) (int, error) {
	args := m.Mock.Called(ctx, repositoryID, query)
	return args.Get(0).(int), args.Error(1)
}
