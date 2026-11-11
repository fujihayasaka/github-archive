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

	aq "github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/logrequest"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	goStatsHttp "github.com/github/go-stats/http"
	"github.com/github/go-stats/ps"
	hydropkg "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agent/agenthttp"
	"github.com/github/sweagentd/internal/agentcallback"
	"github.com/github/sweagentd/internal/agentcleanup"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/api/jobapi"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/consumer"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/aqueduct/jobs/agentjob"
	"github.com/github/sweagentd/internal/aqueduct/jobs/apijob"
	"github.com/github/sweagentd/internal/aqueduct/jobs/eventjob"
	"github.com/github/sweagentd/internal/auth"
	"github.com/github/sweagentd/internal/authnd"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenthttp"
	"github.com/github/sweagentd/internal/events"
	hydroevents "github.com/github/sweagentd/internal/events/hydro"
	hydrotopics "github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/ghchi"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs/store/cosmosdb"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/limiter"
	memory "github.com/github/sweagentd/internal/memory/http"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/observability/hydro"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/codes"
	semconv "go.opentelemetry.io/otel/semconv/v1.20.0"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/sync/errgroup"
)

func main() {
	if err := mainWithLogging(); !errors.Is(err, http.ErrServerClosed) && err != nil {
		fmt.Println("failed to run service:", err)
		os.Exit(1)
	}
}

