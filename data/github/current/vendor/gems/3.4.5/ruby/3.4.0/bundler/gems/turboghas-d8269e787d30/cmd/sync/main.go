// Command sync updates cache entries for any data that has not been seen in a week.
package main

import (
	"context"
	"database/sql"
	stderrors "errors"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-stats"
	"github.com/github/turboghas/cmd/turboghas/configuration"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/internal/resync"
	"github.com/pkg/errors"
)

func Scan[V any](ctx context.Context, db mysql_dual.QueryDB, stmt string, args ...any) (v V, err error) {
	err = fromctx.Retry(ctx, func() error {
		err := db.QueryRowContext(ctx, stmt, args...).Scan(&v)
		if errors.Is(err, sql.ErrNoRows) {
			return backoff.Permanent(err)
		}
		return err
	}, backoff.NewExponentialBackOff())
	return
}

func do(ctx context.Context, skipDelete bool, workers int) error {
	config, err := configuration.LoadConfiguration()
	if err != nil {
		return err
	}

	return config.WithContext(ctx, func(ctx context.Context) (err error) {
		statter := fromctx.Statter.Value(ctx)

		defer func() {
			if err != nil {
				statter.Counter("sync.failed", stats.Tags{}, 1)
			}
		}()

		db, err := mysql_dual.NewConnection(config.MySQLConfigs())
		if err != nil {
			return errors.Wrap(err, "failed to create MySQL connection")
		}
		defer func() {
			err = stderrors.Join(err, db.Close())
		}()

		started := time.Now()
		defer func() {
			statter.Timing("sync", stats.Tags{}, time.Since(started))
		}()

		githubSigner, err := config.GitHubClient(ctx)
		if err != nil {
			return errors.Wrap(err, "could not create github client")
		}

		ghghAPI := config.NewTurboghasAPIClient(githubSigner)

		syncer := resync.New(data.New(db), ghghAPI)

		if !skipDelete {
			if err := deleteStaleData(ctx, db); err != nil {
				return err
			}
		}

		return syncDataWithMonolith(ctx, db, syncer, workers)
	})
}

func main() {
	var skipDelete bool
	var workers int
	flag.BoolVar(&skipDelete, "keep", false, "do not delete stale data")
	flag.IntVar(&workers, "workers", 10, "number of workers to use to fetch internal twirp data")
	flag.Parse()

	if err := do(context.Background(), skipDelete, workers); err != nil {
		fmt.Printf("level=error message=%q\n", err)
		os.Exit(1)
	}
}
