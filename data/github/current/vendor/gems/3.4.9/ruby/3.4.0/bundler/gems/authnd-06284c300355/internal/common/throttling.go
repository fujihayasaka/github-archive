package common

import (
	"context"

	freno "github.com/github/go-freno-client"
	"github.com/pkg/errors"
)

// WriteThrottledError an error return when writes to the configured mysql cluster are throttled by Freno.
var WriteThrottledError = errors.New("write throttled")

// WithThrottling executes the given 'do' function provided
func WithThrottling(ctx context.Context, throttler freno.Throttler, do func() error) error {
	canWrite, err := throttler.CanWrite(ctx)
	if err != nil {
		return errors.Wrap(err, "error checking freno throttling status")
	}

	if canWrite {
		return do()
	}
	return WriteThrottledError
}