func mainWithLogging() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	obsv, err := cfg.NewObservabilityExporters("http-service")
	if err != nil {
		return fmt.Errorf("failed to create observability exporters: %w", err)
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

func realMain(cfg *config.Config, obsv observability.Exporters) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	var err error

	// Setup feature flag client
	ffClient, err := newFeatureFlagsClient(cfg, obsv)
	if err != nil {
		return fmt.Errorf("failed to create feature flag client: %w", err)
	}
	cachingFFClient := featureflags.NewCachingClient(ffClient, obsv)

	// Want to log failure so have to do this after logger configured
	cfg.PopulateFirewallConfiguration(obsv.Logger)

	// Authnd
	authndClient, err := newAuthndClient(cfg, obsv)
	if err != nil {
		return fmt.Errorf("failed to create authnd client: %w", err)
	}

	// CAPI
	capiClient, err := capi.NewClient(obsv, cfg.CopilotAPIURL, cfg.CopilotIntegrationID, cfg.CapiHMACKey)
	if err != nil {
		return fmt.Errorf("failed to create capi client: %w", err)
	}

	// Rate Limiter
	rateLimitClient, err := github.NewAltClientFactoryFromConfig(obsv, cfg)
	if err != nil {
		return fmt.Errorf("failed to create github app client factory: %w", err)
	}
	rateLimiter := limiter.NewRateLimiterV1(rateLimitClient, 1000, time.Minute*5)

	// Github Client
	githubClientFactory, err := github.NewClientFactoryFromConfig(obsv, cfg, ffClient, rateLimiter)
	if err != nil {
		return fmt.Errorf("failed to create github client factory: %w", err)
	}

	// Experiments
	experimentsClient := experiments.NewClientFromConfig(ctx, cfg, obsv)

	// GitHub Twirp Client
	ghTwirp, err := githubtwirp.NewClientFromConfig(obsv, ffClient, cfg)
	if err != nil {
		return fmt.Errorf("failed to create github twirp client: %w", err)
	}

	// Spokesd client
	spokesClient, err := spokes.NewClientFromConfig(obsv, cfg)
	if err != nil {
		return fmt.Errorf("failed to create spokes client: %w", err)
	}

	// Agent Launcher
	al, err := launcher.NewFromConfig(cfg, obsv, ghTwirp, ffClient, githubClientFactory, spokesClient)
	if err != nil {
		return fmt.Errorf("failed to create agent launcher: %w", err)
	}

	// Job store
	jobStore, err := cosmosdb.NewStoreFromConfig(cfg)
	if err != nil {
		return fmt.Errorf("failed to create job store: %w", err)
	}

	// Aqueduct Client
	aqueductClient, err := aqueduct.NewClientFromConfig(ctx, cfg, obsv)
	if err != nil {
		return fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	customAgentSvc := customagent.NewService(obsv, spokesClient, ghTwirp, ffClient)

	// Job Limiter
	jobLimiter := limiter.NewJobLimiter(jobStore, 4000, time.Hour*4)

	// Job Service
	jobService := jobservice.New(obsv, ffClient, jobStore, capiClient, githubClientFactory, ghTwirp, aqueductClient, jobLimiter, experimentsClient, customAgentSvc, cfg.GitHubCommitEmail, spokesClient)

	// Job Executor
	jobExecutor := jobexecutor.NewAgentJobExecutor(obsv, al, ffClient, ghTwirp, githubClientFactory, jobService)

	// App Provider
	copilotApp, err := agenticapp.NewCopilot(cfg.GitHubAppLogin, cfg.GitHubBotLogin)
	if err != nil {
		return fmt.Errorf("failed to create copilot app: %w", err)
	}
	appProvider := agenticapp.NewProvider(copilotApp)

	// Create the event handler
	eventHandler := events.NewHandler(obsv, capiClient, ffClient, jobService, jobExecutor, jobStore, ghTwirp, githubClientFactory, appProvider)

	// Create the hydro event dispatcher
	hydroevt := hydroevents.NewDispatcher(obsv, ffClient, githubClientFactory, aqueductClient, eventHandler, ghTwirp, cfg.Environment, cfg.EnvironmentName)

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

		authenticator := auth.NewAuthenticator(obsv, authndClient, ghTwirp, ffClient)

		callbackHandler := agentcallback.NewHandler(obsv, jobService, capiClient, jobStore, githubClientFactory, ffClient, ghTwirp, cfg.GitHubAppID)
		cleanupHandler := agentcleanup.NewHandler(obsv, jobStore, githubClientFactory, ffClient, ghTwirp, cfg.IsDevelopment(), cfg.GitHubAppID)

		// callbackHandler and cleanupHandler will move to the agent package,
		// but for now we'll just pass them in and use the existing handlers.
		agentHandler := agenthttp.NewHandler(obsv, ffClient, jobStore, githubClientFactory, ghTwirp, callbackHandler, cleanupHandler, customAgentSvc)

		memoryDependencies := memory.NewDependencies(cfg, ffClient, githubClientFactory, obsv)

		// Endpoints for the job API
		jobAPIHandler := jobapi.NewHandler(obsv, githubClientFactory, jobService, jobStore, ffClient, jobExecutor, ghTwirp, cfg.GitHubAppID)

		customAgentsHandler := customagenthttp.NewHandler(obsv, ffClient, customAgentSvc)

		// Group authenticated routes
		r.Group(func(r chi.Router) {
			r.Use(authenticator.Middleware)

			// Register the /agent routes
			agentHandler.RegisterRoutes(r)

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
					obsv.Reporter.Report(ctx, goerrors.WithStack(errors.New("Boom!  This is a test error you can ignore")), nil)
					// Force a panic, mostly for us to test that our monitoring works.
					var someInteger *int
					// We force a panic intentionally here to test our monitoring and observability.
					panic(fmt.Sprintf("Boom! %d", *someInteger))
				})
			}

			// API for use by external systems
			// NOTE: No update / PUT endpoints should be implemented until we have a way to ensure the agent cannot use it.
			// These endpoints should not require the nonce used for the /agent/job endpoint so we need a scope or a way to
			// block the Copilot Coding agent app from using it w/o a passed in shared secret or encrypted token.

			// Register the Job API routes
			jobAPIHandler.RegisterRoutes(r)

			// Register the custom agent routes
			// These are duplicated in /internal until clients have updated.
			customAgentsHandler.RegisterRoutes(r)

			// Register routes that are not meant to be stable nor part of the public API.
			r.Route("/internal", func(r chi.Router) {
				// Register Memory API routes
				memoryDependencies.HTTPHandler.RegisterRoutes(r)

				customAgentsHandler.RegisterRoutes(r)
			})

			// Used by both staging and proxima
			if cfg.Environment != config.EnvironmentProduction {
				r.Get("/runtime", func(w http.ResponseWriter, r *http.Request) {
					zipPath := cfg.RuntimeAppPath

					if _, err := os.Stat(zipPath); os.IsNotExist(err) {
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
			Addr:    addr,
			Handler: r,
		}

		go func() {
			<-ctx.Done()
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if err := server.Shutdown(shutdownCtx); err != nil {
				obsv.Logger.WithError(err).Error("Error shutting down HTTP server")
			}
		}()
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			return fmt.Errorf("http server error: %w", err)
		}

		return nil
	})

	// Start the aqueduct consumer pools
	wg.Go(runAqueductConsumer(ctx, cfg, obsv, rateLimiter, aqueductClient,
		consumer.AgentPoolName,
		[]string{aqueductJobs.AgentJobQueueName},
		agentjob.Handler(obsv, ffClient, aqueductClient, rateLimiter, jobLimiter, jobService, jobExecutor),
	))

	wg.Go(runAqueductConsumer(ctx, cfg, obsv, rateLimiter, aqueductClient,
		consumer.EventPoolName,
		[]string{aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName},
		eventjob.Handler(obsv, ffClient, aqueductClient, rateLimiter, eventHandler),
	))

	wg.Go(runAqueductConsumer(ctx, cfg, obsv, rateLimiter, aqueductClient,
		consumer.APIPoolName,
		[]string{aqueductJobs.APIJobQueueName},
		apijob.Handler(obsv, ffClient, aqueductClient, rateLimiter, jobService),
	))

	// Start Hydro consumer
	wg.Go(runHydroConsumer(ctx, cfg, obsv, hydroevt.Dispatch))

	return wg.Wait()
}

