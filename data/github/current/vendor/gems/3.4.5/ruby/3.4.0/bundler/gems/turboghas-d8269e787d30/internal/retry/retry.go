// Package retry contains a higher order function which will retry a handler on errors.
package retry

import (
	"context"
	"strconv"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/pkg/errors"
)

// JobFunc is a hydro or aqueduct handler function
type JobFunc[Job any] func(ctx context.Context, job Job) error

// Handler will attempt to process a message, notifying if there are any errors
// and if it had to eventually give up
func Handler[Payload any](next JobFunc[Payload], backoffFunc func() backoff.BackOff) JobFunc[Payload] {
	return func(ctx context.Context, v Payload) error {
		var attempt int64

		if retryErr := fromctx.Retry(ctx, func() (err error) {
			then := time.Now()
			defer func() {
				statter := fromctx.Statter.Value(ctx)
				tags := stats.Tags{"error": strconv.FormatBool(err != nil)}
				statter.Timing("duration", tags, time.Since(then))
				statter.Gauge("attempts", tags, attempt)
			}()

			attempt += 1

			defer func() {
				if r := recover(); r != nil {
					var innerErr error
					if panicErr, ok := r.(error); ok {
						innerErr = errors.Wrap(panicErr, "panic")
					} else {
						innerErr = errors.Errorf("panic: %s", r)
					}

					if err == nil {
						err = innerErr
					}
				}
			}()

			return next(ctx, v)
		}, backoffFunc()); retryErr != nil {
			if !fromctx.IsShuttingDown(ctx) {
				fromctx.Logger.Value(ctx).WithError(retryErr).Error("retry handler gave up")
				return retryErr
			}
		}

		return nil
	}
}
