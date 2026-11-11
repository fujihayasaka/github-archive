package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/cenkalti/backoff/v4"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/ingest"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kube"
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

	var readyEpochID types.EpochID // this is set once the epoch is ready to report at /epoch
	corpus := cfg.Corpus()
	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()), kvp.String("cluster", corpus.ClusterName()))
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": corpus.String(), "cluster": corpus.ClusterName()})

	logging.Info(ctx, fmt.Sprintf("%s starting up", cfg.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", cfg)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)

	// debug web server (pyroscope accesses this)
	debugServer := server.NewDebug(cfg)
	// web server (contains k8s probes, pprof, and /epoch endpoint)
	// This must be started early or the Docker health check will kill the process.
	mux := chi.NewRouter()
	mux.Mount("/debug", middleware.Profiler())
	mux.HandleFunc("/ready", kube.Ready(cfg))
	mux.HandleFunc("/epoch", func(w http.ResponseWriter, r *http.Request) {
		resp, err := json.Marshal(map[string]types.EpochID{"epoch_id": readyEpochID})
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}

		w.Header().Set("Content-Type", "application/json")
		w.Write(resp) //nolint:gosec,errcheck
	})

	webServer := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.GetHTTPPort()),
		Handler: mux,
	}

	go func() {
		defer utils.PanicLogger(ctx)

		logging.Info(ctx, "starting debug web server", kvp.Int("port", cfg.GetDebugHTTPPort()))
		if err := debugServer.ListenAndServe(); err != nil {
			if err == http.ErrServerClosed {
				logging.Info(ctx, "debug server has shutdown", kvp.Err(err))
			} else {
				logging.Error(ctx, "debug server exited with error", kvp.Err(err))
			}
		}
	}()

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
		logging.Info(ctx, "received shutdown signal, exiting")
		err := debugServer.Shutdown(ctx)
		if err != nil {
			logging.Error(ctx, "debugServer.Shutdown failed", kvp.Err(err))
		}
		// Do this last so that k8s probes stay alive
		if err := webServer.Shutdown(ctx); err != nil {
			logging.Error(ctx, "error during server shutdown", kvp.Err(err))
		}
	}()

	store := cfg.Store()
	state, err := awaitValidEpoch(ctx, store, corpus)
	if err != nil {
		logging.Error(ctx, "error getting initial corpus state", kvp.Err(err))
		cancel()
		os.Exit(1)
	}

	indexerCluster := cfg.IndexerCluster()
	err = awaitIndexClusterReady(ctx, indexerCluster, state.EpochID)
	if err != nil {
		logging.Error(ctx, "error while waiting for index cluster to be ready", kvp.Err(err))
		cancel()
		os.Exit(1)
	}

	kafkaClusterResolver := cfg.KafkaClusterResolver()

	sharedKafkaAdmin := cfg.SharedKafkaAdminClient()
	defer sharedKafkaAdmin.Close()

	blackbirdKafkaAdmin := cfg.BlackbirdKafkaAdminClient(kafkaClusterResolver)
	defer blackbirdKafkaAdmin.Close()

	// we must wait for incremental consumer group to be present before proceeding.
	// this is required for epoch branching to work correctly and not start consuming
	// from the incremental topic too soon.
	err = awaitConsumerGroupCreation(ctx, sharedKafkaAdmin, corpus, state.EpochID, store, cfg.TopicConfig())
	if err != nil {
		logging.Error(ctx, "error while waiting for consumer group creation", kvp.Err(err))
		cancel()
		os.Exit(1)
	}

	logging.Info(ctx, "creating backfill consumer", kvp.Int64("epoch_id", int64(state.EpochID)))
	backfillConsumer, err := cfg.BackfillConsumer(kafkaClusterResolver, state.EpochID)
	if err != nil {
		logging.Error(ctx, "error creating backfill consumer", kvp.Err(err))
		cancel()
		os.Exit(1)
	}
	defer backfillConsumer.Close()

	logging.Info(ctx, "creating incremental consumer", kvp.Int64("epoch_id", int64(state.EpochID)))
	incrConsumer := cfg.IncrementalConsumer(state.EpochID)
	defer incrConsumer.Close()

	logging.Info(ctx, "creating ingest mode consumer", kvp.Int64("epoch_id", int64(state.EpochID)))
	consumer := ingest.NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		cfg.TopicConfig(),
		backfillConsumer,
		incrConsumer,
		indexerCluster,
		state.EpochID,
		cfg.CheckIngestModeInterval(),
	)

	// Ingest is now ready. Set readyEpochID so /epoch will report it.
	readyEpochID = state.EpochID

	logging.Info(ctx, "starting consume loop and workers", kvp.Int("epoch_id", int(state.EpochID)))
	if err := ingest.RunWorkPool(
		ctx,
		cfg.NumIngestionWorkers(),
		corpus,
		cfg.TopicConfig(),
		store,
		consumer,
		sharedKafkaAdmin,
		blackbirdKafkaAdmin,
		cfg.GitHubClient(),
		cfg.GitClient(),
		cfg.CacheClusters(),
		indexerCluster,
		cfg.GetStamp(),
		cfg.ReportOffsetsInterval(),
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
	tc routing.TopicConfig,
) error {
	start := time.Now()
	cg := corpus.ConsumerGroup(epochID)
	ctx = logging.With(ctx, kvp.Int64("epoch_id", int64(epochID)), kvp.String("consumer_group", cg))
	logging.Info(ctx, "awaiting consumer group creation")
	op := func() error {
		state, err := store.GetCorpusState(ctx, corpus)
		if err != nil {
			return err
		}
		if state.EpochID > epochID {
			return backoff.Permanent(fmt.Errorf("new epoch %d detected (old epoch: %d), giving up waiting consumer group creation", state.EpochID, epochID))
		}

		cgExists, err := c.IsConsumerGroupPresentWithOffsets(ctx, cg, tc)
		if err != nil {
			return fmt.Errorf("error while checking existence of consumer group %s: %w", cg, err)
		}
		if cgExists {
			logging.Info(ctx, "consumer group for current epoch is now present", kvp.Duration("duration_ms", time.Since(start)))
			return nil
		}

		logging.Info(ctx, "consumer group for current epoch is not present, retrying..")
		return fmt.Errorf("consumer group %s doesn't exist. Will retry", cg)
	}

	return backoff.Retry(op, retry.Forever(ctx))
}

