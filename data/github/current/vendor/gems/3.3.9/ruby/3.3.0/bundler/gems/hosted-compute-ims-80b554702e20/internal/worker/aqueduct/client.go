// Package aqueduct provides a client for interacting with aqueduct.
package aqueduct

import (
	"fmt"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
)

// Aliases for easier imports
type (
	Job            = aqueduct.Job
	ReceiveResult  = aqueduct.ReceiveResult
	ReceiveOptions = aqueduct.ReceiveOptions
	Worker         = aqueduct.Worker
	originalClient = aqueduct.Client
)

// Aliases for easier imports
var (
	NewWorker           = aqueduct.NewWorker
	NewHeartbeatConfig  = aqueduct.NewHeartbeatConfig
	WithHeartbeatConfig = aqueduct.WithHeartbeatConfig
	WithReceiveTimeout  = aqueduct.WithReceiveTimeout
	WithJobErrorPolicy  = aqueduct.WithJobErrorPolicy
	WithLogger          = aqueduct.WithLogger
	NackJobErr          = aqueduct.NackJobErr
)

// Client is an interface for aqueduct-client-go, since it only exposes concrete types
type Client interface {
	aqueduct.Client
	GetConfig() *Config
}

// wrapper around aqueduct client so we can also pass around config together
type client struct {
	originalClient
	*Config
}

func (c *client) GetConfig() *Config {
	return c.Config
}

// New creates an aqueduct client using the given config
func NewAqueductClient(cfg *Config) (Client, error) {
	opts := []aqueduct.ClientOption{}
	if cfg.APIKey != "" {
		opts = append(opts, aqueduct.WithAPIKey(cfg.APIKey), aqueduct.WithAPIKeyVersion(cfg.APIKeyVersion))
	}

	originalClient, err := aqueduct.NewClient(cfg.Addr, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	return &client{originalClient, cfg}, nil
}
