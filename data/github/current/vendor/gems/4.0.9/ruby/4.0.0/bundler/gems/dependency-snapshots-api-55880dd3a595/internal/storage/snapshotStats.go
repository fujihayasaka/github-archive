package storage

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
)

// This file ("snapshotStats") is mostly used for non-user-facing data (chatops)

type countModel struct {
	Count uint64 `db:"count"`
}

func (r *MySQLSnapshotsAdapter) TotalSnapshotCounts(ctx context.Context) (*interfaces.ActivityCounts, error) {
	// Note: this SQL is not running through an optimal index (we don't index based on created_at)
	totalCount := new(countModel)
	ok, err := QueryRow(ctx, r.DB, totalCount, "TotalSnapshots", "SELECT COUNT(*) as count FROM ds_snapshots")
	if !ok || err != nil {
		return nil, err
	}

	lastDayCount := new(countModel)
	ok, err = QueryRow(ctx, r.DB, lastDayCount, "TotalSnapshotsInLastDay", "SELECT COUNT(*) as count FROM ds_snapshots WHERE created_at > ?", time.Now().Add(time.Hour*-24))
	if !ok || err != nil {
		return nil, err
	}

	lastWeekCount := new(countModel)
	ok, err = QueryRow(ctx, r.DB, lastWeekCount, "TotalSnapshotsInLastWeek", "SELECT COUNT(*) as count FROM ds_snapshots WHERE created_at > ?", time.Now().Add(time.Hour*-24*7))
	if !ok || err != nil {
		return nil, err
	}

	return &interfaces.ActivityCounts{Total: totalCount.Count, InLastDay: lastDayCount.Count, InLastWeek: lastWeekCount.Count}, nil
}

func (r *MySQLSnapshotsAdapter) UniqueRepositoryCounts(ctx context.Context) (*interfaces.ActivityCounts, error) {
	// Note: this SQL is not running through an optimal index (we don't index based on repository_id or created_at)
	totalCount := new(countModel)
	ok, err := QueryRow(ctx, r.DB, totalCount, "UniqueRepos", "SELECT DISTINCT COUNT(DISTINCT repository_id) as count FROM ds_snapshots WHERE internal = 0")
	if !ok || err != nil {
		return nil, err
	}

	lastDayCount := new(countModel)
	ok, err = QueryRow(ctx, r.DB, lastDayCount, "UniqueReposInLastDay", "SELECT COUNT(DISTINCT repository_id) as count FROM ds_snapshots WHERE created_at > ? AND internal = 0", time.Now().Add(time.Hour*-24))
	if !ok || err != nil {
		return nil, err
	}

	lastWeekCount := new(countModel)
	ok, err = QueryRow(ctx, r.DB, lastWeekCount, "UniqueReposInLastWeek", "SELECT COUNT(DISTINCT repository_id) as count FROM ds_snapshots WHERE created_at > ? AND internal = 0", time.Now().Add(time.Hour*-24*7))
	if !ok || err != nil {
		return nil, err
	}

	return &interfaces.ActivityCounts{Total: totalCount.Count, InLastDay: lastDayCount.Count, InLastWeek: lastWeekCount.Count}, nil
}
