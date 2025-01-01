package main

import (
	"context"
	"fmt"
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/featureflags"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	twirpserver "github.com/github/hosted-compute-ims/internal/twirp"
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

	telem, err := telemetry.InitializeTelemetry(ctx, &cfg.Telemetry)
	if err != nil {
		return fmt.Errorf("failed to initialize telemetry: %w", err)
	}
	defer telem.Shutdown(ctx)

	err = featureflags.SetupNewGlobalFeatureFlagsClient(ctx, &cfg.FeatureFlags)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize feature flags client", err)
		return err
	}

	// initialize database connection
	imagesStore, err := store.NewImagesStoreWithMySQLConnection(&cfg.MySQL)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize database connection", err)
		return err
	}

	// initialize promotion client
	promotionClient, err := promotion.NewImagePromotionClient(ctx, &cfg.Worker.Aqueduct, &cfg.Azure, &cfg.MCP, &cfg.TwirpServer.JWTConfig, imagesStore)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize promotion client", err)
		return err
	}

	// initialize twirp server
	imageManagementServer, err := twirpserver.NewImageManagementServer(ctx, imagesStore, promotionClient, &cfg.TwirpServer, cfg.VssfAuth)
	if err != nil {
		logger.ErrorWithReport(ctx, "failed to initialize twirp server", err)
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

	twirpLogger.Info(ctx, "Starting server...")

	return server.ListenAndServe()
}
