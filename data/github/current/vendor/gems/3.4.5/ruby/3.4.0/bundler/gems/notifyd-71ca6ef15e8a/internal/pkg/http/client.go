// Package http implements an http client with retry features.
package http

import (
	"net/http"
	"time"

	retry "github.com/hashicorp/go-retryablehttp"

	"github.com/github/github-telemetry-go/log"
)

type clientConfig struct {
	retryMax     int
	retryWaitMax time.Duration
	retryWaitMin time.Duration
	retryTimeout time.Duration
	logger       retry.LeveledLogger
}

// Option is a function that sets a client configuration
type Option func(c *clientConfig)

func (c *clientConfig) applyOptions(options []Option) {
	for _, opt := range options {
		opt(c)
	}
}

// NewClient sets up a new http client that performs retries according to the options set up on
// defaultConfig
func NewClient(opts ...Option) *http.Client {
	cfg := defaultConfig()
	cfg.applyOptions(opts)
	client := retry.NewClient()
	client.RetryMax = cfg.retryMax
	client.RetryWaitMax = cfg.retryWaitMax
	client.RetryWaitMin = cfg.retryWaitMin
	client.HTTPClient.Timeout = cfg.retryTimeout
	client.Logger = cfg.logger

	return client.StandardClient()
}

// defaultConfig is:
//
// - retry 2 times at most
// - wait at most 1 second between retries
// - wait at least 100 milliseconds between retries
// - apply a timeout of 1 second to each retry
func defaultConfig() clientConfig {
	return clientConfig{
		retryMax:     2,
		retryWaitMax: time.Second,
		retryWaitMin: 100 * time.Millisecond,
		retryTimeout: time.Second,
	}
}

// WithRetryTimeout sets up the amount of time that a single request can take on the client side.
// This configuration affects individually each one of the retries and has no effect on the overall
// operation. If you need to handle that, use `context` deadlines instead.
func WithRetryTimeout(timeout time.Duration) Option {
	return func(c *clientConfig) {
		c.retryTimeout = timeout
	}
}

// WithLogger sets up a logger for the client.
func WithLogger(logger log.Logger) Option {
	return func(c *clientConfig) {
		c.logger = &leveledLoggerAdapter{logger: logger}
	}
}
