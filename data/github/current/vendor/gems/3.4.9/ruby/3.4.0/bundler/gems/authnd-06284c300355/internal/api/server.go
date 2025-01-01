// Package authnd provides the Authnd Twirp service to be run and gracefully
// shutdown in a convenient way. It's meant to be imported and executed from a
// `main` package.
package api

import (
	"context"
	"net"
	"net/http"
	"time"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/authenticator"
	apiConfig "github.com/github/authnd/internal/api/config"
	"github.com/github/authnd/internal/api/credentials"
	"github.com/github/authnd/internal/api/devices"
	"github.com/github/authnd/internal/api/exchanger"
	"github.com/github/authnd/internal/api/identity"
	"github.com/github/authnd/internal/api/middleware"
	"github.com/github/authnd/internal/api/mux"
	"github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/common/clients"
	"github.com/github/authnd/internal/common/db"
	"github.com/github/authnd/internal/common/db/schemas"
	"github.com/github/authnd/internal/common/db/throttler"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/publisher"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-ctxutil"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/justinas/alice"
	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/go-stats/ps"
)

// Service defines the AuthNd Service
type Service struct {
	srv                  *http.Server
	localMobileClientSrv *http.Server
	statsDuration        time.Duration
	databaseProvider     *db.Provider
	notifyPublisher      publisher.NotificationPublisher
	eventPublisher       publisher.PratEventPublisher
	isEnterpriseServer   bool
	isProxima            bool
	shutdownTracer       func()
}

