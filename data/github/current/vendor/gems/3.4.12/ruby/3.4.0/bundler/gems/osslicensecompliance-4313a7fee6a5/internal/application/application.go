// Package application manages application and it's subsystems
package application

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/azureblob"
	"github.com/github/osslicensecompliance/internal/storage/nullblob"
	"github.com/github/osslicensecompliance/internal/storage/sqlite"
	_ "github.com/go-sql-driver/mysql" // mysql driver
)

// Application represents the overall system decoupled from transport
type Application struct {
	Subsystems *Subsystems
	Logger     log.Logger
	Config     *config.Config
}

// Close closes the application and all of its subsystems
func (a *Application) Close() error {
	if s := a.Subsystems.Storage; s != nil {
		return s.Close()
	}
	return nil
}

// New creates a new Application
func New(cfg *config.Config, logger log.Logger, statsClient stats.Client) (*Application, error) {
	// Create a context for application initialization
	// Use background context with a reasonable timeout for initialization
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if cfg.Environment == "development" && cfg.SubSystems != "real" {
		dependenciesConfig, err := dependencies.LoadNullSeeds(
			"./null_seeds/snapshots_diff.json",
		)
		if err != nil {
			return nil, err
		}
		nullConfig := &NullConfig{
			DependenciesConfig: dependenciesConfig,
			SqlitePersistLoc:   "./olc_sqlite.db",
		}
		app, err := NewNullApplication(nullConfig, logger)
		if err != nil {
			return nil, err
		}
		app.Config = cfg
		return app, nil
	}

	subsystems, err := NewSubsystems(ctx, cfg, logger, statsClient)
	if err != nil {
		return nil, err
	}

	return &Application{Subsystems: subsystems, Logger: logger, Config: cfg}, nil
}

// NewNullApplication creates a application with inmemory storage
// and stubbed DG APIs
// Intended for test and local development
func NewNullApplication(nullConfig *NullConfig, logger log.Logger) (*Application, error) {
	subsystems := &Subsystems{}

	db, err := sqlite.New(nullConfig.SqlitePersistLoc)
	if err != nil {
		return nil, fmt.Errorf("failed to create sqlite database: %w", err)
	}

	subsystems.Storage, err = storage.NewStorage(db, nullblob.NewBucket(), nullblob.NewBucket(), nullblob.NewBucket(), stats.NullStatter)
	if err != nil {
		return nil, err
	}

	subsystems.DependencyGetter = dependencies.NewNullDependencies(nullConfig.DependenciesConfig, logger, stats.NullStatter)

	return &Application{Subsystems: subsystems, Logger: logger}, nil
}

// Subsystems contains the systems required to fulfill the application
type Subsystems struct {
	Storage          *storage.Storage
	DependencyGetter *dependencies.DependencyGetter
}

// NewSubsystems creates subsystems according to configuration
func NewSubsystems(ctx context.Context, cfg *config.Config, logger log.Logger, statsClient stats.Client) (*Subsystems, error) {
	subsystems := &Subsystems{}
	var err error

	subsystems.Storage, err = NewStorage(ctx, cfg, statsClient)
	if err != nil {
		return nil, err
	}

	subsystems.DependencyGetter, err = dependencies.New(cfg, logger, statsClient)
	if err != nil {
		return nil, err
	}

	return subsystems, nil
}

// NewStorage creates a new storage instance based on the configuration
func NewStorage(ctx context.Context, cfg *config.Config, statsClient stats.Client) (*storage.Storage, error) {
	// TODO: when production database is setup put this back https://github.com/github/dependency-graph/issues/7223
	// Currently we are only using Blob storage for persistence
	// db, err := NewLiveDatabase(cfg)
	// if err != nil {
	// 	return nil, fmt.Errorf("failed to create mysql connection: %w", err)
	// }

	buckets, err := azureblob.NewBlobBuckets(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create bucket clients: %w", err)
	}

	s, err := storage.NewStorage(nil, buckets.RepositoryBucket(), buckets.OrganizationBucket(), buckets.EnterpriseBucket(), statsClient)
	if err != nil {
		return nil, err
	}
	return s, nil
}

const mySQLDBConnFormat = "%s:%s@tcp(%s:%s)/%s?parseTime=true"

const (
	dbMaxIdleTime  = 25 * time.Second
	dbMaxLifetime  = 5 * time.Minute
	dbMaxIdleConns = 32
	dbMaxOpenConns = 64
)

// NewLiveDatabase creates a MySQL implementation of the Database interface.
func NewLiveDatabase(cfg *config.Config) (*sql.DB, error) {
	uri := fmt.Sprintf(mySQLDBConnFormat,
		cfg.MySQL["user"],
		cfg.MySQL["password"],
		cfg.MySQL["host"],
		cfg.MySQL["port"],
		cfg.MySQL["database"],
	)

	db, err := sql.Open("mysql", uri)
	if err != nil {
		return nil, err
	}

	// See docs for more information: https://github.com/github/go/blob/main/docs/database_access.md
	db.SetConnMaxIdleTime(dbMaxIdleTime)
	db.SetConnMaxLifetime(dbMaxLifetime)
	db.SetMaxIdleConns(dbMaxIdleConns)
	db.SetMaxOpenConns(dbMaxOpenConns)

	return db, nil
}

// NullConfig is for creating a null application
// To inject in stubbed dependencies
type NullConfig struct {
	DependenciesConfig dependencies.NullConfig
	SqlitePersistLoc   string
}
