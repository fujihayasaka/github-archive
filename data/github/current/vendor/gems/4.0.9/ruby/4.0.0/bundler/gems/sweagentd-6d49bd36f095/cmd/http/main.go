// Package main provides the HTTP service for sweagentd, handling authentication,
// job execution, and event processing through various HTTP endpoints.
package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	goStatsHttp "github.com/github/go-stats/http" //nolint:staticcheck // TODO: migrate to trace metrics (https://gh.io/tracemetrics)
	"github.com/github/go-stats/ps"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agent/agenthttp"
	"github.com/github/sweagentd/internal/agentcallback"
	"github.com/github/sweagentd/internal/agentcleanup"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticappsync"
	"github.com/github/sweagentd/internal/api/jobapi"
	"github.com/github/sweagentd/internal/aqueduct"
	aqueductConsumer "github.com/github/sweagentd/internal/aqueduct/consumer"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/aqueduct/jobs/agentjob"
	"github.com/github/sweagentd/internal/aqueduct/jobs/apijob"
	"github.com/github/sweagentd/internal/aqueduct/jobs/eventjob"
	"github.com/github/sweagentd/internal/aqueduct/jobs/stopagentcomputejob"
	"github.com/github/sweagentd/internal/auth"
	"github.com/github/sweagentd/internal/auth/oidc"
	"github.com/github/sweagentd/internal/auth/oidc/authndsigner"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
	"github.com/github/sweagentd/internal/auth/oidc/devsigner/signerhttp"
	"github.com/github/sweagentd/internal/auth/oidc/varfetcher"
	"github.com/github/sweagentd/internal/authnd"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenthttp"
	"github.com/github/sweagentd/internal/encryption"
	"github.com/github/sweagentd/internal/events"
	hydroevents "github.com/github/sweagentd/internal/events/hydro"
	"github.com/github/sweagentd/internal/events/hydro/syncmux"
	hydrotopics "github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/ghchi"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/httpratelimit"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs/store/cosmosdb"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	memory "github.com/github/sweagentd/internal/memory/memoryhttp"
	"github.com/github/sweagentd/internal/models"
	"github.com/github/sweagentd/internal/models/modelshttp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/observability/hydro"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/plugins/pluginshttp"
	"github.com/github/sweagentd/internal/readiness"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sandbox"
	"github.com/github/sweagentd/internal/sandbox/stopguard"
	"github.com/github/sweagentd/internal/skills"
	"github.com/github/sweagentd/internal/skills/skillshttp"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/go-chi/chi/v5"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	semconv "go.opentelemetry.io/otel/semconv/v1.20.0"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/sync/errgroup"
)

func main() {
	err := mainWithLogging()
	if !errors.Is(err, http.ErrServerClosed) && err != nil {
		fmt.Println("failed to run service:", err)
		os.Exit(1)
	}
}

func mainWithLogging() error {
	cfg, err := config.Load()
	if err != nil {
		return goerrors.Errorf("failed to load config: %w", err)
	}

	obsv, err := cfg.NewObservabilityExporters("http-service")
	if err != nil {
		return goerrors.Errorf("failed to create observability exporters: %w", err)
	}
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)

	err = realMain(cfg, obsv)

	if !errors.Is(err, http.ErrServerClosed) && err != nil {
		obsv.Logger.WithError(err).Error("unexpected main termination")
		obsv.Statter.Counter("unexpected_process_terminations", stats.Tags{"application": "http"}, 1)
	} else {
		obsv.Logger.WithError(err).Info("main terminated due to server shutdown")
	}

	return err
}

