package transitionsapp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	dbmigrator "github.com/github/go-dbmigrator"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/internal/transitions"
	"github.com/github/trust-metadata-api/internal/transitions/database"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"

	_ "github.com/go-sql-driver/mysql" // mysql driver
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// ConfigStruct is the struct that holds the configuration values for the transitions app.
type Config struct {
	// database arguments
	AppEnv string `mapstructure:"app-env"`
	// primary DB arguments
	MySQLDBConn   string
	MySQLHost     string `mapstructure:"mysql-host"`
	MySQLDatabase string `mapstructure:"mysql-database"`
	MySQLPassword string `mapstructure:"mysql-password"`
	MySQLPort     string `mapstructure:"mysql-port"`
	MySQLUser     string `mapstructure:"mysql-user"`
	// read only replica DB arguments
	MySQLRODBConn   string
	MySQLRODatabase string `mapstructure:"mysql-ro-database"`
	MySQLROHost     string `mapstructure:"mysql-ro-host"`
	MySQLROPassword string `mapstructure:"mysql-ro-password"`
	MySQLROPort     string `mapstructure:"mysql-ro-port"`
	MySQLROUser     string `mapstructure:"mysql-ro-user"`
	// azure blob arguments
	UseLocalClient     bool   `mapstructure:"use-local-client"`
	AzureBlobAccount   string `mapstructure:"azure-blob-account"`
	AzureBlobContainer string `mapstructure:"azure-blob-container"`
	// transition arguments
	DryRun    bool   `mapstructure:"dry-run"`
	ID        uint   `mapstructure:"id"` // ID of the transition to run
	MinID     uint64 `mapstructure:"min-id"`
	MaxID     uint64 `mapstructure:"max-id"`
	BatchSize uint64 `mapstructure:"batch-size"`
}

// App is the transitions app
type App struct {
	Config Config
	logger log.Logger
}

// New creates a new App
func New(c Config) (*App, error) {
	logger, err := newLogger(c.AppEnv)
	if err != nil {
		return nil, errors.Wrap(err, "error creating logger")
	}

	return &App{
		Config: c,
		logger: logger,
	}, nil
}

// Run starts the transitions app
func (a *App) Run(ctx context.Context) error {
	a.logger.Info("Transitions app run started...")
	a.logger.Info("Transition ID:", kvp.Uint("Transition ID:", a.Config.ID))
	a.logger.Info("Min ID:", kvp.Uint64("MinID:", a.Config.MinID))
	a.logger.Info("Max ID:", kvp.Uint64("MaxID:", a.Config.MaxID))
	a.logger.Info("Batch Size:", kvp.Uint64("Batch Size:", a.Config.BatchSize))

	// connect to database
	db, err := sqlx.Connect("mysql", a.Config.MySQLDBConn)
	if err != nil {
		a.logger.Error("error connecting to mysql", kvp.Err(err))
		return errors.Wrap(err, "error connecting to mysql")
	}
	defer db.Close()

	// connect to Azure Blob Storage
	var azBlobClient azureblob.Client
	if a.Config.UseLocalClient {
		azBlobClient, err = azureblob.NewLocalClient(a.Config.AzureBlobContainer)
		if err != nil {
			return err
		}
	} else {
		azBlobClient, err = azureblob.NewRemoteClient(a.Config.AzureBlobAccount, a.Config.AzureBlobContainer, a.logger, stats.NullStatter)
		if err != nil {
			return err
		}
	}

	// parse transition arguments
	transitionArgs := parseTransitionArgs(a.Config)

	// load transitions
	transitions, err := a.getTransitions(db, azBlobClient, transitionArgs, a.logger)
	if err != nil {
		a.logger.Error("error loading transitions", kvp.Err(err))
		return errors.Wrap(err, "error loading transitions")
	}

	// get the transition by ID
	tID := uint(transitionArgs.ID)
	t, success := transitions.GetTransition(tID)
	if !success {
		a.logger.Error("error loading transitions", kvp.Err(err))
		return fmt.Errorf("transition with ID %d not found", tID)
	}

	a.logger.Info("Ready to run transition with ID:", kvp.Uint("Transition ID:", tID))

	// run the transition
	err = t.Run(ctx)

	a.logger.Info("Finished running transition with ID:", kvp.Uint("Transition ID:", tID))

	if err != nil {
		a.logger.Error("error running transitions", kvp.Err(err))
	}

	return nil
}

// getTransitions returns a dbmigrator Transitioner with all the transitions loaded.
func (a *App) getTransitions(db *sqlx.DB, azBlob azureblob.Client, args *transitions.Args, logger log.Logger) (*dbmigrator.Transitioner, error) {
	t := dbmigrator.NewTransitioner()

	entries := transitions.Entries()
	for _, entry := range entries {
		switch {
		case entry.TransitionFn != nil:
			err := t.Add(entry.ID, entry.TransitionFn(args, logger).Run)
			if err != nil {
				a.logger.Error("error adding TransitionFn", kvp.Err(err))
				return nil, errors.Wrap(err, "adding TransitionFn")
			}
		case entry.DbTransitionFn != nil:
			err := t.Add(entry.ID, entry.DbTransitionFn(db, args, logger).Run)
			if err != nil {
				a.logger.Error("error adding DB transition", kvp.Err(err))
				return nil, errors.Wrap(err, "adding DB transition")
			}
		case entry.AzBlobTransitionFn != nil:
			err := t.Add(entry.ID, entry.AzBlobTransitionFn(azBlob, args, logger).Run)
			if err != nil {
				a.logger.Error("error adding blob storage transition", kvp.Err(err))
				return nil, errors.Wrap(err, "adding blob storage transition")
			}
		default:
			return nil, fmt.Errorf("no transition function provided")
		}
	}

	return t, nil
}

// parseTransitionArgs parses the command line arguments for the transition.
func parseTransitionArgs(c Config) *transitions.Args {
	id := c.ID
	dryRun := c.DryRun
	batchSize := c.BatchSize
	minID := c.MinID
	maxID := c.MaxID

	return &transitions.Args{
		ID:        id,
		DryRun:    dryRun,
		BatchSize: batchSize,
		MinID:     minID,
		MaxID:     maxID,
		DBConfig: database.DBConfig{
			PrimaryDBConn: database.DBConn{
				MySQLHost:     c.MySQLHost,
				MySQLDatabase: c.MySQLDatabase,
				MySQLPassword: c.MySQLPassword,
				MySQLPort:     c.MySQLPort,
				MySQLUser:     c.MySQLUser,
			},
			ROReplicaDBConn: database.DBConn{
				MySQLDatabase: c.MySQLRODatabase,
				MySQLHost:     c.MySQLROHost,
				MySQLPassword: c.MySQLROPassword,
				MySQLPort:     c.MySQLROPort,
				MySQLUser:     c.MySQLROUser,
			},
		},
	}
}

// newLogger creates a new logger
func newLogger(appEnv string) (log.Logger, error) {
	logger, err := log.NewFromConfig(log.Config{
		Environment:        appEnv,
		LogLevel:           log.InfoLevel.String(),
		LogConsoleEncoding: "logfmt",
	})
	if err != nil {
		return nil, err
	}

	logger = logger.Named("trust-metadata-api-transitions")

	return logger, nil
}
