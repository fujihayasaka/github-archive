package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/httpserver"
	"github.com/github/billing-platform/lib/messaging"
	twirpserver "github.com/github/billing-platform/lib/twirp"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-http/v2/middleware/hmac"
	stats "github.com/github/go-stats"
	"github.com/github/go-twirp/v2/server/hooks/auth"
	"github.com/pkg/errors"
	"github.com/rs/cors"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel"
	otelBridge "go.opentelemetry.io/otel/bridge/opentracing"
)

func main() {
	if err := realMain(); err != nil {
		fmt.Printf("failed to run service: %v\n", err)
		os.Exit(1)
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

	logger := cfg.ConfigureLogger(telem.Logger, "BillingPlatformAPI")
	logger.Info("initializing service",
		kvp.Int("net.host.port", cfg.HTTPPort),
		kvp.String("db.cosmosdb.container", cfg.ContainerName),
		kvp.String("db.cosmosdb.database", cfg.DatabaseName),
		kvp.String("db.cosmosdb.host", cfg.DatabaseEndPoint),
		kvp.String("db.cosmosdb.gateway_host", cfg.GatewayDatabaseEndPoint),
	)

	tracer := telem.Tracer.Tracer
	bridgeTracer, wrapperTracerProvider := otelBridge.NewTracerPair(tracer)
	otel.SetTracerProvider(wrapperTracerProvider)

	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.Environment, "service": "api"})
	statter.Run()
	defer statter.Stop()

	flagger := cfg.NewFeatureFlagClient(logger, statter)
	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)

	hooks := twirpserver.DefaultHooks(logger, errorReporter, statter, bridgeTracer)
	if !cfg.SkipHmacForLocalDev() {
		hmacKeys := strings.Split(cfg.HmacKeys, " ")
		hooks = twirp.ChainHooks(hooks, auth.VerifyRequestHMACHooks(hmacKeys...))
	}

	aqueductClient, err := messaging.NewMessagingClient(ctx, cfg, statter)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	monolithClient, err := cfg.NewMonolithClient(ctx)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	twirpServer, err := twirpserver.NewTwirpServer(hooks, cfg, errorReporter, logger, statter, flagger, readWriteDB, aqueductClient, monolithClient, tracer)
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	//nolint:staticcheck
	//lint:ignore SA1019 the recommended alternative HmacValidator.Handler() causes the HMAC related error responses to be
	// returned as a plain text response instead of a Twirp reponse. This is because the new validator performs the validation
	// at the HTTP level and the Twirp middleware auth.VerifyRequestHMACHooks() is not called when the request is terminated.
	// We decided to temporarily ignore the deprecation warning and use the Twirp middleware to perform the validation.
	// Once we are stable on the v2 versions of go-http and go-twirp we can test whether our clients can handle the plain
	// text response and switch to the new handler.
	twirpServer = hmac.Handler(twirpServer)

	if !cfg.IsProduction() {
		// Make a CORS wrapper:
		corsWrapper := cors.New(cors.Options{
			AllowedOrigins: []string{"*"},
			AllowedMethods: []string{"POST"},
			AllowedHeaders: []string{"Content-Type"},
		})

		// Do the wrapping, and serve it:
		twirpServer = corsWrapper.Handler(twirpServer)
	}

	const GracefulServerShutDownTimeOut = 3 * time.Second
	server := httpserver.NewGracefulServer(cfg.HTTPPort, twirpServer, logger, flagger, errorReporter)

	go server.WaitForExitingSignal(GracefulServerShutDownTimeOut)

	logger.Info("listening on port", kvp.Int("net.host.port", cfg.HTTPPort))
	err = server.ListenAndServe()
	if err != nil {
		_ = errorReporter.Report(ctx, err, nil)
		return err
	}

	logger.Info("shutdown processed successfully")
	return nil
}