//nolint:maintidx // complexity is acceptable here for the sake of clarity and we set up a lot of stuff
func realMain(cfg *config.Config, obsv observability.Exporters) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	var err error

	// Setup feature flag client
	ffClient, err := newFeatureFlagsClient(cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create feature flag client: %w", err)
	}
	cachingFFClient := featureflags.NewCachingClient(ffClient, obsv)

	// Want to log failure so have to do this after logger configured
	cfg.PopulateFirewallConfiguration(obsv.Logger)

	// Authnd
	authndClient, err := newAuthndClient(cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create authnd client: %w", err)
	}

	// CAPI
	capiClient, err := capi.NewClient(obsv, cfg.CopilotAPIURL, cfg.CopilotIntegrationID, cfg.CapiHMACKey, ffClient)
	if err != nil {
		return goerrors.Errorf("failed to create capi client: %w", err)
	}

	cacheStore, err := cache.NewCacheStore(ctx, cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create cache store: %w", err)
	}

	httpRateLimiter := httpratelimit.New(
		cfg.HTTPRateLimitRequestsPerMinute,
		cacheStore, obsv, ffClient,
	)

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

	// Custom Agent service
	customAgentSvc := customagent.NewService(obsv, spokesClient, ghTwirp, ffClient)

	// OIDC service
	signer, err := newTokenSigner(cfg, obsv)
	if err != nil {
		return goerrors.Errorf("failed to create OIDC signer: %w", err)
	}
	fetcher := varfetcher.NewGitHubVariableFetcher(githubClientFactory, ghTwirp)
	if cfg.IsDevelopment() && cfg.AgentLauncher == config.AgentLauncherDocker {
		fetcher = varfetcher.NewEnvVariableFetcher()
	}
	oidcService := oidc.NewService(ffClient, signer, spokesClient, ghTwirp, obsv, oidc.ServiceConfig{
		HTTPProxy:       cfg.OIDCHTTPProxy,
		HTTPSProxy:      cfg.OIDCHTTPSProxy,
		VariableFetcher: fetcher,
	})

	// Skills service
	skillsSvc := skills.NewService(obsv, spokesClient, ghTwirp)

	// Plugins service
	pluginsSvc := plugins.NewService(obsv, spokesClient, ghTwirp, cfg.GitHubServerURL)

	// Job Limiter
	countTracker := limiter.NewJobCountRedisTracker(cacheStore)
	jobLimiter := limiter.NewJobLimiter(jobStore, countTracker, appProvider)

	// Job Event Emitter (used by agent HTTP handler for progress event emission)
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
	jobExecutor := jobexecutor.NewAgentJobExecutor(obsv, launcherBuilder, ffClient, ghTwirp, githubClientFactory, jobService, customAgentSvc, pluginsSvc, appProvider)

	// Create the event handler
	// triggerChecker is nil because trigger events are exclusively Worker
	// topics and are never processed by the HTTP service.
	eventHandler := events.NewHandler(obsv, capiClient, ffClient, jobService, jobExecutor, jobStore, ghTwirp, githubClientFactory, appProvider, customAgentSvc, nil)

	// In development, wire the workflow completion handler into the builder
	// so each launched docker container triggers the same finalization flow
	// as GitHub Actions workflow_run events.
	if cfg.IsDevelopment() {
		launcherBuilder.SetWorkflowCompletedHandler(events.NewLauncherAdapter(eventHandler))
	}

	// Create the hydro event dispatcher
	hydroevt := hydroevents.NewDispatcher(obsv, ffClient, githubClientFactory, aqueductClient, eventHandler, ghTwirp, cfg.Environment, cfg.EnvironmentName, appProvider, nil)

	// Integration sync handler (reloads agentic app registry on integration updates)
	appSyncHandler := agenticappsync.NewHandler(obsv, ghTwirp, cfg, appProvider)

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

	// Start the HTTP server
	wg.Go(func() error {
		r := chi.NewRouter()
		r = registerMiddleware(r, obsv, cfg.ServiceName)

		// Ensure we are getting the same feature flag results for a given request
		r.Use(cachingFFClient.Middleware)

		r.Get("/_ping", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("OK"))
		})

		// Register a development-only route for self-hosting a signing endpoint for OIDC.
		// This has to be at the root so you can publicly port forward port 2208.
		if !cfg.OIDCAuthndEnabled && cfg.IsDevelopment() {
			if ds, ok := signer.(*devsigner.Signer); ok {
				signerHandler := signerhttp.NewHandler(ds)
				signerHandler.RegisterRoutes(r)
			}
		}

		authenticator := auth.NewAuthenticator(obsv, authndClient, ghTwirp, ffClient)
		authenticator.SetAppProvider(appProvider)

		// Rate limiter for /agent/jobs/{jobID}/tokens endpoint.
		tokensRateLimiter := httpratelimit.New(
			cfg.TokensRateLimitRequestsPerMinute,
			cacheStore, obsv, ffClient,
		)

		callbackHandler := agentcallback.NewHandler(obsv, jobService, capiClient, jobStore, githubClientFactory, ffClient, ghTwirp, cfg.GitHubAppID, appProvider)
		cleanupHandler := agentcleanup.NewHandler(obsv, jobStore, githubClientFactory, ffClient, ghTwirp, cfg.IsDevelopment(), appProvider)

		// callbackHandler and cleanupHandler will move to the agent package,
		// but for now we'll just pass them in and use the existing handlers.
		agentHandler := agenthttp.NewHandler(obsv, ffClient, jobStore, githubClientFactory, ghTwirp, callbackHandler, cleanupHandler, customAgentSvc, skillsSvc, pluginsSvc, appProvider, jobEventEmitter, cfg.GitHubServerURL, jobService, capiClient, oidcService, cfg.GitHubDownloadsURL)

		memoryDependencies := memory.NewDependencies(cfg, ffClient, githubClientFactory, obsv, appProvider, ghTwirp, expSDKClient)

		// Endpoints for the job API
		jobAPIHandler := jobapi.NewHandler(obsv, githubClientFactory, jobService, jobStore, ffClient, jobExecutor, ghTwirp, appProvider, spokesClient)

		customAgentsHandler := customagenthttp.NewHandler(obsv, ffClient, ghTwirp, customAgentSvc)

		skillsHandler := skillshttp.NewHandler(skillsSvc, obsv, ghTwirp)

		pluginsHandler := pluginshttp.NewHandler(pluginsSvc, obsv, ghTwirp, ffClient)

		modelsSvc := models.NewService(capiClient, ffClient)
		modelsHandler := modelshttp.NewHandler(obsv, modelsSvc, ghTwirp, ffClient)

		// Group authenticated routes
		r.Group(func(r chi.Router) {
			r.Use(authenticator.Middleware)

			// Register the /agent routes
			agentHandler.RegisterRoutes(r, tokensRateLimiter.JobMiddleware)

			// Register the /models routes with per-user rate limiting
			modelsHandler.RegisterRoutes(r, httpRateLimiter.Middleware)

			r.Get("/user", func(w http.ResponseWriter, r *http.Request) {
				u, ok := requestctx.User(r.Context())
				if !ok {
					w.WriteHeader(http.StatusUnauthorized)
					return
				}
				_, _ = w.Write([]byte(u.Login))
			})

			if cfg.IsStaging() || cfg.IsDevelopment() {
				r.Get("/boom", func(w http.ResponseWriter, r *http.Request) {
					//nolint:errcheck,gosec // Intentionally ignoring error for test endpoint
					obsv.Reporter.Report(ctx, goerrors.WithStack(goerrors.New("boom!  This is a test error you can ignore")), nil)
					// Force a panic, mostly for us to test that our monitoring works.
					var someInteger *int
					// We force a panic intentionally here to test our monitoring and observability.
					panic(fmt.Sprintf("Boom! %d", *someInteger)) //nolint:govet,revive // intentional panic for testing purposes
				})
			}

			// API for use by external systems
			// NOTE: No update / PUT endpoints should be implemented until we have a way to ensure the agent cannot use it.
			// These endpoints should not require the nonce used for the /agent/job endpoint so we need a scope or a way to
			// block the Copilot Coding agent app from using it w/o a passed in shared secret or encrypted token.

			// Register the Job API routes
			jobAPIHandler.RegisterRoutes(r)

			// Register the custom agent routes
			customAgentsHandler.RegisterRoutes(r)

			// Register the skills routes
			skillsHandler.RegisterRoutes(r)

			// Register the plugins route
			pluginsHandler.RegisterRoutes(r)

			// Register routes that are not meant to be stable nor part of the public API.
			r.Route("/internal", func(r chi.Router) {
				// Register all Memory API routes (repo-scoped, user-scoped, combined-prompt).
				//
				// Repo-scoped routes (RegisterRepoRoutes) are gated by
				// withRepoMemoryCheck, which runs the consolidated memory
				// enablement chain (Copilot Memory policy via Monolith Twirp
				// -> repo/owner feature flag -> repo admin setting). The
				// combined-prompt route runs the chain inline when ?repo= is
				// supplied and drops both repo and user scopes from the
				// response when the chain is disabled-or-error, so that
				// sensitive content from an opted-out repo cannot egress
				// through user-scope memory in that prompt context.
				//
				// User-scoped routes (RegisterUserRoutes) are NOT gated here
				// today — the URL carries no repo identifier. The v1
				// enforcement strategy for user-scope routes is described in
				// internal/memory/memoryhttp/router.go (RegisterUserRoutes
				// docstring): runtime self-suppression when /enabled returns
				// false (primary), plus a future active-repo header for
				// defence-in-depth.
				memoryDependencies.HTTPHandler.RegisterAllMemoryRoutes(r)
			})

			// Used by both staging and proxima
			if cfg.Environment != config.EnvironmentProduction {
				r.Get("/runtime", func(w http.ResponseWriter, r *http.Request) {
					zipPath := cfg.RuntimeAppPath

					_, err := os.Stat(zipPath)
					if os.IsNotExist(err) {
						w.WriteHeader(http.StatusNotFound)
						_, _ = w.Write([]byte("Runtime app zip file not found. This means that the runtime app was not correctly embedded in the dockerfile."))
						return
					}

					// Set appropriate headers for file download
					w.Header().Set("Content-Type", "application/gzip")
					w.Header().Set("Content-Disposition", "attachment; filename=runtime-app.tar.gz")

					// Serve the file
					http.ServeFile(w, r, zipPath)
				})
			}
		})

		addr := fmt.Sprintf(":%d", cfg.HTTPPort)
		if cfg.IsDevelopment() && !cfg.ForceListenAllInterfaces {
			addr = "127.0.0.1" + addr // Prevents MacOS from prompting you about accepting network connections.
		}

		fmt.Printf("Starting server on %s\n", addr)
		server := &http.Server{
			Addr:              addr,
			Handler:           r,
			ReadHeaderTimeout: 30 * time.Second, // Protect against slowloris attacks
			ReadTimeout:       60 * time.Second,
			WriteTimeout:      60 * time.Second,
			IdleTimeout:       120 * time.Second,
		}

		go func() {
			<-ctx.Done()
			shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 60*time.Second)
			defer cancel()
			err := server.Shutdown(shutdownCtx)
			if err != nil {
				obsv.Logger.WithError(err).Error("Error shutting down HTTP server")
			}
		}()
		err := server.ListenAndServe()
		if err != nil && err != http.ErrServerClosed {
			return goerrors.Errorf("http server error: %w", err)
		}

		return nil
	})

	// Start the aqueduct consumer pools
	wg.Go(aqueductConsumer.Run(ctx, cfg, obsv, rateLimiter, aqueductClient, ffClient,
		aqueductConsumer.AgentPoolName,
		[]string{aqueductJobs.AgentJobQueueName},
		agentjob.Handler(obsv, ffClient, aqueductClient, rateLimiter, jobLimiter, appProvider, jobService, jobExecutor),
		agentjob.NewFailJobFunc(obsv, jobService),
	))

	wg.Go(aqueductConsumer.Run(ctx, cfg, obsv, rateLimiter, aqueductClient, ffClient,
		aqueductConsumer.EventPoolName,
		aqueductJobs.EventJobServiceQueues,
		eventjob.Handler(obsv, ffClient, aqueductClient, rateLimiter, appProvider, eventHandler),
		nil,
	))

	wg.Go(aqueductConsumer.Run(ctx, cfg, obsv, rateLimiter, aqueductClient, ffClient,
		aqueductConsumer.APIPoolName,
		[]string{aqueductJobs.APIJobQueueName},
		apijob.Handler(obsv, ffClient, aqueductClient, rateLimiter, appProvider, jobService),
		apijob.NewFailJobFunc(obsv, jobService),
	))

	// Sandbox service is used by the delayed stop-agent-compute consumer.
	sandboxSvc := sandbox.NewService(obsv, ffClient, ghTwirp, sandbox.ServiceOpts{
		LaunchTwirpBaseURL:    cfg.LaunchTwirpAPIURL,
		LaunchTwirpHMACKey:    cfg.LaunchTwirpHMACKey,
		MissionControlBaseURL: cfg.SandboxMCBaseURL,
		UseDockerBackend:      cfg.SandboxUseDocker,
		GitHubServerURL:       cfg.GitHubServerURL,
		CopilotAPIURL:         cfg.CopilotAPIURL,
	})

	// stopGuard tracks per-compute generation counters so a later
	// StopAgentCompute request supersedes any earlier still-pending one.
	stopGuard := stopguard.New(cacheStore, stopguard.DefaultTTL)

	wg.Go(aqueductConsumer.Run(ctx, cfg, obsv, rateLimiter, aqueductClient, ffClient,
		aqueductConsumer.StopAgentComputePoolName,
		[]string{aqueductJobs.StopAgentComputeJobQueueName},
		stopagentcomputejob.Handler(obsv, sandboxSvc, stopGuard),
		nil,
	))

	// Start Hydro consumer
	wg.Go(runHydroConsumer(ctx, cfg, obsv, jobStore, hydroevt.Dispatch))

	// Start Hydro sync consumer for integration sync events
	syncDispatch := syncmux.New(map[string]hydropkg.MessageHandler{
		hydrotopics.IntegrationCreate: appSyncHandler.Dispatch,
		hydrotopics.IntegrationUpdate: appSyncHandler.Dispatch,
	})
	wg.Go(runSyncConsumer(ctx, cfg, obsv, syncDispatch.Dispatch))

	return wg.Wait()
}

