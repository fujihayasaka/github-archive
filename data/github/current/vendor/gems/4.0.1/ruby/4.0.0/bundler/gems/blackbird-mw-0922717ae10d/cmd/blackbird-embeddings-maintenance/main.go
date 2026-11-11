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

	"github.com/github/blackbird-mw/internal/embeddings"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/server"
	"github.com/github/blackbird-mw/internal/utils"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cfg := env.New(ctx)
	defer cfg.Close()
	defer utils.PanicLogger(ctx)
	repoPublisher := cfg.RepoPublisher()
	defer repoPublisher.Close()

	logging.Info(ctx, fmt.Sprintf("%s starting up", cfg.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", cfg)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)
	embeddingsMaint := embeddings.NewMaintenance(
		cfg.GitHubClient(),
		repoPublisher,
	)
	embeddingsMaint.Run(ctx)
	defer embeddingsMaint.Shutdown()

	// initialize debug web server (pyroscope accesses this)
	debugServer := server.NewDebug(cfg)

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
		err := debugServer.Shutdown(ctx)
		if err != nil {
			logging.Error(ctx, "debugServer.Shutdown failed", kvp.Err(err))
		}
		err = server.Shutdown(ctx) // Do this last so that k8s probes stay alive
		if err != nil {
			logging.Error(ctx, "server.Shutdown failed", kvp.Err(err))
		}
	}()

	go func() {
		logging.Info(ctx, "starting debug web server", kvp.Int("port", cfg.GetDebugHTTPPort()))
		if err := debugServer.ListenAndServe(); err != nil {
			if err == http.ErrServerClosed {
				logging.Info(ctx, "debug server has shutdown", kvp.Err(err))
			} else {
				logging.Error(ctx, "debug server exited with error", kvp.Err(err))
			}
		}
	}()

	logging.Info(ctx, "starting embeddings maintenance web server", kvp.Int("port", cfg.GetHTTPPort()))
	if err := server.ListenAndServe(); err != nil {
		if err == http.ErrServerClosed {
			logging.Info(ctx, "embeddings maintenance server has shutdown", kvp.Err(err))
		} else {
			logging.Error(ctx, "embeddings maintenance server exited with error", kvp.Err(err))
		}
	}

	logging.Info(ctx, "exiting…")
}
