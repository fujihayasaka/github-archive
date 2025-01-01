package storage

// This file deals with determining which snapshots are *canonical*.
// Bottom line, a snapshot is canonical iff it relates to the default branch and
// is the most recent snapshot for the given repository and build type,
// where "most recent" means:
// - there are no comparable snapshots associated with the same commit with a later timestamp
// - there are no comparable snapshots associated with a newer commit
//
// From a user-centric point of view, canonical snapshots are the ones with the repository's active
// dependencies. The combined dependencies from all canonical snapshots for a repository
// are returned from the GetDependenciesForRepository endpoint.

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/util"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// rectifyCanonicalSnapshot _idempotently_ updates the canonical snapshot for the given repository and build type.
// It finds the most recent snapshot (by scanned time) for the most recent commit (in topological order) associated
// with the given repository and build type, and ensures that that snapshot is stored in the `ds_canonical_snapshots`
// table. It will retry twice before returning an error.
func (r *MySQLSnapshotsAdapter) rectifyCanonicalSnapshot(ctx context.Context, git gitaccess.Client, repositoryID uint64, buildTypeID uint64, mode interfaces.CanonicalUpdateMode) (hadCanonicalUpdates bool, err error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySQLSnapshotsAdapterTracer", "rectifyCanonicalSnapshot")
	defer ender()

	maxTries := 3
	baseDelay := time.Millisecond * 5
	if mode == interfaces.DefaultUpdateMode {
		hadCanonicalUpdates, err = util.Retry(maxTries, baseDelay, func() (bool, bool, error) {
			return r.rectifyCanonicalSnapshotOnce(ctx, git, repositoryID, buildTypeID, 0)
		})
	} else if mode == interfaces.InternalUpdateMode {
		hadCanonicalUpdates, err = util.Retry(maxTries, baseDelay, func() (bool, bool, error) {
			return r.rectifyInternalCanonicalSnapshotOnce(ctx, repositoryID, buildTypeID, 0)
		})
	} else {
		return false, errors.Errorf("unknown canonical update mode: %v", mode)
	}
	if err != nil {
		return false, errors.Wrapf(err, "rectifying canonical snapshot failed after %d tries", maxTries)
	}
	return hadCanonicalUpdates, nil
}

type candidateCanonicalSnapshotRow struct {
	SnapshotID uint64    `db:"snapshot_id"`
	SHA        string    `db:"sha"`
	ScannedAt  time.Time `db:"scanned_at"`
}

// rectifyCanonicalSnapshotOnce is the same as rectifyCanonicalSnapshot, but it does not retry. It returns a boolean flag indicating whether the
// function can be retried. Only errors that originate while updating the canonical row are considered retryable, since that is the place where
// deadlocks/race conditions are most likely.
func (r *MySQLSnapshotsAdapter) rectifyCanonicalSnapshotOnce(ctx context.Context, git gitaccess.Client, repositoryID uint64, buildTypeID uint64, tryCount int) (hadCanonicalUpdates bool, retryable bool, err error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySQLSnapshotsAdapterTracer", "rectifyCanonicalSnapshotOnce")
	defer ender()

	// Do a quick cleanup to make sure we don't have any dangling canonical rows
	err = cleanUpOldCanonicalSnapshots(ctx, r.DB, repositoryID)
	if err != nil {
		return false, true, errors.Wrapf(err, "cleaning up old canonical snapshots failed")
	}

	// We intentionally retrieve the canonical row without being transactionally bound here.
	currentCanonicalRow, err := selectCanonicalRowIfExists(ctx, r.DB, repositoryID, buildTypeID)
	if err != nil {
		return false, false, errors.Wrapf(err, "selecting canonical snapshot failed")
	}

	recentSHAs, err := git.GetRecentCommits(ctx, repositoryID, 1000)
	if err != nil {
		return false, false, errors.Wrapf(err, "getting recent commits failed")
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
			err = errors.Wrapf(err, "rolling back rectifyCanonicalSnapshotOnce failed with error: %s", txErr)
		}
	}()

	// Note that canonicalRow may be empty, and that's ok.
	// We'll just end up creating a new canonical snapshot row.
	newerSHAs := convertAndTruncateAfter(recentSHAs, currentCanonicalRow.SHA)
	snapshotsForNewerSHAs, err := candidateCanonicalSnapshots(ctx, tx, repositoryID, buildTypeID, newerSHAs)
	if err != nil {
		return false, false, errors.Wrapf(err, "getting possibly more canonical snapshots failed")
	}

	candidatesBySHA := groupLatestBySHA(snapshotsForNewerSHAs)
	newCanonicalRow := firstValueFromKeys(candidatesBySHA, newerSHAs)

	if newCanonicalRow == nil {
		// This is not necessarily an error. It could just mean that there are no snapshots for the default branch.
		return false, false, nil
	}

	if newCanonicalRow.SnapshotID == currentCanonicalRow.SnapshotID {
		// no op, we're already canonical
		return false, false, nil
	}

	beforeUpdateCanonical := time.Now()
	retryable, err = updateCanonicalSnapshot(ctx, tx, repositoryID, buildTypeID, newCanonicalRow.SnapshotID, currentCanonicalRow.UpdatedStamp)

	contextlogger.Info(ctx, "Updated canonical snapshot",
		kvp.Uint64("snapshotID", newCanonicalRow.SnapshotID),
		kvp.Uint64("repositoryID", repositoryID),
		kvp.Uint("timeTakenMs", uint(time.Since(beforeUpdateCanonical).Milliseconds())),
		kvp.Int("tryCount", tryCount),
		kvp.Bool("wasError", err != nil),
	)

	if err != nil {
		return false, retryable, errors.Wrapf(err, "updating canonical snapshot failed")
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

	_, err = r.ExpireSnapshots(ctx, repositoryID, recentSHAs)
	if err != nil {
		return true, false, errors.Wrapf(err, "expiring snapshots failed")
	}

	return true, false, nil
}

