// Package root provides the CodeQL garbage collector
package root

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/olivere/elastic"
	"github.com/pkg/errors"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/jinzhu/gorm"
	"github.com/spf13/cobra"
)

const jobName = "turboscan-codeql-garbage-collector"
const DeleteOlderThanInDays = 1
const DefaultBatchSize = 100
const DefaultRepoBatchSize = 10000

var CodeQLGarbageCollectorCmd = &cobra.Command{
	Use:   "codeql-garbage-collector",
	Short: "Command codeql-garbage-collector garbage collects old CodeQL items such as runs",
	Long:  `Command codeql-garbage-collector garbage collects old CodeQL items such as runs.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		dryRun, err := cmd.Flags().GetBool("dry-run")
		if err != nil {
			return err
		}
		return cronjob.Execute(jobName, runCmd(cmd, dryRun))
	},
}

func init() {
	CodeQLGarbageCollectorCmd.Flags().Bool("dry-run", true, "When 'true' will print details of what would be deleted, but won't actually delete")
}

func runCmd(_ *cobra.Command, dryRun bool) cronjob.JobFunc {
	return func(ctx context.Context, cfg *config.Config) error {
		var cleaner app.Cleaner
		defer cleaner.Clean(ctx)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleaner.Append(closeDB)

		return run(db, ctx, dryRun, DefaultRepoBatchSize, DefaultBatchSize)
	}
}

// NB repoBatchSize must be > 1, otherwise the code cannot determine when it has finished processing a repo's runs
func run(db *gorm.DB, ctx context.Context, dryRun bool, repoBatchSize int, batchSize int) error {
	nErrors := 0
	ctx, cancel := context.WithTimeout(ctx, time.Hour*4)
	defer cancel()

	appctx.Logger(ctx).Info(fmt.Sprintf("%s started.", jobName))
	start := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("scheduled_job", stats.Tags{"job": jobName}, time.Since(start))

		appctx.Logger(ctx).Info(fmt.Sprintf("%s completed.", jobName))
	}()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	deleteOlderThan := sqltime.Now().Add(-time.Hour * (DeleteOlderThanInDays * 24))
	totalDeletions := 0
	startRepoId := 0
	largestRepoId, err := maxRepoId(db)
	if err != nil {
		return err
	}

	throttler := cfg.NewFrenoThrottler()
outerLoop:
	for startRepoId <= largestRepoId {
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

		endRepoId := startRepoId + repoBatchSize

		appctx.Logger(ctx).WithFields(
			kvp.Int("gh.turboscan.start_repo_id", startRepoId),
			kvp.Int("gh.turboscan.end_repo_id", endRepoId),
			kvp.Int("gh.turboscan.batch_size", batchSize),
		).Info("CodeQL garbage collection cron job running")

		// We want to keep the last steady run for each repo, regardless of age.
		rows, err := db.Raw(`
			SELECT max(id) FROM ts_codeql_runs
			WHERE repository_id >= ? AND repository_id <= ?
			AND run_type = ?
			AND status > ?
			GROUP BY repository_id
		`, startRepoId, endRepoId,
			ts.CodeqlRunType_STEADY,
			ts.CodeqlRunStatus_INPROGRESS).Rows()
		if err != nil {
			// We don't want the backoff to kick in in tests, since this
			// makes them slow and hard to debug in case of failure
			if testing.Testing() {
				return errors.Wrap(err, "failed to query for codeql runs to keep")
			}

			nErrors += 1
			appctx.Logger(ctx).WithError(err).Error("failed to query for codeql runs to keep")
			continue
		} else {
			nErrors = 0
		}

		idsToKeep := []ts.CodeqlRunID{}

		func() {
			defer rows.Close()

			var runID ts.CodeqlRunID
			for rows.Next() {
				err = rows.Scan(&runID)
				if err != nil {
					appctx.Logger(ctx).WithError(err).Info("Unexpected value returned from ID query.")
				} else {
					idsToKeep = append(idsToKeep, runID)
				}
			}
		}()

		rows, err = db.Raw(`
			SELECT id FROM ts_codeql_runs
			WHERE repository_id >= ? AND repository_id <= ?
			AND run_type = ?
			AND status > ?
			AND updated_at < ?
			AND id NOT IN (?)
			LIMIT ?;
		`, startRepoId, endRepoId,
			ts.CodeqlRunType_STEADY,
			ts.CodeqlRunStatus_INPROGRESS,
			deleteOlderThan,
			idsToKeep,
			batchSize).Rows()
		if err != nil {
			// We don't want the backoff to kick in in tests, since this
			// makes them slow and hard to debug in case of failure
			if testing.Testing() {
				return errors.Wrap(err, "failed to query for codeql runs to delete")
			}

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

		deletionsThisTime := len(idsForDeletion)

		// waitloop until freno clears us to clean if we're deleting
		if deletionsThisTime > 0 && !dryRun {
			canWrite := false
			for !canWrite {
				canWrite, err = throttler.CanWrite(ctx)
				if err != nil {
					appctx.Logger(ctx).WithError(err).Error("Error checking Freno")
					appctx.Stats(ctx).Counter("gc_analyses.freno_error", stats.Tags{}, 1)
					time.Sleep(1 * time.Second)
				}
				if !canWrite {
					appctx.Logger(ctx).Info("Waiting on Freno")
					appctx.Stats(ctx).Counter("gc_analyses.throttled", stats.Tags{}, 1)
					time.Sleep(1 * time.Second)
				}
			}
		}

		// Only move to the next repo range if the last result was exhaustive for the current range.
		// Or if we're in dry-run mode, when nothing is deleted.
		if dryRun || deletionsThisTime < batchSize {
			startRepoId = endRepoId + 1
		}

		if dryRun {
			appctx.Logger(ctx).Info(fmt.Sprintf("Would delete %d codeql runs\n", deletionsThisTime))
			if deletionsThisTime > 0 {
				n := 10
				if deletionsThisTime < n {
					n = deletionsThisTime
				}
				appctx.Logger(ctx).Info(fmt.Sprintf("First %d ids: %v", n, idsForDeletion[0:n]))
			}
			continue
		}

		if deletionsThisTime == 0 {
			continue
		}

		err = db.
			Where("id IN (?)", idsForDeletion).
			Delete(ts.CodeqlRun{}).
			Error
		if err != nil {
			// We don't want the backoff to kick in in tests, since this
			// makes them slow and hard to debug in case of failure
			if testing.Testing() {
				return errors.Wrap(err, "failed to delete codeql runs")
			}

			nErrors += 1
			appctx.Logger(ctx).WithError(err).Error("failed to delete codeql runs")
			continue
		} else {
			nErrors = 0
		}

		appctx.Stats(ctx).Counter(fmt.Sprintf("%s.codeql_runs_deleted", jobName), stats.Tags{}, int64(deletionsThisTime))
		totalDeletions += deletionsThisTime
	}
	appctx.Stats(ctx).Counter(fmt.Sprintf("%s.total_codeql_runs_deleted", jobName), stats.Tags{}, int64(totalDeletions))

	return nil
}

func maxRepoId(db *gorm.DB) (int, error) {
	var maxRepoId []int
	err := db.Table("ts_codeql_runs").Select("COALESCE(MAX(repository_id), 0) as max_id").Pluck("max_id", &maxRepoId).Error
	if err != nil {
		return 0, errors.Wrap(err, "failed to get max repo id")
	}
	return maxRepoId[0], nil
}
