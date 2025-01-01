// Package infrastats bundles reporting of procstats and dbstats
package infrastats

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/go-stats"
	dbstats "github.com/github/go-stats/db"
	"github.com/github/go-stats/ps"
)

const interval = 5 * time.Second

type Reporter struct {
	procstats ps.Reporter
	dbstats   *dbstats.Reporter
}

func New(stats stats.Client, db *sql.DB) *Reporter {

	var dbstatter *dbstats.Reporter
	if db != nil {
		dbstatter = &dbstats.Reporter{
			Stats: stats,
			DB:    db,
		}
	}

	return &Reporter{
		procstats: ps.Reporter{Stats: stats},
		dbstats:   dbstatter,
	}
}

func (r *Reporter) Run(ctx context.Context) {

	tick := time.NewTicker(interval)
	defer tick.Stop()

	for {
		select {
		case <-tick.C:
			r.procstats.Report()
			if r.dbstats != nil {
				r.dbstats.Report()
			}
		case <-ctx.Done():
			return
		}
	}
}
