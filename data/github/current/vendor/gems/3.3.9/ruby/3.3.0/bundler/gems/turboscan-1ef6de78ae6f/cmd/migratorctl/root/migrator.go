// Package root contains the main logic for the migratorctl command. The migratorctl
// command runs migrations and transitions against the Turboscan database.
package root

// Command migratorctl runs migrations (update the schema) and transitions (upgrade the data) against the Turboscan database.

import (
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/mysql/upgrades"
	"github.com/spf13/cobra"

	"github.com/pkg/errors"

	"github.com/github/turboscan/migrations"

	"github.com/github/turboscan/ts/config"
	_ "github.com/go-sql-driver/mysql"
	"golang.org/x/net/context"
)

func init() {
	MigratorCTLCmd.Flags().String("transition", "", "a specific transition to run e.g. '20220829050713_populate_new_column.go'")
	MigratorCTLCmd.Flags().Uint64("minid", 0, "the minimum 'id' to consider when running the transition")
	MigratorCTLCmd.Flags().Uint64("maxid", 0, "the maximum 'id' to consider when running the transition")
	MigratorCTLCmd.Flags().Duration("delay", 1, "wait this long before running each step of the transition. Valid time units are \"ns\", \"us\" (or \"µs\"), \"ms\", \"s\", \"m\", \"h\".")
	MigratorCTLCmd.Flags().Uint64("step", 0, "override the default step for the transition")
	MigratorCTLCmd.Flags().Bool("status", false, "emit the status of each migrations for GHES")
	// use this if you need to run a performance sensitive transition and Vitess does not support some part of the query
	// e.g: a LATERAL JOIN or grouped subqueries
	MigratorCTLCmd.Flags().Int("shard", -1, "run the transition directly against a Vitess shard and avoid the Vitess query parser")
}

var MigratorCTLCmd = &cobra.Command{
	Use:   "migratorctl",
	Short: "Command migratorctl runs migrations (update the schema) and transitions (upgrade the data) against the Turboscan database.",
	Long:  "Command migratorctl runs migrations (update the schema) and transitions (upgrade the data) against the Turboscan database.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return realMain(cmd)
	},
}

const MigrationsTable = "ts_migrations"

func realMain(cmd *cobra.Command) error {
	transitionFlag, err := cmd.Flags().GetString("transition")
	if err != nil {
		return err
	}
	minIDFlag, err := cmd.Flags().GetUint64("minid")
	if err != nil {
		return err
	}
	maxIDFlag, err := cmd.Flags().GetUint64("maxid")
	if err != nil {
		return err
	}
	delayFlag, err := cmd.Flags().GetDuration("delay")
	if err != nil {
		return err
	}
	stepFlag, err := cmd.Flags().GetUint64("step")
	if err != nil {
		return err
	}
	shardFlag, err := cmd.Flags().GetInt("shard")
	if err != nil {
		return err
	}

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	return appctx.WithContext(cfg, "migrator", func(ctx context.Context) error {
		logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

		opts := &config.DBOptions{
			Config:          cfg,
			MultiStatements: true,
			// increase the group_concat_max_len (GHES only) to make it less likely that unattended transitions
			// that use group_concat will fail
			Params: map[string]string{
				"group_concat_max_len": "8192",
			},
		}

		var dbopts []config.DBOption
		if shardFlag >= 0 {
			dbopts = append(dbopts, config.VitessShard(shardFlag))
		}

		db, err := config.OpenDB(opts, logger, statter, dbopts...)
		if err != nil {
			return err
		}
		defer func() {
			if closeErr := db.Close(); closeErr != nil {
				appctx.Logger(ctx).WithError(closeErr).Error("could not close db connection")
			}
		}()

		upgradeEnv := upgrades.NewEnv("./migrations", gormext.GetDB(db), MigrationsTable)

		logger.Info("building transitions")

		tr, err := migrations.Transitions.Build(upgradeEnv, &upgrades.Opts{
			MinID: minIDFlag,
			MaxID: maxIDFlag,
			Delay: delayFlag,
			Step:  stepFlag,
		})
		if err != nil {
			return err
		}

		if transitionFlag != "" {
			logger.Info("running transition", kvp.String("file", transitionFlag))

			version, ok := upgrades.VersionFromFile(transitionFlag)
			if !ok {
				return errors.Errorf("invalid transition name %q", transitionFlag)
			}
			transition, ok := tr[version]
			if !ok {
				return errors.Errorf("unknown transition %q", transitionFlag)
			}
			return transition(ctx)
		}

		if !cfg.IsEnterpriseEnv() {
			if err := upgradeEnv.Verify(ctx); err != nil {
				return err
			}
			logger.Info("please specify a transition to run with --transition")
			return nil
		}

		logger.Info("running GHES migrations...")

		// For GHES, run both migrations and transitions
		return upgradeEnv.RunMigrations(ctx, tr)
	})
}
