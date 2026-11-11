package storage

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/util"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// Expiration:
// This is a process that happens, currently, at the end of snapshot creation.
// The entry point should be called _after_ the new canonical snapshots are determined,
// but before the response is returned to the client.
// In the future we may call this out of band, e.g., via stafftools.

const ExpirationThreshold = 2 * time.Hour

// ExpireSnapshots can be called at any time to expire canonical snapshots belonging to the given repository.
// recentSHAs should be the output of git.GetRecentCommits
// It returns the number of snapshots that were expired.
func (r *MySQLSnapshotsAdapter) ExpireSnapshots(ctx context.Context, repositoryID uint64, recentSHAs []gitaccess.SHA) (int64, error) {
	canonicalRows, err := r.allCanonicalSnapshotRows(ctx, repositoryID)
	if err != nil {
		return 0, errors.Wrapf(err, "error expiring snapshots: could not retrieve prior canonical snapshots for repository")
	}
	if len(canonicalRows) == 0 {
		return 0, errors.Wrapf(err, "expiring canonical snapshots: no prior canonical snapshots found for repository")
	}

	newlyStale := filterNewlyStale(canonicalRows, recentSHAs, ExpirationThreshold)

	staleAsOf := canonicalRows[0].UpdatedStamp
	for _, row := range newlyStale {
		if err := r.markStale(ctx, row, staleAsOf); err != nil {
			return 0, err
		}
	}

	// delete all snapshots that have been stale for at least 2 hours
	return r.deleteStaleCanonicalRows(ctx, repositoryID)
}

func (r *MySQLSnapshotsAdapter) allCanonicalSnapshotRows(ctx context.Context, repositoryID uint64) ([]*canonicalSnapshotRow, error) {
	results := []*canonicalSnapshotRow{}

	rowHandler := func(rows *sqlx.Rows) error {
		var row canonicalSnapshotRow
		if err := rows.StructScan(&row); err != nil {
			return err
		}
		results = append(results, &row)
		return nil
	}

	err := ExecuteQueryAndReadRows(ctx, r.DB, rowHandler, "SelectCanonicalRowsQuery", getCanonicalSnapshotsForRepositorySQLQuery, repositoryID, interfaces.IncludeInternal)
	if err != nil {
		return nil, err
	}

	return results, nil
}

func filterNewlyStale(canonicalRows []*canonicalSnapshotRow, recentSHAs []gitaccess.SHA, threshold time.Duration) []*canonicalSnapshotRow {
	if len(canonicalRows) <= 1 {
		// There's no way we can expire the last snapshot, and nothing we can do with an empty list
		return []*canonicalSnapshotRow{}
	}

	newlyStale := []*canonicalSnapshotRow{}

	// It's important that we find the latest SHA for which we have a snapshot,
	// and unfortunately that may not be the most recent snapshot in the table.
	// Here we iterate through the recent SHAs until we find one that we have a snapshot for.
	var latestSnapshotSHA string
	canonicalSHAs := util.ToSet(util.Map(canonicalRows, func(row *canonicalSnapshotRow) string {
		return row.SHA
	}))
	for _, sha := range recentSHAs {
		shaString := string(sha)
		if canonicalSHAs.Contains(shaString) {
			latestSnapshotSHA = shaString
			break
		}
	}

	// note: it's possible for latestSnasphotSHA to be empty if all of the snapshots we have are extremely old.
	// in that case, the following loop will designate all snapshots as stale that are not stale already.
	for _, row := range canonicalRows {
		alreadyStale := row.StaleSince.Valid
		if !alreadyStale && row.SHA != latestSnapshotSHA {
			newlyStale = append(newlyStale, row)
		}
	}

	return newlyStale
}

func (r *MySQLSnapshotsAdapter) markStale(ctx context.Context, canonicalRow *canonicalSnapshotRow, asOf time.Time) error {
	markStaleQuery := `
		update ds_canonical_snapshots
		set stale_since = ?
		where id = ?
		  and repository_id = ?
	`

	_, err := r.DB.ExecContext(ctx, markStaleQuery, asOf, canonicalRow.ID, canonicalRow.RepositoryID)
	return err
}

func (r *MySQLSnapshotsAdapter) deleteStaleCanonicalRows(ctx context.Context, repositoryID uint64) (int64, error) {
	deleteStaleCanonicalRowsQuery := `
		delete from ds_canonical_snapshots
		where repository_id = ?
			and stale_since < date_sub(now(), interval ? second)
	`

	res, err := r.DB.ExecContext(ctx, deleteStaleCanonicalRowsQuery, repositoryID, ExpirationThreshold.Seconds())
	if err != nil {
		return 0, err
	}

	rowsAffected, err := res.RowsAffected()
	return rowsAffected, err
}
