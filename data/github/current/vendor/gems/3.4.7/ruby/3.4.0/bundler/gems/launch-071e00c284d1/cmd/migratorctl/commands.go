package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strconv"

	"github.com/github/launch/observability/statter"

	"github.com/pkg/errors"
	"github.com/spf13/cobra"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/pkg/dbmigrator"
	"github.com/github/launch/pkg/dbmigrator/mysql"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/dsn"
)

func getRootCommand(ctx context.Context) *cobra.Command {
	rootCmd := &cobra.Command{
		Use:   "migratorctl",
		Short: "Lightweight tool for running database migrations for each Actions App dependency",
	}

	rootCmd.AddCommand(getMigrateCommand(ctx))
	rootCmd.AddCommand(getSetupCommand(ctx))
	rootCmd.AddCommand(getTransitionCommand(ctx))
	rootCmd.AddCommand(getForceCommand(ctx))
	rootCmd.AddCommand(getTruncateCommand(ctx))

	return rootCmd
}

func getMigrateCommand(ctx context.Context) *cobra.Command {
	migrateCmd := &cobra.Command{
		Use:   "migrate",
		Short: "Use for migrating the databases of every `launch` database",
	}

	migrateCmd.AddCommand(getMigrateDeployerCommand(ctx))
	migrateCmd.AddCommand(getMigratePayloadsCommand(ctx))

	return migrateCmd
}

func getForceCommand(ctx context.Context) *cobra.Command {
	forceCmd := &cobra.Command{
		Use:   "force",
		Short: "Use for forcing the database versions for specific databases",
	}

	forceCmd.AddCommand(getForceDeployerCommand(ctx))
	forceCmd.AddCommand(getForcePayloadsCommand(ctx))

	return forceCmd
}

// nolint: unparam
func getForceDeployerCommand(_ context.Context) *cobra.Command {
	var sourceDirectory string
	var databaseURL string

	forceDeployerCommand := &cobra.Command{
		Use:   "deployer",
		Short: "Forces a specific migration version for the deployer database",
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) < 1 {
				return errors.New("missing version argument")
			}

			db, err := getDB(databaseURL)
			if err != nil {
				return errors.Wrap(err, "error connecting to deployer db")
			}

			m, err := newMigrator(db, sourceDirectory, "actions_deployer_schema_migrations")
			if err != nil {
				return errors.Wrap(err, "error creating mysql migrator")
			}
			defer m.Close()

			versionStr := args[0]
			version, err := strconv.Atoi(versionStr)
			if err != nil {
				return errors.Wrap(err, "error parsing version")
			}

			return m.Force(version)
		},
	}

	forceDeployerCommand.Flags().StringVarP(&sourceDirectory, "source", "s", "migrations/deployer", "Source directory for migrations")

	forceDeployerCommand.Flags().StringVarP(&databaseURL, "database", "d", "", "Full database URL for running migrations")
	forceDeployerCommand.MarkFlagRequired("database") // nolint: errcheck

	return forceDeployerCommand
}

// nolint: unparam
func getForcePayloadsCommand(_ context.Context) *cobra.Command {
	var sourceDirectory string
	var databaseURL string

	forcePayloadsCommand := &cobra.Command{
		Use:   "payloads",
		Short: "Forces a specific migration version for the payloads database",
		RunE: func(cmd *cobra.Command, args []string) error {
			if len(args) < 1 {
				return errors.New("missing version argument")
			}

			db, err := getDB(databaseURL)
			if err != nil {
				return errors.Wrap(err, "error connecting to payloads db")
			}

			m, err := newMigrator(db, sourceDirectory, "actions_payloads_schema_migrations")
			if err != nil {
				return errors.Wrap(err, "error creating mysql migrator")
			}
			defer m.Close()

			versionStr := args[0]
			version, err := strconv.Atoi(versionStr)
			if err != nil {
				return errors.Wrap(err, "error parsing version")
			}

			return m.Force(version)
		},
	}

	forcePayloadsCommand.Flags().StringVarP(&sourceDirectory, "source", "s", "migrations/actions_workflow_payloads", "Source directory for migrations")

	forcePayloadsCommand.Flags().StringVarP(&databaseURL, "database", "d", "", "Full database URL for running migrations")
	forcePayloadsCommand.MarkFlagRequired("database") // nolint: errcheck

	return forcePayloadsCommand
}

type transitionCmd func(deployerTransitioner, payloadsTransitioner *dbmigrator.Transitioner) error

