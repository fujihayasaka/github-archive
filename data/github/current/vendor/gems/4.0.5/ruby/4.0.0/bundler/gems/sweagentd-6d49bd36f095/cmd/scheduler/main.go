// Package main provides the sweagentd-scheduler binary for periodic execution of interval triggers.
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
	"github.com/github/sweagentd/internal/agenticappsync"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/automations/reconciler"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/config"
	cosmosclient "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/encryption"
	"github.com/github/sweagentd/internal/envrouting"
	"github.com/github/sweagentd/internal/events/hydro/syncmux"
	hydrotopics "github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/store/cosmosdb"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/observability/hydro"
	"github.com/github/sweagentd/internal/readiness"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/scheduler"
	schedulercosmos "github.com/github/sweagentd/internal/scheduler/store/cosmos"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/triggers"
	"golang.org/x/sync/errgroup"
)

func main() {
	err := mainWithLogging()
	if err != nil && !errors.Is(err, context.Canceled) {
		fmt.Println("failed to run service:", err)
		os.Exit(1)
	}
}

func mainWithLogging() error {
	cfg, err := config.Load()
	if err != nil {
		return goerrors.Errorf("failed to load config: %w", err)
	}

	obsv, err := cfg.NewObservabilityExporters("scheduler")
	if err != nil {
		return goerrors.Errorf("failed to create observability exporters: %w", err)
	}
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)

	err = realMain(cfg, obsv)
	if err != nil && !errors.Is(err, context.Canceled) {
		obsv.Logger.WithError(err).Error("unexpected main termination")
	} else if err != nil {
		obsv.Logger.WithError(err).Info("main terminated due to server shutdown")
	}

	return err
}

