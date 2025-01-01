package upgrades

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
)

func readValue[T any](ctx context.Context, db *throttleDB, sql string, args ...interface{}) (T, error) {
	var result T

	logger := appctx.Logger(ctx).WithFields(
		kvp.String("gh.turboscan.query", sql),
	)

	for ctx.Err() == nil {
		logger.Info("Executing statement")
		row := db.QueryRowContext(ctx, sql, args...)
		if err := row.Scan(&result); err != nil {
			logger.WithError(err).Error("error reading value")
			time.Sleep(1 * time.Second)
			continue
		}
		return result, nil
	}
	return result, ctx.Err()
}

type uint64Range struct {
	min uint64
	max uint64
}

func getIDRange(ctx context.Context, env *Env, opts *Opts, table string) (uint64Range, error) {
	result := uint64Range{
		min: opts.MinID,
		max: opts.MaxID,
	}

	quotedTable := "`" + strings.ReplaceAll(table, "`", "``") + "`"

	var err error

	if result.min == 0 {
		result.min, err = readValue[uint64](ctx, env.db, fmt.Sprintf("SELECT COALESCE(MIN(id),0) FROM %s LIMIT 1", quotedTable))
	}

	if err == nil && result.max == 0 {
		result.max, err = readValue[uint64](ctx, env.db, fmt.Sprintf("SELECT COALESCE(MAX(id),0) FROM %s LIMIT 1", quotedTable))
	}

	return result, err
}