func updateCanonicalSnapshot(ctx context.Context, queryable Queryable, repositoryID, buildTypeID, snapshotID uint64, updatedStamp time.Time) (retryable bool, err error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySQLSnapshotsAdapterTracer", "updateCanonicalSnapshot")
	defer ender()

	var res sql.Result
	if updatedStamp.IsZero() {
		// Precondition: Earlier, outside of a transaction, no row was detected.
		// We attempt an insert -- If the insert fails due to duplicate key, we consider this retryable, and let the flow happen again (should be update).
		_, err = ExecuteQuery(ctx, queryable, "InsertCanonicalSnapshot", insertCanonicalSnapshotSQLQuery,
			repositoryID, buildTypeID, snapshotID)
		if db.IsMysqlRecordNotUnique(err) {
			return true, err
		}

		if db.IsMysqlDeadlockError(err) || db.IsMysqlQueryInterrupted(err) {
			return true, err
		}
	} else {
		// Precondition: Earlier, outside of a transaction, we saw a canonical snapshot row we need to update with a new snapshot ID.
		// We try updating it, but there's a chance no rows will be updated if the updatedStamp has gotten out of date.
		res, err = ExecuteQuery(ctx, queryable, "UpdateCanonicalSnapshot", updateCanonicalSnapshotSQLQuery,
			snapshotID, repositoryID, buildTypeID, updatedStamp)

		if db.IsMysqlDeadlockError(err) || db.IsMysqlQueryInterrupted(err) {
			return true, err
		}

		rows, err := res.RowsAffected()
		if err != nil {
			return false, err
		}

		// If the update changes no rows, we know that the optimistic concurrency model has protected an out of date update, and we should retry.
		if rows == 0 {
			return true, errors.New("no canonical snaphot was updated")
		}
	}

	return false, err
}

// candidateCanonicalSnapshots returns a list of snapshots related to the commits in `shas`. It is used to find snapshots
// that _could_ replace the current canonical snapshot.
func candidateCanonicalSnapshots(ctx context.Context, queryable Queryable, repositoryID, buildTypeID uint64, shas []string) ([]*candidateCanonicalSnapshotRow, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySQLSnapshotsAdapterTracer", "candidateCanonicalSnapshots")
	defer ender()

	getCandidateCanonicalSnapshots := `
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
		and sha in (?)
		order by s.created_at desc
	`

	results := make([]*candidateCanonicalSnapshotRow, 0)

	rowHandler := func(rows *sqlx.Rows) error {
		row := candidateCanonicalSnapshotRow{}
		err := rows.StructScan(&row)
		if err != nil {
			return err
		}
		results = append(results, &row)
		return nil
	}

	adjustedQuery, argList, err := sqlx.In(getCandidateCanonicalSnapshots, repositoryID, buildTypeID, shas)
	if err != nil {
		return nil, errors.Wrapf(err, "building query failed")
	}

	adjustedQuery = queryable.Rebind(adjustedQuery)

	err = ExecuteQueryAndReadRows(ctx, queryable, rowHandler, "getPossiblyMoreCanonicalSnapshots", adjustedQuery, argList...)
	if err != nil {
		return nil, errors.Wrapf(err, "executing query failed")
	}

	return results, nil
}