func newFeatureFlagsClient(cfg *config.Config, obsv observability.Exporters) (ffClient featureflags.Client, err error) {
	switch {
	case cfg.DisableHydroConsumer:
		// Feature flags won't work in ACA or locally, so if the HydroConsumer is disabled, assume its set
		ffClient = featureflags.NewNoopClient(map[string]bool{
			"copilot_swe_agent":                             true,
			featureflags.CopilotSWEAgentHTTPRateLimit:       true,
			featureflags.CopilotSWEAgentHTTPTokensRateLimit: true,
		})
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

func newAuthndClient(cfg *config.Config, obsv observability.Exporters) (a authnd.Authenticator, err error) {
	var authndClient authnd.Authenticator = authnd.NewNoopClient(cfg.GitHubAppID)
	if cfg.IsProductionLike() {
		authndClient, err = authnd.NewClient(obsv, authnd.ClientOpts{
			AuthndURL:   cfg.AuthndURL,
			HMACKey:     cfg.AuthndHMACKey,
			ServiceName: cfg.ServiceName,
		})
		if err != nil {
			return nil, goerrors.Errorf("failed to create authnd client: %w", err)
		}
	}

	return authndClient, nil
}

func registerMiddleware(r *chi.Mux, obsv observability.Exporters, serviceName string) *chi.Mux {
	// headers middleware
	hdrs := headers.Headers{
		ServerName: serviceName,
	}

	rec := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			//nolint:contextcheck // No parent context available in recovery handler when req is nil
			var ctx context.Context
			if req != nil {
				ctx = req.Context()
			} else {
				ctx = context.Background()
			}
			_, sentryTags, kvps := requestctx.ToTelemetry(ctx, nil)
			obsv.Logger.WithError(err).WithFields(kvps...).Error("panic!")
			_ = obsv.Reporter.Report(ctx, err, sentryTags)

			return nil
		},
	}

	// tenant middleware
	t := tenant.Tenant{Logger: obsv.Logger}

	// Register GitHub middleware
	r.Use(
		requestid.Handler,
		t.Handler,
		goStatsHttp.WithResponseMetrics(obsv.Statter, goStatsHttp.Options{FormatRequest: ghchi.Route}), //nolint:staticcheck // TODO: migrate to trace metrics (https://gh.io/tracemetrics)
		rec.Handler,
		hdrs.Handler,
		tracingMiddleware,
	)

	return r
}

