package aqueduct

import (
	"context"
	"fmt"
	"strconv"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

const (
	excludeCanonicalSnapshotsFeatureFlag  = "dependency_graph_snapshots_exclude_job"
	excludeCanonicalSnapshotsMetricPrefix = "aqueduct.handler.exclude_canonical_snapshots."
)

// HandleExcludeCanonicalSnapshotsJob removes all canonical snapshots for the given repository.
// Processing is gated behind a feature flag and is a no-op when feature flags are unavailable (e.g., GHES).
func HandleExcludeCanonicalSnapshotsJob(
	ctx context.Context,
	_ *config.Config,
	logger log.Logger,
	statter stats.Client,
	snapshotsSvc interfaces.SnapshotsService,
	job *jobsproto.ExcludeCanonicalSnapshotsJob,
) error {
	repoID := uint64(job.GetRepositoryId())
	triggeredBy := job.GetTriggeredBy().String()

	logger = logger.WithFields(
		semconv.RequestID(job.GetRequestId()),
		semconv.MessagingMessageID(job.GetEventId()),
		semconv.RepoID(repoID),
		semconv.JobTriggeredBy(triggeredBy),
	)

	tags := stats.Tags{"triggered_by": triggeredBy}

	if repoID == 0 {
		statter.Counter(excludeCanonicalSnapshotsMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "invalid_repo"}), 1)
		return nil
	}

	if snapshotsSvc == nil {
		return fmt.Errorf("snapshots service is not configured")
	}

	canonicalSnapshots, err := snapshotsSvc.CanonicalSnapshotsForRepository(ctx, repoID, interfaces.DefaultQueryMode)
	if err != nil {
		statter.Counter(excludeCanonicalSnapshotsMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "canonical_snapshot_fetch_failed"}), 1)
		return err
	}

	if len(canonicalSnapshots) == 0 {
		statter.Counter(excludeCanonicalSnapshotsMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "no_canonical_snapshots"}), 1)
		return nil
	}

	snapshotIDs := make([]uint64, 0, len(canonicalSnapshots))
	for _, snap := range canonicalSnapshots {
		snapshotIDs = append(snapshotIDs, snap.ID)
	}

	removedSnapshots, err := snapshotsSvc.ExcludeDependencySnapshots(ctx, repoID, snapshotIDs)
	if err != nil {
		statter.Counter(excludeCanonicalSnapshotsMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "exclude_failed"}), 1)
		return err
	}

	statter.Counter(excludeCanonicalSnapshotsMetricPrefix+"success", tags.Merge(stats.Tags{"removed_count": strconv.Itoa(len(removedSnapshots))}), 1)
	logger.WithFields(
		kvp.Int("gh.dgp.snapshots.removed_count", len(removedSnapshots)),
	).Info("excluded canonical snapshots")

	return nil
}
