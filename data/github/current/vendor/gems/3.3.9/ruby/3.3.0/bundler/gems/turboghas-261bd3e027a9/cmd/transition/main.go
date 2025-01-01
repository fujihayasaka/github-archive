// Command transition runs migrations (update the schema) and transitions (upgrade the data) against the TurboGHAS database.
package main

import (
	"context"
	"database/sql"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/cmd/turboghas/configuration"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/migrations"
	"github.com/go-sql-driver/mysql"
	"github.com/golang-migrate/migrate/v4"
	"github.com/pkg/errors"
)

func main() {
	if err := do(context.Background()); err != nil {
		fmt.Printf("level=error message=%q\n", err)
		os.Exit(1)
	}
}

func do(ctx context.Context) error {
	config, err := configuration.LoadConfiguration()
	if err != nil {
		return err
	}

	return config.WithContext(ctx, func(ctx context.Context) (err error) {
		logger := fromctx.Logger.Value(ctx)

		cfg, fn := config.MysqlConfig(func(cfg *mysql.Config) {
			cfg.MultiStatements = true
			cfg.ClientFoundRows = true
		})

		db, err := sql.Open("mysql", cfg.FormatDSN())
		if err != nil {
			return errors.Wrap(err, "failed to create MySQL connection")
		}

		if err := fromctx.Retry(ctx, db.Ping, fromctx.DefaultBackOff()); err != nil {
			return errors.Wrap(err, "failed to ping MySQL")
		}

		fn(db)

		src, err := migrations.Source()
		if err != nil {
			return err
		}

		if !config.Environment.IsEnterprise() {
			var version uint
			var vars string
			var delay time.Duration
			flag.UintVar(&version, "version", 0, "transition version to run")
			flag.StringVar(&vars, "vars", `{}`, "a value you want to make available to the query")
			flag.DurationVar(&delay, "delay", time.Second, "delay between queries")
			flag.Parse()

			if version == 0 {
				logger.Info("please specify a transition version with -version")
				return nil
			}

			up, id, err := src.ReadUp(version)
			if err != nil {
				return err
			}

			logger.Info("running single migration", kvp.Uint("transition.version", version), kvp.String("transition.id", id))

			query, err := io.ReadAll(up)
			if err != nil {
				return err
			}

			for {
				res, err := db.ExecContext(ctx, fmt.Sprintf(`SET @vars = ?; %s`, string(query)), vars)
				if err != nil {
					if mysql_dual.IsTransientError(err) {
						continue
					}
					return err
				}
				rows, err := res.RowsAffected()
				if err != nil {
					return err
				}
				logger.Info("rows updated", kvp.Int64("count", rows))
				if rows == 0 {
					return nil
				}
				select {
				case <-ctx.Done():
					return ctx.Err()
				case <-time.After(delay):
				}
			}
		}

		driver, err := migrations.Driver(db)
		if err != nil {
			return err
		}

		logger.Info("running migrations in enterprise")

		m, err := migrations.New(ctx, driver, src)
		if err != nil {
			return err
		}

		upErr := m.Up()
		if errors.Is(upErr, migrate.ErrNoChange) {
			return nil
		}
		return upErr
	})
}
