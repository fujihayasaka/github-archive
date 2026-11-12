package dependencies

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/go-stats"
)

type dependenciesService struct {
	snapshotsService interfaces.SnapshotsService
	statter          stats.Client
}

func NewDependenciesService(snapshotsService interfaces.SnapshotsService, statter stats.Client) interfaces.DependenciesService {
	return &dependenciesService{snapshotsService, statter}
}

func (d *dependenciesService) CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode interfaces.SnapshotQueryMode) ([]*interfaces.Snapshot, error) {
	// At this point, this method is just a thin wrapper around grabbing the canonical snapshots for a repository.
	canonicalSnapshots, err := d.snapshotsService.CanonicalSnapshotsForRepository(ctx, repositoryID, mode)
	if err != nil {
		return nil, err
	}

	if len(canonicalSnapshots) == 0 {
		return nil, nil
	}

	return canonicalSnapshots, nil
}

func (d *dependenciesService) HasManifests(ctx context.Context, repositoryID uint64) (bool, error) {
	return d.snapshotsService.HasManifests(ctx, repositoryID)
}

func (d *dependenciesService) RepositoriesContainingDependency(ctx context.Context, purl, versionRange string, mode interfaces.SnapshotQueryMode) ([]uint64, error) {
	repos, err := d.snapshotsService.RepositoriesContainingDependency(ctx, purl, versionRange)
	if err != nil || len(repos) == 0 {
		return nil, err
	}
	return repos, nil
}
