package aqueduct

import (
	"errors"
	"fmt"
	"time"
)

const (
	defaultHeartbeatInterval = 60 * time.Second
	defaultHeartbeatTimeout  = 5 * time.Second
)

// HeartbeatConfig configures how a Worker handles heartbeating for a job being
// processed.
//
// It must be created by NewHeartbeatConfig.
type HeartbeatConfig struct {
	interval time.Duration
	timeout  time.Duration
}

// HeartbeatOption is the functional option type for configuring a
// HeartbeatConfig.
type HeartbeatOption func(*HeartbeatConfig) error

// WithHeartbeatInterval is the HeartbeatOption that sets the interval that
// heartbeats should occur. It returns an error for negative or zero durations.
func WithHeartbeatInterval(d time.Duration) HeartbeatOption {
	return func(h *HeartbeatConfig) error {
		if d <= 0 {
			return errors.New("heartbeat interval config must be a positive value")
		}
		h.interval = d
		return nil
	}
}

// WithHeartbeatTimeout is the HeartbeatOption that sets the duration in which
// a heartbeat is considered logically timed out, including time spent sending
// requests and any retries. It returns an error for negative or zero durations.
func WithHeartbeatTimeout(d time.Duration) HeartbeatOption {
	return func(h *HeartbeatConfig) error {
		if d <= 0 {
			return errors.New("heartbeat timeout config must be a positive value")
		}
		h.timeout = d
		return nil
	}
}

// NewHeartbeatConfig returns a new HeartbeatConfig configured with the
// provided options.
func NewHeartbeatConfig(opts ...HeartbeatOption) (*HeartbeatConfig, error) {
	h := &HeartbeatConfig{
		interval: defaultHeartbeatInterval,
		timeout:  defaultHeartbeatTimeout,
	}

	for _, o := range opts {
		if err := o(h); err != nil {
			return nil, fmt.Errorf("applying heartbeat option: %w", err)
		}
	}
	return h, nil
}