func getTransitionCommand(ctx context.Context) *cobra.Command {
	withTransitioners := func(fn transitionCmd) error {
		deployerDB, err := getDB(os.Getenv("DEPLOYER_DATABASE_URL"))
		if err != nil {
			return errors.Wrap(err, "error connecting to deployer DB for transitions")
		}

		deployerTransitioner, err := getDeployerTransitions(deployerDB)
		if err != nil {
			return errors.Wrap(err, "error intializing transitions")
		}

		mode := launchconfig.ParseMode(os.Getenv("LAUNCH_MODE"))

		// The payloads database is only used in GHES
		if mode != launchconfig.EnterpriseAppMode {
			return fn(deployerTransitioner, nil)
		}

		payloadsCluster, err := getDB(os.Getenv("PAYLOADS_DATABASE_URL"))
		if err != nil {
			return errors.Wrap(err, "error connecting to payloads DB for transitions")
		}

		payloadsTransitioner, err := getPayloadsTransitions(payloadsCluster)
		if err != nil {
			return errors.Wrap(err, "error intializing transitions")
		}
		return fn(deployerTransitioner, payloadsTransitioner)
	}

	transitionCmd := &cobra.Command{
		Use:   "transition",
		Short: "Runs the latest transition",
		RunE: func(cmd *cobra.Command, args []string) error {
			return withTransitioners(func(deployerTransitioner, payloadsTransitioner *dbmigrator.Transitioner) error {
				transition := latestTransition(deployerTransitioner, payloadsTransitioner)
				return transition.Run(ctx)
			})
		},
	}

	var (
		version uint
		dbname  string
	)
	transitionSpecificCmd := &cobra.Command{
		Use:   "specific",
		Short: "Runs a specific transition",
		RunE: func(cmd *cobra.Command, args []string) error {
			return withTransitioners(func(deployerTransitioner, payloadsTransitioner *dbmigrator.Transitioner) error {
				var transitioner *dbmigrator.Transitioner
				switch dbname {
				case "deployer":
					transitioner = deployerTransitioner
				case "payloads":
					transitioner = payloadsTransitioner
				default:
					return errors.Errorf("no such DB: %q - pick one of (deployer|payloads)", dbname)
				}
				transition, ok := transitioner.Get(version)
				if !ok {
					return errors.Errorf("no such transition version: %d", version)
				}
				return transition.Run(ctx)
			})
		},
	}
	transitionSpecificCmd.Flags().UintVar(&version, "version", 0, "version of the transition to run")
	transitionSpecificCmd.Flags().StringVar(&dbname, "dbname", "deployer", "(deployer|payloads) name of the DB for which the transition is defined")

	transitionCmd.AddCommand(transitionSpecificCmd)

	return transitionCmd
}

// Creates the initial database.
func getSetupCommand(ctx context.Context) *cobra.Command {

	var databaseURL string
	var databaseName string

	setupCommand := &cobra.Command{
		Use:   "setup",
		Short: "Creates a database initially",
		RunE: func(cmd *cobra.Command, args []string) error {
			db, err := sql.Open("mysql", databaseURL)
			if err != nil {
				return err
			}
			defer db.Close()

			// Match the default collation and character set of MySQL 5.7
			// This ensures the schema migration tables created by `golang-migrate/migrate` have the right collation
			createDB := fmt.Sprintf("CREATE DATABASE IF NOT EXISTS %s DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_general_ci", databaseName)
			_, err = db.ExecContext(ctx, createDB)
			if err != nil {
				return err
			}

			return nil
		},
	}

	setupCommand.Flags().StringVar(&databaseURL, "url", "", "sets the database url")
	setupCommand.Flags().StringVar(&databaseName, "name", "", "sets the database name")

	return setupCommand
}

func getMigrateDeployerCommand(ctx context.Context) *cobra.Command {
	var sourceDirectory string
	var databaseURL string

	migrateDeployerCommand := &cobra.Command{
		Use:   "deployer",
		Short: "Applies migrations and transitions for workflow_builds, workflow_schedules, workflow_jobs, and azp_resources tables",
		RunE: func(cmd *cobra.Command, args []string) error {
			db, err := getDB(databaseURL)
			if err != nil {
				return errors.Wrap(err, "error connecting to deployer db")
			}

			transitioner, err := getDeployerTransitions(db)
			if err != nil {
				return errors.Wrap(err, "error intializing transitions")
			}

			m, err := newMigrator(db, sourceDirectory, "actions_deployer_schema_migrations")
			if err != nil {
				return errors.Wrap(err, "error creating mysql migrator")
			}
			defer m.Close()

			return m.Migrate(ctx, transitioner)
		},
	}

	migrateDeployerCommand.Flags().StringVarP(&sourceDirectory, "source", "s", "migrations/deployer", "Source directory for migrations")

	migrateDeployerCommand.Flags().StringVarP(&databaseURL, "database", "d", "", "Full database URL for running migrations")
	migrateDeployerCommand.MarkFlagRequired("database") // nolint: errcheck

	return migrateDeployerCommand
}