// Wait until a valid epoch ID (> 0) exists.
//
// Helps with bootstrapping so the app isn't restarting over and over again trying to ingest an epoch that doesn't exist.
func awaitValidEpoch(ctx context.Context, store db.Store, corpus routing.Corpus) (*db.CorpusState, error) {
	start := time.Now()
	logging.Info(ctx, "awaiting valid epoch")
	var state *db.CorpusState
	var err error
	op := func() error {
		state, err = store.GetCorpusState(ctx, corpus)
		if err != nil {
			return backoff.Permanent(err)
		}

		if state.EpochID == 0 {
			return errors.New("invalid epoch ID")
		}

		logging.Info(ctx, "valid epoch ID is now present", kvp.Uint("epoch_id", uint(state.EpochID)), kvp.Duration("duration_ms", time.Since(start)))
		return nil
	}

	err = backoff.Retry(op, retry.Forever(ctx))
	return state, err
}

// Wait for the indexer cluster to respond to status RPCs and verify the epoch
// mode is compatible with blackbird-ingest.
//
// The consumer requires the indexer to be up or it will error out and restart
// the process. This is mostly an issue in e2e tests, but it will not hurt to
// enforce in production.
func awaitIndexClusterReady(ctx context.Context, cluster *routing.IndexerCluster, epochID types.EpochID) error {
	if epochID == 0 {
		panic("epoch ID should be valid by this point")
	}

	start := time.Now()
	logging.Info(ctx, "awaiting index cluster")
	logIncompatible := true
	attempt := 0
	op := func() error {
		attempt += 1
		host, err := cluster.GetHost()
		if err != nil {
			logging.Error(ctx, "error getting host", kvp.Err(err))
			return err
		}

		res, err := host.IndexAPI.Status(ctx, &servingpb.StatusRequest{})
		if err != nil {
			logging.Error(ctx, "error getting index API status", kvp.Err(err))
			return err
		}

		if res.Status.EpochId != uint32(epochID) {
			logging.Error(ctx, "indexer cluster not serving expected epoch ID", kvp.Int("indexer_epoch_id", int(res.Status.EpochId)), kvp.Int("ingest_epoch_id", int(epochID)))
			return errors.New("mismatched epoch ID")
		}

		// NOTE: Must get blackbird.EpochMode (a bitfield) **not** the entities.EpochMode (an int).
		epochMode := epoch.EpochMode(cluster.EpochInfo().EpochMode)
		if epoch.EpochFeaturesExternalContent.SupportedBy(epochMode) {
			if logIncompatible {
				logging.Info(ctx, "epoch is not compatible with blackbird-ingest", kvp.String("indexer_epoch_mode", res.Status.EpochMode.String()), kvp.String("dsa_epoch_mode", epochMode.String()))
				logIncompatible = false
			}
			return errors.New("incompatible")
		}

		logging.Info(ctx, "index cluster ready", kvp.Int("await_indexer_attempt", attempt), kvp.Duration("duration_ms", time.Since(start)))

		return nil
	}

	return backoff.Retry(op, retry.Forever(ctx))
}
