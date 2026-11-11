package hydro

import (
	"context"
	"fmt"

	env "github.com/caarlos0/env/v11"
	"github.com/github/configsd/internal/db"
	"github.com/github/configsd/internal/handlers"
	"github.com/github/configsd/internal/model"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-server/runtime"
	"github.com/github/go-server/runtime/features"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/jmoiron/sqlx"
)

// Consumer manages Kafka message consumption and database operations for configuration events
type Consumer struct {
	dbConn      *sqlx.DB
	configStore model.Store
	hydroSource hydro.Source
	server      *runtime.Server
}

type consumerConfig struct {
	Brokers []string `env:"KAFKA_BROKERS" envDefault:"localhost:9092"`
	Group   string   `env:"KAFKA_GROUP"   envDefault:"configsd-consumer-dev"`
}

// NewConsumer creates a new Consumer with the provided database connection.
// All other dependencies (server, config store, Kafka settings) are created from environment variables.
// If flagger is nil, the server will create its own flagger.
func NewConsumer(dbConn *sqlx.DB, flagger features.Flagger) (*Consumer, error) {
	// Parse environment config
	var cfg consumerConfig
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse environment variables: %w", err)
	}

	// Create server from environment, optionally with provided flagger
	var server *runtime.Server
	var err error
	if flagger != nil {
		server, err = runtime.NewServer(runtime.WithFlagger(flagger))
	} else {
		server, err = runtime.NewServer()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to create server: %w", err)
	}

	// Create config store with provided database connection
	configStore, err := db.NewStore(dbConn, server.Statter)
	if err != nil {
		return nil, fmt.Errorf("failed to create store: %w", err)
	}

	hydroSource, err := KafkaSource(
		cfg.Brokers,
		server,
		cfg.Group,
		handlers.RepoCreationHandlerTopic,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create hydro source: %w", err)
	}

	return &Consumer{
		dbConn:      dbConn,
		configStore: configStore,
		hydroSource: hydroSource,
		server:      server,
	}, nil
}

// Close gracefully shuts down the consumer and releases all resources
func (c *Consumer) Close(ctx context.Context) error {
	if err := c.hydroSource.Close(); err != nil {
		return fmt.Errorf("error closing hydro source: %w", err)
	}
	if err := c.dbConn.Close(); err != nil {
		return fmt.Errorf("error closing database connection: %w", err)
	}
	if err := c.server.Shutdown(ctx); err != nil {
		return fmt.Errorf("error shutting down server: %w", err)
	}
	return nil
}

// ConsumeRepoCreationEvents starts consuming repository creation events from Kafka
func (c *Consumer) ConsumeRepoCreationEvents(ctx context.Context, cancelFunc context.CancelFunc) error {
	repoCreationHandler := handlers.NewRepoCreationHandler(c.configStore, c.server.Logger, c.server.Flagger, cancelFunc)
	c.server.Logger.Debug("starting hydro source...")
	if err := c.hydroSource.Consume(ctx, repoCreationHandler); err != nil {
		c.server.Logger.Error("Failed to process messages", kvp.String("error", err.Error()))
		return fmt.Errorf("failed to consume messages: %w", err)
	}
	return nil
}
