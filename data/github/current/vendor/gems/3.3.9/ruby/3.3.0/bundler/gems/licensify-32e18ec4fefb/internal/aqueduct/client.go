// Package aqueduct provides a client and handler for aqueduct jobs.
package aqueduct

import (
	"fmt"
	"os"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/go-stats"
)

// NewClient creates a new aqueduct client.
func NewClient(aqueductURL, apiKey string, apiKeyVersion int, statter stats.Client) (aqueduct.Client, error) {
	statsConfig, err := aqueduct.NewStatsConfig(
		aqueduct.WithStatsClient(statter),
	)
	if err != nil {
		return nil, fmt.Errorf("could not create stats config for aqueduct client: %w", err)
	}

	opts := []aqueduct.ClientOption{
		aqueduct.WithClientStats(statsConfig),
	}
	if apiKey != "" {
		opts = append(opts, aqueduct.WithAPIKey(apiKey), aqueduct.WithAPIKeyVersion(apiKeyVersion))
	}

	client, err := aqueduct.NewClient(aqueductURL, opts...)
	if err != nil {
		return nil, fmt.Errorf("could not create aqueduct client: %w", err)
	}
	return client, nil
}

// CreateReadinessProbeFile creates a file in /tmp to be used as a readiness probe.
func CreateReadinessProbeFile() error {
	_, err := os.Create("/tmp/worker_healthy") //nolint:gosec // not using os.CreateTemp because it adds a random string to the filename and the readiness probe won't be able to find it
	if err != nil {
		return fmt.Errorf("creating worker_healthy file for readiness probe: %w", err)
	}
	return nil
}