func getMigratePayloadsCommand(ctx context.Context) *cobra.Command {
	var sourceDirectory string
	var databaseURL string

	migratePayloadsCommand := &cobra.Command{
		Use:   "payloads",
		Short: "Applies migrations and transitions for workflow_payloads",
		RunE: func(cmd *cobra.Command, args []string) error {
			db, err := getDB(databaseURL)
			if err != nil {
				return errors.Wrap(err, "error connection to payloads db")
			}

			transitioner, err := getPayloadsTransitions(db)
			if err != nil {
				return errors.Wrap(err, "error intializing transitions")
			}

			m, err := newMigrator(db, sourceDirectory, "actions_payloads_schema_migrations")
			if err != nil {
				return errors.Wrap(err, "error creating mysql migrator")
			}
			defer m.Close()

			return m.Migrate(ctx, transitioner)
		},
	}

	migratePayloadsCommand.Flags().StringVarP(&sourceDirectory, "source", "s", "migrations/actions_workflow_payloads", "Source directory for migrations")

	migratePayloadsCommand.Flags().StringVarP(&databaseURL, "database", "d", "", "Full database URL for running migrations")
	migratePayloadsCommand.MarkFlagRequired("database") // nolint: errcheck

	return migratePayloadsCommand
}

func getTruncateCommand(ctx context.Context) *cobra.Command {
	forceCmd := &cobra.Command{
		Use:   "truncate",
		Short: "Truncate all data from Actions related tables. Used in ghe-actions-teardown script on GHES.",
	}

	forceCmd.AddCommand(getTruncateServiceCommand(ctx, serviceDeployer))
	forceCmd.AddCommand(getTruncateServiceCommand(ctx, servicePayloads))

	return forceCmd
}

func getTruncateServiceCommand(ctx context.Context, service serviceName) *cobra.Command {
	var dryRun bool
	var databaseURL string

	truncateDeployerCommand := &cobra.Command{
		Use:   string(service),
		Short: fmt.Sprintf("truncates all tables in the %s database", service),
		RunE: func(cmd *cobra.Command, args []string) error {
			db, err := getDB(databaseURL)
			if err != nil {
				return errors.Wrap(err, "error connecting to db")
			}

			t := &truncator{db: db, service: service}
			return t.truncate(ctx, dryRun)
		},
	}

	truncateDeployerCommand.Flags().BoolVar(&dryRun, "dry-run", true, "Run in dry-run mode, not actually performing the truncate. Set to `false` to perform the truncation")

	truncateDeployerCommand.Flags().StringVarP(&databaseURL, "database", "d", "", "Full database URL for truncation")
	truncateDeployerCommand.MarkFlagRequired("database") // nolint: errcheck

	return truncateDeployerCommand
}

func newMigrator(db *sql.DB, sourceDirectory, migrationsSchema string) (*mysql.Migrator, error) {
	fullSourceURL := fmt.Sprintf("file://%s", sourceDirectory)
	return mysql.NewWithDatabaseInstance(db, fullSourceURL, migrationsSchema)
}

func latestTransition(deployer, payloads *dbmigrator.Transitioner) *dbmigrator.Transition {
	td, vd := deployer.LatestTransition()
	if payloads == nil {
		return td
	}

	tp, vp := payloads.LatestTransition()

	if vd > vp {
		return td
	}
	return tp
}

func getDB(databaseURL string) (*sql.DB, error) {
	dbURL, err := dsn.WithInterpolateParams(databaseURL, "true")
	if err != nil {
		return nil, errors.Wrap(err, "unable to set interpolate params attribute")
	}
	dbURL, err = dsn.WithMultiStatementsEnabled(dbURL)
	if err != nil {
		return nil, errors.Wrap(err, "unable to set multi statements params attribute")
	}
	db, err := mysqldb.NewDB(statter.NullStatter(), dbURL)
	if err != nil {
		return nil, errors.Wrap(err, "error creating mysql connection")
	}
	return db, err
}