// selectCanonicalRowIfExists returns the canonical snapshot for the given repository and build type, _if there is one_.
// It is not considered an error if there is no canonical snapshot. In that case, this returns the empty canonicalSnapshotRow.
func selectCanonicalRowIfExists(ctx context.Context, queryable Queryable, repositoryID, buildTypeID uint64) (canonicalSnapshotRow, error) {
	row := canonicalSnapshotRow{}
	_, err := QueryRow(ctx, queryable, &row, "SelectCanonicalRow", selectCanonicalRowSQLQuery, repositoryID, buildTypeID)
	// not checking the `ok` return value here because we're not doing anything different if it's false
	if err != nil {
		return row, errors.Wrapf(err, "selecting canonical row failed")
	}
	return row, nil
}

// There are times when a row in ds_canonical_snapshots points to a snapshot_id that no longer exists,
// possibly due to an error during snapshot creation. This query deletes any such rows.
// Parameters: (repository_id)
const cleanUpOldCanonicalSnapshotsSQLQuery = `
  delete cs
	from ds_canonical_snapshots cs
		left join ds_snapshots s on cs.snapshot_id = s.id
			and cs.repository_id = s.repository_id
	where cs.repository_id = ?
		and s.id is null
`

func cleanUpOldCanonicalSnapshots(ctx context.Context, queryable Queryable, repositoryID uint64) error {
	_, err := ExecuteQuery(ctx, queryable, "CleanUpOldCanonicalSnapshots", cleanUpOldCanonicalSnapshotsSQLQuery, repositoryID)
	if err != nil {
		return errors.Wrapf(err, "cleaning up old canonical snapshots failed")
	}

	return nil
}

// Parameters: (repository_id, buildTypeID)
// Guaranteed to return no more than one row by table constraints.
const selectCanonicalRowSQLQuery = `
    select cs.id,
		   s.id as snapshot_id,
		   cs.repository_id,
	       s.sha,
		   s.scanned_at,
		   cs.updated_stamp
	from ds_canonical_snapshots cs
		left join ds_snapshots s on cs.snapshot_id = s.id
			and cs.repository_id = s.repository_id
	where cs.repository_id = ? and cs.build_type_id = ?
	for update
`

// Parameters: (repository_id int, build_type_id int, snapshot_id int)
const insertCanonicalSnapshotSQLQuery = `
  insert into ds_canonical_snapshots (repository_id, build_type_id, snapshot_id, created_at, updated_at)
	values (?, ?, ?, now(), now())
`

// Parameters: (snapshot_id int, repository_id int, build_type_id int, updated_stamp time.Time)
const updateCanonicalSnapshotSQLQuery = `
  update ds_canonical_snapshots
		set snapshot_id = ?, created_at = now(), updated_at = now(), stale_since = null
	where repository_id = ? AND build_type_id = ? AND updated_stamp = ?
`

// Parameters: (repository_id int)
const getCanonicalBlobIDsSQLQuery = `
	select snapshot_blob_id
	from ds_canonical_snapshots cs
		join ds_snapshots s on cs.snapshot_id = s.id
			and cs.repository_id = s.repository_id
	where cs.repository_id = ?
`

