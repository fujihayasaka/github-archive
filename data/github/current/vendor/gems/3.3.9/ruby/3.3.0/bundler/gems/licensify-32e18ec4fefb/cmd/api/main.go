// The main.go file is the entry point for the API service.
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	twauth "github.com/github/go-twirp/v2/server/hooks/auth"
	"github.com/github/licensify/internal/aqueduct"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/httpserver"
	"github.com/github/licensify/internal/twirpserver"
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/twitchtv/twirp"
)

func main() {
	if err := runAPI(); err != nil {
		fmt.Printf("failed to run service: %v\n", err)
		os.Exit(1)
	}
}

func runAPI() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	errorReporter, err := cfg.NewExceptionReporter()
	if err != nil {
		fmt.Printf("Failed initializing exception reporter: %v\n", err)
		return err
	}

	ctx := context.Background()
	telem, err := telemetry.NewFromEnv()

	tracer := telem.Tracer.Tracer

	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("failed configuring telemetry: %w", err)
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			_ = errorReporter.Report(ctx, err, nil)
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, cfg.ServiceName).Named("api")

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.HeavenEnv, "service": cfg.ServiceName, "process.executable.name": "api"})
	statter.Run()
	defer statter.Stop()

	dbConnection, err := cosmos.NewDatabaseConnection(ctx, cfg, logger, statter)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	hooks := twirpserver.DefaultHooks(logger, errorReporter, statter)

	if !cfg.SkipHmacForLocalDev() {
		hooks = twirp.ChainHooks(hooks, twauth.VerifyRequestHMACHooks(cfg.GetAllHmacKeys()...))
	}

	aqueductClient, err := aqueduct.NewClient(
		cfg.AqueductURL,
		cfg.AqueductAPIKey,
		cfg.AqueductAPIKeyVersion,
		statter,
	)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	handler, err := twirpserver.NewTwirpServer(ctx, cfg, logger, statter, tracer, dbConnection, hooks, aqueductClient)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}
	//nolint:staticcheck // The hmac.Handler is needed to set the Request-HMAC header in the context for twauth.VerifyRequestHMACHooks to work.
	// The HmacValidator alternative currently returns errors as plain text instead of twirp responses,
	// so we're using the hmac.Handler for now.
	handler = hmac.Handler(handler)
	handler = requestid.Handler(handler)
	handler = oteltwirp.Middleware(handler)

	server := httpserver.NewGracefulServer(cfg.HTTPPort, handler, logger, errorReporter)

	const timeout = 3 * time.Second
	go server.WaitForExitingSignal(timeout)

	logger.Info("listening on port", kvp.Int("net.host.port", cfg.HTTPPort))
	err = server.ListenAndServe()
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	logger.Info("shutdown processed successfully")
	return nil
}
