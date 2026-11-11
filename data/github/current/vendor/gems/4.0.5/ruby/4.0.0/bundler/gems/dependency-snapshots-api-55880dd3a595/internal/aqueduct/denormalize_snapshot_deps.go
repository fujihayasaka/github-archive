package aqueduct

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/dependency-snapshots-api/internal/snapshots"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

const denormalizeSnapshotDepsMetricPrefix = "aqueduct.handler.denormalize_snapshot_deps."

// HandleDenormalizeSnapshotDependenciesJob denormalizes the canonical dependency
// information for a repository. This is the async counterpart to the synchronous
// denormalization that happens in StoreSnapshot.
func HandleDenormalizeSnapshotDependenciesJob(
	ctx context.Context,
	logger log.Logger,
	statter stats.Client,
	storageAdapter snapshots.StorageAdapter,
	job *jobsproto.DenormalizeSnapshotDependenciesJob,
) error {
	repoID := job.GetRepositoryId()
	logger = logger.WithFields(semconv.RepoID(repoID))

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "HandleDenormalizeSnapshotDependenciesJob", "denormalize",
		kvp.Uint64("repositoryID", repoID),
	)
	defer ender()

	if err := storageAdapter.DenormalizeSnapshotDependencies(ctx, repoID); err != nil {
		statter.Counter(denormalizeSnapshotDepsMetricPrefix+"error", stats.Tags{}, 1)
		logger.WithError(err).Error("denormalization failed")
		return err
	}

	statter.Counter(denormalizeSnapshotDepsMetricPrefix+"success", stats.Tags{}, 1)
	return nil
}
