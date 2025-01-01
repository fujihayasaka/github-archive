package mysql

import (
	"context"
	"database/sql/driver"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/go-sql-driver/mysql"

	"github.com/github/notifyd/internal/pkg/errors"
)

const (
	// maxRetries indicates the maximum retry attempts for an operation that keeps
	// failing with retriable errors.
	maxRetries = 2
)

type config struct {
	maxRetries    int
	operationName string
	retrier       func(error) bool
}

// RetryOption represents functions that modifyd the retry configuration.
type RetryOption func(*config)

// WithMaxRetries sets how many times the operation can be retried
//
// Default is: 2
func WithMaxRetries(attempts int) RetryOption {
	return func(c *config) {
		c.maxRetries = attempts
	}
}

// WithOperationName uses a name for the operation. This is only used for logging but it makes sense
// and it is recommended to add one so that the retries can be easily identified when they happen.
//
// Default is: mysql
func WithOperationName(name string) RetryOption {
	return func(c *config) {
		c.operationName = name
	}
}

// WithRetrier sets the function that will be used to decide if an error is retriable or not.
//
// Default is: mysql.IsRetriable, which looks for common mysql retriable errors like timeouts,
// replication throttling, etc.
func WithRetrier(retrier func(error) bool) RetryOption {
	return func(c *config) {
		c.retrier = retrier
	}
}

func newConfig(opts ...RetryOption) *config {
	c := &config{}

	defaults := []RetryOption{
		WithMaxRetries(maxRetries),
		WithOperationName("mysql"),
		WithRetrier(IsRetriable),
	}

	opts = append(defaults, opts...)

	for _, opt := range opts {
		opt(c)
	}

	return c
}

// WithRetries performs the provided operation function once, and then retries it up to the
// configured number or retries.
//
// It retries when it finds an error that can be detected as retriable. By default that's
// determined by IsRetriable.
//
// It expects the operation function to return a value, along with the error. If the function
// doesn't return any value, wrap it with ToCallback to adapt it to WithRetries signature
//
// It logs most cases for further analysis.
//
// Example: Returning values
//
//	result, err := mysql.WithRetries(ctx, clock, func (ctx context.Context) (sql.Result, error) {
//		return db.ExecContext(ctx, ...)
//	})
//
// Example: Without returning values
//
//	_, err := mysql.WithRetries(ctx, clock, ToCallback(func (ctx context.Context) error {
//		return errors.New("Oh no!")
//	}))
func WithRetries[T any](ctx context.Context, clock clockpkg.Clock, telem *telemetry.Provider, operation Callback[T], opts ...RetryOption) (T, error) {
	cfg := newConfig(opts...)
	start := clock.Now()
	var result T
	var err error
	attempt := 0
	logger := telem.Logger.WithContext(ctx)
	for attempt <= maxRetries {
		attempt++
		result, err = operation(ctx)

		fields := toFields(attempt, cfg.operationName, clock.Since(start))
		switch {
		case err == nil:
			// it worked!
			logger.WithFields(fields...).Info("WithRetries succeeded")
			return result, nil
		case cfg.retrier(err):
			// stay in the loop
			logger.WithFields(fields...).Info("WithRetries needed to retry")
			continue
		default:
			// Unexpected error happened
			logger.WithFields(fields...).WithError(err).Error("WithRetries failed")
			return result, err
		}
	}

	// We ran out of retries
	logger.WithFields(toFields(attempt, cfg.operationName, clock.Since(start))...).WithError(err).Error("WithRetries ran out of retries")
	return result, errors.Wrap(err, "WithRetries ran out of retries")
}

func toFields(attempt int, operationName string, duration time.Duration) []kvp.Field {
	return []kvp.Field{
		kvp.String("code.function", operationName),
		kvp.Int("gh.notifyd.retry.attempt", attempt),
		kvp.Int("gh.notifyd.retry.attempts", maxRetries),
		kvp.Duration("gh.duration_ms", duration),
	}
}

// IsRetriable detects errors that are normally retriable from the mysql perspective.
//
// Those errors are: Invalid connections, replication throttling...
func IsRetriable(err error) bool {
	if errors.Is(err, mysql.ErrInvalidConn) || errors.Is(err, driver.ErrBadConn) {
		return true
	}

	// Server shutdown, see https://github.com/github/notifyd/issues/4154.
	var mysqlError *mysql.MySQLError
	if errors.As(err, &mysqlError) && mysqlError.Number == 1053 {
		return true
	}

	var timeout *throttleTimeoutError
	return errors.As(err, &timeout)
}
