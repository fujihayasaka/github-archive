// The aqueduct-worker command runs a lightweight worker dedicated to Aqueduct queues.
package main

import (
	"context"
	"flag"
	"fmt"
	"os/signal"
	"syscall"
	"time"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/dependabot"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/freno"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/repolocks"
	"github.com/github/dependency-snapshots-api/internal/snapshots"
	"github.com/github/dependency-snapshots-api/internal/storage"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

var (
	modeFlag    = flag.String("mode", "worker", "worker|send-echo")
	messageFlag = flag.String("message", "hello from dependency-snapshots-api", "message to send when mode=send-echo")
)

// BuildCommit - latest commit SHA for this build; injected at compile-time
var BuildCommit = "UNKNOWN"

func main() {
	if err := realMain(); err != nil {
		log.Fatal(err.Error())
	}
}

func realMain() error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return err
	}

	if err := cfg.InitDefaultLogger(); err != nil {
		return err
	}
	logger := log.Named("aqueduct-worker")

	if cfg.Enterprise {
		logger.Info("Aqueduct worker is not supported in GHES; exiting")
		return nil
	}

	if !cfg.AqueductConfigured() {
		logger.Info("Aqueduct is disabled; exiting")
		return nil
	}

	statter, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	statter.Run()
	defer statter.Stop()

	client, err := aqueduct.NewClient(cfg, logger, statter)
	if err != nil {
		return err
	}
	enqueuer := aqueduct.NewJobEnqueuer(cfg, client, statter)

	switch *modeFlag {
	case "worker":
		return runWorker(ctx, cfg, client, logger, statter)
	case "send-echo":
		jobID, err := aqueduct.SendEcho(ctx, enqueuer, *messageFlag, time.Now())
		if err != nil {
			return err
		}
		logger.Info("sent aqueduct echo job", kvp.String("job_id", jobID), kvp.String("queue", cfg.AqueductEchoQueue))
		return nil
	default:
		return fmt.Errorf("unknown mode %q", *modeFlag)
	}
}

func runWorker(ctx context.Context, cfg *config.Config, client aqueduct.Client, logger log.Logger, statter stats.Client) error {
	gitClient, err := cfg.NewGitAccessClient()
	if err != nil {
		return err
	}

	ffClient, err := features.NewFeaturesClient(ctx, cfg, logger, statter)
	if err != nil {
		return err
	}

	publisher, err := hydro.NewPublisher(cfg, logger, statter)
	if err != nil {
		return err
	}

	connectCtx, cancelConnectCtx := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelConnectCtx()

	sqlDB, err := db.ConnectToMysql(connectCtx, cfg.NewReadWriteMysqlConfig(), cfg.DBIdleConnections, cfg.DBMaxConnections)
	if err != nil {
		return err
	}

	executorDB := db.NewComposite(sqlDB, logger, statter)
	defer func() {
		if err := executorDB.Close(); err != nil {
			logger.WithError(err).Error("error closing DB")
		}
	}()

	repoLockService := repolocks.NewService(executorDB, logger, statter)

	sqlxDB, err := db.NewSqlxDatabase(sqlDB)
	if err != nil {
		return err
	}

	blobClient, err := blob.InitializeSnapshotsBlobClientIfEnabled(ctx, cfg)
	if err != nil {
		return err
	}

	frenoClient := freno.NewFrenoClient(cfg)

	storageAdapter := storage.NewAdapter(storage.AdapterOptions{
		DB:                             sqlxDB,
		BlobClient:                     blobClient,
		Git:                            gitClient,
		Freno:                          frenoClient,
		RepoLocker:                     repoLockService,
		Features:                       ffClient,
		Statter:                        statter,
		ShouldStoreBlobsInAzure:        !cfg.Enterprise,
		ShouldStoreHistoricalSnapshots: !cfg.Enterprise,
		ShouldStoreBlobsInDatabase:     cfg.Enterprise,
	})

	snapshotsSvc := snapshots.NewSnapshotsService(storageAdapter, gitClient)
	dependabotEventSvc := dependabot.NewEventService(storageAdapter, statter)

	statsCfg, err := aq.NewStatsConfig(aq.WithStatsClient(statter))
	if err != nil {
		return err
	}

	queues := []string{cfg.AqueductEchoQueue, aqueduct.DependabotSnapshotInitQueue, aqueduct.DependabotSnapshotPostPushQueue, aqueduct.UpdateGraphComputeUsageQueue, aqueduct.ExcludeCanonicalSnapshotsQueue}
	poolName := fmt.Sprintf("%s-worker", cfg.AqueductAppName)

	jobHandler := aqueduct.NewDSAPIJobHandler(cfg, logger, statter, nil, gitClient, publisher, ffClient, snapshotsSvc, dependabotEventSvc)

	worker, err := aq.NewWorker(
		client,
		cfg.AqueductAppName,
		queues,
		jobHandler.HandlerFn,
		aq.WithWorkerStats(statsCfg),
		aq.WithPool(poolName),
		aq.WithShuffleQueues(),
		aq.WithJobErrorPolicy(aq.NackJobErr), // jobs are marked as failed on error but not redelivered.
	)
	if err != nil {
		return err
	}

	logger.Info("starting aqueduct worker",
		kvp.String("queues", fmt.Sprintf("%v", queues)))

	for {
		select {
		case <-ctx.Done():
			logger.Info("aqueduct worker received shutdown signal")
			return nil
		default:
		}

		if err := worker.ProcessJob(ctx); err != nil {
			logger.WithError(err).Error("aqueduct worker error")
			// keep looping so we do not exit on transient errors, but avoid tight spinning on repeated failures
			time.Sleep(100 * time.Millisecond)
		}
	}
}
