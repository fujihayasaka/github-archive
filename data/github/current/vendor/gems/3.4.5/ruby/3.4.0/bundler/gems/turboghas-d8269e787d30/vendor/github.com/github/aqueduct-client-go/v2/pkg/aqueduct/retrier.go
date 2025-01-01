package aqueduct

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/avast/retry-go"
)

// RetrierConfig is used to control how a retryable request should be handled
// on failure.
//
// It must be created using NewRetrierConfig.
type RetrierConfig struct {
	maxRetries    uint
	lastErrorOnly bool
	delay         time.Duration
	maxDelay      time.Duration
}

// RetryOption is the functional option type for configuring a RetrierConfig.
type RetryOption func(config *RetrierConfig) error

// WithMaxRetries is the RetryOption that sets the max amount of times a failed
// request will be retried. A zero value disables retry behavior.
func WithMaxRetries(n uint) RetryOption {
	return func(r *RetrierConfig) error {
		r.maxRetries = n
		return nil
	}
}

// WithLastErrorOnly is the RetryOption that controls how the error from a
// failed final attempt should be returned. When false only the last error will
// be returned. When true all attempt errors will be aggregated and returned.
func WithLastErrorOnly(b bool) RetryOption {
	return func(r *RetrierConfig) error {
		r.lastErrorOnly = b
		return nil
	}
}

// WithInitialDelay is the RetryOption that sets the initial delay which
// increases exponentially with each attempt after the first retry. It returns
// an error when negative.
func WithInitialDelay(d time.Duration) RetryOption {
	return func(r *RetrierConfig) error {
		if d < 0 {
			return errors.New("delay must be non-negative")
		}
		r.delay = d
		return nil
	}
}

// WithMaxDelay is the RetryOption that limits the max delay between retry
// attempts. A zero duration disables the limit. It returns an error when
// negative.
func WithMaxDelay(d time.Duration) RetryOption {
	return func(r *RetrierConfig) error {
		if d < 0 {
			return errors.New("max delay must be non-negative")
		}
		r.maxDelay = d
		return nil
	}
}

const (
	defaultMaxRetries    uint = 4
	defaultLastErrorOnly      = true
	defaultDelay              = 1 * time.Second
	defaultMaxDelay           = 10 * time.Second
)

// NewRetrierConfig returns a new RetrierConfig configured with any provided
// RetryOption.
//
// The default RetrierConfig uses an exponetial backoff delay with:
//   - Max Retries: 4
//   - Last Error Only: true
//   - Delay: 1s
//   - Max Delay: 10s
func NewRetrierConfig(opts ...RetryOption) (*RetrierConfig, error) {
	r := &RetrierConfig{
		maxRetries:    defaultMaxRetries,
		lastErrorOnly: defaultLastErrorOnly,
		delay:         defaultDelay,
		maxDelay:      defaultMaxDelay,
	}
	for _, o := range opts {
		if err := o(r); err != nil {
			return nil, fmt.Errorf("applying retrier option: %w", err)
		}
	}
	return r, nil
}

func (r *RetrierConfig) opts(ctx context.Context) []retry.Option {
	// retry-go considers that retry.Attempts includes the initial execution as
	// an "attempt", i.e. retry.Attempts(0) will never execute a func. This is
	// confusing when used in the context of "retry".
	//
	// To not propagate this unintuitive behavior we explicitly use
	// "maxRetries" and account for the difference.
	attempts := r.maxRetries + 1

	return []retry.Option{
		retry.DelayType(retry.BackOffDelay),
		retry.Attempts(attempts),
		retry.LastErrorOnly(r.lastErrorOnly),
		retry.Delay(r.delay),
		retry.MaxDelay(r.maxDelay),
		retry.Context(ctx),
	}
}