// NewService returns a new service for the given configuration.
func NewService(ctx context.Context, cfg *apiConfig.Config) (*Service, error) {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	if err := cfg.Validate(); err != nil {
		return nil, errors.Wrap(err, "invalid config")
	}

	// #region: database connections
	dbProvider, err := db.NewProvider(&cfg.CommonConfig, schemas.All(), logger, statter)
	if err != nil {
		return nil, errors.Wrap(err, "error creating database provider")
	}

	var dbStore store.Store
	if cfg.IsProxima {
		logger.Info("configuring store for proxima")
		dbStore, err = store.NewProximaStore(dbProvider)
		if err != nil {
			return nil, errors.Wrap(err, "error creating proxima store")
		}
	} else {
		if cfg.MySQLWriteThrottlingEnabled() && cfg.MySQLPrimaryReadsEnabled {
			logger.Info("primary reads enabled")
			//TODO(chriskirkland): enable throttling on collab and lodge as necessary https://github.com/github/authentication/issues/4228
			throttler := throttler.NewCachingThrottler(cfg.FrenoHost, cfg.AppName, cfg.MySQLClusterName(), logger, statter)
			dbStore, err = store.NewPrimaryReadStore(dbProvider, throttler, cfg.IsEnterpriseServer)
			if err != nil {
				return nil, errors.Wrap(err, "error creating primary read store")
			}
		} else {
			// default with no primary reads
			logger.Info("primary reads disabled")
			dbStore, err = store.NewStore(dbProvider, cfg.IsEnterpriseServer)
			if err != nil {
				return nil, errors.Wrap(err, "error creating store")
			}
		}
	}
	// #endregion

	// #region: PrAT event publishing
	sinkFn := publisher.WithDefaultSinkFn
	if cfg.KafkaDevelopmentEnv {
		logger.Info("starting kafka sink in development mode", kvp.String("messaging.system", "kafka"), kvp.String("messaging.dev_file", publisher.KafkaDevelopmentFile))
		sinkFn = publisher.WithDevelopmentSinkFn
	}

	eventPublisher, err := publisher.NewPratEventPublisher(ctx, &cfg.CommonConfig, sinkFn)
	if err != nil {
		return nil, errors.Wrap(err, "error creating prat event publisher")
	}
	// #endregion

	// #region: HTTP handler with necessary functionality
	notificationPublisher, err := publisher.NewNotificationPublisher(ctx, &cfg.CommonConfig, sinkFn)
	if err != nil {
		return nil, errors.Wrap(err, "error creating notification publisher")
	}
	hooks := middleware.NewServerHooks(cfg, logger, statter, cfg.GetHMACKeys()...)
	authenticationServer := authenticator.NewAuthenticatorServer(dbStore, hooks, cfg.IsEnterpriseServer)
	credentialManagementServer := credentials.NewCredentialManagerServer(dbStore, eventPublisher, hooks)
	tokenExchangerServer, err := exchanger.NewTokenExchangerServer(dbStore, hooks, cfg.TokenExchangeSigningKey, cfg.IsEnterpriseServer)
	if err != nil {
		return nil, errors.Wrap(err, "error creating token exchanger server")
	}

	prefixHandlers := []mux.PrefixHandler{
		mux.HandlePrefix(pb.AuthenticatorPathPrefix, authenticationServer),
		mux.HandlePrefix(pb.TokenExchangerPathPrefix, tokenExchangerServer),
		mux.HandlePrefix(pb.CredentialManagerPathPrefix, credentialManagementServer),
	}

	if cfg.IdentityManagementServerEnabled() {
		logger.Info("identity management server enabled")
		identityManagementServer, err := identity.NewManagerServer(&identity.RawPrivateKey{PrivateKey: cfg.IdentityPrivateKey, Certificate: cfg.IdentityCertificate}, []*identity.RawPublicKey{{PublicKey: cfg.IdentityPublicKey, Certificate: cfg.IdentityCertificate}}, hooks)
		if err != nil {
			return nil, errors.Wrap(err, "error creating identity management server")
		}
		prefixHandlers = append(prefixHandlers,
			mux.HandlePrefix(pb.IdentityManagerPathPrefix, identityManagementServer),
		)
	} else {
		logger.Info("identity management server disabled")
	}

	prefixHandlers = append(prefixHandlers,
		mux.Ping(),
		mux.Boom(),
	)

	tracerShutdown := func() {}
	if !cfg.IsEnterpriseServer {
		// tracing does not apply to GHES
		tracerShutdown, err = tracing.Instrument(logger)
		if err != nil {
			return nil, errors.Wrap(err, "error creating tracer")
		}
	}

	if !cfg.IsEnterpriseServer && !cfg.IsProxima {
		// GH Mobile doesn't apply to GHES or Proxima
		chatopsHandler, err := instantiateChatopsHandling(cfg, logger)
		if err != nil {
			return nil, errors.Wrap(err, "error creating chatops handler")
		}

		deviceManagerServer := devices.NewMobileDeviceManagerServer(dbStore, notificationPublisher, hooks)
		prefixHandlers = append(prefixHandlers,
			mux.HandlePrefix(pb.MobileDeviceManagerPathPrefix, deviceManagerServer),
			mux.HandlePrefix("/_chatops", chatopsHandler),
			mux.HandlePrefix("/_chatops/", chatopsHandler),
		)
	}
	tenancyResolver := tenancy.NewResolver(dbStore.FindBusinessBySlug)
	handler := mux.NewMux(logger, statter, cfg.IsProxima, tenancyResolver, prefixHandlers...)

	// Wrap in fault injection if enabled.
	// For now, we only permit this in development.
	if cfg.IsDevelopment() {
		handler, err = cfg.BuildFaultHandlers(handler, logger)
		if err != nil {
			return nil, errors.Wrap(err, "error building fault handlers")
		}
	}

	if cfg.IsCanary() {
		// add canary header to all responses
		handler = &canaryHandler{handler}
	}
	// #endregion

	recoveryHandler := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			requestId := req.Header.Get(headers.GitHubRequestID)
			params := map[string]string{
				"http.request.method": req.Method,
				"url.full":            req.URL.String(),
				"gh.request_id":       requestId,
			}
			diagnostics.ReportError(req.Context(), err, "error during request", params)
			return nil
		},
	}

	srv := &http.Server{
		Addr: cfg.BindAddress(),
		Handler: alice.New(
			recoveryHandler.Handler,
		).Then(handler),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
		BaseContext: func(l net.Listener) context.Context {
			// We _don't_ want cancellation of the parent context to cause cancellation of a request.
			// Requests need to complete even when the parent context is cancelled.
			// ctxutil.DetatchedCancel returns a new context that carries Values (like loggers/statters) through, but does not carry cancellation signals from the parent.
			return ctxutil.DetachedCancel(ctx)
		},
	}

	return &Service{
		srv:                  srv,
		localMobileClientSrv: NewLocalMobileClientServer(ctx, cfg, logger, statter),
		statsDuration:        cfg.StatsPeriod,
		databaseProvider:     dbProvider,
		notifyPublisher:      notificationPublisher,
		eventPublisher:       eventPublisher,
		isEnterpriseServer:   cfg.IsEnterpriseServer,
		isProxima:            cfg.IsProxima,
		shutdownTracer:       tracerShutdown,
	}, nil
}

func instantiateChatopsHandling(cfg *apiConfig.Config, logger log.Logger) (http.Handler, error) {
	chatterboxClient, err := instantiateChatterboxClient(cfg)
	if err != nil {
		return nil, err
	}

	chatopsHandler, err := instantiateChatops(cfg, logger, chatterboxClient)
	if err != nil {
		return nil, err
	}

	return chatopsHandler, nil
}

