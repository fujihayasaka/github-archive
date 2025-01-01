// Package retry provides a simple way to retry a function with backoff.
// It is a wrapper around the backoff package that logs the number of attempts.
package retry

import (
	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// BackoffPolicyFn is a function that returns a backoff policy
type BackoffPolicyFn func() backoff.BackOff

// Retry decorates a backoff.Retry function to log the number of retried attempts.
func Retry(retryFn backoff.Operation, b backoff.BackOff, logger log.Logger) error {
	var attempts int
	fn := func() error {
		err := retryFn()
		if err == nil {
			return nil
		}
		attempts++
		logger.WithError(err).WithFields(kvp.Int("attempts", attempts)).Warn("retrying")
		return err
	}
	return backoff.Retry(fn, b)
}
