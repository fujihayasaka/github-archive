// Package application manages application and it's subsystems
package application

import (
	"context"
	"database/sql"
	"fmt"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/github/osslicensecompliance/internal/dsapiclient"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	"github.com/github/osslicensecompliance/internal/storage"
	"github.com/github/osslicensecompliance/internal/storage/azureblob"
	"github.com/github/osslicensecompliance/internal/storage/sequence"
	_ "github.com/go-sql-driver/mysql" // mysql driver
)

// Application represents the overall system decoupled from transport
type Application struct {
	Subsystems  *Subsystems
	Logger      log.Logger
	StatsClient stats.Client
	Config      *config.Config
	bgWork      sync.WaitGroup // tracks background goroutines
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
			"./null_seeds/list_package_versions.json",
		)
		if err != nil {
			return nil, err
		}
		diffStatusConfig, err := dsapiclient.LoadNullSeeds(
			"./null_seeds/snapshots_diff_status.json",
		)
		if err != nil {
			return nil, err
		}
		nullConfig := &NullConfig{
			DependenciesConfig: dependenciesConfig,
			DiffStatusConfig:   diffStatusConfig,
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

	return &Application{Subsystems: subsystems, Logger: logger, StatsClient: statsClient, Config: cfg}, nil
}

// NewNullApplication creates a application with inmemory storage
// and stubbed DG APIs
// Intended for test and local development
func NewNullApplication(nullConfig *NullConfig, logger log.Logger) (*Application, error) {
	subsystems := &Subsystems{}

	storageSubsystem, err := storage.NewNullStorage(nullConfig.SqlitePersistLoc, logger)
	if err != nil {
		return nil, err
	}
	subsystems.Storage = storageSubsystem

	subsystems.DependencyGetter = dependencies.NewNullDependencies(nullConfig.DependenciesConfig, logger, stats.NullStatter)

	subsystems.DiffStatusGetter = dsapiclient.NewNullDiffStatus(nullConfig.DiffStatusConfig, logger, stats.NullStatter)

	subsystems.EventPublisher, err = eventpublisher.NewNull(logger, stats.NullStatter)
	if err != nil {
		return nil, fmt.Errorf("failed to create null event publisher: %w", err)
	}

	return &Application{Subsystems: subsystems, Logger: logger, StatsClient: stats.NullStatter}, nil
}

// Close closes the application and all of its subsystems
func (a *Application) Close() error {
	// Wait for background goroutines to complete with a timeout
	done := make(chan struct{})
	go func() {
		a.bgWork.Wait()
		close(done)
	}()

	select {
	case <-done:
		// Background work completed
	case <-time.After(1 * time.Minute):
		a.Logger.Warn("shutdown timeout waiting for background work to complete")
	}

	var closeErrors []error

	if s := a.Subsystems.Storage; s != nil {
		err := s.Close()
		if err != nil {
			closeErrors = append(closeErrors, fmt.Errorf("failed to close storage: %w", err))
		}
	}

	if p := a.Subsystems.EventPublisher; p != nil {
		err := p.Close()
		if err != nil {
			closeErrors = append(closeErrors, fmt.Errorf("failed to close event publisher: %w", err))
		}
	}

	if len(closeErrors) > 0 {
		return fmt.Errorf("errors closing application subsystems: %v", closeErrors)
	}

	return nil
}

// BackgroundWorkAdd increments the background work counter
func (a *Application) BackgroundWorkAdd(delta int) {
	a.bgWork.Add(delta)
}

// BackgroundWorkDone decrements the background work counter
func (a *Application) BackgroundWorkDone() {
	a.bgWork.Done()
}

// Subsystems contains the systems required to fulfill the application
type Subsystems struct {
	Storage          *storage.Storage
	DependencyGetter *dependencies.DependencyGetter
	DiffStatusGetter *dsapiclient.StatusGetter
	EventPublisher   *eventpublisher.Publisher
}

// NewSubsystems creates subsystems according to configuration
func NewSubsystems(ctx context.Context, cfg *config.Config, logger log.Logger, statsClient stats.Client) (*Subsystems, error) {
	subsystems := &Subsystems{}
	var err error

	subsystems.Storage, err = NewStorage(ctx, cfg, statsClient, logger)
	if err != nil {
		return nil, err
	}

	subsystems.DependencyGetter, err = dependencies.New(cfg, logger, statsClient)
	if err != nil {
		return nil, err
	}

	subsystems.DiffStatusGetter, err = dsapiclient.New(cfg, logger, statsClient)
	if err != nil {
		return nil, err
	}

	subsystems.EventPublisher, err = eventpublisher.New(cfg, logger, statsClient)
	if err != nil {
		return nil, err
	}

	return subsystems, nil
}

// NewStorage creates a new storage instance based on the configuration
func NewStorage(ctx context.Context, cfg *config.Config, statsClient stats.Client, logger log.Logger) (*storage.Storage, error) {
	db, err := NewLiveDatabase(cfg, logger)
	if err != nil {
		return nil, fmt.Errorf("failed to create mysql connection: %w", err)
	}

	buckets, err := azureblob.NewBlobBuckets(ctx, cfg, logger)
	if err != nil {
		return nil, fmt.Errorf("failed to create bucket clients: %w", err)
	}

	s, err := storage.NewStorageWithAzureBuckets(db, buckets.RepositoryBucket(), buckets.OrganizationBucket(), buckets.EnterpriseBucket(), sequence.NewMySQLGenerator(db), statsClient, logger)
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
func NewLiveDatabase(cfg *config.Config, logger log.Logger) (*sql.DB, error) {
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
	DiffStatusConfig   dsapiclient.NullConfig
	SqlitePersistLoc   string
}