func instantiateChatterboxClient(cfg *apiConfig.Config) (clients.ChatterboxClient, error) {
	var chatterboxClient clients.ChatterboxClient
	if cfg.IsDevelopmentOrTest() {
		chatterboxClient = clients.NewDevelopmentChatterboxClient()
	} else {
		chatterboxToken := cfg.ChatterboxToken
		chatterboxUrl := cfg.ChatterboxUrl
		client, err := clients.NewChatterboxClient("", chatterboxToken, chatterboxUrl)
		if err != nil {
			return nil, err
		}
		chatterboxClient = client
	}

	return chatterboxClient, nil
}

func instantiateChatops(cfg *apiConfig.Config, logger log.Logger, chatterboxClient clients.ChatterboxClient) (http.Handler, error) {
	chatopsHandler, err := cfg.NewChatopsHandler(logger, chatterboxClient)
	if err != nil {
		return nil, err
	}

	return chatopsHandler, nil
}

// Run runs the service with the given context.
func (s *Service) Run(ctx context.Context) error {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	diagnostics.StartService(ctx)

	go func() {
		fields := []kvp.Field{
			kvp.Bool("gh.authnd.is_enterprise_server", s.isEnterpriseServer),
			kvp.String("gh.authnd.server.addr", s.srv.Addr),
		}
		logger.Info("starting internal HTTP server", fields...)

		// wrap the listening socket in a counter so we can keep a count
		// of the number of new incoming connections each authnd has,
		// ideally this number should be low and stabalise quickly after deploy
		// indicating that GLB is reusing connections.
		l, err := net.Listen("tcp", s.srv.Addr)
		if err != nil {
			logger.WithError(errors.WithStack(err)).Error("listen failed", fields...)
			return
		}
		cl := &countingListener{
			st:       statter,
			Listener: l,
		}

		// Ignore normal shutdown error (http.ErrServerClosed)
		if err := s.srv.Serve(cl); err != nil && err != http.ErrServerClosed {
			logger.WithError(errors.WithStack(err)).Error("server closed", fields...)
		}
	}()

	if s.localMobileClientSrv != nil {
		go func() {
			fields := []kvp.Field{
				kvp.Bool("gh.authnd.server.is_enterprise_server", s.isEnterpriseServer),
				kvp.String("gh.authnd.server.addr", s.localMobileClientSrv.Addr),
			}
			logger.Info("starting local mobile client HTTP server", fields...)
			if err := s.localMobileClientSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				logger.WithError(errors.WithStack(err)).Error("mock mobile client server closed", fields...)
			}
		}()
	}

	go func() {
		logger.Info("starting proc and db stats reporters")
		procStats := &ps.Reporter{Stats: statter}

		tick := time.NewTicker(s.statsDuration)
		defer tick.Stop()

		for {
			select {
			case <-tick.C:
				procStats.Report()
			case <-ctx.Done():
				return
			}
		}
	}()

	<-ctx.Done()

	logger.Info("shutdown requested")
	// Use a new context with a 5s timeout to shutdown.
	// Shutdown will immediately stop new requests and give existing requests until the provided context terminates to complete.
	// If we give it the context that just terminated, we cancel existing requests immediately!
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	logger.Info("shutting down")
	shutdownErr := s.stop(ctx)

	// Log shutdown errors, but don't report them to Sentry
	if shutdownErr != nil {
		logger.WithError(shutdownErr).Error("shutdown error")
		statter.Counter("service.stop.error", nil, 1)
	}

	// flush statistics
	statter.Stop()
	return nil
}

// stop shutdowns the server and closes all underlying connections (if any)
func (s *Service) stop(ctx context.Context) error {
	var errs diagnostics.MultiError
	statter := diagnostics.Statter(ctx)

	diagnostics.Logger(ctx).Info("shutting down authnd service...")
	statter.Counter("service.stop", nil, 1)

	err := s.srv.Shutdown(ctx)
	if err != nil && !errors.Is(err, context.Canceled) {
		errs = append(errs, errors.WithStack(err))
	}

	// stop otel tracer
	s.shutdownTracer()

	// close kafka producer connection
	if err := s.notifyPublisher.Close(); err != nil {
		errs = append(errs, errors.WithStack(err))
	}

	if err := s.eventPublisher.Close(); err != nil {
		errs = append(errs, errors.WithStack(err))
	}

	// shut down sqlx.DB instances
	if err := s.databaseProvider.Close(); err != nil {
		errs = append(errs, errors.WithStack(err))
	}

	return errs.ErrorOrNil()
}

// countingListener records the number of times Accept is called.
type countingListener struct {
	st stats.Client
	net.Listener
}

func (c *countingListener) Accept() (net.Conn, error) {
	conn, err := c.Listener.Accept()
	c.st.Counter("http.accept", nil, 1)
	return conn, err
}

type canaryHandler struct {
	handler http.Handler
}

func (ch *canaryHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	header := w.Header()
	header.Add("X-GitHub-Canary", "true")
	ch.handler.ServeHTTP(w, r)
}
