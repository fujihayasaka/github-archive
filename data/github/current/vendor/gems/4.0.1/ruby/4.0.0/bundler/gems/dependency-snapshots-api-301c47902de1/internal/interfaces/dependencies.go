package interfaces

import (
	"context"
)

type DependenciesService interface {
	// CanonicalSnapshotsForRepository returns all of the canonical snapshots for a given repository.
	CanonicalSnapshotsForRepository(ctx context.Context, repositoryID uint64, mode SnapshotQueryMode) ([]*Snapshot, error)
	// HasManifests returns true if we have at least one canonical snapshot for
	// the repository with at least one manifest.
	HasManifests(ctx context.Context, repositoryID uint64) (bool, error)
	// RepositoriesContainingDependency returns a range of repository ids that
	// have a dependency matching the submitted criteria.
	RepositoriesContainingDependency(ctx context.Context, purl, versionRange string, mode SnapshotQueryMode) ([]uint64, error)
}
