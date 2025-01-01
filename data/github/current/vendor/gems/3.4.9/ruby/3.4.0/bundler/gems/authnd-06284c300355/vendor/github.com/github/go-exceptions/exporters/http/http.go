// Package http implements a HTTP exporter for exceptions.
package http

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/github/go-stats"
	"github.com/sony/gobreaker"
)

// Option function that allows us to configure the reporter.
type Option func(opts *options) error

// options defines the configuration for the reporter.
type options struct {
	client *http.Client
	cb     CircuitBreaker
	stats  stats.Client

	// url is the Exception endpoint where to POST the exceptions. The URL must
	// contain username & password if required for authentication.
	url string
}

// Exporter defines a HTTP exporter that satisfies the exceptions.Exporter interface.
type Exporter struct {
	client *http.Client
	cb     CircuitBreaker
	stats  stats.Client

	// url is the Exception endpoint where to POST the exceptions. The URL must
	// contain username & password if required for authentication.
	url string
}

// WithClient sets the HTTP client.
func WithClient(client *http.Client) Option {
	return func(opts *options) error {
		opts.client = client
		return nil
	}
}

// WithCircuitBreaker sets the circuit breaker to use for the HTTP requests.
func WithCircuitBreaker(cb CircuitBreaker) Option {
	return func(opts *options) error {
		opts.cb = cb
		return nil
	}
}

// WithStatter sets the statter to use for reporting circuit breaker metrics.
func WithStatter(statter stats.Client) Option {
	return func(opts *options) error {
		opts.stats = statter
		return nil
	}
}

// WithURL sets the endpoint URL of the service the exceptions are sent to. It
// will be added as "app" on all exception payloads.
func WithURL(u string) Option {
	return func(opts *options) error {
		if u == "" {
			return errors.New("the endpoint URL for the exporter must be set")
		}

		parsed, err := url.Parse(u)
		if err != nil {
			return err
		}

		if parsed.User == nil {
			return errors.New("endpoint URL must have authentication set in the form of http://username:password@address/api/needles")
		}

		opts.url = u
		return nil
	}
}

// NewExporter returns a new reporter with the given options.
func NewExporter(opts ...Option) (*Exporter, error) {
	repOpts := &options{
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
		url: os.Getenv("FAILBOT_HAYSTACK_URL"),
	}

	for _, opt := range opts {
		if err := opt(repOpts); err != nil {
			return nil, err
		}
	}

	if repOpts.url == "" {
		return nil, errors.New("FAILBOT_HAYSTACK_URL environment variable must be set")
	}

	// if no circuit breaker is set, create a default one
	var err error
	if repOpts.cb == nil {
		var opts []CircuitBreakerOption
		if repOpts.stats != nil {
			opts = append(opts, WithStats(repOpts.stats))
		}
		repOpts.cb, err = NewCircuitBreaker(opts...)
		if err != nil {
			return nil, fmt.Errorf("failed to create circuit breaker: %w", err)
		}
	}

	return &Exporter{
		cb:     repOpts.cb,
		stats:  repOpts.stats,
		client: repOpts.client,
		url:    repOpts.url,
	}, nil
}

// RedactErrorURL receives an error pointer, and redacts the username and password.
// This function is borrowed from [url.Redacted], to prevent logging our failbotg username.
func RedactErrorURL(err error) {
	var ue *url.Error
	if errors.As(err, &ue) {
		u, uErr := url.Parse(ue.URL)
		if uErr != nil {
			// Couldn't parse the URL, so we can't redact it.
			return
		}
		u.User = url.UserPassword("xxxxx", "xxxxx")
		ue.URL = u.String()
	}
}

// Export exports the given data by making a HTTP Post request to the configured URL.
func (e *Exporter) Export(ctx context.Context, data []byte) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, e.url, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	_, err = e.cb.Execute(func() (interface{}, error) {
		res, err := e.client.Do(req)
		if err != nil {
			RedactErrorURL(err)
			return nil, err
		}
		if res != nil {
			defer res.Body.Close()
		}

		if res != nil && res.StatusCode != 201 {
			return nil, fmt.Errorf("failed to report the exception (http err: %d)", res.StatusCode)
		}

		return nil, nil
	})

	if errors.Is(err, gobreaker.ErrOpenState) {
		if e.stats != nil {
			e.stats.Counter("failbotg.needles.dropped", stats.Tags{"reason": "circuit_breaker_open", "intentional": "true"}, 1)
		}
	}

	return err
}
