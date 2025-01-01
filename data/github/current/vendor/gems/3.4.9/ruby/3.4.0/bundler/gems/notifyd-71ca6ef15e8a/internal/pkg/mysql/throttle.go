package mysql

import (
	"context"
	"fmt"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/telemetry"
	freno "github.com/github/go-freno-client"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
)

// Default timeout for the FrenoThrottler.Wait function
var defaultTimeout = 1500 * time.Millisecond

// FrenoConfig represents Freno configuration options
type FrenoConfig struct {
	FrenoEnabled bool   `config:"false,env=FRENO_ENABLED"`
	FrenoAddr    string `config:",env=FRENO_ADDR"`
	FrenoApp     string `config:"notifyd,env=FRENO_APP"`
	FrenoCluster string `config:"notifyd,env=FRENO_CLUSTER"`
}

// Throttler represents a throttler.
type Throttler interface {
	freno.Throttler
	Wait(context.Context) error
}

// throttleTimeoutError is a special error used to notify when waiting for a Throttler timeout.
// This error can be retriable by the WithRetries function.
type throttleTimeoutError struct {
	time.Duration
}

func (e *throttleTimeoutError) Error() string {
	return fmt.Sprintf("timeout after %s", e.String())
}

func newErrThrottleTimeout(duration time.Duration) *throttleTimeoutError {
	return &throttleTimeoutError{duration}
}

// frenoThrottler is a wrapper around freno's own throttlers
// It extends these throttlers with the Wait() function, which adds
// stats and logs around the wait operation.
type frenoThrottler struct {
	frenoThrottler freno.Throttler
	clock          clockpkg.Clock
	telem          *telemetry.Provider
	statter        stats.Client
}

func (t *frenoThrottler) CanWrite(ctx context.Context) (bool, error) {
	return t.frenoThrottler.CanWrite(ctx)
}

// Wait until it is possible to write or until the deadline of the context is up
func (t *frenoThrottler) Wait(ctx context.Context) error {
	var err error
	start := t.clock.Now()
	var finish time.Duration
	track := func() {
		tags := stats.Tags{"status": "success"}
		if err != nil {
			tags["status"] = "failed"
			var toutErr throttleTimeoutError
			if errors.Is(err, &toutErr) {
				tags["freno_error"] = "timeout"
			} else {
				tags["freno_error"] = "unknown"
			}
		}
		t.statter.DistributionMs("freno.throttle.time", tags, finish)
	}
	defer track()

	err = freno.WaitOnThrottler(ctx, t.frenoThrottler)
	finish = t.clock.Since(start)

	if err != nil {
		if errors.IsType[freno.ErrTimeout](err) {
			return errors.Wrap(newErrThrottleTimeout(finish), "freno timeout error")
		}

		err = errors.Wrap(err, "freno error")
		t.telem.Logger.WithContext(ctx).WithError(err).Error("throttling error while waiting on freno")
		return err
	}

	return nil
}

// NewFrenoThrottler creates a new FrenoThrottler
func NewFrenoThrottler(cfg FrenoConfig, clock clockpkg.Clock, telem *telemetry.Provider, statter stats.Client) Throttler {
	var throttler freno.Throttler

	if cfg.FrenoEnabled {
		throttler = freno.NewFrenoThrottler(cfg.FrenoAddr, cfg.FrenoApp, cfg.FrenoCluster)
	} else {
		throttler = freno.DefaultThrottler // passthrough implemenation
	}

	return &frenoThrottler{
		frenoThrottler: throttler,
		clock:          clock,
		telem:          telem,
		statter:        statter,
	}
}

// WithThrottling waits until the throttler allows it to execute the given operation callback
// If the given context doesn't have a deadline, a default timeout will be used (see `defaultTimeout`)
//
// Example: Using a timeout
//
//	throttler, err := mysql.NewThrottlerFromEnv(logger, statter)
//	if err != nil {
//		return nil, err
//	}
//	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
//	defer cancel()
//	result, err := mysql.WithThrottling(ctx, throttler, func (ctx context.Context) (sql.Result, error) {
//		return db.ExecContext(ctx, ...)
//	})
//
// Example: Using default timeout
//
//	throttler, err := mysql.NewThrottlerFromEnv(logger, statter)
//	if err != nil {
//		return nil, err
//	}
//	ctx = context.Background()
//	result, err := mysql.WithThrottling(ctx, throttler, func (ctx context.Context) (sql.Result, error) {
//		return db.ExecContext(ctx, ...)
//	})
func WithThrottling[T any](ctx context.Context, throttler Throttler, fn Callback[T]) (T, error) {
	timedCtx := ctx
	if _, ok := timedCtx.Deadline(); !ok {
		// Add a default timeout to prevent hangouts
		timed, cancel := context.WithTimeout(ctx, defaultTimeout)
		defer cancel()
		timedCtx = timed
	}

	if err := throttler.Wait(timedCtx); err != nil {
		var result T // zero value of T
		return result, err
	}

	return fn(ctx)
}

// WrapThrottling wraps an operation callback with a throttler so it waits until the throttler allows it
// Use this in combination with WithRetries
//
// Example:
//
//	throttler, err := mysql.NewThrottlerFromEnv(logger, statter)
//	if err != nil {
//		return nil, err
//	}
//	operation := mysql.WrapThrottling(throttler, func (ctx context.Context) (sql.Result, error) {
//		return db.ExecContext(ctx, ...)
//	})
//	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
//	defer cancel()
//	result, err := mysql.WithRetries(ctx, "select", logger, operation)
func WrapThrottling[T any](throttler Throttler, fn Callback[T]) Callback[T] {
	return func(ctx context.Context) (T, error) {
		return WithThrottling(ctx, throttler, fn)
	}
}
