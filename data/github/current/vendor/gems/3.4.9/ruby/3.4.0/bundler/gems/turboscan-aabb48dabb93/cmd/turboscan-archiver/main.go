// Command turboscan-archiver archives old analyses data from the database.
// See https://github.com/github/code-scanning/issues/6239 for context.
package main

import (
	"context"
	"flag"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/turboscan/ts/app"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts/archivalstore"

	"github.com/github/turboscan/ts/mysql/archiver"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"golang.org/x/sync/errgroup"
)

type arguments struct {
	repositoryID     ts.RepositoryEID
	analysisID       ts.AnalysisID
	uploadOnly       bool
	dryRun           bool
	delete           bool
	retryFailed      bool
	rearchive        bool
	skipVerification bool
	age              int
	limit            int
	deadline         uint
	threads          uint
}

var archiverService *archiver.Service
var start time.Time
var totalArchived uint

func parseArgs() *arguments {
	var args arguments
	flag.Uint64Var((*uint64)(&args.repositoryID), "repositoryID", 0, "Repository ID.")
	flag.Uint64Var((*uint64)(&args.analysisID), "analysisID", 0, "Analysis ID.")
	flag.BoolVar(&args.uploadOnly, "upload-only", false, "Do not update the state after having uploaded and validated the SARIF file.")
	flag.BoolVar(&args.dryRun, "dry-run", false, "Log which analyses are eligible for archival without archiving them.")
	flag.BoolVar(&args.delete, "delete", false, "Delete analysis after archiving SARIF file.")
	flag.BoolVar(&args.retryFailed, "retry-failed", false, "Retry archival for analyses that were failed.")
	flag.BoolVar(&args.rearchive, "rearchive", false, "Rebuild the processed SARIF processed file.")
	flag.BoolVar(&args.skipVerification, "skip-verification", false, "Skip verification of the SARIF file after uploading.")
	flag.IntVar(&args.limit, "limit", 10000, "The maximum number of analyses to clean.")
	flag.IntVar(&args.age, "age", 30, "How old (no of days, default 30) analysis we want to archive")
	flag.UintVar(&args.deadline, "deadline", 0, "Number of minutes the script is allowed to run. If specified, it will exit after that time, regardless of whether it has completed.")
	flag.UintVar(&args.threads, "threads", 0, "Number of parallel threads to run.")

	flag.Parse()
	return &args
}

func main() {
	if err := realMain(parseArgs()); err != nil {
		log.WithError(err).Error("Unexpected error")
		os.Exit(1)
	}
}

func realMain(args *arguments) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	signalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	return appctx.WithContext(cfg, "archiver", func(ctx context.Context) error {
		ctx = appctx.WithShutdown(ctx, signalCtx.Done())

		logger := appctx.Logger(ctx)
		statsClient := appctx.Stats(ctx)

		totalArchived = 0
		start = time.Now()
		defer func() {
			duration := time.Since(start)
			statsClient.DistributionMs("scheduled_job", stats.Tags{"job": "archiver"}, duration)
			statsClient.Counter("archiver.total_archived", nil, int64(totalArchived))

			logger.WithError(err).WithFields(
				kvp.Uint("gh.turboscan.total_archived", totalArchived),
				kvp.String("gh.operation.name", "archiver"),
				kvp.Float64("gh.operation.duration", float64(duration)),
			).Info("archiver run.")
		}()

		var cleaner app.Cleaner
		defer cleaner.Clean(ctx)

		sarifStore, closeSarifStore, err := app.NewSarifStore(ctx, cfg)
		if err != nil {
			return err
		}
		cleaner.Append(closeSarifStore)

		archivalStore, err := archivalstore.NewArchivalStoreFromConfig(sarifStore, cfg)
		if err != nil {
			return err
		}

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleaner.Append(closeDB)

		archiverService = archiver.NewService(db, archivalStore, archiver.WithConcurrency(cfg.ArchiverConcurrency))

		partitions := archiver.MakePartitions(int(args.threads))
		g, gCtx := errgroup.WithContext(ctx)
		for _, p := range partitions {
			g.Go(func() error {
				return archiveAnalyses(gCtx, args, p)
			})
		}
		// Wait on all queries
		if err := g.Wait(); err != nil {
			return err
		}

		return err
	})
}

func archiveAnalyses(ctx context.Context, args *arguments, partition archiver.FetchPartition) error {
	var analyses []*ts.Analysis
	var err error

	logger := appctx.Logger(ctx)
	statsClient := appctx.Stats(ctx)
	throttler := appctx.Throttler(ctx)

	analyses, err = archiverService.FetchEligibleAnalyses(ctx, args.age, args.limit, partition, args.repositoryID, args.analysisID, args.retryFailed)
	if err != nil {
		log.WithError(err).Error("Failed to get analyses", kvp.Int("gh.repo.id", int(args.repositoryID)))
		return nil
	}

	if len(analyses) == 0 {
		log.Error("Analyses not found", kvp.Int("gh.repo.id", int(args.repositoryID)))
		return nil
	}

	for _, analysis := range analyses {
		// If the deadline has been exceeded, just stop processing.
		if args.deadline > 0 && time.Since(start) > time.Duration(args.deadline)*time.Minute {
			logger.Info("Deadline exceeded")
			return nil
		}

		if args.dryRun {
			logger.Info("Would have archived but skipping due to dry-run", kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)))
			continue
		}

		logger.Info("Archiving analysis", kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)))

		var canWrite bool
		for !canWrite {
			canWrite, err = throttler.CanWrite(ctx)
			if err != nil {
				logger.WithError(err).Error("Error checking Freno")
				statsClient.Counter("archiver.freno_error", stats.Tags{}, 1)
				time.Sleep(1 * time.Second)
			}
			if !canWrite {
				logger.Info("Waiting on Freno")
				statsClient.Counter("archiver.throttled", stats.Tags{}, 1)
				time.Sleep(1 * time.Second)
			}
		}

		opts := archiver.ArchiveOpts{
			UploadOnly:       args.uploadOnly,
			Delete:           args.delete,
			SkipVerification: args.skipVerification,
		}
		err = archiverService.FullArchive(ctx, analysis.RepositoryID, analysis.ID, opts)
		if err != nil {
			logger.WithError(err).Error("Failed to archive analysis", kvp.Int("gh.repo.id", int(analysis.RepositoryID)), kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)))
			return nil
		}
		logger.Info("Archival complete", kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)))
		totalArchived++
	}

	return nil
}
