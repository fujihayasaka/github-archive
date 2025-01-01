package stats

import (
	"context"

	ghstats "github.com/github/go-stats"
	dbstats "github.com/github/go-stats/db"
	"github.com/github/go-stats/ps"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/jmoiron/sqlx"
)

// Run sets up a `gh-stats` client. It also spawns 2 go routines that track
// stats for the DB and for the API process itself. DB client can be nil.
//
// Its return value is a cancellation function that stops the stats client.
func Run(ctx context.Context, db *mysql.DB, statter ghstats.Client) (cancelFunc func()) {
	statter.Run()

	if db != nil {
		runDBReporter(ctx, db.Write, "primary", statter)
		runDBReporter(ctx, db.Read, "replica", statter)
	}

	psReporter := ps.Reporter{Stats: statter}
	go func() { _ = psReporter.Run(ctx) }()

	return statter.Stop
}

func runDBReporter(ctx context.Context, db *sqlx.DB, dbType string, statter ghstats.Client) {
	reporter := dbstats.Reporter{
		Stats: statter,
		DB:    db.DB,
		Tags: ghstats.Tags{
			"database":      "notifyd",
			"database-type": dbType,
		},
	}
	go func() { _ = reporter.Run(ctx) }()
}
