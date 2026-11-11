package aqueduct

import (
	"fmt"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/pkg/errors"
)

// ErrNotConfigured is returned when Aqueduct is disabled or missing required configuration.
var ErrNotConfigured = errors.New("aqueduct is not configured for this environment")

// Client aliases the upstream Aqueduct client interface so callers do not need to
// import the upstream package directly.
type Client = aq.Client

func statsConfig(statter stats.Client) (*aq.StatsConfig, error) {
	return aq.NewStatsConfig(aq.WithStatsClient(statter))
}

// ErrNotSupportedOnGHES is returned when Aqueduct is used in an enterprise (GHES) environment.
var ErrNotSupportedOnGHES = errors.New("aqueduct is not supported in GHES")

// NewClient creates an instrumented Aqueduct client using service configuration.
// It requires Aqueduct to be explicitly enabled and the necessary connection fields set.
// It refuses to create a real client in GHES (enterprise) environments.
func NewClient(cfg *config.Config, logger log.Logger, statter stats.Client) (aq.Client, error) {
	if cfg.Enterprise {
		return nil, ErrNotSupportedOnGHES
	}

	if !cfg.AqueductConfigured() {
		return nil, ErrNotConfigured
	}

	statsCfg, err := statsConfig(statter)
	if err != nil {
		return nil, err
	}

	client, err := aq.NewClient(
		cfg.AqueductURL,
		aq.WithAPIKey(cfg.AqueductAPIKey),
		aq.WithAPIKeyVersion(cfg.AqueductAPIKeyVersion),
		aq.WithClientLogger(logger),
		aq.WithClientStats(statsCfg),
	)
	if err != nil {
		return nil, errors.Wrap(err, "create aqueduct client")
	}

	return client, nil
}

// NewEchoWorker builds a worker bound to the configured echo queue with the standard handler.
func NewEchoWorker(cfg *config.Config, client aq.Client, logger log.Logger, statter stats.Client) (*aq.Worker, error) {
	if client == nil {
		return nil, fmt.Errorf("aqueduct client is required")
	}
	if cfg.AqueductEchoQueue == "" {
		return nil, fmt.Errorf("aqueduct echo queue must be set")
	}
	poolName := fmt.Sprintf("%s-%s-worker", cfg.AqueductAppName, cfg.AqueductEchoQueue)

	statsCfg, err := statsConfig(statter)
	if err != nil {
		return nil, err
	}

	handler := NewEchoHandler(logger)

	worker, err := aq.NewWorker(
		client,
		cfg.AqueductAppName,
		[]string{cfg.AqueductEchoQueue},
		handler,
		aq.WithWorkerStats(statsCfg),
		aq.WithPool(poolName),
	)
	if err != nil {
		return nil, errors.Wrap(err, "create aqueduct echo worker")
	}

	return worker, nil
}
