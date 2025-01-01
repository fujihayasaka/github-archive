// Main package for the Twirp server
// This runs the endpoint that gh/gh calls
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	twirpserver "github.com/github/osslicensecompliance/internal/twirp"
	"github.com/github/otel-instrumentation-go/oteltwirp"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("failed to run twirp service: %v", err)
	}
}

const (
	readTimeout     = 5 * time.Second
	writeTimeout    = 10 * time.Second
	shutdownTimeout = 30 * time.Second
)

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	// configure github-telemetry-go. currently it only handles logging,
	// but eventually it will handle all forms of telemetry
	telemetryProvider, err := telemetry.NewFromEnv()
	if err != nil {
		return err
	}

	logger := telemetryProvider.Logger.Named("twirp-service")

	reporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return err
	}

	// initialize statting
	statter, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	logger.Info("starting statsd client.")
	statter.Run()
	defer statter.Stop()

	statter.Counter("internal.service.start", nil, 1)

	// initialize distributed tracing

	// create new twirp service
	hooks, err := twirpserver.DefaultHooks(logger, reporter, statter)
	if err != nil {
		return err
	}

	app, err := application.New(cfg, logger, statter)
	if err != nil {
		return err
	}

	defer func() {
		if err := app.Close(); err != nil {
			logger.Error("failed to close application %s", kvp.String("error msg:", err.Error()))
		}
	}()

	twirpServer, err := twirpserver.NewTwirpServer(hooks, app)
	if err != nil {
		return err
	}
	server := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.HTTPPort),
		Handler:      oteltwirp.Middleware(twirpServer),
		ReadTimeout:  readTimeout,
		WriteTimeout: writeTimeout,
	}

	// example log usage: use key-values instead of `printf` string interpolation,
	// to facilitate searching of logs with key-value arguments.
	logger.Info("twirp service initialized in environment", kvp.String("deployment.environment", cfg.Environment))

	serverErrors := make(chan error, 1)
	go func() {
		logger.Info("twirp server starting", kvp.String("address", server.Addr))
		serverErrors <- server.ListenAndServe()
	}()

	// Set up signal handling for graceful shutdown
	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, syscall.SIGINT, syscall.SIGTERM)

	// Block until we receive a shutdown signal or server error
	select {
	case err := <-serverErrors:
		return fmt.Errorf("server error: %w", err)

	case sig := <-shutdown:
		logger.Info("shutdown signal received", kvp.String("signal", sig.String()))

		// Create context with timeout for graceful shutdown
		ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()

		// Attempt graceful shutdown
		logger.Info("shutting down server gracefully")
		if err := server.Shutdown(ctx); err != nil {
			logger.Error("graceful shutdown failed, forcing shutdown", kvp.String("error", err.Error()))
			return fmt.Errorf("could not stop server gracefully: %w", err)
		}

		logger.Info("server shutdown complete")
		return nil
	}
}