func realMain(cfg *config.Config, obsv observability.Exporters) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Report process stats
	procStats := &ps.Reporter{
		Stats:    obsv.Statter,
		Interval: time.Second * 5,
	}
	go procStats.Run(ctx)

	// Setup feature flag client
	ffClient, err := newSchedulerFeatureFlagsClient(cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create feature flag client: %w", err)
	}

	// Cache store
	cacheStore, err := cache.NewCacheStore(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create cache store: %w", err)
	}

	encryptionService, err := encryption.NewEncryptionService(cfg)
	if err != nil {
		return goerrors.Errorf("failed to create encryption service: %w", err)
	}
	tokenCache := cache.NewEncryptedTokenStore(encryptionService, cacheStore, obsv, ffClient)

	// GitHub Twirp Client
	ghTwirp, err := githubtwirp.NewClientFromConfig(obsv, ffClient, cacheStore, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create github twirp client: %w", err)
	}

	// App Provider
	copilotApp, apps, err := agenticapp.NewApps(ctx, cfg, ghTwirp, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create agentic apps: %w", err)
	}
	appProvider := agenticapp.NewProvider(copilotApp, apps...).
		WithReloadOnMiss(agenticapp.NewReloadFunc(cfg, ghTwirp, obsv), obsv.Logger, obsv.Statter).
		WithVersionSync(cacheStore, agenticapp.DefaultVersionCheckInterval)

	// Integration sync handler (reloads agentic app registry on integration updates)
	appSyncHandler := agenticappsync.NewHandler(obsv, ghTwirp, cfg, appProvider)
	// Rate limiter client
	rateLimitClient, err := github.NewAltClientFactoryFromConfig(obsv, cfg, ffClient, github.WithTokenCacheAlt(tokenCache))
	if err != nil {
		return goerrors.Errorf("failed to create rate limit client: %w", err)
	}
	rateLimiter := limiter.NewCacheRateLimiter(rateLimitClient, obsv, cacheStore, appProvider)

	// GitHub Client Factory
	githubClientFactory, err := github.NewClientFactoryFromConfig(obsv, cfg, ffClient, rateLimiter, appProvider, github.WithTokenCache(tokenCache), github.WithTwirpClient(ghTwirp))
	if err != nil {
		return goerrors.Errorf("failed to create github client factory: %w", err)
	}

	// CAPI
	capiClient, err := capi.NewClient(obsv, cfg.CopilotAPIURL, cfg.CopilotIntegrationID, cfg.CapiHMACKey, ffClient)
	if err != nil {
		return goerrors.Errorf("failed to create capi client: %w", err)
	}

	// Spokes client
	spokesClient, err := spokes.NewClientFromConfig(obsv, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create spokes client: %w", err)
	}

	// Experiments
	// TODO: Remove once all experiment access migrates to exp-go-sdk.
	experimentsClient := experiments.NewClientFromConfig(ctx, cfg, obsv)

	// exp-go-sdk client for local experiment evaluation via Azure Blob config.
	expSDKClient, err := exp.NewClientFromConfig(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create exp-go-sdk client: %w", err)
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
	jobLimiter := limiter.NewJobLimiter(jobStore, countTracker, appProvider)

	// Job Event Emitter
	jobEventEmitter := jobservice.NewHydroJobEventEmitter(obsv.HydroPbl)

	// Job Service
	committerName, committerEmail := cfg.CommitterIdentity()
	jobSvc := jobservice.New(
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
		committerName,
		committerEmail,
		spokesClient,
		appProvider,
		jobEventEmitter,
	).WithExpSDKClient(expSDKClient)

	// Setup Cosmos clients for scheduler-specific stores
	cosmosOpts := cosmosclient.Opts{
		ConnectionString:         cfg.AzureCosmosDBConnectionString,
		Endpoint:                 cfg.AzureCosmosDBEndpoint,
		Obsv:                     obsv,
		AzureCosmosDBSPNTenantID: cfg.AzureCosmosDBSPNTenantID,
		AzureCosmosDBSPNClientID: cfg.AzureCosmosDBSPNClientID,
	}

	triggerStore, err := schedulercosmos.NewStoreFromOpts(&cosmosclient.ContainerOpts{
		Opts:        cosmosOpts,
		DatabaseID:  cfg.AzureCosmosDBDatabase,
		ContainerID: cfg.AzureCosmosDBContainerIntervalTriggers,
	})
	if err != nil {
		return goerrors.Errorf("failed to create interval trigger store: %w", err)
	}

	// Create scheduling hook and executor
	schedulingHook := scheduler.NewDefaultSchedulingHook(cfg.SchedulerBatchSize)
	triggerChecker := triggers.NewChecker(nil, ghTwirp, obsv)
	automationLookup := newSchedulerAutomationLookup(cfg, obsv, triggerChecker)
	executor := scheduler.NewExecutor(githubClientFactory, triggerChecker, appProvider, jobSvc, ffClient, obsv, automationLookup)

	// Cross-stamp gate: prevents every environment's scheduler from racing on the shared interval-triggers container.
	envRouter := envrouting.NewRouter(ffClient, cfg.Environment, cfg.EnvironmentName)

	// Determine worker ID from pod name or hostname
	workerID := cfg.KubePodName
	if workerID == "" || workerID == "sweagentd" {
		hostname, _ := os.Hostname()
		workerID = hostname
	}

	// Create and run the scheduler
	sched := scheduler.New(
		triggerStore,
		executor,
		schedulingHook,
		envRouter,
		obsv,
		workerID,
		cfg.SchedulerTickInterval,
		time.Minute,
		cfg.SchedulerStaleLockThreshold,
	)

	wg, ctx := errgroup.WithContext(ctx)

	wg.Go(func() error {
		return sched.Run(ctx)
	})

	// Build the sync handler map for the scheduler's Hydro consumer.
	syncHandlers, syncTopics, err := buildSyncHandlers(cfg, obsv, triggerStore, schedulingHook, appSyncHandler, envRouter)
	if err != nil {
		return err
	}

	syncDispatch := syncmux.New(syncHandlers)
	wg.Go(runSyncConsumer(ctx, cfg, obsv, syncDispatch.Dispatch, syncTopics))

	// Mark the pod as ready
	if cfg.IsProductionLike() {
		probe := readiness.NewProbe()
		err := probe.MarkReady(ctx)
		if err != nil {
			return goerrors.Errorf("creating readiness probe file: %w", err)
		}
	}

	obsv.Logger.Info("scheduler up and running")

	return wg.Wait()
}

