package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/actions-usage-metrics/internal/blob"
	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/httpserver"
	"github.com/github/actions-usage-metrics/internal/kusto"
	"github.com/github/actions-usage-metrics/internal/orgs"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/repositories"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/internal/twirp"
	"github.com/github/github-telemetry-go/log"
)

func main() {
	if err := mainNoExit(); err != nil {
		log.WithError(err).Error("Application exited with error")
		os.Exit(1)
	}
	log.Info("Application exited successfully")
}

func mainNoExit() error {
	ctx := context.Background()

	logger := log.WithContext(ctx)
	logger.Info("starting api-server")
	cfg, err := config.Load[config.ApiServerConfig]()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	telem, err := telemetry.NewTelemetry(ctx, &cfg.Telemetry)
	if err != nil {
		return fmt.Errorf("failed to initialize telemetry: %w", err)
	}
	logger = telem.Logger.WithContext(ctx)

	err = repositories.SetRepositoryService(telem, cfg.Http)
	if err != nil {
		logger.WithError(err).Error("failed to create repository service")
		return err
	}

	orgs.SetOrgService(telem)

	// For now, just test that we can connect to Kusto if enabled
	var kustoClient *kusto.Client
	kustoClient, err = kusto.NewKustoClient(cfg.Kusto)
	if err != nil {
		logger.WithError(err).Error("failed to create kusto client")
		return fmt.Errorf("failed to create kusto client: %w", err)
	}

	common.SetKustoSnapshotTableConfig(cfg.Kusto)
	if common.KustoRepositoryNamesTable.Name() != cfg.Kusto.RepoTable {
		logger.WithError(err).Error("failed to set repo table name")
		return fmt.Errorf("failed to set repo table name")
	}
	if common.KustoOrgNamesTable.Name() != cfg.Kusto.OrgTable {
		logger.WithError(err).Error("failed to set org table name")
		return fmt.Errorf("failed to set org table name")
	}

	if err := kustoClient.TestConnection(ctx); err != nil {
		logger.WithError(err).Error("failed to connect to kusto")
		return fmt.Errorf("failed to connect to kusto: %w", err)
	}

	if err := kustoClient.TestConnectionRepos(ctx); err != nil {
		logger.WithError(err).Error("failed to connect to kusto repos db")
		return err
	}

	err = blob.SetupBlobClient(cfg.StorageAccount)
	if err != nil {
		logger.WithError(err).Fatal("failed to create blob client")
		return fmt.Errorf("failed to create blob client: %w", err)
	}

	err = blob.TestBlobClient(ctx)
	if err != nil {
		logger.WithError(err).Fatal("blob client test failed")
		return fmt.Errorf("failed to test blob client: %w", err)
	}

	twirpUsageServer := twirp.NewTwirpUsageServer(telem, *cfg, kustoClient)

	middleware := httpserver.NewDefaultHttpMiddleware(telem)
	middleware.UseHmacAuthentication(cfg.Http)
	unauthenticatedHealthHandler := middleware.Unauthenticated.ThenFunc(httpserver.HealthCheckHandler)
	authenticatedTwirpUsageHandler := middleware.Authenticated.Then(twirpUsageServer)

	mux := http.NewServeMux()
	mux.Handle("/health", unauthenticatedHealthHandler)
	mux.Handle("/", authenticatedTwirpUsageHandler)

	server := httpserver.NewHttpServer(cfg.Http.Port, mux)
	go server.Run()

	// Gracefully shut down on signal
	signalCh := make(chan os.Signal, 1)
	signal.Notify(signalCh, syscall.SIGINT, syscall.SIGTERM)
	<-signalCh

	// Give the server time to drain connections and shut down gracefully first
	logger.Info("shutting down http server")
	serverShutdownTimeout := 10
	serverShutdownCtx, cancelShutdownServerTimer := context.WithTimeout(context.Background(), time.Duration(serverShutdownTimeout)*time.Second)
	defer cancelShutdownServerTimer()
	if err := server.Shutdown(serverShutdownCtx); err != nil {
		logger.WithError(err).Error("failed to gracefully shutdown http server")
	}

	// Now move forward with shutting down anything else
	otherShutdownTimeout := 5
	otherShutdownCtx, cancelShutdownOtherTimer := context.WithTimeout(context.Background(), time.Duration(otherShutdownTimeout)*time.Second)
	defer cancelShutdownOtherTimer()

	logger.Info("Closing Kusto client")
	kustoClient.Close()

	logger.Info("shutting down telemetry")
	telem.Shutdown(otherShutdownCtx)

	logger.Info("api-server shut down")
	return nil
}
