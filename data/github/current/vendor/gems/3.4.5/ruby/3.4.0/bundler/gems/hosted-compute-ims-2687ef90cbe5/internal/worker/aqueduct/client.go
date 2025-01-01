// Package aqueduct provides a client for interacting with aqueduct.
package aqueduct

import (
	"context"
	"fmt"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	aqueduct_api "github.com/github/aqueduct-client-go/v2/proto"
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
	WithPool            = aqueduct.WithPool
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

// New creates an aqueduct client using the given config and validates the connection
func NewAqueductClient(ctx context.Context, cfg *Config) (Client, error) {
	opts := []aqueduct.ClientOption{}
	if cfg.APIKey != "" {
		opts = append(opts, aqueduct.WithAPIKey(cfg.APIKey), aqueduct.WithAPIKeyVersion(cfg.APIKeyVersion))
	}

	originalClient, err := aqueduct.NewClient(cfg.Addr, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	// validate new client connection by listing queues
	// this will fail if the client is not able to connect to the aqueduct server
	// or if the app name is invalid
	newClient := &client{originalClient, cfg}
	_, err = newClient.TwirpClient().ListQueues(ctx, &aqueduct_api.ListQueuesRequest{
		App: cfg.AppName,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to validate aqueduct connection: %w", err)
	}

	return newClient, nil
}
