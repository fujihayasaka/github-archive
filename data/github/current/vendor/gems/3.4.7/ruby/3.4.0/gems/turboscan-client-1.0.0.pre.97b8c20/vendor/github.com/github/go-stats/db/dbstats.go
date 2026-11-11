// Package db provides an API to report the DB statistics to a statsd endpoint
package db

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/go-stats"
)

const defaultInterval = 5 * time.Second

// StatsEnabledDB exposes an interface for DB statistics. The golang sql.DB type fullfills this interface.
type StatsEnabledDB interface {
	Stats() sql.DBStats
}

// Reporter is a helper struct to periodically report the DB statistics metrics
// to the given stats client.
type Reporter struct {
	Stats stats.Client

	// DB is the database handle used for reporting the statistics
	DB StatsEnabledDB

	// Interval defines the period to publish reports
	Interval time.Duration

	// Tags represents the tags to be included with each report. This is
	// optional and can be used to add additional information.
	Tags stats.Tags

	prevMaxIdleClosed     int64
	prevMaxIdleTimeClosed int64
	prevMaxLifetimeClosed int64
	prevWaitCount         int64
	prevWaitDuration      int64
}

// Run runs the reporting loop and blocks until the given context is cancelled.
func (r *Reporter) Run(ctx context.Context) error {
	if r.Interval == 0 {
		r.Interval = defaultInterval
	}

	tick := time.NewTicker(r.Interval)
	defer tick.Stop()

	for {
		select {
		case <-tick.C:
			r.Report()
		case <-ctx.Done():
			return nil
		}
	}
}

// Report reports all current DB statistics to the stats client.  This method
// is periodically called by (*Reporter).Run, but it may be called manually if
// you don't want a full reporting loop running.
func (r *Reporter) Report() {
	dbstats := r.DB.Stats()
	maxIdleClosed := dbstats.MaxIdleClosed
	maxIdleTimeClosed := dbstats.MaxIdleTimeClosed
	maxLifetimeClosed := dbstats.MaxLifetimeClosed
	waitCount := dbstats.WaitCount
	waitDuration := dbstats.WaitDuration.Nanoseconds()

	r.Stats.Gauge("db.sql.max_open_connections", r.Tags, int64(dbstats.MaxOpenConnections))
	r.Stats.Gauge("db.sql.open_connections", r.Tags, int64(dbstats.OpenConnections))
	r.Stats.Gauge("db.sql.idle", r.Tags, int64(dbstats.Idle))
	r.Stats.Gauge("db.sql.in_use", r.Tags, int64(dbstats.InUse))

	// The following metrics are a cumulative total, so we need to calculate the delta to send to DataDog.

	r.Stats.Counter("db.sql.max_idle_closed", r.Tags, maxIdleClosed-r.prevMaxIdleClosed)
	r.Stats.Counter("db.sql.max_idle_time_closed", r.Tags, maxIdleTimeClosed-r.prevMaxIdleTimeClosed)
	r.Stats.Counter("db.sql.max_lifetime_closed", r.Tags, maxLifetimeClosed-r.prevMaxLifetimeClosed)
	r.Stats.Counter("db.sql.wait_count", r.Tags, waitCount-r.prevWaitCount)
	r.Stats.Counter("db.sql.wait_duration", r.Tags, waitDuration-r.prevWaitDuration)

	r.prevMaxIdleClosed = maxIdleClosed
	r.prevMaxIdleTimeClosed = maxIdleTimeClosed
	r.prevMaxLifetimeClosed = maxLifetimeClosed
	r.prevWaitCount = waitCount
	r.prevWaitDuration = waitDuration
}
