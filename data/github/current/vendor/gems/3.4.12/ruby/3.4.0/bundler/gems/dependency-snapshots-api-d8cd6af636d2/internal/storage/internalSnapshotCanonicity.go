// This file is the internal-snapshot counterpart of snapshotCanonicity.go.
package storage

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
)

// To update canonical internal snapshots:
// 1. Query for the current canonical internal snapshot.
// 2. Query for any snapshots that are newer than the current canonical internal snapshot.
// 3. If there are no newer snapshots, return.
// 4. If there is a newer snapshot, update the canonical internal snapshot to the newest snapshot.

// rectifyInternalCanonicalSnapshotOnce is the same as rectifyInternalCanonicalSnapshot, but it does not retry. It returns a boolean flag
// indicating whether the function can be retried. Only errors that originate while updating the canonical row are considered retryable,
// since that is the place where deadlocks/race conditions are most likely.
func (r *MySQLSnapshotsAdapter) rectifyInternalCanonicalSnapshotOnce(ctx context.Context, repositoryID uint64, buildTypeID uint64, tryCount int) (hadCanonicalUpdates bool, retryable bool, err error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySQLSnapshotsAdapterTracer", "rectifyInternalCanonicalSnapshotOnce")
	defer ender()

	// We intentionally retrieve the canonical row without being transactionally bound here.
	currentCanonicalRow, err := selectCanonicalRowIfExists(ctx, r.DB, repositoryID, buildTypeID)
	if err != nil {
		return false, false, errors.Wrapf(err, "selecting canonical snapshot failed")
	}

	// begin transaction to maintain a lock and rollback if necessary
	tx, err := r.DB.BeginTxx(ctx, &sql.TxOptions{
		Isolation: sql.LevelReadCommitted,
	})
	if err != nil {
		return false, false, err
	}
	defer func() {
		txErr := tx.Rollback()
		if txErr != nil {
			retryable = false
			err = errors.Wrapf(err, "rolling back rectifyInternalCanonicalSnapshotOnce failed with error: %s", txErr)
		}
	}()

	newestSnapshot, err := newestInternalSnapshot(ctx, tx, repositoryID, buildTypeID, currentCanonicalRow.ScannedAt)

	if newestSnapshot == nil {
		// This is not necessarily an error. It could just mean that there are no snapshots for the default branch.
		return false, false, nil
	}

	if newestSnapshot.SnapshotID == currentCanonicalRow.SnapshotID {
		// no op, we're already canonical
		return false, false, nil
	}

	beforeUpdateCanonical := time.Now()
	retryable, err = updateCanonicalSnapshot(ctx, tx, repositoryID, buildTypeID, newestSnapshot.SnapshotID, currentCanonicalRow.UpdatedStamp)

	contextlogger.Info(ctx, "Updating internal canonical snapshot",
		kvp.Uint64("snapshotID", newestSnapshot.SnapshotID),
		kvp.Uint64("repositoryID", repositoryID),
		kvp.Uint("timeTakenMs", uint(time.Since(beforeUpdateCanonical).Milliseconds())),
		kvp.Int("tryCount", tryCount),
		kvp.Bool("wasError", err != nil),
	)

	if err != nil {
		return false, retryable, errors.Wrapf(err, "updating internal canonical snapshot failed")
	}

	if !r.ShouldStoreHistoricalSnapshots {
		err = deleteSnapshot(ctx, tx, repositoryID, currentCanonicalRow.SnapshotID, nil)
		if err != nil {
			return false, retryable, errors.Wrapf(err, "error cleaning up old canonical snapshot")
		}
	}

	err = tx.Commit()
	if err != nil {
		return false, true, errors.Wrapf(err, "committing snapshot creation transaction failed")
	}

	return true, false, nil
}

func newestInternalSnapshot(ctx context.Context, queryable Queryable, repositoryID, buildTypeID uint64, previousTime time.Time) (*candidateCanonicalSnapshotRow, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySQLSnapshotsAdapterTracer", "newerInternalSnapshots")
	defer ender()

	getNewestInternalSnapshot := `
		select s.id as snapshot_id, s.sha, s.scanned_at
		from ds_snapshots s
			left join ds_builds b on s.build_id = b.id
				and b.repository_id = s.repository_id
			left join ds_build_types bt on b.build_type_id = bt.id
				and bt.repository_id = s.repository_id
			left join ds_snapshot_blobs sb on s.snapshot_blob_id = sb.id
				and sb.repository_id = s.repository_id
		where s.repository_id = ?
		and bt.id = ?
		and s.created_at > ?
		and s.internal = 1
		order by s.scanned_at desc
		limit 1
	`

	result := candidateCanonicalSnapshotRow{}

	if previousTime.IsZero() {
		// We use NO_ZERO_DATE in our connection settings, which means we can't use a zero time.Time in a query.
		// Instead, we use a time that is guaranteed to be before any snapshot.
		previousTime = previousTime.Add(time.Second)
	}

	ok, err := QueryRow(ctx, queryable, &result, "getNewestInternalSnapshot", getNewestInternalSnapshot, repositoryID, buildTypeID, previousTime)
	if err != nil || !ok {
		return nil, errors.Wrapf(err, "selecting newest internal snapshot failed")
	}

	return &result, nil
}
