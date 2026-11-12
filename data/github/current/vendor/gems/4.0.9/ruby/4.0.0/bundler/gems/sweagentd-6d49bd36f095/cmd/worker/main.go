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

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats/ps"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticappsync"
	"github.com/github/sweagentd/internal/agentsync"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductConsumer "github.com/github/sweagentd/internal/aqueduct/consumer"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/aqueduct/jobs/eventjob"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/config"
	cosmosclient "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/customagent"
	agentcosmos "github.com/github/sweagentd/internal/customagent/store/cosmos"
	"github.com/github/sweagentd/internal/encryption"
	"github.com/github/sweagentd/internal/envrouting"
	"github.com/github/sweagentd/internal/events"
	hydroevents "github.com/github/sweagentd/internal/events/hydro"
	"github.com/github/sweagentd/internal/events/hydro/syncmux"
	hydrotopics "github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/experiments/exp"
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
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/readiness"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/triggers"
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
	capiClient, err := capi.NewClient(obsv, cfg.CopilotAPIURL, cfg.CopilotIntegrationID, cfg.CapiHMACKey, ffClient)
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
	tokenCache := cache.NewEncryptedTokenStore(encryptionService, cacheStore, obsv, ffClient)

	// GitHub Twirp Client
	ghTwirp, err := githubtwirp.NewClientFromConfig(obsv, ffClient, cacheStore, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create github twirp client: %w", err)
	}

	// Rate Limiter
	rateLimitClient, err := github.NewAltClientFactoryFromConfig(obsv, cfg, ffClient, github.WithTokenCacheAlt(tokenCache), github.WithTwirpClientAlt(ghTwirp))
	if err != nil {
		return goerrors.Errorf("failed to create rate limit client: %w", err)
	}

	// App Provider
	copilotApp, apps, err := agenticapp.NewApps(ctx, cfg, ghTwirp, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create agentic apps: %w", err)
	}
	appProvider := agenticapp.NewProvider(copilotApp, apps...).
		WithReloadOnMiss(agenticapp.NewReloadFunc(cfg, ghTwirp, obsv), obsv.Logger, obsv.Statter).
		WithVersionSync(cacheStore, agenticapp.DefaultVersionCheckInterval)

	rateLimiter := limiter.NewCacheRateLimiter(rateLimitClient, obsv, cacheStore, appProvider)

	// Github Client
	githubClientFactory, err := github.NewClientFactoryFromConfig(obsv, cfg, ffClient, rateLimiter, appProvider, github.WithTokenCache(tokenCache), github.WithTwirpClient(ghTwirp))
	if err != nil {
		return goerrors.Errorf("failed to create github client factory: %w", err)
	}

	// Legacy: TAS HTTP API client - used by existing GetFeatureAssignment() calls.
	// TODO: Remove once all experiment access migrates to exp-go-sdk.
	experimentsClient := experiments.NewClientFromConfig(ctx, cfg, obsv)

	// exp-go-sdk client for local experiment evaluation via Azure Blob config.
	expSDKClient, err := exp.NewClientFromConfig(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create exp-go-sdk client: %w", err)
	}

	// Spokesd client
	spokesClient, err := spokes.NewClientFromConfig(obsv, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create spokes client: %w", err)
	}

	// Agent Launcher Builder
	launcherBuilder, err := launcher.NewBuilderFromConfig(cfg, obsv, ghTwirp, ffClient, githubClientFactory, spokesClient, appProvider)
	if err != nil {
		return goerrors.Errorf("failed to create agent launcher builder: %w", err)
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
		committerName,
		committerEmail,
		spokesClient,
		appProvider,
		jobEventEmitter,
	).WithExpSDKClient(expSDKClient)

	// Job Executor
	pluginsSvc := plugins.NewService(obsv, spokesClient, ghTwirp, cfg.GitHubServerURL)
	jobExecutor := jobexecutor.NewAgentJobExecutor(obsv, launcherBuilder, ffClient, ghTwirp, githubClientFactory, jobService, customAgentSvc, pluginsSvc, appProvider)

	// Trigger checker for custom agent trigger evaluation from the store
	triggerChecker, repoAgentStore := newTriggerChecker(cfg, obsv, ffClient, ghTwirp)
	legacyAutomationLookup := automations.NewLegacyLookup(triggerChecker)
	cmcAutomationsClient, err := automations.NewCMCAutomationsClientFromConfig(cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create CMC automations client: %w", err)
	}
	baseLookup := automations.NewCMCLookup(cmcAutomationsClient, legacyAutomationLookup, obsv, time.Duration(cfg.CopilotMissionControlTwirpRequestTimeoutMs)*time.Millisecond)
	automationLookup := baseLookup
	var cachedLookup *automations.CachedLookup
	if baseLookup != nil && cfg.AutomationLookupCacheSize > 0 {
		cachedLookup = automations.NewCachedLookup(baseLookup, cfg.AutomationLookupCacheSize, cfg.AutomationLookupCacheTTL).
			WithStats(&obsv)
		automationLookup = cachedLookup
		obsv.Logger.Info("automations: in-memory HasActiveForEvent cache enabled",
			kvp.Int("size", cfg.AutomationLookupCacheSize),
			kvp.Duration("ttl", cfg.AutomationLookupCacheTTL))
	}

	// Create the event handler
	eventHandler := events.NewHandler(obsv, capiClient, ffClient, jobService, jobExecutor, jobStore, ghTwirp, githubClientFactory, appProvider, customAgentSvc, automationLookup)

	// Create the hydro event dispatcher
	hydroevt := hydroevents.NewDispatcher(obsv, ffClient, githubClientFactory, aqueductClient, eventHandler, ghTwirp, cfg.Environment, cfg.EnvironmentName, appProvider, automationLookup)

	// Agent config sync handler (shares the repo agent store with the trigger checker).
	var invalidator func(repoID int64)
	if cachedLookup != nil {
		invalidator = cachedLookup.InvalidateRepo
	}
	agentSyncHandler := newAgentSyncHandler(cfg, obsv, spokesClient, ffClient, ghTwirp, repoAgentStore, invalidator)

	// Integration sync handler (reloads agentic app registry on integration updates)
	integrationSyncHandler := agenticappsync.NewHandler(obsv, ghTwirp, cfg, appProvider)

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
	wg.Go(aqueductConsumer.Run(ctx, cfg, obsv, rateLimiter, aqueductClient, ffClient,
		aqueductConsumer.EventPoolName,
		aqueductJobs.EventJobWorkerQueues,
		eventjob.Handler(obsv, ffClient, aqueductClient, rateLimiter, appProvider, eventHandler),
		nil,
	))

	// Start Hydro consumer
	wg.Go(runHydroConsumer(ctx, cfg, obsv, jobStore, hydroevt.Dispatch))

	// Start Hydro sync consumer (separate topic group) with topic-based routing
	syncDispatch, syncTopics := newSyncDispatcher(agentSyncHandler, integrationSyncHandler)
	if syncDispatch != nil {
		wg.Go(runSyncConsumer(ctx, cfg, obsv, syncTopics, syncDispatch))
	}

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
			logMsg := fmt.Sprintf("would've started hydro consumer with parameters: Env: %s, HydroClientID: %s, HydroKafkaVersion: %s, HydroGroupName: %s, HydroBrokers: %v", cfg.EnvironmentName, cfg.HydroClientID, cfg.HydroKafkaVersion, cfg.HydroWorkerGroupName, cfg.HydroBrokers)
			obsv.Logger.Info(logMsg)
			obsv.Logger.Info("hydro consumer is disabled, skipping")
			return nil
		}

		hydroSrc, err := hydro.NewConsumer(
			cfg.IsDevelopment(),
			cfg.HydroClientID,
			cfg.HydroKafkaVersion,
			cfg.HydroWorkerGroupName,
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

func newTriggerChecker(cfg *config.Config, obsv observability.Exporters, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface) (*triggers.Checker, *agentcosmos.Store) {
	if cfg.IsDevelopment() && cfg.AzureCosmosDBConnectionString == "" {
		obsv.Logger.Info("triggers: skipping trigger checker in development (no CosmosDB)")
		return nil, nil
	}

	repoStore, err := newRepoAgentStore(cfg, obsv, ffClient)
	if err != nil {
		obsv.Logger.WithError(err).Error("triggers: failed to create repo agent store, trigger checking disabled")
		return nil, nil
	}

	return triggers.NewChecker(repoStore, ghTwirp, obsv), repoStore
}

func newAgentSyncHandler(cfg *config.Config, obsv observability.Exporters, spokesClient *spokes.Client, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface, repoStore *agentcosmos.Store, invalidator func(repoID int64)) *agentsync.Handler {
	if cfg.IsDevelopment() && cfg.AzureCosmosDBConnectionString == "" {
		obsv.Logger.Info("agentsync: skipping agent sync handler in development (no CosmosDB)")
		return nil
	}

	// Use the shared repo store if available, otherwise create a new one.
	if repoStore == nil {
		var err error
		repoStore, err = newRepoAgentStore(cfg, obsv, ffClient)
		if err != nil {
			obsv.Logger.WithError(err).Error("agentsync: failed to create repo agent store, sync disabled")
			return nil
		}
	}

	cosmosOpts := cosmosclient.Opts{
		ConnectionString:         cfg.AzureCosmosDBConnectionString,
		Endpoint:                 cfg.AzureCosmosDBEndpoint,
		Obsv:                     obsv,
		AzureCosmosDBSPNTenantID: cfg.AzureCosmosDBSPNTenantID,
		AzureCosmosDBSPNClientID: cfg.AzureCosmosDBSPNClientID,
	}

	orgStore, err := agentcosmos.NewStoreFromOpts(&cosmosclient.ContainerOpts{
		Opts:        cosmosOpts,
		DatabaseID:  cfg.AzureCosmosDBDatabase,
		ContainerID: cfg.AzureCosmosDBContainerOrganizationAgents,
	})
	if err != nil {
		obsv.Logger.WithError(err).Error("agentsync: failed to create org agent store, sync disabled")
		return nil
	}

	enterpriseStore, err := agentcosmos.NewStoreFromOpts(&cosmosclient.ContainerOpts{
		Opts:        cosmosOpts,
		DatabaseID:  cfg.AzureCosmosDBDatabase,
		ContainerID: cfg.AzureCosmosDBContainerEnterpriseAgents,
	})
	if err != nil {
		obsv.Logger.WithError(err).Error("agentsync: failed to create enterprise agent store, sync disabled")
		return nil
	}

	enterpriseResolver := agentsync.NewTwirpEnterpriseResolver(ghTwirp.SweagentdAPI())

	var handlerOpts []agentsync.HandlerOption

	envRouter := envrouting.NewRouter(ffClient, cfg.Environment, cfg.EnvironmentName)

	// Wire downstream cache invalidation if provided.
	if invalidator != nil {
		handlerOpts = append(handlerOpts, agentsync.WithRepoInvalidator(invalidator))
	}

	return agentsync.NewHandler(
		spokesClient,
		repoStore,
		orgStore,
		enterpriseStore,
		ffClient,
		enterpriseResolver,
		envRouter,
		obsv,
		handlerOpts...,
	)
}

func newRepoAgentStore(cfg *config.Config, obsv observability.Exporters, ffClient featureflags.Client) (*agentcosmos.Store, error) {
	cosmosOpts := cosmosclient.Opts{
		ConnectionString:         cfg.AzureCosmosDBConnectionString,
		Endpoint:                 cfg.AzureCosmosDBEndpoint,
		Obsv:                     obsv,
		AzureCosmosDBSPNTenantID: cfg.AzureCosmosDBSPNTenantID,
		AzureCosmosDBSPNClientID: cfg.AzureCosmosDBSPNClientID,
	}

	return agentcosmos.NewStoreFromOpts(&cosmosclient.ContainerOpts{
		Opts:        cosmosOpts,
		DatabaseID:  cfg.AzureCosmosDBDatabase,
		ContainerID: cfg.AzureCosmosDBContainerRepositoryAgents,
	})
}

func runSyncConsumer(ctx context.Context, cfg *config.Config, obsv observability.Exporters, topics []string, fn hydropkg.MessageHandler) func() error {
	return func() error {
		if cfg.DisableHydroConsumer {
			obsv.Logger.Info("sync: hydro consumer disabled, skipping")
			return nil
		}

		if len(topics) == 0 {
			obsv.Logger.Info("sync: no topics to consume, skipping")
			return nil
		}

		hydroSrc, err := hydro.NewConsumer(
			cfg.IsDevelopment(),
			cfg.HydroClientID,
			cfg.HydroKafkaVersion,
			cfg.HydroSyncGroupName,
			cfg.HydroBrokers,
			topics,
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

// newSyncDispatcher creates a topic-based multiplexer for the sync consumer.
// It routes AgentsUpdated to the agentsync handler and IntegrationCreate/IntegrationUpdate
// to the integrationsync handler. Returns nil if no handlers are available.
// The returned topics slice contains only topics with registered handlers.
func newSyncDispatcher(agentSyncHandler *agentsync.Handler, integrationSyncHandler *agenticappsync.Handler) (hydropkg.MessageHandler, []string) {
	handlers := make(map[string]hydropkg.MessageHandler)

	if agentSyncHandler != nil {
		handlers[hydrotopics.AgentsUpdated] = agentSyncHandler.Dispatch
	}

	if integrationSyncHandler != nil {
		handlers[hydrotopics.IntegrationCreate] = integrationSyncHandler.Dispatch
		handlers[hydrotopics.IntegrationUpdate] = integrationSyncHandler.Dispatch
	}

	if len(handlers) == 0 {
		return nil, nil
	}

	topics := make([]string, 0, len(handlers))
	for topic := range handlers {
		topics = append(topics, topic)
	}

	mux := syncmux.New(handlers)
	return mux.Dispatch, topics
}
