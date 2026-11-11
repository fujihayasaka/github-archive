// Package main provides the sweagentd-worker binary for background processing of Aqueduct and Hydro events.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/go-stats/ps"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductConsumer "github.com/github/sweagentd/internal/aqueduct/consumer"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/aqueduct/jobs/eventjob"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/encryption"
	"github.com/github/sweagentd/internal/events"
	hydroevents "github.com/github/sweagentd/internal/events/hydro"
	hydrotopics "github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs/store/cosmosdb"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/observability/hydro"
	"github.com/github/sweagentd/internal/readiness"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes"
	"golang.org/x/sync/errgroup"
)

func main() {
	err := mainWithLogging()
	if err != nil {
		fmt.Println("failed to run service:", err)
		os.Exit(1)
	}
}

func mainWithLogging() error {
	cfg, err := config.Load()
	if err != nil {
		return goerrors.Errorf("failed to load config: %w", err)
	}

	obsv, err := cfg.NewObservabilityExporters("worker")
	if err != nil {
		return goerrors.Errorf("failed to create observability exporters: %w", err)
	}
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)

	err = realMain(cfg, obsv)
	if err != nil {
		obsv.Logger.WithError(err).Info("main terminated due to server shutdown")
	}

	return err
}

func realMain(cfg *config.Config, obsv observability.Exporters) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Setup feature flag client
	ffClient, err := newFeatureFlagsClient(cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create feature flag client: %w", err)
	}

	cfg.PopulateFirewallConfiguration(obsv.Logger)

	// CAPI
	capiClient, err := capi.NewClient(obsv, cfg.CopilotAPIURL, cfg.CopilotIntegrationID, cfg.CapiHMACKey)
	if err != nil {
		return goerrors.Errorf("failed to create capi client: %w", err)
	}

	// Cache store for rate limiting and caching
	cacheStore, err := cache.NewCacheStore(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create cache store: %w", err)
	}

	encryptionService, err := encryption.NewEncryptionService(cfg)
	if err != nil {
		return goerrors.Errorf("failed to create encryption service: %w", err)
	}
	tokenCache := cache.NewEncryptedTokenStore(encryptionService, cacheStore, obsv)

	// Rate Limiter
	rateLimitClient, err := github.NewAltClientFactoryFromConfig(obsv, cfg, ffClient, github.WithTokenCacheAlt(tokenCache))
	if err != nil {
		return goerrors.Errorf("failed to create rate limit client: %w", err)
	}

	// GitHub Twirp Client
	ghTwirp, err := githubtwirp.NewClientFromConfig(obsv, ffClient, cacheStore, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create github twirp client: %w", err)
	}

	// App Provider
	copilotApp, apps, err := agenticapp.NewAppsFromConfig(cfg, ghTwirp)
	if err != nil {
		return goerrors.Errorf("failed to create agentic apps: %w", err)
	}
	appProvider := agenticapp.NewProvider(copilotApp, apps...)

	rateLimiter := limiter.NewCacheRateLimiter(rateLimitClient, obsv, cacheStore, appProvider)

	// Github Client
	githubClientFactory, err := github.NewClientFactoryFromConfig(obsv, cfg, ffClient, rateLimiter, appProvider, github.WithTokenCache(tokenCache))
	if err != nil {
		return goerrors.Errorf("failed to create github client factory: %w", err)
	}

	// Experiments
	experimentsClient := experiments.NewClientFromConfig(ctx, cfg, obsv)

	// Spokesd client
	spokesClient, err := spokes.NewClientFromConfig(obsv, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create spokes client: %w", err)
	}

	// Agent Launcher
	al, err := launcher.NewFromConfig(cfg, obsv, ghTwirp, ffClient, githubClientFactory, spokesClient, appProvider)
	if err != nil {
		return goerrors.Errorf("failed to create agent launcher: %w", err)
	}

	// Job store
	jobStore, err := cosmosdb.NewStoreFromConfig(obsv, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create job store: %w", err)
	}

	// Aqueduct Client
	aqueductClient, err := aqueduct.NewClientFromConfig(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create aqueduct client: %w", err)
	}

	customAgentSvc := customagent.NewService(obsv, spokesClient, ghTwirp, ffClient)

	// Job Limiter
	countTracker := limiter.NewJobCountRedisTracker(cacheStore)
	jobLimiter := limiter.NewJobLimiter(jobStore, countTracker)

	// Job Event Emitter
	jobEventEmitter := jobservice.NewHydroJobEventEmitter(obsv.HydroPbl)

	// Job Service
	jobService := jobservice.New(
		obsv,
		ffClient,
		jobStore,
		capiClient,
		githubClientFactory,
		ghTwirp,
		aqueductClient,
		jobLimiter,
		experimentsClient,
		customAgentSvc,
		cfg.GitHubCommitEmail,
		spokesClient,
		appProvider,
		jobEventEmitter,
	)

	// Job Executor
	jobExecutor := jobexecutor.NewAgentJobExecutor(obsv, al, ffClient, ghTwirp, githubClientFactory, jobService, customAgentSvc, appProvider)

	// Create the event handler
	eventHandler := events.NewHandler(obsv, capiClient, ffClient, jobService, jobExecutor, jobStore, ghTwirp, githubClientFactory, appProvider, customAgentSvc)

	// Create the hydro event dispatcher
	hydroevt := hydroevents.NewDispatcher(obsv, ffClient, githubClientFactory, aqueductClient, eventHandler, ghTwirp, cfg.Environment, cfg.EnvironmentName, appProvider)

	// run the procStats in the background
	procStats := &ps.Reporter{
		Stats:    obsv.Statter,
		Interval: time.Second * 5,
	}
	go procStats.Run(ctx)

	// Start a work group so that we can run multiple things in parallel,
	// and if any of the goroutines return an error, we can cancel the
	// context and wait for the other goroutines to exit.
	wg, ctx := errgroup.WithContext(ctx)

	// Start the aqueduct consumer pools
	wg.Go(aqueductConsumer.Run(ctx, cfg, obsv, rateLimiter, aqueductClient,
		aqueductConsumer.EventPoolName,
		aqueductJobs.EventJobWorkerQueues,
		eventjob.Handler(obsv, ffClient, aqueductClient, rateLimiter, appProvider, eventHandler),
	))

	// Start Hydro consumer
	wg.Go(runHydroConsumer(ctx, cfg, obsv, jobStore, hydroevt.Dispatch))

	obsv.Logger.Info("worker up and running")

	return wg.Wait()
}

