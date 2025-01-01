// Package main implements the entrypoint for the api.
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strings"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-chatops/v2"
	ghconfig "github.com/github/go-config"
	ghexceptions "github.com/github/go-exceptions"
	ghhttp "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-http/v2/middleware/hmac"
	hydroclient "github.com/github/hydro-client-go/v7/pkg/hydro"
	"go.opentelemetry.io/otel"

	"github.com/github/notifyd/internal/api/apiservice"
	"github.com/github/notifyd/internal/api/chatopsserver"
	"github.com/github/notifyd/internal/api/chatopsservice"
	devicetokensserver "github.com/github/notifyd/internal/api/devicetokensserver/v2"
	"github.com/github/notifyd/internal/api/maintenanceserver"
	"github.com/github/notifyd/internal/api/newsiesserver"
	"github.com/github/notifyd/internal/api/newsiesservice"
	"github.com/github/notifyd/internal/api/routingsettingsserver"
	"github.com/github/notifyd/internal/api/subscriptionsserver"
	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/hydro"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/notify/stages"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/o11y/stats"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pprof"
	"github.com/github/notifyd/internal/pkg/process"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/shutdown"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

const unitName = "api"

func main() {
	config.LoadDotEnv()
	cfg := Config{Environment: "development"}
	if err := ghconfig.Load(&cfg); err != nil {
		fmt.Printf("couldn't load config: %v", err)
		process.Exit(process.ConfigLoadError)
	}
	ctx := o11y.CtxSetProcessInfo(context.Background(), cfg.Deployment.Environment, unitName)

	// Telemetry: logs, metrics and exceptions.
	telem, err := telemetry.NewFromConfig(cfg.Telemetry)
	if err != nil {
		fmt.Printf("couldn't initialize telemetry: %v", err)
		process.Exit(process.ConfigLoadError)
	}
	telem.Logger = logs.New(telem.Logger)

	logger := telem.Logger.WithContext(ctx).WithFields(kvp.String("ctx", "boot"))
	logger.WithContext(ctx).Info("booting api process")

	otel.SetErrorHandler(tracing.NewErrorHandler(logger))
	tracing.SetTracer(telem.Tracer.Tracer)
	tracing.SetProvider(telem.Tracer.Provider)

	statter, err := stats.NewClient(cfg.StatsdAddr, "notifyd."+unitName, cfg.Deployment.Environment)
	if err != nil {
		fail(process.RuntimeError, logger, errors.Wrap(err, "error loading statter for API"))
	}

	var exporter ghexceptions.Exporter
	if cfg.ExceptionHTTPExporter {
		exporter, err = ghhttp.NewExporter()
		if err != nil {
			fail(process.RuntimeError, logger, errors.Wrap(err, "error creating exceptions exporter"))
		}
	} else {
		exporter = writer.NewExporter(os.Stderr)
	}
	reporter, err := exceptions.NewReporter(cfg.Deployment, unitName, exporter)
	if err != nil {
		fail(process.RuntimeError, logger, errors.Wrap(err, "error creating exceptions reporter"))
	}

	// Database
	db, dbCleanup, err := mysql.New(ctx, cfg.Database, cfg.Environment)
	if err != nil {
		fail(process.DBConnectionError, logger, errors.Wrap(err, "error initializing DB"))
	}

	// Feature flags client
	features, err := featureflags.NewClient(cfg.MonolithTwirpAPIURL, cfg.MonolithTwirpAPIHMACKey, telem.Logger)
	if err != nil {
		fail(process.RuntimeError, logger, errors.Wrap(err, "error creating feature flag client"))
	}

	// Hydro client
	hydroPublisher, err := newHydroPublisher(cfg.Environment, cfg.Kafka)
	if err != nil {
		fail(process.KafkaInitError, logger, errors.Wrap(err, "initializing hydro publisher"))
	}

	clock := clockpkg.New()
	tokensStorage := devicetokens.NewStorage(clock, telem, statter, db)
	settingsStorage := routing.NewStorage(clock, telem, db)
	settingsService := routing.NewSettingsService(settingsStorage, telem, statter)
	settingsServer := routingsettingsserver.NewServer(settingsService, telem, statter, clock)
	routingService := routing.NewRoutingService(settingsStorage, telem, statter, features)
	subscriptionsStorage := subscriptions.NewStorage(clock, telem, db)
	subscriptionsService := subscriptions.NewService(subscriptionsStorage, telem, statter)
	subscriptionsServer := subscriptionsserver.NewServer(subscriptionsService, telem)
	newsiesService := newsiesservice.NewService(settingsService, subscriptionsService, statter, clock)
	newsiesServer := newsiesserver.New(newsiesService, telem)
	routeToChannels := stages.NewRouteRecipientsToChannelsStage(routingService, clock, telem, statter)

	ops := []chatops.Chatop{
		chatopsserver.PingChatop(),
		chatopsserver.HMACChatop(cfg.API.HmacKeys, telem),
		chatopsserver.RouteTest(routeToChannels),
	}
	var chatopsServer http.Handler
	chatopsHandler, err := chatopsserver.NewChatopsHandler(cfg.Chatops, telem, ops)
	if err != nil {
		logger.WithError(err).Error("error building chatops handler")
	} else {
		chatopsServer = chatopsserver.NewChatopsServer(chatopsHandler)
	}
	chatopsService := chatopsservice.NewService(cfg.Chatops.Addr, telem, chatopsServer)

	// API service
	hooks, err := apiservice.NewHooks(ctx, telem.Logger.WithContext(ctx), statter)
	if err != nil {
		fail(process.RuntimeError, logger, errors.Wrap(err, "error creating twirp hooks"))
	}

	hmacValidator := &hmac.Validator{
		Secrets: strings.Split(cfg.API.HmacKeys, " "),
		Logger:  logger,
	}

	apiService := apiservice.NewService(
		cfg.API,
		tenancy.NewTenant(cfg.Tenancy),
		clock,
		telem,
		reporter,
		hooks,
		hmacValidator,
		devicetokensserver.NewServer(clock, telem, tokensStorage),
		subscriptionsServer,
		settingsServer,
		maintenanceserver.NewServer(hydroPublisher, telem, metrics.NewPublisherMetrics(telem, statter)),
		newsiesServer,
	)

	pprofService := pprof.NewService(cfg.PprofAddr, clock, logger)

	// Run services
	chatopsCleanup := chatopsService.Run(ctx)
	apiCleanup := apiService.Run(ctx)
	statsCleanup := stats.Run(ctx, &db, statter)
	pprofCleanup := pprofService.Run(ctx)

	// Graceful shutdown
	sd := shutdown.New(cfg.ShutdownTimeout, logger)
	sd.Register(chatopsCleanup)
	sd.Register(apiCleanup)
	sd.Register(shutdown.WrapNoErrorAndContext(statsCleanup))
	sd.Register(shutdown.WrapNoContext(dbCleanup))
	sd.Register(pprofCleanup)
	sd.Register(telem.Shutdown)
	if err := sd.Wait(ctx); err != nil {
		fail(process.ShutdownError, logger, errors.Wrap(err, "error shutting down gracefully"))
	}
}

func fail(code process.ExitCode, logger log.Logger, err error) {
	logger.WithError(err).Error("failed to initialize the service")
	process.Exit(code)
}

func newHydroPublisher(env string, cfg hydro.Config) (*hydroclient.Publisher, error) {
	if env == "test" {
		// The MemorySink writes events to a channel.
		events := make(chan hydroclient.Message, 100)
		sink, err := hydroclient.NewMemorySink(events)
		if err != nil {
			return nil, err
		}
		return hydroclient.NewPublisher(sink)
	}
	return hydro.NewKafkaPublisher(cfg)
}
