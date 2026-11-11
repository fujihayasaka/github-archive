package mysql

import (
	"context"
	"fmt"
	"strings"
	"time"

	freno "github.com/github/go-freno-client"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/db"
)

func NewMaintenance(db db.RetryableDB, analyticsDB db.RetryableDB, throttler freno.Throttler) *Maint {
	return &Maint{
		db:          db,
		analyticsDB: analyticsDB,
		throttler:   throttler,
	}
}

type Maint struct {
	db          db.RetryableDB
	analyticsDB db.RetryableDB
	throttler   freno.Throttler
}

// Report publishes stats about the database.
func (m *Maint) Report(ctx context.Context) {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "maint.report.duration", time.Since(start))
	}()

	logging.Info(ctx, "Beginning database report")

	m.countDeletedRepositories(ctx)

	count := func(table string) {
		start := time.Now()
		var count int64
		err := m.analyticsDB.GetContext(ctx, &count, fmt.Sprintf("SELECT count(*) FROM %s", table))
		if err != nil {
			logging.Error(
				ctx,
				fmt.Sprintf("counting %s failed", table),
				kvp.Duration("duration_ms", time.Since(start)),
				kvp.Any("duration", time.Since(start)),
				kvp.Err(err),
			)
			return
		}

		// NOTE: Maintain legacy stat for repositories table to preserve historical metrics
		if table == "blackbird_repositories" {
			statting.Gauge(ctx, "maint.report.repositories.count", count)
		} else {
			statting.Gauge(ctx, fmt.Sprintf("maint.report.%s", strings.TrimPrefix(table, "blackbird_")), count)
		}

		logging.Info(
			ctx,
			fmt.Sprintf("counted number of rows in %s", table),
			kvp.Int64("num_rows", count),
			kvp.Duration("duration_ms", time.Since(start)),
			kvp.Any("duration", time.Since(start)),
		)
	}

	count("blackbird_repositories")

	logging.Info(ctx, "database report complete", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)))
}

func (m *Maint) countDeletedRepositories(ctx context.Context) {
	start := time.Now()
	var count int64
	err := m.analyticsDB.GetContext(ctx, &count, "SELECT count(*) FROM blackbird_repositories WHERE deleted_at IS NOT NULL")
	if err != nil {
		logging.Error(
			ctx,
			"counting deleted repositories failed",
			kvp.Any("duration", time.Since(start)),
			kvp.Duration("duration_ms", time.Since(start)),
			kvp.Err(err),
		)
		return
	}

	statting.Gauge(ctx, "maint.report.deleted_repositories.count", count)
	logging.Info(
		ctx,
		"counted deleted repositories",
		kvp.Int64("num_repos", count),
		kvp.Any("duration", time.Since(start)),
		kvp.Duration("duration_ms", time.Since(start)),
	)
}

func (m *Maint) GC(ctx context.Context) error {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "maint.gc.duration", time.Since(start))
	}()

	logging.Info(ctx, "Beginning database GC")

	if err := m.gcRepositories(ctx); err != nil {
		return err
	}

	logging.Info(ctx, "Database GC complete", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)))
	statting.Gauge(ctx, "maint.gc.last_success", time.Now().Unix())
	return nil
}

// gcRepositories removes rows from the blackbird_repositories table when they
// are marked as deleted long enough in the past and are no longer associated
// with a tree entry.
func (m *Maint) gcRepositories(ctx context.Context) error {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "maint.gc.repositories.duration", time.Since(start))
	}()

	logging.Info(ctx, "Beginning repository GC")

	q := `
SELECT id FROM blackbird_repositories
WHERE deleted_at < (UTC_TIMESTAMP() - INTERVAL 7 DAY)
LIMIT 1000
`

	var repoIDs []int
	err := m.db.SelectContext(ctx, &repoIDs, q)
	if err != nil {
		return errors.Wrap(err, "could not select deleted repositories to GC")
	}

	if len(repoIDs) == 0 {
		logging.Info(ctx, "Finished repository GC, no repositories to GC", kvp.Any("duration", time.Since(start)), kvp.Duration("duration_ms", time.Since(start)))
		return nil
	}

	if err := m.waitOnThrottler(ctx); err != nil {
		logging.Error(ctx, "repository GC canceled due to throttling", kvp.Err(err))
		return err
	}

	q, args, err := sqlx.In("DELETE FROM blackbird_repositories WHERE id IN (?)", repoIDs)
	if err != nil {
		return errors.Wrap(err, "could not generate delete statement")
	}

	result, err := m.db.ExecContext(ctx, q, args...)
	if err != nil {
		return errors.Wrap(err, "could not delete batch of repositories by ID")
	}

	deleted, err := result.RowsAffected()
	if err != nil {
		return errors.Wrap(err, "error deleting repositories")
	}

	logging.Info(
		ctx,
		"Finished repository GC",
		kvp.Int64("rows_deleted", deleted),
		kvp.Any("duration", time.Since(start)),
		kvp.Duration("duration_ms", time.Since(start)),
	)
	statting.Counter(ctx, "maint.gc.rows_deleted", deleted)

	return nil
}

// waitOnThrottler waits for up to a timeout for the throttler to tell us it's
// OK to write to the database. If we don't get a response before the timeout,
// it returns an error.
func (m *Maint) waitOnThrottler(ctx context.Context) error {
	const timeout = 1 * time.Minute
	return db.WaitOnThrottler(ctx, m.throttler, timeout)
}