func newFeatureFlagsClient(cfg *config.Config, obsv observability.Exporters) (ffClient featureflags.Client, err error) {
	if cfg.DisableHydroConsumer {
		// Feature flags won't work in ACA or locally, so if the HydroConsumer is disabled, assume its set
		ffClient = featureflags.NewNoopClient(map[string]bool{"copilot_swe_agent": true})
	} else if cfg.IsDevelopment() {
		ffClient, err = featureflags.NewDevClient(context.Background(), cfg.ServiceName, obsv)
		if err != nil {
			return nil, fmt.Errorf("creating feature flag client: %w", err)
		}
	} else {
		ffClient, err = featureflags.NewClient(context.Background(), cfg, obsv)
		if err != nil {
			return nil, fmt.Errorf("setting up feature flag client: %w", err)
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
			return nil, fmt.Errorf("failed to create authnd client: %w", err)
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
			ctx := context.Background()
			if req != nil {
				ctx = req.Context()
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
		goStatsHttp.WithResponseMetrics(obsv.Statter, goStatsHttp.Options{FormatRequest: ghchi.Route}),
		rec.Handler,
		hdrs.Handler,
		tracingMiddleware,
		// Logging middleware needs to go last so that it can log the request ID
		func(next http.Handler) http.Handler {
			return logrequest.Handler(next, obsv.Logger)
		},
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

func runAqueductConsumer(
	ctx context.Context,
	cfg *config.Config,
	obsv observability.Exporters,
	limiter limiter.RateLimiter,
	aqueductClient sweagentd.AqueductClient,
	pool consumer.PoolName,
	queues []string,
	handler aq.JobHandler,
) func() error {
	return func() error {
		newctx, span := obsv.Tracer.Start(ctx, "main.StartAqueductConsumerPool")
		defer span.End()

		options := []consumer.PoolOption{
			consumer.WithWorkerCount(cfg.AqueductWorkerCount),
			consumer.WithHeartbeatInterval(30 * time.Second),
			consumer.WithHeartbeatTimeout(60 * time.Second),
			consumer.WithQueues(queues),
			consumer.WithEnvironmentPoolName(cfg.EnvironmentName, pool),
			consumer.WithHandler(aqueductJobs.Handler(obsv, aqueductClient, handler)),
			consumer.WithBeforeReceiveHook(aqueductJobs.BeforeReceive(obsv, limiter, aqueductJobs.DefaultReceiveHook)),
			consumer.WithErrorHook(aqueductJobs.OnError(obsv)),
		}

		pool, err := consumer.NewWorkerPool(
			newctx,
			obsv,
			aqueductClient,
			options...)
		if err != nil {
			// Make the error special
			err = fmt.Errorf("failed to create Aqueduct worker pool: %w", err)
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())

			obsv.Logger.WithError(err).Error("Error initializing Aqueduct worker pool")
			return err
		}

		// wait for the shutdown context to be done then call shutdown
		go func() {
			<-ctx.Done()
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			if err := pool.Shutdown(shutdownCtx); err != nil {
				obsv.Logger.WithError(err).Error("Error shutting down Aqueduct worker pool")
			}
		}()

		if err := pool.Start(); err != nil {
			err = fmt.Errorf("failed to start Aqueduct worker pool: %w", err)
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			obsv.Logger.WithError(err).Error("Error starting Aqueduct worker pool")
			return err
		}

		obsv.Logger.Info("Aqueduct worker pool initialized successfully")
		return nil
	}
}

func runHydroConsumer(ctx context.Context, cfg *config.Config, obsv observability.Exporters, fn hydropkg.MessageHandler) func() error {
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
			hydrotopics.All,
			obsv.Logger,
			obsv.Reporter,
			obsv.Statter,
		)
		if err != nil {
			return fmt.Errorf("failed to create hydro consumer: %w", err)
		}
		// Make sure to close the consumer before exiting.
		defer hydroSrc.Close()

		if cfg.IsProductionLike() {
			if err = hydro.CreateReadinessProbeFile(); err != nil {
				return fmt.Errorf("creating readiness probe file: %w", err)
			}
		}

		err = hydroSrc.Consume(ctx, fn)
		if err != nil && !errors.Is(err, context.Canceled) {
			return fmt.Errorf("failed to consume hydro event: %w", err)
		}
		return nil
	}
}
