// The api command runs the dependency-snapshots-api server.
// See ../docs/dependency-snapshots-service.md for design.
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/dependency-snapshots-api/internal/chatops"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/dependencies"
	"github.com/github/dependency-snapshots-api/internal/diagnostic"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/freno"
	"github.com/github/dependency-snapshots-api/internal/httputil"
	"github.com/github/dependency-snapshots-api/internal/repolocks"
	"github.com/github/dependency-snapshots-api/internal/snapshots"
	"github.com/github/dependency-snapshots-api/internal/storage"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/github/dependency-snapshots-api/internal/twirp"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-auth/hmac"
	statsdb "github.com/github/go-stats/db"
	"github.com/github/go-stats/ps"
	"github.com/pkg/errors"
)

// BuildCommit - latest commit SHA for this build; injected at compile-time
var BuildCommit string = "UNKNOWN"

func main() {
	if err := realMain(); err != nil {
		crashingError := errors.Wrap(err, "application failed")
		contextlogger.Error(context.Background(), "Application crashed",
			kvp.String("exception.message", err.Error()))
		log.Fatal(crashingError.Error())
	}
}

func realMain() error {
	ctx := context.Background()
	cfg, err := config.Load(BuildCommit)
	if err != nil {
		return err
	}

	err = cfg.InitDefaultLogger()
	if err != nil {
		log.WithError(err).Fatal("couldn't initialize logger")
	}
	logger := log.Named("default")
	logger.Info("initializing service...")

	gitClient, err := cfg.NewGitAccessClient()
	if err != nil {
		return err
	}

	reporter, err := cfg.NewExceptionReporter()
	if err != nil {
		return err
	}

	// initialize statting
	statter, err := cfg.NewStatsClient()
	if err != nil {
		return err
	}
	contextlogger.Info(context.Background(), "starting statsd client.")
	statter.Run()

	procStats := &ps.Reporter{
		Stats:    statter,
		Interval: time.Second * 5,
	}

	go func() {
		err = procStats.Run(context.Background())
		// At the time of this code being written, procStats.Run had no error case.
		contextlogger.Error(context.Background(), "procStats.Run returned an error", kvp.String("exception.message", err.Error()))
	}()

	defer statter.Stop()

	tracerTeardown, err := config.Instrument(cfg)
	if err != nil {
		return errors.Wrap(err, "failed to create tracer")
	}
	defer tracerTeardown()

	// create new twirp service
	hooks, err := twirp.DefaultHooks(reporter, statter)
	if err != nil {
		return err
	}

	var featuresClient features.Client
	twirpFeaturesClient, err := features.NewTwirpFeaturesClient(statter, cfg.MonolithTwirpURL, cfg.MonolithTwirpHMACKey, cfg.DevStandaloneMode)
	if err != nil {
		return err
	}
	vexiFeaturesClient, err := features.NewVexiFeaturesClient(ctx, logger, statter, cfg.VexiHydroBrokers, cfg.DevStandaloneMode)
	if err != nil {
		featuresClient = twirpFeaturesClient // fallback to twirp client if vexi client fails
		contextlogger.Error(ctx, "Failed to initialize Vexi features client, falling back to Twirp client", kvp.String("exception.message", err.Error()))
	} else {
		featuresClient, err = features.WrapFeaturesClientWithFallback(vexiFeaturesClient, twirpFeaturesClient)
		if err != nil {
			return errors.Wrap(err, "failed to create wrapped features client")
		}
	}

	diagnosticSvc := diagnostic.NewDiagnosticService(featuresClient)

	connectCtx, cancelConnectCtx := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelConnectCtx()
	sqlDB, err := db.ConnectToMysql(connectCtx, cfg.NewMysqlConfig(), cfg.DBIdleConnections, cfg.DBMaxConnections)
	if err != nil {
		return err
	}

	executorDB := db.NewComposite(sqlDB, logger, statter)
	defer func() {
		if err := executorDB.Close(); err != nil {
			logger.WithError(err).Error("error closing DB")
		}
	}()

	repoLockService := repolocks.NewService(executorDB, logger, statter)

	dbStats := &statsdb.Reporter{
		Stats:    statter,
		Interval: time.Second * 5,
		DB:       sqlDB,
	}

	go func() {
		err = dbStats.Run(context.Background())
		// At the time of this code being written, dbStats.Run had no error case.
		contextlogger.Error(context.Background(), "dbStats.Run returned an error", kvp.String("exception.message", err.Error()))
	}()

	sqlxDB, err := db.NewSqlxDatabase(sqlDB)
	if err != nil {
		return err
	}

	frenoClient := freno.NewFrenoClient(cfg)
	blobClient, err := blob.InitializeSnapshotsBlobClientIfEnabled(context.Background(), cfg)
	if err != nil {
		return err
	}

	storageAdapter := storage.NewAdapter(storage.AdapterOptions{
		DB:                             sqlxDB,
		BlobClient:                     blobClient,
		Git:                            gitClient,
		Freno:                          frenoClient,
		RepoLocker:                     repoLockService,
		Features:                       featuresClient,
		Statter:                        statter,
		Reporter:                       reporter,
		ShouldStoreBlobsInAzure:        !cfg.Enterprise,
		ShouldStoreHistoricalSnapshots: !cfg.Enterprise,
		ShouldStoreBlobsInDatabase:     cfg.Enterprise,
	})

	snapshotsSvc := snapshots.NewSnapshotsService(storageAdapter, gitClient)
	dependenciesSvc := dependencies.NewDependenciesService(snapshotsSvc, statter)

	mux := http.NewServeMux()
	twirp.AddHandlers(mux, hooks, statter, featuresClient, diagnosticSvc, snapshotsSvc, dependenciesSvc, cfg)
	httputil.ApplyRestHandlers(mux, reporter, diagnosticSvc)

	contextlogger.Info(context.Background(), "twirp+rest service initialized")

	// set up a chatops handler
	chatopsHandler, err := chatops.NewChatopsHandler(cfg, reporter, snapshotsSvc)
	if err != nil {
		return err
	}
	chatopsHandler.Setup(mux)

	// Print out an HMAC for devs
	if cfg.IsDevelopment() && cfg.DevForceHmacAuthentication {
		contextlogger.Info(context.Background(), "HMAC : "+hmac.NewRequestHMAC(cfg.HMACKey).String())
	}

	addr := fmt.Sprintf(":%d", cfg.HTTPPort)

	var srv = http.Server{
		Addr:    addr,
		Handler: mux,
	}

	// Graceful shutdown pattern naively taken from https://pkg.go.dev/net/http#Server.Shutdown
	idleConnsClosed := make(chan struct{})
	go func() {
		gracefulExitSignal := make(chan os.Signal, 1)
		// SIGINT: Ctrl+C, SIGTERM: kube's shutdown code, NOHUP: loss of parent terminal
		signal.Notify(gracefulExitSignal, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
		<-gracefulExitSignal

		contextlogger.Info(context.Background(), "graceful shutdown initiated")

		// Cancel after 30 seconds
		ctx, cancelTimeout := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancelTimeout()

		// We received an interrupt signal, shut down.
		if err := srv.Shutdown(ctx); err != nil {
			// Error from closing listeners, or context timeout:
			contextlogger.Info(context.Background(), "HTTP server Shutdown", kvp.String("exception.message", err.Error()))
			// Instead of potentially waiting "forever", we choose to panic here because the service has not exited gracefully.
			panic(errors.Wrap(err, "graceful shutdown could not be completed"))
		}

		contextlogger.Info(context.Background(), "graceful shutdown completed")
		close(idleConnsClosed)
	}()

	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		// Error starting or closing listener:
		return errors.Wrap(err, "HTTP server ListenAndServe")
	}

	<-idleConnsClosed

	return nil
}
