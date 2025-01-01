package main

import (
	"context"
	"fmt"
	"net/http"

	coreosoidc "github.com/coreos/go-oidc/v3/oidc"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/oidc"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
	twirpserver "github.com/github/hosted-compute-ims/internal/twirp"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
)

func main() {
	if err := realMain(); err != nil {
		panic(err)
	}
}

func realMain() error {
	ctx := context.Background()

	// load app config
	cfg := &config.Config{}
	if err := cfg.Load(); err != nil {
		return err
	}

	// initialize telemetry
	telem, err := telemetry.NewTelemetry(ctx, cfg.ServiceName, cfg.Telemetry)
	if err != nil {
		return err
	}

	defer telem.Shutdown(ctx)
	logger := telem.Logger
	statter := telem.Stats

	err = featureflags.SetupNewGlobalFeatureFlagsClient(ctx, &cfg.FeatureFlags, logger)
	if err != nil {
		logger.ErrorWithReport("failed to initialize feature flags client", err)
		return err
	}

	// initialize database connection
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL, telem.Logger, statter)
	if err != nil {
		logger.ErrorWithReport("failed to initialize database connection", err)
		return err
	}

	workerQueueClient, err := queue.NewWorkerQueueClient(&cfg.Worker.Aqueduct)
	if err != nil {
		logger.ErrorWithReport("failed to create worker queue client", err)
		return err
	}

	vssfAuthClient, err := oidc.NewAuthClient(ctx, cfg.VssfAuth, logger, coreosoidc.NewProvider)
	if err != nil {
		logger.ErrorWithReport("failed to initialize vssf auth client", err)
		panic(err)
	}

	resourceManager := resources.NewManager(cfg.Resources, imagesStore, logger)

	// initialize twirp server
	imageManagementServer, err := twirpserver.NewImageManagementServer(imagesStore, workerQueueClient, vssfAuthClient, resourceManager, &cfg.TwirpServer, telem)
	if err != nil {
		logger.ErrorWithReport("failed to initialize twirp server", err)
		return err
	}

	server := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.TwirpServer.HTTPPort),
		Handler:      imageManagementServer,
		ReadTimeout:  cfg.TwirpServer.Timeout,
		WriteTimeout: 2 * cfg.TwirpServer.Timeout, // 2x read timeout
	}

	twirpLogger := logger.WithFields(
		kvp.Int("server.port", cfg.TwirpServer.HTTPPort),
		kvp.String("server.address", server.Addr),
		kvp.Bool("server.hmac_enabled", cfg.TwirpServer.HmacAuthEnabled),
		kvp.Bool("server.auth_enabled", cfg.VssfAuth.Enabled),
	)

	twirpLogger.Info("Starting server...")

	return server.ListenAndServe()
}
