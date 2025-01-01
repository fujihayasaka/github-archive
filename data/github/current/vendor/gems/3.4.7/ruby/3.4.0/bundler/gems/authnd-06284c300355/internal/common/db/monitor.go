package db

import (
	"time"

	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
)

// Monitor emits stats for the provided sql.DB instances. Should be called in a goroutine.
func Monitor(statter stats.Client, dbs map[string]*sqlx.DB) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		for name, db := range dbs {
			dbStatter := statter.WithTags(stats.Tags{"database": name})
			dbstats := db.Stats()
			dbStatter.Gauge("sql.idle", nil, int64(dbstats.Idle))
			dbStatter.Gauge("sql.in_use", nil, int64(dbstats.InUse))
			dbStatter.Gauge("sql.max_idle_closed", nil, dbstats.MaxIdleClosed)
			dbStatter.Gauge("sql.max_idle_time_closed", nil, dbstats.MaxIdleTimeClosed)
			dbStatter.Gauge("sql.max_lifetime_closed", nil, dbstats.MaxLifetimeClosed)
			dbStatter.Gauge("sql.max_open_connections", nil, int64(dbstats.MaxOpenConnections))
			dbStatter.Gauge("sql.open_connections", nil, int64(dbstats.OpenConnections))
			dbStatter.Gauge("sql.wait_count", nil, dbstats.WaitCount)
			dbStatter.Gauge("sql.wait_duration", nil, dbstats.WaitDuration.Nanoseconds())
		}
	}
}
