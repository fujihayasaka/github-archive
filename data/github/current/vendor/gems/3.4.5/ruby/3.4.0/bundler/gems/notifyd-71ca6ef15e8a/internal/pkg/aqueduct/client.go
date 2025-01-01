package aqueduct

import (
	"context"

	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
)

// Sender represents a client that can send jobs to aqueduct.
type Sender interface {
	Send(context.Context, ghaqueduct.Job, ...ghaqueduct.SendOption) (string, error)
}

// NewClient creates a new aqueduct client.
func NewClient(cfg ClientConfig, logger log.Logger, statter stats.Client) (ghaqueduct.Client, error) {
	statsConfig, err := ghaqueduct.NewStatsConfig(ghaqueduct.WithStatsClient(statter))
	if err != nil {
		return nil, errors.Wrap(err, "initializing aqueduct client stats")
	}

	opts := []ghaqueduct.ClientOption{
		ghaqueduct.WithClientLogger(logger),
		ghaqueduct.WithClientStats(statsConfig),
		ghaqueduct.WithClientID("notifyd-production"),
	}

	if cfg.APIKey != "" {
		opts = append(
			opts,
			ghaqueduct.WithAPIKey(cfg.APIKey),
			ghaqueduct.WithAPIKeyVersion(cfg.APIKeyVersion),
		)
	}

	client, err := ghaqueduct.NewClient(cfg.URL, opts...)
	if err != nil {
		return nil, errors.Wrap(err, "initializing aqueduct client")
	}

	return client, nil
}