func (r *MySQLSnapshotsAdapter) ExcludeDependencySnapshots(ctx context.Context, repositoryID uint64, snapshotIDs []uint64) ([]uint64, error) {
	// Parameters: (repository_id int, snapshotIDs []int)
	const getCanonicalSnapshotIDsByParameters = `
	select ds.id, ds.snapshot_id
	from ds_canonical_snapshots ds
	where ds.repository_id = ?
		and ds.snapshot_id in (?)`

	type canonicalIDResponse struct {
		ID         uint64 `db:"id"`
		SnapshotID uint64 `db:"snapshot_id"`
	}

	adjustedQuery, argList, err := sqlx.In(getCanonicalSnapshotIDsByParameters, repositoryID, snapshotIDs)
	if err != nil {
		return nil, errors.Wrapf(err, "building query failed")
	}

	adjustedQuery = r.DB.Rebind(adjustedQuery)

	ids := make([]uint64, 0)
	deletedSnapshotIDs := make([]uint64, 0)
	rowHandler := func(rows *sqlx.Rows) error {
		row := canonicalIDResponse{}
		err := rows.StructScan(&row)
		if err != nil {
			return err
		}
		ids = append(ids, row.ID)
		deletedSnapshotIDs = append(deletedSnapshotIDs, row.SnapshotID)
		return nil
	}

	err = ExecuteQueryAndReadRows(ctx, r.DB, rowHandler, "getCanonicalSnapshotIDsByParameters", adjustedQuery, argList...)
	if err != nil {
		return nil, errors.Wrapf(err, "getting canonical snapshot IDs by parameters failed")
	}

	if len(ids) < 1 {
		return nil, errors.New("no matching included snapshots could be found for the input snapshots ids")
	}

	// Parameters: (repository_id int, snapshotIDs []int)
	const deleteCanonicalSnapshotsByID = `
	delete from ds_canonical_snapshots
	where repository_id = ? AND id in (?)`

	adjustedQuery, argList, err = sqlx.In(deleteCanonicalSnapshotsByID, repositoryID, ids)
	if err != nil {
		return nil, errors.Wrapf(err, "building query failed")
	}

	adjustedQuery = r.DB.Rebind(adjustedQuery)

	_, err = ExecuteQuery(ctx, r.DB, "deleteCanonicalSnapshotsById", adjustedQuery, argList...)
	if err != nil {
		return nil, errors.Wrapf(err, "executing query failed")
	}

	return deletedSnapshotIDs, nil
}

// getCanonicalBlobIDs returns the snapshot blob IDs for the canonical snapshots of the given repository.
// It can be used to determine whether a "new" blob ID is already present in the canonical snapshots.
func getCanonicalBlobIDs(ctx context.Context, queryable Queryable, repositoryID uint64) ([]uint64, error) {
	type blobIDResponse struct {
		SnapshotBlobID uint64 `db:"snapshot_blob_id"`
	}
	blobIDRowss := make([]blobIDResponse, 0)

	err := QueryRows(ctx, queryable, &blobIDRowss, "GetCanonicalBlobIDs", getCanonicalBlobIDsSQLQuery, repositoryID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to query canonical blob IDs")
	}

	blobIDs := make([]uint64, 0, len(blobIDRowss))
	for _, row := range blobIDRowss {
		blobIDs = append(blobIDs, row.SnapshotBlobID)
	}
	return blobIDs, nil
}

// convertAndTruncateAfter returns the given sequence of SHAs up to _and including_ `endpoint`, as strings.
func convertAndTruncateAfter(xs []gitaccess.SHA, endpoint string) []string {
	res := []string{}

	for i := 0; i < len(xs); i++ {
		x := xs[i]
		sha := string(x)
		res = append(res, sha)
		if sha == endpoint {
			break
		}
	}
	return res
}

// groupLatestBySHA returns a map from SHA to the most recent snapshot (by `ScannedAt`) for that SHA.
func groupLatestBySHA(rows []*candidateCanonicalSnapshotRow) map[string]*candidateCanonicalSnapshotRow {
	bySHA := map[string]*candidateCanonicalSnapshotRow{}
	for _, row := range rows {
		if prev, ok := bySHA[row.SHA]; ok {
			if row.ScannedAt.After(prev.ScannedAt) {
				bySHA[row.SHA] = row
			} else if row.ScannedAt.Equal(prev.ScannedAt) && row.SnapshotID > prev.SnapshotID {
				// This else if case is a little weird: if someone submits two snapshots with the same SHA and ScannedAt, we want to take the latest.
				bySHA[row.SHA] = row
			}
		} else {
			bySHA[row.SHA] = row
		}
	}
	return bySHA
}

// firstValueFromKeys checks each of the given keys against the map and returns
// the first value found, or nil if none is found.
func firstValueFromKeys(m map[string]*candidateCanonicalSnapshotRow, keys []string) *candidateCanonicalSnapshotRow {
	for i := 0; i < len(keys); i++ {
		key := keys[i]
		if row, ok := m[key]; ok {
			return row
		}
	}
	return nil
}
