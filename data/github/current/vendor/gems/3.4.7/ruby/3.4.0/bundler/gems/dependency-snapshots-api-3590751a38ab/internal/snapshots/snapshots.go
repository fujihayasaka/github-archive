package snapshots

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/interfaces"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/pkg/errors"
)

// StorageAdapter represents storage operations used by dependency-snapshots-api.
// It is agnostic to the underlying storage technology (e.g. MySQL).
type StorageAdapter interface {
	SnapshotByID(ctx context.Context, repositoryID uint64, id uint64) (*interfaces.Snapshot, error)
	CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error)
	QuerySnapshots(ctx context.Context, repositoryID uint64, query interfaces.SnapshotsQuery) ([]*interfaces.Snapshot, error)
	StoreSnapshot(ctx context.Context, snapshot *interfaces.Snapshot) (uint64, time.Time, interfaces.SnapshotResult, error)
	HasManifests(ctx context.Context, repositoryID uint64) (bool, error)
	SearchForRepositoriesContainingDependency(ctx context.Context, purl string, versionRange string) ([]uint64, error)
	ExcludeDependencySnapshots(ctx context.Context, repositoryID uint64, snapshotIDs []uint64) ([]uint64, error)
	UniqueRepositoryCounts(ctx context.Context) (*interfaces.ActivityCounts, error)
	TotalSnapshotCounts(ctx context.Context) (*interfaces.ActivityCounts, error)
}

type snapshotsService struct {
	adapter   StorageAdapter
	gitClient gitaccess.Client
}

func NewSnapshotsService(adapter StorageAdapter, gitClient gitaccess.Client) interfaces.SnapshotsService {
	return &snapshotsService{adapter, gitClient}
}

func (s *snapshotsService) SnapshotByID(ctx context.Context, repositoryID uint64, snapshotID uint64) (*interfaces.Snapshot, error) {
	return s.adapter.SnapshotByID(ctx, repositoryID, snapshotID)
}

func (s *snapshotsService) QuerySnapshots(ctx context.Context, repositoryID uint64, query interfaces.SnapshotsQuery) ([]*interfaces.Snapshot, error) {
	return s.adapter.QuerySnapshots(ctx, repositoryID, query)
}

func (s *snapshotsService) StoreSnapshot(ctx context.Context, snapshot *interfaces.Snapshot) (uint64, time.Time, interfaces.SnapshotResult, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "StoreSnapshotTracer", "StoreSnapshot",
		kvp.Int64("gh.repo.id", int64(snapshot.RepositoryID)),
		kvp.String("gh.push.commit_sha", snapshot.SHA),
		kvp.String("gh.push.ref", snapshot.Ref),
		kvp.Bool("gh.dependency_graph.snapshot.internal", snapshot.Internal))
	defer ender()

	return s.adapter.StoreSnapshot(ctx, snapshot)
}

func (s *snapshotsService) CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	return s.adapter.CanonicalSnapshotsForRepository(ctx, repositoryID, mode)
}

func (s *snapshotsService) HasManifests(ctx context.Context, repositoryID uint64) (bool, error) {
	return s.adapter.HasManifests(ctx, repositoryID)
}

func (s *snapshotsService) ExcludeDependencySnapshots(ctx context.Context, repositoryID uint64, snapshotIDs []uint64) ([]uint64, error) {
	return s.adapter.ExcludeDependencySnapshots(ctx, repositoryID, snapshotIDs)
}

func (s *snapshotsService) UniqueRepositoryCounts(ctx context.Context) (*interfaces.ActivityCounts, error) {
	return s.adapter.UniqueRepositoryCounts(ctx)
}

func (s *snapshotsService) TotalSnapshotCounts(ctx context.Context) (*interfaces.ActivityCounts, error) {
	return s.adapter.TotalSnapshotCounts(ctx)
}

// RepositoriesContainingDependency calls SearchCanonicalSnapshots to get snapshots that contain a given PURL and version range
// and returns a set of repository IDs that contain snapshots with the given PURLs and version ranges.
func (s *snapshotsService) RepositoriesContainingDependency(ctx context.Context, purl, versionRange string) ([]uint64, error) {
	repositoryIDs, err := s.adapter.SearchForRepositoriesContainingDependency(ctx, purl, versionRange)
	if err != nil {
		return nil, errors.Wrap(err, "unable to search repositories")
	}

	return repositoryIDs, nil
}