func newSchedulerFeatureFlagsClient(cfg *config.Config, obsv observability.Exporters) (featureflags.Client, error) {
	switch {
	case cfg.IsDevelopment():
		return featureflags.NewDevClient(context.Background(), cfg.ServiceName, obsv)
	default:
		return featureflags.NewClient(context.Background(), cfg, obsv)
	}
}

// buildSyncHandlers assembles the topic-to-handler map and the topic list for
// the scheduler's Hydro sync consumer.
func buildSyncHandlers(
	cfg *config.Config,
	obsv observability.Exporters,
	triggerStore *schedulercosmos.Store,
	schedulingHook scheduler.SchedulingHook,
	appSyncHandler *agenticappsync.Handler,
	envRouter *envrouting.Router,
) (map[string]hydropkg.MessageHandler, []string, error) {
	handlers := map[string]hydropkg.MessageHandler{
		hydrotopics.IntegrationCreate: appSyncHandler.Dispatch,
		hydrotopics.IntegrationUpdate: appSyncHandler.Dispatch,
	}
	topicsList := []string{hydrotopics.IntegrationCreate, hydrotopics.IntegrationUpdate}

	automationReconciler := reconciler.NewHandler(triggerStore, envRouter, schedulingHook, obsv)
	handlers[hydrotopics.AutomationLifecycleChanged] = automationReconciler.Dispatch
	topicsList = append(topicsList, hydrotopics.AutomationLifecycleChanged)
	return handlers, topicsList, nil
}

// newSchedulerAutomationLookup builds the automation lookup the executor uses
// to resolve CMC-sourced interval trigger records.
func newSchedulerAutomationLookup(cfg *config.Config, obsv observability.Exporters, triggerChecker *triggers.Checker) automations.Lookup {
	legacy := automations.NewLegacyLookup(triggerChecker)
	if cfg.CopilotMissionControlTwirpURL == "" {
		return legacy
	}
	cmcClient, err := automations.NewCMCAutomationsClientFromConfig(cfg, obsv)
	if err != nil {
		obsv.Logger.WithError(err).Error("scheduler: failed to create CMC automations client, falling back to legacy lookup")
		return legacy
	}
	return automations.NewCMCLookup(cmcClient, legacy, obsv, time.Duration(cfg.CopilotMissionControlTwirpRequestTimeoutMs)*time.Millisecond)
}

func runSyncConsumer(ctx context.Context, cfg *config.Config, obsv observability.Exporters, fn hydropkg.MessageHandler, syncTopics []string) func() error {
	return func() error {
		if cfg.DisableHydroConsumer {
			obsv.Logger.Info("sync: hydro consumer disabled, skipping")
			return nil
		}

		hydroSrc, err := hydro.NewConsumer(
			cfg.IsDevelopment(),
			cfg.HydroClientID,
			cfg.HydroKafkaVersion,
			cfg.HydroSyncGroupName,
			cfg.HydroBrokers,
			syncTopics,
			obsv.Logger,
			obsv.Reporter,
			obsv.Statter,
		)
		if err != nil {
			return goerrors.Errorf("failed to create sync hydro consumer: %w", err)
		}
		defer hydroSrc.Close()

		obsv.Logger.Info("sync: hydro consumer started")

		err = hydroSrc.Consume(ctx, fn)
		if err != nil && !errors.Is(err, context.Canceled) {
			return goerrors.Errorf("failed to consume sync hydro event: %w", err)
		}
		return nil
	}
}
