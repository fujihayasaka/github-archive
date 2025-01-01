package main

import (
	"context"
	"fmt"
	"net/http"

	"github.com/github/billing-platform/admin"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/httpserver"
	"github.com/github/billing-platform/lib/okta"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/gorilla/csrf"
	"github.com/pkg/errors"
)

func main() {
	fmt.Println("Starting server on port 8888")

	err := realMain()
	if err != nil {
		fmt.Printf("failed to run service: %v\n", err)
	}
}

func realMain() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	errorReporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return err
	}

	ctx := context.Background()
	telem, err := telemetry.NewFromEnv()
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return errors.Wrap(err, "failed configuring telemetry")
	}
	defer func() {
		if err := telem.Shutdown(ctx); err != nil {
			_ = errorReporter.Report(ctx, err, nil)
			fmt.Printf("failed to shutdown telemetry: %v\n", err)
		}
	}()

	logger := cfg.ConfigureLogger(telem.Logger, "BillingPlatformAdmin")
	logger.Info("initializing service", kvp.Int("net.host.port", cfg.HTTPPort))

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.Environment, "service": "admin"})
	statter.Run()
	defer statter.Stop()

	flagger := cfg.NewFeatureFlagClient(logger, statter)
	tracer := telem.Tracer.Tracer

	readOnlyDB, err := db.NewReadOnlyDatabase(cfg, logger, statter, tracer)

	if err != nil {
		logger.Error("failed to create read only database", kvp.String("error", err.Error()))
		_ = errorReporter.Report(ctx, err, nil)
	}

	adminServer := admin.NewAdminServer(logger, errorReporter, readOnlyDB.GetConnection(), cfg.ContainerName, cfg.OktaHMACSecret, cfg.Environment)

	mux := http.NewServeMux()
	mux.HandleFunc("/static/", adminServer.StaticFileHandler)
	mux.HandleFunc("/", adminServer.RootHandler)
	mux.HandleFunc("/query", adminServer.QueryHandler)
	mux.HandleFunc("/_ping", adminServer.PingHandler)
	mux.HandleFunc("/_boom", adminServer.BoomHandler)

	handler := okta.Middleware([]byte(adminServer.OktaHMACSecret), nil, mux)

	csrfSecret := cfg.CSRFSecret
	if csrfSecret == "" {
		logger.Error("No csrf secret set in vault")
		err := errors.New("No csrf secret set in vault")
		_ = errorReporter.Report(ctx, err, nil)

		return err
	}

	CSRF := csrf.Protect([]byte(cfg.CSRFSecret))

	err = httpserver.NewGracefulServer(8888, CSRF(handler), logger, flagger, errorReporter).ListenAndServe()

	return err
}
