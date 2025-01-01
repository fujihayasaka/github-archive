// Package main implements the entrypoint for the deliver-email-worker.
package main

import (
	"context"
	"fmt"
	"os"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	ghconfig "github.com/github/go-config"
	ghexceptions "github.com/github/go-exceptions"
	ghhttp "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	ghstats "github.com/github/go-stats"

	"github.com/github/notifyd/internal/email"
	layout "github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/deliverytracking"
	"github.com/github/notifyd/internal/pkg/dotcom"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/job/middlewares"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/o11y/stats"
	"github.com/github/notifyd/internal/pkg/pprof"
	"github.com/github/notifyd/internal/pkg/process"
	"github.com/github/notifyd/internal/pkg/shutdown"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const unitName = "deliver-email-worker"

func main() {
	config.LoadDotEnv()
	cfg := Config{
		Environment: "development",
		Layout: layout.Config{
			FromAddressName: "notifications",
			SenderDomain:    "github.com",
		},
	}
	if err := ghconfig.Load(&cfg); err != nil {
		fmt.Printf("couldn't load config: %v", err)
		process.Exit(process.ConfigLoadError)
	}
	ctx := o11y.CtxSetProcessInfo(context.Background(), cfg.Deployment.Environment, unitName)
	ctx = o11y.CtxSetAqueductInfo(ctx, cfg.AqueductWorker)

	// Telemetry: logs, metrics and exceptions.
	telem, err := telemetry.NewFromConfig(cfg.Telemetry)
	if err != nil {
		fmt.Printf("couldn't initialize telemetry: %v", err)
		process.Exit(process.ConfigLoadError)
	}
	telem.Logger = logs.New(telem.Logger)

	logger := telem.Logger.WithFields(kvp.String("ctx", "boot"))
	logger.WithContext(ctx).Info("booting worker process")

	statter, err := stats.NewClient(cfg.StatsdAddr, "notifyd", cfg.Deployment.Environment)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing stats client"))
	}
	statter = statter.WithTags(ghstats.Tags{"message_source": "aqueduct", "aqueduct_worker": cfg.AqueductWorker.Queue, "notifyd_unit": unitName})

	var exporter ghexceptions.Exporter
	if cfg.ExceptionHTTPExporter {
		exporter, err = ghhttp.NewExporter()
		if err != nil {
			fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "error creating exceptions exporter"))
		}
	} else {
		exporter = writer.NewExporter(os.Stderr)
	}
	reporter, err := exceptions.NewReporter(cfg.Deployment, unitName, exporter)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "error creating exceptions reporter"))
	}

	// Worker pool
	statsCleanup := stats.Run(ctx, nil, statter)

	clock := clockpkg.New()

	var sender email.Sender
	if cfg.SMTPClient == "smtp" {
		sender = email.NewSMTP(cfg.Email, clock, telem, statter)
	} else {
		sender = email.NewLog(telem)
	}

	publisher, err := hydro.NewKafkaPublisher(cfg.Kafka)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing hydro publisher"))
	}
	publisherMetrics := metrics.NewPublisherMetrics(telem, statter)
	tracker := deliverytracking.NewHydroTracker(publisher, publisherMetrics)

	aqueductClient, err := aqueduct.NewClient(cfg.AqueductClient, telem.Logger, statter)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing aqueduct client"))
	}

	apiClient, err := dotcom.NewAPIClient(cfg.MonolithTwirpAPIURL, cfg.MonolithTwirpAPIHMACKey, cfg.CheckerTimeout, telem.Logger)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing monolith-twirp API client"))
	}
	checker := policy.NewChecker(apiClient, telem)

	postProcessor := pipeline.NewMinifier()
	handler := email.NewHandler(checker, sender, tracker, clock, telem, statter, cfg.Layout, postProcessor)
	chain := middlewares.NewChain(cfg.AqueductRetries, "deliver-email", clock, telem, statter, reporter, aqueductClient)

	// Track DeliverEmail messages into our analytics system
	chain.Add(middlewares.NewConcurrentHandler(email.NewTracker(telem, statter, publisher)))

	tenant := tenancy.NewTenant(cfg.Tenancy)
	adapter := email.NewAdapter(clock, telem, tenant, handler, chain)
	worker, err := aqueduct.NewWorker(cfg.AqueductWorker, aqueductClient, telem.Logger, statter, adapter.Run)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing worker"))
	}
	pool := aqueduct.NewPool(cfg.AqueductWorker.ParallelJobs, telem, worker)

	poolCleanup := pool.Run(ctx)
	pprofCleanup := pprof.NewService(cfg.PprofAddr, clock, logger).Run(ctx)

	logger.WithContext(ctx).Info("worker process booted")

	sd := shutdown.New(cfg.ShutdownTimeout, logger)
	sd.Register(shutdown.WrapNoErrorAndContext(poolCleanup))
	sd.Register(shutdown.WrapNoErrorAndContext(tracker.Close))
	sd.Register(shutdown.WrapNoErrorAndContext(statsCleanup))
	sd.Register(pprofCleanup)
	sd.Register(telem.Shutdown)
	if err := sd.Wait(ctx); err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "error shutting down gracefully"))
	}
}

func fail(ctx context.Context, code process.ExitCode, logger log.Logger, err error) {
	logger.WithContext(ctx).WithError(err).Error("failed to initialize the service")
	process.Exit(code)
}
