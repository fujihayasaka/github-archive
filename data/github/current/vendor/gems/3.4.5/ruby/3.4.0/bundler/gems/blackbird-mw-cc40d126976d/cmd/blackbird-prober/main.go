package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/healthcheck"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/server"
	"github.com/github/blackbird-mw/internal/utils"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cfg := env.New(ctx)
	defer cfg.Close()
	defer utils.PanicLogger(ctx)

	logging.Info(ctx, fmt.Sprintf("%s starting up", cfg.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", cfg)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)

	store := cfg.Store()
	gitClient := cfg.GitClient()
	pager := cfg.PagerCache()
	githubClient := cfg.GitHubClient()

	tsReader := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		msgReader, err := kafka.NewSaramaMessageReader(cfg.SharedAutoCommittingKafkaClient())
		if err != nil {
			panic(fmt.Errorf("failed to create kafka msg reader: %w", err))
		}
		return msgReader
	}, routing.IncrementalSourceTopic)
	tsReader.Run(ctx)

	sharedKafkaClient := cfg.SharedAutoCommittingKafkaClient()
	defer sharedKafkaClient.Close()

	repoPublisher := cfg.RepoPublisher()
	defer repoPublisher.Close()

	prober := healthcheck.NewProber(
		store,
		pager,
		gitClient,
		cfg.GetStamp(),
		cfg.SearchClusters(),
		cfg.IndexerClusters(),
		sharedKafkaClient,
		githubClient,
		repoPublisher,
		cfg.CopilotClient(),
		tsReader,
	)
	prober.Run(ctx)
	defer prober.Shutdown()

	server := server.New(cfg)

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
		err := server.Shutdown(ctx) // Do this last so that k8s probes stay alive
		if err != nil {
			logging.Error(ctx, "server.Shutdown failed", kvp.Err(err))
		}
	}()

	logging.Info(ctx, "starting prober web server", kvp.Int("port", cfg.GetHTTPPort()))
	if err := server.ListenAndServe(); err != nil {
		if err == http.ErrServerClosed {
			logging.Info(ctx, "prober server has shutdown", kvp.Err(err))
		} else {
			logging.Error(ctx, "prober server exited with error", kvp.Err(err))
		}
	}

	logging.Info(ctx, "exiting...")
}
