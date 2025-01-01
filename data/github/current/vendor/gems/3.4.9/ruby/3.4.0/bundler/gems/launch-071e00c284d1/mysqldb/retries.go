package mysqldb

import (
	"context"
	"database/sql"
	"strconv"

	"github.com/cenkalti/backoff/v4"
	"github.com/go-sql-driver/mysql"

	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
)

const (
	ServerShutdownErrorCode = 1053 // 1053: Server shutdown in progress
	deadlockErrorCode       = 1213 // 1213: Deadlock found when trying to get lock; try restarting transaction
)

// WithDeadlockRetry runs a function returning a the result of a sql package operation, and retries
// any deadlocks or server shutdown errors with exponential backoff.
// MySQL is designed with the principle that deadlocks are expected and safe to retry.
// See: https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks.html
func WithDeadlockRetry(ctx context.Context, operation string, statter statter.Statter, fn func() (sql.Result, error)) (sql.Result, error) {
	var result sql.Result
	var attempt int
	err := backoff.Retry(func() error {
		attempt++
		r, err := fn()
		if err == nil {
			result = r
			return nil
		}

		// Retry on invalid connections too
		if err == mysql.ErrInvalidConn {
			if statter != nil {
				statter.Counter(ctx, metrickeys.MySQLRetries, map[string]string{
					metrickeys.OperationName: operation,
					"attempt":                strconv.Itoa(attempt),
				}, 1)
			}
			return err
		}

		if driverErr, ok := err.(*mysql.MySQLError); ok {
			if driverErr.Number == deadlockErrorCode {
				if statter != nil {
					statter.Counter(ctx, metrickeys.DeadlockRetry, map[string]string{
						metrickeys.OperationName: operation,
						"attempt":                strconv.Itoa(attempt),
					}, 1)
				}

				return driverErr
			}

			if driverErr.Number == ServerShutdownErrorCode {
				if statter != nil {
					statter.Counter(ctx, metrickeys.ServerShutdownRetry, map[string]string{
						metrickeys.OperationName: operation,
						"attempt":                strconv.Itoa(attempt),
					}, 1)
				}

				return driverErr
			}
		}

		return backoff.Permanent(err)
	}, backoff.NewExponentialBackOff())
	return result, err
}
