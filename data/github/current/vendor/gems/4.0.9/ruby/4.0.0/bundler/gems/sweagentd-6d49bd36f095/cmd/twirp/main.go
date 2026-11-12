// Package main provides the Twirp server entry point for sweagentd.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/github/go-server/hosting/httphost"
	"github.com/github/go-server/hosting/httphost/twirpapi"
	twirphooks "github.com/github/go-server/hosting/httphost/twirpapi/hooks"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticappsync"
	"github.com/github/sweagentd/internal/api/quotaapi"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/encryption"
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
	"github.com/github/sweagentd/internal/sandbox"
	"github.com/github/sweagentd/internal/sandbox/stopguard"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/twirpserver"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"
)

func main() {
	err := realMain()
	if err != nil && !errors.Is(err, context.Canceled) {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
}

func realMain() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return goerrors.Errorf("failed to load configuration: %w", err)
	}

	host, err := newTwirpHost(cfg)
	if err != nil {
		return err
	}

	obsv, err := hostToObsv(cfg, host)
	if err != nil {
		return goerrors.Errorf("failed to setup observability exporters: %w", err)
	}
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)

	// Convert go-server runtime feature flag bits to our internal feature flag client
	ffClient := featureflags.NewClientWithExistingVexiClient(host.Flagger(), obsv)

	jobStore, err := cosmosdb.NewStoreFromConfig(obsv, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create job store: %w", err)
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

	// Integration sync handler (reloads agentic app registry on integration updates)
	appSyncHandler := agenticappsync.NewHandler(obsv, ghTwirp, cfg, appProvider)

	rateLimiter := limiter.NewCacheRateLimiter(rateLimitClient, obsv, cacheStore, appProvider)

	capiClient, err := capi.NewClient(obsv, cfg.CopilotAPIURL, cfg.CopilotIntegrationID, cfg.CapiHMACKey, ffClient)
	if err != nil {
		return goerrors.Errorf("failed to create capi client: %w", err)
	}

	githubClientFactory, err := github.NewClientFactoryFromConfig(obsv, cfg, ffClient, rateLimiter, appProvider, github.WithTokenCache(tokenCache), github.WithTwirpClient(ghTwirp))
	if err != nil {
		return goerrors.Errorf("failed to create github client factory: %w", err)
	}

	// Spokesd client
	spokesClient, err := spokes.NewClientFromConfig(obsv, cfg)
	if err != nil {
		return goerrors.Errorf("failed to create spokes client: %w", err)
	}

	customAgentSvc := customagent.NewService(obsv, spokesClient, ghTwirp, ffClient)

	// Create aqueduct client
	aqueductClient, err := aqueduct.NewClientFromConfig(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create aqueduct client: %w", err)
	}

	// Experiments
	// TODO: Remove once all experiment access migrates to exp-go-sdk.
	experimentsClient := experiments.NewClientFromConfig(ctx, cfg, obsv)

	// exp-go-sdk client for local experiment evaluation via Azure Blob config.
	expSDKClient, err := exp.NewClientFromConfig(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create exp-go-sdk client: %w", err)
	}

	// Create job limiter
	countTracker := limiter.NewJobCountRedisTracker(cacheStore)
	jobLimiter := limiter.NewJobLimiter(jobStore, countTracker, appProvider)

	// Create job service
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
		jobservice.NewHydroJobEventEmitter(obsv.HydroPbl),
	).WithExpSDKClient(expSDKClient)

	// Agent launcher builder (needed for cancelling running jobs)
	launcherBuilder, err := launcher.NewBuilderFromConfig(cfg, obsv, ghTwirp, ffClient, githubClientFactory, spokesClient, appProvider)
	if err != nil {
		return goerrors.Errorf("failed to create agent launcher builder: %w", err)
	}

	// Job executor (provides cancel logic)
	pluginsSvc := plugins.NewService(obsv, spokesClient, ghTwirp, cfg.GitHubServerURL)
	je := jobexecutor.NewAgentJobExecutor(obsv, launcherBuilder, ffClient, ghTwirp, githubClientFactory, jobService, customAgentSvc, pluginsSvc, appProvider)

	// Sandbox service
	sandboxSvc := sandbox.NewService(obsv, ffClient, ghTwirp, sandbox.ServiceOpts{
		LaunchTwirpBaseURL:        cfg.LaunchTwirpAPIURL,
		LaunchTwirpHMACKey:        cfg.LaunchTwirpHMACKey,
		MissionControlBaseURL:     cfg.SandboxMCBaseURL,
		UseDockerBackend:          cfg.SandboxUseDocker,
		GitHubServerURL:           cfg.GitHubServerURL,
		CopilotAPIURL:             cfg.CopilotAPIURL,
		RequiredFirewallAllowList: cfg.AgentFirewallRequiredAllowList,
	})

	// setup twirp
	s := twirpserver.NewServer(obsv, githubClientFactory, ghTwirp, jobStore, jobService, ffClient, appProvider, je, sandboxSvc, aqueductClient, stopguard.New(cacheStore, stopguard.DefaultTTL)).
		WithMemoryService(newLazyMemoryService(cfg, ffClient, obsv, ghTwirp))

	// Build a custom hooks chain that replaces the default go-twirp logging hooks
	// (which use a captured logger without trace context) with our LogInterceptor
	// that calls WithSpanContext(ctx) to include TraceId/SpanId in every log line.
	customHooks := twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twirphooks.LoggingTraceFieldsHook(),
	)
	interceptors := twirp.WithServerInterceptors(LogInterceptor(host.Logger()))
	quotaAPIHandler := quotaapi.NewHandler(obsv, ghTwirp, ffClient)
	host.Handle(jobs_pb.NewJobsAPIServer(s, s.ServerHooks(customHooks), interceptors))
	host.Handle(jobs_pb.NewQuotaAPIServer(quotaAPIHandler, s.ServerHooks(customHooks), interceptors))

	// Verify CosmosDB connectivity before starting the server
	if cfg.IsProductionLike() {
		probe := readiness.NewProbe(readiness.WithHealthChecker(jobStore))
		err = probe.MarkReady(ctx)
		if err != nil {
			return goerrors.Errorf("readiness check failed: %w", err)
		}
	}

	// Run both the Twirp server and the Hydro sync consumer inside an errgroup
	// so that if either fails, the shared context is cancelled and both shut down cleanly.
	wg, ctx := errgroup.WithContext(ctx)

	// Start Hydro sync consumer for integration sync events
	syncDispatch := syncmux.New(map[string]hydropkg.MessageHandler{
		hydrotopics.IntegrationCreate: appSyncHandler.Dispatch,
		hydrotopics.IntegrationUpdate: appSyncHandler.Dispatch,
	})
	wg.Go(runSyncConsumer(ctx, cfg, obsv, syncDispatch.Dispatch))

	// Start the server
	wg.Go(func() error {
		err := host.Run(ctx)
		if err != nil {
			return goerrors.Errorf("failed to start Twirp server: %w", err)
		}
		return nil
	})

	return wg.Wait()
}

