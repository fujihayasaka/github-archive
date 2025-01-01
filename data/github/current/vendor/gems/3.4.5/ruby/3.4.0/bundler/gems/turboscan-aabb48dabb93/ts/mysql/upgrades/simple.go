package upgrades

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
)

// Simple will run queries repeatedly in a
// loop, terminating when zero rows are modified as a result of a query. As a
// result you must be careful to include LIMIT clauses on your UPDATE statements
// and to use INSERT IGNORE or similar techniques.
//
// If the transition is defined with a step size then it will be passed in as a parameter to be given to LIMIT
// this way it can be adjusted dynamically using command-line options.
// Use a step size of zero to disable this behaviour.
//
// This type of transition is recommended only for small tables or when the
// columns used in the WHERE clause are indexed. If this is not the case
// repeated executions requiring a table scan will likely start to time out.
//
// Example statement:
//
//	UPDATE foo SET bar = baz + 1 WHERE bar < baz LIMIT ?
func (t *transitions) Simple(stmts ...string) Builder {
	defaultStep := t.step

	return t.add(func(env *Env, opts *Opts) (func(ctx context.Context) error, error) {
		return withTimeout(opts.Timeout, func(ctx context.Context, heartbeatFn heartbeatFunc) error {
			startTime := time.Now()

			step := defaultStep
			// if this transition has a step, allow it to be overridden
			if defaultStep != 0 && opts.Step > 0 {
				step = opts.Step
			}

			for _, stmt := range stmts {
				var totalRowsAffected int64 = 0

				for i := 1; ; i++ {
					if heartbeatFn != nil {
						heartbeatFn()
					}

					var args []any

					if step > 0 {
						args = append(args, step)
					}

					var result sql.Result
					err := withRetry(ctx, opts.Delay, func(attempt int) error {
						var innerErr error
						result, innerErr = env.db.ExecContext(ctx, stmt, args...)
						return innerErr
					})
					if err != nil {
						appctx.Logger(ctx).WithError(err).Error("error executing transition query")
						time.Sleep(opts.Delay)
						return err
					}

					rowsAffected, err := result.RowsAffected()
					if err != nil {
						appctx.Logger(ctx).WithError(err).Error("error getting rows affected")
						time.Sleep(opts.Delay)
						continue
					}

					totalRowsAffected += rowsAffected
					appctx.Logger(ctx).Info(
						"Query execution complete",
						kvp.String("gh.turboscan.query", stmt),
						kvp.Int("gh.turboscan.attempts", i),
						kvp.String("gh.turboscan.total_duration", fmt.Sprintf("%v", time.Since(startTime))),
						kvp.Int64("gh.turboscan.rows_affected", rowsAffected),
						kvp.Int64("gh.turboscan.total_rows_affected", totalRowsAffected))

					if rowsAffected == 0 {
						// We are done!
						break
					}
				}
			}
			return nil
		}), nil
	})
}
