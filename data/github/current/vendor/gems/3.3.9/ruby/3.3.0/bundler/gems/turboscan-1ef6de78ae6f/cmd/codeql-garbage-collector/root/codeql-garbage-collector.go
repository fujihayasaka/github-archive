// Package root provides the CodeQL garbage collector
package root

import (
	"context"
	"fmt"
	"time"

	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/olivere/elastic"
	"github.com/pkg/errors"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	"github.com/jinzhu/gorm"
	"github.com/spf13/cobra"
)

const jobName = "turboscan-codeql-garbage-collector"
const DeleteOlderThanInDays = 30
const DefaultBatchSize = 100

var CodeQLGarbageCollectorCmd = &cobra.Command{
	Use:   "codeql-garbage-collector",
	Short: "Command codeql-garbage-collector garbage collects old CodeQL items such as runs",
	Long:  `Command codeql-garbage-collector garbage collects old CodeQL items such as runs.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute(jobName, runCmd(cmd))
	},
}

func runCmd(_ *cobra.Command) cronjob.JobFunc {
	return func(ctx context.Context, cfg *config.Config) error {
		var cleaner app.Cleaner
		defer cleaner.Clean(ctx)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleaner.Append(closeDB)

		return run(db, ctx, DefaultBatchSize)
	}
}

func run(db *gorm.DB, ctx context.Context, batchSize int) error {
	nErrors := 0
	ctx, cancel := context.WithTimeout(ctx, time.Hour*4)
	defer cancel()

	appctx.Logger(ctx).Info(fmt.Sprintf("%s started.", jobName))
	start := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("scheduled_job", stats.Tags{"job": jobName}, time.Since(start))

		appctx.Logger(ctx).Info(fmt.Sprintf("%s completed.", jobName))
	}()

	deleteOlderThan := sqltime.Now().Add(-time.Hour * (DeleteOlderThanInDays * 24))
	numDeletions := 0
outerLoop:
	for {
		select {
		case <-ctx.Done():
			// we've been running for long enough, stop now and it'll run again as it's a cron job
			appctx.Logger(ctx).Info("CodeQL garbage collection cron job has had its context cancelled, exiting.")
			break outerLoop
		default:
		}
		backoff, retry := elastic.NewExponentialBackoff(10*time.Second, 5*time.Minute).Next(nErrors - 1)
		if !retry {
			return errors.New("Aborting due to error backoff maxTimeout exceeded.")
		}
		// the backoff function gives us a value for the -1 case, so ignore it
		if nErrors > 0 {
			time.Sleep(backoff)
		}

		appctx.Logger(ctx).Info(fmt.Sprintf("CodeQL garbage collection cron job running for batch size %d", batchSize))

		// NOTE: This query only returns runs that are old enough to be garbage-
		// collected. The newest of these for each repository is not garbage-
		// collected, as we need to ensure that at least one run is available
		// for every repository.
		rows, err := db.Raw(`
			SELECT id FROM ts_codeql_runs AS outer_query
			WHERE run_type = ?
			AND status > ?
			AND id < (
				SELECT MAX(id) FROM ts_codeql_runs WHERE status > ? AND repository_id = outer_query.repository_id
			)
			AND updated_at < ?
			LIMIT ?;
		`, ts.CodeqlRunType_STEADY, ts.CodeqlRunStatus_INPROGRESS, ts.CodeqlRunStatus_INPROGRESS, deleteOlderThan, batchSize).Rows()
		if err != nil {
			nErrors += 1
			appctx.Logger(ctx).WithError(err).Error("failed to query for codeql runs to delete")
			continue
		} else {
			nErrors = 0
		}

		idsForDeletion := []ts.CodeqlRunID{}

		// wrap in a function to ensure defer'ed cleanup
		// happens every time round the loop
		func() {
			defer rows.Close()

			var runID ts.CodeqlRunID
			for rows.Next() {
				err = rows.Scan(&runID)
				if err != nil {
					appctx.Logger(ctx).WithError(err).Info("Unexpected value returned from ID query.")
				} else {
					idsForDeletion = append(idsForDeletion, runID)
				}
			}
		}()

		numDeletions += len(idsForDeletion)
		appctx.Stats(ctx).Counter(fmt.Sprintf("%s.codeql_runs_deleted", jobName), stats.Tags{}, int64(len(idsForDeletion)))

		err = db.
			Where("id IN (?)", idsForDeletion).
			Delete(ts.CodeqlRun{}).
			Error
		if err != nil {
			nErrors += 1
			appctx.Logger(ctx).WithError(err).Error("failed to delete codeql runs")
			continue
		} else {
			nErrors = 0
		}

		if len(idsForDeletion) < batchSize {
			// no more runs to process, we're done!
			appctx.Logger(ctx).Info("CodeQL garbage collection cron job has no more runs to process, exiting.")
			break
		}
	}
	appctx.Stats(ctx).Counter(fmt.Sprintf("%s.total_codeql_runs_deleted", jobName), stats.Tags{}, int64(numDeletions))

	return nil
}
