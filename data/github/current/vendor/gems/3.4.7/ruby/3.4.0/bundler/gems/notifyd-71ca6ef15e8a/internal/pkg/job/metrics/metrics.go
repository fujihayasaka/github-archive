// Package metrics implements metrics for job processing.
package metrics

import (
	"context"

	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
)

// Metric keys
const (
	AqueductKey = "aqueduct.publish"
	HydroKey    = "hydro.publish"
)

const defaultKey = HydroKey

// SendConfig represents the configuration of a send operation
type SendConfig struct {
	Key string
}

// SendOption is a function that sets a send configuration
type SendOption func(*SendConfig)

// WithHydroKey sets the key to use when sending metrics to hydro
func WithHydroKey() SendOption {
	return func(cfg *SendConfig) {
		cfg.Key = HydroKey
	}
}

// WithAqueductKey sets the key to use when sending metrics to aqueduct
func WithAqueductKey() SendOption {
	return func(cfg *SendConfig) {
		cfg.Key = AqueductKey
	}
}

// PublisherMetrics knows how to send the relevant metrics related with a publisher. In case of
// error it can report it to the right places and make sure it appears properly where it needs to
// appear (logs and stats).
type PublisherMetrics struct {
	telem   *telemetry.Provider
	statter stats.Client
}

// BuildPublisherMetrics builds for wire setups
func BuildPublisherMetrics(telem *telemetry.Provider, statter stats.Client) (*PublisherMetrics, error) {
	return NewPublisherMetrics(telem, statter), nil
}

// NewPublisherMetrics creates a new PublisherMetrics
func NewPublisherMetrics(telem *telemetry.Provider, statter stats.Client) *PublisherMetrics {
	return &PublisherMetrics{
		telem:   telem,
		statter: statter,
	}
}

// Send sends the result of a publisher.Publish method call into the right metric destinations.
func (m *PublisherMetrics) Send(ctx context.Context, msgType string, err error, opts ...SendOption) {
	status := "succeeded"
	cfg := &SendConfig{Key: defaultKey}
	for _, opt := range opts {
		opt(cfg)
	}

	defer func() {
		m.statter.Counter(cfg.Key, stats.Tags{"status": status, "message_type": msgType}, 1)
	}()

	if err == nil {
		return
	}

	status = "failed"
	m.telem.Logger.WithContext(ctx).WithError(err).Error("error publishing notification")
}
