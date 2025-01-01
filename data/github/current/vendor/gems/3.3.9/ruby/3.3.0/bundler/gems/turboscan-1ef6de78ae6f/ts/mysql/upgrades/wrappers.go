package upgrades

import (
	"context"
	"database/sql/driver"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"fmt"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
)

type heartbeatFunc = func()

func withTimeout(timeout time.Duration, fn func(context.Context, heartbeatFunc) error) func(context.Context) error {
	return func(parent context.Context) error {
		if timeout <= 0 {
			return fn(parent, func() {})
		}
		ctx, cancelParent := context.WithCancel(parent)

		timer := time.AfterFunc(timeout, cancelParent)
		defer func() {
			cancelParent()
			timer.Stop()
		}()
		heartbeatFn := func() {
			timer.Reset(timeout)
		}
		return fn(ctx, heartbeatFn)
	}
}

func withBatchedLoop(ctx context.Context, heartbeatFn heartbeatFunc, r uint64Range, step uint64, fn func(ctx context.Context, start uint64, end uint64) error) error {
	if step == 0 {
		step = 1
	}
	totalIds := r.max - r.min + 1

	// equivalent to ceil(totalIDs / step) but avoids conversion to floating point
	partitions := 1 + (totalIds-1)/step
	appctx.Logger(ctx).Info(fmt.Sprintf("Will run update query on id range %d-%d in %d partitions (%d rows)",
		r.min,
		r.max,
		partitions,
		totalIds))

	startTime := time.Now()
	i := 1
	for start := r.min; start <= r.max; start += step {
		end := start + step - 1
		if end > r.max {
			end = r.max
		}

		batchStartTime := time.Now()
		err := errors.Wrap(fn(ctx, start, end), fmt.Sprintf("withBatchedLoop partition %d-%d failed", start, end))
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("error executing batched transition")
			return err
		}
		if heartbeatFn != nil {
			heartbeatFn()
		}
		batchTimeTaken := time.Since(batchStartTime)
		totalTimeTaken := time.Since(startTime)
		idsProcessed := end - r.min + 1

		remainingTimeEstimate := time.Duration(float64(totalTimeTaken)/(float64(idsProcessed)/float64(totalIds))) - totalTimeTaken

		appctx.Logger(ctx).Info(fmt.Sprintf("Partition %d/%d (%.2f%%): id range %d-%d (batch time: %.2fs, total time so far: %.2fh, estimated time remaining: %.2fh)",
			i,
			partitions,
			100.0*float64(idsProcessed)/float64(totalIds),
			start,
			end,
			batchTimeTaken.Seconds(),
			totalTimeTaken.Hours(),
			remainingTimeEstimate.Hours()))

		i++
	}

	return nil
}

// AnyMySQLErrorNumber returns true if the error is a MySQLError with a number that matches any of the oneOf
// arguments.
func AnyMySQLErrorNumber(err error, oneOf ...uint16) bool {
	var mysqlErr *mysql.MySQLError

	if err != nil && errors.As(err, &mysqlErr) {
		for _, code := range oneOf {
			if mysqlErr.Number == code {
				return true
			}
		}
	}

	return false
}

// DynamicRetry will withRetry over a partition and reduce the step size automatically if there is an SQL timeout error.
// Throttle will be called before each attempt.
func withDynamicRetry(ctx context.Context, delay time.Duration, minId, maxId uint64, fn func(start, end uint64) error) error {
	// we will attempt to update 100% of the rows in this partition, however if this causes a timeout we will
	// reduce the step size, halving it on each withRetry attempt until it reaches 1
	step := (maxId - minId) + 1

	return withRetry(ctx, delay, func(attempt int) error {
		// during normal operation this will loop once with a start and end that are
		// the same as minId and maxId above
		for start := minId; start <= maxId; start += step {
			end := start + step - 1
			if end > maxId {
				end = maxId
			}

			err := fn(start, end)

			if err != nil {
				// if we have a timeout error, reduce step size to try and make progress
				// make at least two attempts before starting to reduce the partition size in case the error
				// is due to load and the default step size would have worked
				// 1317: Killed by mysqld: ER_QUERY_INTERRUPTED
				// 2013: Canceled by Vitess due to -queryserver-config-query-timeout
				// 1153: Packet bigger than max size allowed
				if AnyMySQLErrorNumber(err, 1317, 2013, 1153) {
					if attempt > 1 && step > 1 {
						appctx.Logger(ctx).Info(
							"reducing partition size to try and make progress",
							kvp.Int("attempt", attempt),
							kvp.Uint64("step", step),
						)
						// ensure there are twice as many partitions next time
						step = step/2 + step%2
					}

					// force a retry even if withRetry would not normally retry the error
					return stderrors.Join(err, errRetry)
				}

				return err
			}
		}

		return nil
	})
}

func isTemporaryError(err error) bool {
	// 1317: Killed by mysqld: ER_QUERY_INTERRUPTED
	// 2013: Canceled by Vitess due to -queryserver-config-query-timeout
	// 1053: Server shutdown in progress
	return errors.Is(err, driver.ErrBadConn) || errors.Is(err, mysql.ErrInvalidConn) || AnyMySQLErrorNumber(err, 1317, 2013, 1053)
}

var errRetry = errors.New("retry")

func withRetry(ctx context.Context, delay time.Duration, fn func(attempt int) error) error {
	var attempt int
	for ctx.Err() == nil {
		attempt += 1

		if delay > 0 {
			appctx.Logger(ctx).Info(fmt.Sprintf("Waiting %d seconds...", delay))
			time.Sleep(delay)
		}

		err := fn(attempt)

		// on the first attempt if we see an error that doesn't look temporary we should retry on the chance
		// we make progress rather than blocking the GHES upgrade
		if err != nil && (attempt == 1 || errors.Is(err, errRetry) || isTemporaryError(err)) {
			appctx.Logger(ctx).WithError(err).Error("failed to execute function, retrying")

			time.Sleep(delay)

			continue
		}

		return err
	}

	return ctx.Err()
}
