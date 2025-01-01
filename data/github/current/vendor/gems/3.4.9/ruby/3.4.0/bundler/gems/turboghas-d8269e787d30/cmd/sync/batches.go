package main

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/pkg/errors"
)

func retryInBatches(ctx context.Context, db *mysql_dual.Connection, table string, step uint64, next func(ctx context.Context, start, end uint64) error) (err error) {
	logger := fromctx.Logger.Value(ctx).WithFields(kvp.String("table", table))
	defer func() {
		logger.Info("finished")
	}()

	startTime := time.Now()

	quotedTable := "`" + strings.ReplaceAll(table, "`", "``") + "`"

	last, err := Scan[uint64](ctx, db.Replica, `SELECT COALESCE(MAX(id), 0) FROM `+quotedTable)
	if err != nil {
		return err
	}

	start, err := Scan[uint64](ctx, db.Replica, `SELECT COALESCE(MIN(id), 0) FROM `+quotedTable)
	if err != nil {
		return errors.Wrap(err, "failed to get start")
	}

	if last == 0 {
		return nil
	}

	for start <= last {
		batchStartTime := time.Now()

		end, err := Scan[uint64](ctx, db.Replica, `SELECT id FROM `+quotedTable+` WHERE id >= ? ORDER BY id ASC LIMIT ?, 1`, start, step-1)
		if err != nil {
			if !errors.Is(err, sql.ErrNoRows) {
				return errors.Wrap(err, "failed to get end")
			}
			end = last
		}

		if err := fromctx.Retry(ctx, func() error {
			totalTimeTaken := time.Since(startTime)
			progress := float64(start) / float64(last)

			remainingTimeEstimate := time.Duration(float64(totalTimeTaken)/progress) - totalTimeTaken
			logger := logger.WithFields(
				kvp.Uint64("start", start),
				kvp.Uint64("end", end),
				kvp.String("progress", fmt.Sprintf("%d/%d", start, last)),
				kvp.String("batch_time", time.Since(batchStartTime).String()),
				kvp.String("total_time", totalTimeTaken.String()),
				kvp.String("remaining_time", remainingTimeEstimate.String()),
			)
			logger.Info("starting partition")
			fromctx.Statter.Value(ctx).Gauge("sync_progress", stats.Tags{"table": table}, int64(math.Ceil(progress*100.0)))

			err := next(fromctx.Logger.With(ctx, logger), start, end)
			if err != nil {
				// halve the batch size on an error
				end = start + ((end - start) / 2.0)
			}
			return err
		}, NewShortBackOff()); err != nil {
			return err
		}

		start = end + 1
	}

	return nil
}
