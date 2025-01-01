// Package root represents a command that checks for stale CodeQL validation runs and makes sure
// the corresponding repositories are offboarded. This prevents the repos that have tried to enable
// Code Scanning via Default Setup from being stuck in limbo when we couldn't get a conclusion for
// the validation run.
package root

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/hydro/publishers"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/managedanalyses"
	maservice "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/spf13/cobra"
)

const jobName = "turboscan-stale-validation-runs"

var StaleValidationRunsCmd = &cobra.Command{
	Use:   "stale-validation-runs",
	Short: "Checks for stale CodeQL validation runs and makes sure the corresponding repositories are offboarded",
	Long: `Checks for stale CodeQL validation runs and makes sure the corresponding repositories are offboarded.
This prevents the repos that have tried to enable Code Scanning via Default Setup from being stuck in limbo
when we couldn't get a conclusion for the validation run.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute(jobName, func(ctx context.Context, cfg *config.Config) error {
			return realMain(ctx, cmd, cfg)
		})
	},
}

const BATCH_SIZE = 1000

type arguments struct {
	horizon       uint64
	repoID        uint64
	workflowRunID uint64
}

func parseArgs(cmd *cobra.Command) (*arguments, error) {
	var args arguments
	var err error
	args.horizon, err = cmd.Flags().GetUint64("horizon")
	if err != nil {
		return nil, err
	}
	args.repoID, err = cmd.Flags().GetUint64("repoID")
	if err != nil {
		return nil, err
	}
	args.workflowRunID, err = cmd.Flags().GetUint64("workflowRunID")
	if err != nil {
		return nil, err
	}
	return &args, nil
}

func realMain(ctx context.Context, cmd *cobra.Command, cfg *config.Config) error {
	appctx.Logger(ctx).Info("stale-validation-runs started.")
	startTime := time.Now()
	defer func() {
		duration := time.Since(startTime)
		appctx.Stats(ctx).DistributionMs("scheduled_job", stats.Tags{"job": "stale-validation-runs"}, duration)
		appctx.Logger(ctx).Info("stale-validation-runs completed.")
	}()

	args, err := parseArgs(cmd)
	if err != nil {
		return err
	}

	var cleaner app.Cleaner
	defer cleaner.Clean(ctx)

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return err
	}
	cleaner.Append(closeDB)

	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)
	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return err
	}

	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return err
	}
	cleaner.Append(publisher.Close)

	maDB := managedanalysis.NewService(db, publisher)
	maAPI, err := cfg.NewManagedAnalysesAPI(appctx.Logger(ctx), appctx.Stats(ctx))
	if err != nil {
		return err
	}

	repoAPI, err := cfg.NewRepositoryAPI(appctx.Logger(ctx), appctx.Stats(ctx))
	if err != nil {
		return err
	}
	repoService := repository.NewService(db)

	ma := &maservice.ManagedAnalyses{
		GitHubTwirpApiClient: maAPI,
		DataService:          maDB,
		UpdateRepoMetadata:   managedanalyses.NewRepoMetaUpdater(repoService, repoAPI),
	}

	var repoID *ts.RepositoryEID = nil
	if args.repoID != 0 {
		r := ts.RepositoryEID(args.repoID)
		repoID = &r
	}

	// If a workflowRunID is provided, we only cancel that run.
	if args.workflowRunID != 0 && args.repoID != 0 {
		run, err := ma.DataService.GetCodeqlRun(ctx, *repoID, ts.WorkflowRunEID(args.workflowRunID))
		if err != nil {
			return err
		}
		return ma.CancelQueuedRuns(ctx, []ts.CodeqlRun{*run})
	}

	// Otherwise, we cancel all stale runs.
	// If a repoID was provided, this is restricted to runs for that repository only.
	// If repoID is nil, all runs are considered.
	timeout := time.Duration(args.horizon) * time.Hour
	for {
		runs, err := maDB.GetStaleValidationRuns(ctx, repoID, timeout, BATCH_SIZE)
		if err != nil {
			return err
		}
		appctx.Logger(ctx).Info("Stale validation runs found.", kvp.Int("count", len(runs)))
		if len(runs) == 0 {
			return nil
		}
		err = ma.CancelQueuedRuns(ctx, runs)
		if err != nil {
			return err
		}

		if len(runs) < BATCH_SIZE {
			break
		}
	}

	return nil
}

func init() {
	StaleValidationRunsCmd.Flags().Uint64("horizon", 24, "The number of hours to look back for stale validation runs.")
	StaleValidationRunsCmd.Flags().Uint64("repoID", 0, "The repository ID to restrict the stale validation runs to.")
	StaleValidationRunsCmd.Flags().Uint64("workflowRunID", 0, "The workflow run ID to cancel.")
}