func tracingMiddleware(next http.Handler) http.Handler {
	routeAttrHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		span := trace.SpanFromContext(r.Context())
		if span.IsRecording() {
			if route := ghchi.Route(r); route != "" {
				span.SetAttributes(semconv.HTTPRoute(route))
			}
		}

		next.ServeHTTP(w, r)
	})

	return otelhttp.NewHandler(routeAttrHandler, "",
		otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string {
			pattern := ghchi.Route(r)
			if pattern == "" {
				// if no route pattern, then use the default low-cardinality route
				return "HTTP " + r.Method
			}

			return r.Method + " " + pattern
		}),
	)
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
			hydrotopics.Service, // only consume service topics
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

func newTokenSigner(cfg *config.Config, obsv observability.Exporters) (oidc.TokenSigner, error) {
	if cfg.OIDCAuthndEnabled || cfg.IsProductionLike() {
		signer, err := authndsigner.NewSigner(cfg, obsv)
		if err != nil {
			return nil, goerrors.Errorf("failed to create authnd signer: %w", err)
		}
		return signer, nil
	}
	signer, err := devsigner.NewDefaultSigner(cfg.OIDCDevSignerIssuerURL, cfg.CopilotAPIURL, cfg.HTTPPort)
	if err != nil {
		return nil, goerrors.Errorf("failed to create OIDC signer: %w", err)
	}
	return signer, nil
}

func runSyncConsumer(ctx context.Context, cfg *config.Config, obsv observability.Exporters, fn hydropkg.MessageHandler) func() error {
	return func() error {
		if cfg.DisableHydroConsumer {
			obsv.Logger.Info("sync: hydro consumer disabled, skipping")
			return nil
		}

		topics := []string{hydrotopics.IntegrationCreate, hydrotopics.IntegrationUpdate}

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
