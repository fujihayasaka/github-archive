package main

import (
	"context"
	"database/sql"
	"log"
	"os"
	"time"

	"github.com/github/dependency-snapshots-api/internal/command"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/freno"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/github/go-dbmigrator/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

var commands = []command.Command{
	{
		Name:    "all",
		Desc:    "Run all pending migrations and any transitions that apply to those schema versions. This is the normal mode for Enterprise installs.",
		Execute: runAll,
	},
	{
		Name:    "transition",
		Desc:    "Run only the latest transition. This is the normal way of running transitions in the cloud.",
		Execute: runLatestTransition,
	},
	{
		Name:    "reset",
		Desc:    "Resets the local development database instance.",
		Execute: resetDevelopmentDatabase,
	},
	{
		Name:    "await",
		Desc:    "Awaits availability of the configured database instance.",
		Execute: awaitDatabase,
	},
}

// BuildCommit - latest commit SHA for this build; injected at compile-time
var BuildCommit string = "UNKNOWN"

func main() {
	if len(os.Args) < 2 {
		log.Fatalf("usage: migrate <command>\n" + command.ListCommands(commands))
	}

	err := command.DispatchCommand(os.Args[1], commands)
	if err != nil {
		log.Fatalf("failed to run command: %v", err)
	}
}

// getDBServerConnection gets a connection to the configured database server _only_, and does
// not connect to any individual database.
func getDBServerConnection(cfg *config.Config) (*sql.DB, error) {
	mysqlConfig := cfg.NewMysqlConfig()
	mysqlConfig.DBName = ""
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return db.ConnectToMysql(ctx, mysqlConfig, cfg.DBIdleConnections, cfg.DBMaxConnections)
}

// runAll runs both migrations and transitions. This is for running in container
// installs such as development and enterprise environments. This runs each
// schema migration in sequence, checking after each one for transitions labeled
// with that schema version and running those.
func runAll(c *command.Command) error {

	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return errors.Wrap(err, "loading configuration")
	}
	log.Printf("running all migrations on %s\n", cfg.DB)
	return runAllMigrations(cfg)
}

func runAllMigrations(cfg *config.Config) error {
	serverConn, err := getDBServerConnection(cfg)
	if err != nil {
		return err
	}

	if err := db.MysqlCreateSchema(serverConn, cfg.DB); err != nil {
		return err
	}
	if err := serverConn.Close(); err != nil {
		return err
	}

	sqlxDB, blobClient, freno, err := getTransitionDependencies(cfg)
	if err != nil {
		return err
	}

	trans, err := getTransitions(cfg, sqlxDB, blobClient, freno)
	if err != nil {
		return errors.Wrap(err, "loading transitions")
	}

	fullSourceURL := "file://migrations"
	opts := &mysql.MigratorOpts{}
	migrator, err := mysql.NewWithDatabaseInstance(opts, sqlxDB.DB, fullSourceURL, "ds_migrations")
	if err != nil {
		return errors.Wrap(err, "creating migrator")
	}
	defer migrator.Close()

	return migrator.Migrate(context.Background(), trans)
}

// awaitDatabase waits for the DB to become ready for a fixed amount of time.
func awaitDatabase(c *command.Command) error {
	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return errors.Wrap(err, "loading configuration for await")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	start := time.Now()
	err = db.WaitForDatabase(ctx, func() (*sql.DB, error) {
		return getDBServerConnection(cfg)
	})
	if err != nil {
		log.Printf("database not ready after %v\n", time.Since(start))
		return err
	}
	log.Printf("database ready after %v\n", time.Since(start))
	return nil
}

// resetDevelopmentDatabase "resets" the database to a pristine state, only if the configured environment is Development
func resetDevelopmentDatabase(c *command.Command) error {
	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return errors.Wrap(err, "loading configuration for reset")
	}

	if !cfg.IsDevelopment() {
		return errors.New("environment is not development - cannot reset DB")
	}
	log.Printf("resetting db %s\n", cfg.DB)

	serverConn, err := getDBServerConnection(cfg)
	if err != nil {
		return err
	}

	if err := db.MysqlDropSchema(serverConn, cfg.DB); err != nil {
		return err
	}
	if err := db.MysqlCreateSchema(serverConn, cfg.DB); err != nil {
		return err
	}

	if err := runAllMigrations(cfg); err != nil {
		return err
	}

	return serverConn.Close()
}

// runLatestTransition runs only the latest transition. This is for running
// transitions in the cloud. In that environment schema migrations are handled
// by skeefree, and it's expected that the database is up to date except for the
// latest transition.
func runLatestTransition(c *command.Command) error {
	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return errors.Wrap(err, "loading configuration")
	}
	log.Printf("running the latest transition on db %s\n", cfg.DB)

	sqlxDB, blobClient, frenoClient, err := getTransitionDependencies(cfg)
	if err != nil {
		return err
	}

	trans, err := getTransitions(cfg, sqlxDB, blobClient, frenoClient)
	if err != nil {
		return errors.Wrap(err, "loading transitions")
	}

	return trans.LatestTransition().Run(context.Background())
}

func getTransitionDependencies(cfg *config.Config) (*sqlx.DB, blob.BlobClient, *freno.FrenoClient, error) {
	dbConn, err := db.ConnectToMysql(context.Background(), cfg.NewMysqlConfig(), cfg.DBIdleConnections, cfg.DBMaxConnections)
	if err != nil {
		return nil, nil, nil, err
	}

	sqlxConn, err := db.NewSqlxDatabase(dbConn)
	if err != nil {
		return nil, nil, nil, err
	}

	frenoClient := freno.NewFrenoClient(cfg)

	blobClient, err := blob.InitializeSnapshotsBlobClientIfEnabled(context.Background(), cfg)
	if err != nil {
		return nil, nil, nil, err
	}
	return sqlxConn, blobClient, frenoClient, nil
}