func newTwirpHost(cfg *config.Config) (*twirpapi.Host, error) {
	httpCfg, err := httphost.LoadConfig()
	if err != nil {
		return nil, goerrors.Errorf("failed to load HTTP host config: %w", err)
	}
	httpCfg.Port = cfg.HTTPPort
	httpCfg.Runtime.App.ServiceName = cfg.ServiceName
	httpCfg.Runtime.App.CatalogService = cfg.ServiceName

	// TODO: Remove this when the Twirp CreateJob API is fully async
	// Increase go-server's default WriteTimeout because creating a job can take a while
	httpCfg.WriteTimeout = 10 * time.Second

	// `cfg.HydroBrokers` is a slice of strings, so we need to convert it to a comma-separated string
	httpCfg.Runtime.FeatureFlags.VexiHydroBrokers = strings.Join(cfg.HydroBrokers, ",")
	// Set additional owning services to match the HTTP API configuration
	httpCfg.Runtime.FeatureFlags.VexiAdditionalOwningServices = featureflags.AdditionalOwningServices

	// Load all HMAC keys from vault with the APP_HMAC_KEY_ prefix
	hmacKeys := httphost.LoadHMACKeys()

	host, err := twirpapi.NewHost(
		twirpapi.WithConfig(httpCfg),
		twirpapi.WithHMACKeys(hmacKeys...),
	)
	if err != nil {
		return nil, goerrors.Errorf("failed to create server: %w", err)
	}
	return host, nil
}

// Convert go-server runtime telemetry bits to `obsv`:
func hostToObsv(cfg *config.Config, host *twirpapi.Host) (observability.Exporters, error) {
	tracer := host.Tracer()
	reporter := host.Reporter()
	statter := host.Statter()
	logger := host.Logger()
	hydroPublisher, err := hydro.NewPublisher(cfg.IsDevelopment(), cfg.HydroClientID, cfg.HydroKafkaVersion, cfg.HydroBrokers, logger, reporter, statter)
	if err != nil {
		return observability.NewNoopExporters(), goerrors.Errorf("failed to create hydro publisher: %w", err)
	}
	return observability.NewExporters(tracer, reporter, statter, hydroPublisher, logger), nil
}

func runSyncConsumer(ctx context.Context, cfg *config.Config, obsv observability.Exporters, fn hydropkg.MessageHandler) func() error {
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
			[]string{hydrotopics.IntegrationCreate, hydrotopics.IntegrationUpdate},
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
