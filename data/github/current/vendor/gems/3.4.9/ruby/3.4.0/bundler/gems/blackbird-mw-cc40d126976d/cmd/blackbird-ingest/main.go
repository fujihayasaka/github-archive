package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/deltaingest"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/server"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cfg := env.New(ctx)
	defer cfg.Close()
	defer utils.PanicLogger(ctx)

	corpus := cfg.Corpus()
	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()))
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": corpus.String()})

	logging.Info(ctx, fmt.Sprintf("%s starting up", cfg.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", cfg)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)

	// initialize web server (contains k8s probes and pprof)
	webServer := server.New(cfg)
	go func() {
		defer utils.PanicLogger(ctx)

		logging.Info(ctx, "starting web server", kvp.Int("port", cfg.GetHTTPPort()))
		if err := webServer.ListenAndServe(); err != nil {
			if err == http.ErrServerClosed {
				logging.Info(ctx, "web server has shutdown", kvp.Err(err))
			} else {
				logging.Error(ctx, "web server exited with error", kvp.Err(err))
			}
		}
	}()

	// Wait on OS signals and allow graceful shutdown.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		defer utils.PanicLogger(ctx)
		defer close(stop)
		defer cancel()

		// Received stop signal (SIGINT/SIGTERM)
		<-stop
		logging.Info(ctx, "received shutdown signal, exiting")
		// Do this last so that k8s probes stay alive
		if err := webServer.Shutdown(ctx); err != nil {
			logging.Error(ctx, "error during server shutdown", kvp.Err(err))
		}
	}()

	store := cfg.Store()
	state, err := store.GetCorpusState(ctx, corpus)
	if err != nil {
		logging.Error(ctx, "error getting initial corpus state", kvp.Err(err))
		os.Exit(1)
	}

	indexerCluster := cfg.IndexerCluster()

	backfillConsumer, err := cfg.BackfillConsumer(state.EpochID)
	if err != nil {
		logging.Error(ctx, "error creating backfill consumer", kvp.Err(err))
		os.Exit(1)
	}
	defer backfillConsumer.Close()

	sharedKafkaAdmin := cfg.SharedKafkaAdminClient()
	defer sharedKafkaAdmin.Close()

	// we must wait for incremental consumer group to be present before proceeding.
	// this is required for epoch branching to work correctly and not start consuming
	// from the incremental topic too soon.
	err = awaitConsumerGroupCreation(ctx, sharedKafkaAdmin, corpus, state.EpochID, store)
	if err != nil {
		logging.Error(ctx, "error while waiting for consumer group creation", kvp.Err(err))
		cancel()
		os.Exit(1)
	}

	incrConsumer := cfg.IncrementalConsumer(state.EpochID)
	defer incrConsumer.Close()

	syncProducer := cfg.SnapshotProducer()
	defer syncProducer.Close()

	blackbirdKafkaAdmin := cfg.BlackbirdKafkaAdminClient()
	defer blackbirdKafkaAdmin.Close()

	consumer := deltaingest.NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		backfillConsumer,
		incrConsumer,
		indexerCluster,
		state.EpochID,
	)

	logging.Info(ctx, "starting consume loop and workers", kvp.Int("current_epoch_id", int(state.EpochID)))
	if err := deltaingest.RunWorkPool(
		ctx,
		cfg.NumIngestionWorkers(),
		corpus,
		cfg.TopicConfig(),
		store,
		consumer,
		cfg.GitHubClient(),
		cfg.GitClient(),
		cfg.CacheClusters(),
		indexerCluster,
		cfg.GetStamp(),
	); err != nil {
		if err != ctx.Err() {
			logging.Error(ctx, "ingest consumer work pool errored", kvp.Err(err))
			cancel()
		}
	}

	logging.Info(ctx, "exiting…")
}

func awaitConsumerGroupCreation(
	ctx context.Context,
	c *kafka.AdminClient,
	corpus routing.Corpus,
	epochID types.EpochID,
	store db.Store,
) error {

	cg := corpus.ConsumerGroup(epochID)
	op := func() error {
		state, err := store.GetCorpusState(ctx, corpus)
		if err != nil {
			return err
		}
		if state.EpochID > epochID {
			return backoff.Permanent(fmt.Errorf("new epoch %d detected(old epoch: %d), giving up waiting consumer group creation", state.EpochID, epochID))
		}

		cgExists, err := c.IsConsumerGroupPresent(cg)
		if err != nil {
			return fmt.Errorf("error while checking existence of consumer group %s: %w", cg, err)
		}
		if cgExists {
			logging.Info(ctx, "consumer group for current epoch is now present", kvp.String("consumer_group", cg))
			return nil
		}

		logging.Info(ctx, "consumer group for current epoch is not present, retrying..", kvp.String("consumer_group", cg))
		return fmt.Errorf("consumer group %s doesn't exist. Will retry", cg)
	}

	return backoff.Retry(op, retry.Forever(ctx))
}