func newFeatureFlagsClient(cfg *config.Config, obsv observability.Exporters) (ffClient featureflags.Client, err error) {
	switch {
	case cfg.DisableHydroConsumer:
		// Feature flags won't work in ACA or locally, so if the HydroConsumer is disabled, assume its set
		ffClient = featureflags.NewNoopClient(map[string]bool{"copilot_swe_agent": true})
	case cfg.IsDevelopment():
		ffClient, err = featureflags.NewDevClient(context.Background(), cfg.ServiceName, obsv)
		if err != nil {
			return nil, goerrors.Errorf("creating feature flag client: %w", err)
		}
	default:
		ffClient, err = featureflags.NewClient(context.Background(), cfg, obsv)
		if err != nil {
			return nil, goerrors.Errorf("setting up feature flag client: %w", err)
		}
	}

	return ffClient, nil
}

func runHydroConsumer(ctx context.Context, cfg *config.Config, obsv observability.Exporters, healthChecker readiness.HealthChecker, fn hydropkg.MessageHandler) func() error {
	return func() error {
		if cfg.DisableHydroConsumer {
			logMsg := fmt.Sprintf("would've started hydro consumer with parameters: Env: %s, HydroClientID: %s, HydroKafkaVersion: %s, HydroGroupName: %s, HydroBrokers: %v", cfg.EnvironmentName, cfg.HydroClientID, cfg.HydroKafkaVersion, cfg.HydroGroupName, cfg.HydroBrokers)
			obsv.Logger.Info(logMsg)
			obsv.Logger.Info("hydro consumer is disabled, skipping")
			return nil
		}

		hydroSrc, err := hydro.NewConsumer(
			cfg.IsDevelopment(),
			cfg.HydroClientID,
			cfg.HydroKafkaVersion,
			cfg.HydroGroupName,
			cfg.HydroBrokers,
			hydrotopics.Worker, // only consume worker topics
			obsv.Logger,
			obsv.Reporter,
			obsv.Statter,
		)
		if err != nil {
			return goerrors.Errorf("failed to create hydro consumer: %w", err)
		}
		// Make sure to close the consumer before exiting.
		defer hydroSrc.Close()

		if cfg.IsProductionLike() {
			probe := readiness.NewProbe(readiness.WithHealthChecker(healthChecker))
			err = probe.MarkReady(ctx)
			if err != nil {
				return goerrors.Errorf("creating readiness probe file: %w", err)
			}
		}

		err = hydroSrc.Consume(ctx, fn)
		if err != nil && !errors.Is(err, context.Canceled) {
			return goerrors.Errorf("failed to consume hydro event: %w", err)
		}
		return nil
	}
}
