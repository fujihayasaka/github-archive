package upgrades

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/turboscan/ts/appctx"
)

type throttleDB struct {
	*sql.DB
}

func (r *throttleDB) ExecContext(ctx context.Context, stmt string, args ...any) (sql.Result, error) {
	err := r.Throttle(ctx)
	if err != nil {
		return nil, err
	}

	return r.DB.ExecContext(ctx, stmt, args...)
}

// Throttle waits until Freno says it is ok to use the database.
// It will return ctx.Err() if ctx is cancelled.
func (r *throttleDB) Throttle(ctx context.Context) error {
	for ctx.Err() == nil {
		can, err := appctx.Throttler(ctx).CanWrite(ctx)

		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("error checking Freno")
			time.Sleep(1 * time.Second)
			continue
		}

		if !can {
			appctx.Logger(ctx).Info("Waiting on Freno")
			time.Sleep(1 * time.Second)
			continue
		}

		break
	}

	return ctx.Err()
}
