// Package main implements the entrypoint for the notify-worker.
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

	"github.com/github/notifyd/internal/notify"
	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/deliverytracking"
	"github.com/github/notifyd/internal/pkg/dotcom"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/job/middlewares"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/notify/auth"
	"github.com/github/notifyd/internal/pkg/notify/stages"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/o11y/stats"
	"github.com/github/notifyd/internal/pkg/pprof"
	"github.com/github/notifyd/internal/pkg/process"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/shutdown"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const unitName = "notify-worker"

func main() {
	config.LoadDotEnv()
	cfg := Config{
		Environment: "development",
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

	// Database
	db, dbCleanup, err := mysql.New(ctx, cfg.Database, cfg.Environment)
	if err != nil {
		fail(ctx, process.DBConnectionError, logger, errors.Wrap(err, "initializing DB connection"))
	}

	// Worker pool
	statsCleanup := stats.Run(ctx, &db, statter)

	clock := clockpkg.New()

	publisher, err := hydro.NewKafkaPublisher(cfg.Kafka)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing hydro publisher"))
	}
	publisherMetrics := metrics.NewPublisherMetrics(telem, statter)
	tracker := deliverytracking.NewHydroTracker(publisher, publisherMetrics)

	features, err := featureflags.NewClient(cfg.MonolithTwirpAPIURL, cfg.MonolithTwirpAPIHMACKey, telem.Logger)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing feature flag client"))
	}

	aqueductClient, err := aqueduct.NewClient(cfg.AqueductClient, telem.Logger, statter)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing aqueduct client"))
	}

	var authorizer auth.Authorizer
	if cfg.Environment == "development" {
		authorizer = auth.NewDummyAuthorizer()
	} else {
		authorizer, err = auth.NewAuthzdAuthorizer(cfg.AuthzdURL, statter, telem)
		if err != nil {
			fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing authorizer"))
		}
	}

	apiClient, err := dotcom.NewAPIClient(cfg.MonolithTwirpAPIURL, cfg.MonolithTwirpAPIHMACKey, cfg.CheckerTimeout, telem.Logger)
	if err != nil {
		fail(ctx, process.RuntimeError, logger, errors.Wrap(err, "initializing monolith-twirp API client"))
	}
	checker := policy.NewChecker(apiClient, telem)

	subscriptionService := subscriptions.NewService(subscriptions.NewStorage(clock, telem, db), telem, statter)
	calculateRecipients := stages.NewCalculateRecipientsStage(subscriptionService, clock, telem, statter, features)
	authorizeRecipients := stages.NewAuthorizeRecipientsStage(authorizer, clock, telem, statter)
	validateRecipients := stages.NewValidateDotcomRecipientPoliciesStage(checker, clock, telem, statter)

	// Route recipients to channel stage
	routingService := routing.NewRoutingService(routing.NewStorage(clock, telem, db), telem, statter, features)
	routeRecipients := stages.NewRouteRecipientsToChannelsStage(routingService, clock, telem, statter)

	// Schedule notification stages
	metricsPublisher := metrics.NewPublisherMetrics(telem, statter)
	emailPublisher := stages.NewEmailPublisher(aqueductClient, cfg.AqueductClient.App, telem, metricsPublisher)
	scheduleEmail := stages.NewScheduleEmailNotificationsStage(emailPublisher, clock, telem, statter)
	pushPublisher := stages.NewPushPublisher(aqueductClient, cfg.AqueductClient.App, telem, metricsPublisher)
	schedulePush := stages.NewSchedulePushNotificationsStage(cfg.Push, pushPublisher, clock, telem, statter)
	webPublisher := stages.NewWebPublisher(publisher, metricsPublisher)
	scheduleWeb := stages.NewWebScheduler(webPublisher, clock, telem, statter)

	// Notifications service
	route := stages.NewRouteRecipientsStage(authorizeRecipients, routeRecipients, schedulePush, scheduleEmail, scheduleWeb, validateRecipients, clock, telem, statter, features)

	batchQueuePublisher := stages.NewBatchQueuePublisher(aqueductClient, cfg.AqueductClient.App, telem)
	queueBatched := stages.NewQueueBatchedRecipientsStage(batchQueuePublisher, clock, telem, statter)

	notificationService := notify.NewNotificationService(calculateRecipients, authorizeRecipients, validateRecipients, routeRecipients, scheduleEmail, schedulePush, scheduleWeb, route, queueBatched)

	// Handler
	handler := notify.NewHandler(notificationService, features, telem, statter)

	chain := middlewares.NewChain(cfg.AqueductRetries, "notify", clock, telem, statter, reporter, aqueductClient)

	// Concurrently track messages into our analytics system
	chain.Add(middlewares.NewConcurrentHandler(notify.NewTracker(telem, statter, publisher)))

	tenant := tenancy.NewTenant(cfg.Tenancy)
	adapter := notify.NewAdapter(clock, telem, tenant, handler, chain)

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
	sd.Register(shutdown.WrapNoContext(dbCleanup))
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
