package mu

import (
	"context"
	"encoding/json"
	"errors"
	"expvar"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"

	chatops "github.com/github/go-chatops/v2"
	"github.com/github/go-config/v2"
	"github.com/github/go-kvp"
	"github.com/go-chi/chi"
	"github.com/soheilhy/cmux"
	"golang.org/x/sync/errgroup"

	gokvp "github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	stats "github.com/github/launch/observability/statter"
)

// Servicer describes a service that can set up Routes and has a function that
// allows a service to set per-request context data before running its handler.
type Servicer interface {
	Routes() []Route
	ServiceContext(*http.Request)
}

// Service composes a statter, logger, and http router to run an HTTP service.
// Service handles gracefully shutting down and is able to run under systemd
// socket activation or plain old TCP.
type Service struct {
	Config       *Config
	Name         string
	BuildVersion string
	MuVersion    string
	Mux          chi.Router // Base router for the primary HTTP listener
	PrimaryMux   chi.Router // Router with middleware stack for services
	InternalMux  chi.Router // Router for the internal HTTP listener
	hservice     *httpService
	hserver      *httpServer
	iservice     *httpService
	iserver      *httpServer
	cservice     *chatopsService
	lis          *listeners
	statter      stats.Statter
	logger       logger.Logger
	bootTime     time.Time
}

// New creates and configures a new service.
func New(cfg *Config) (*Service, error) {
	if err := config.Load(cfg); err != nil {
		return nil, err
	}

	// Allow application to override the mu configuration
	if configured, ok := cfg.Application.(configger); ok {
		if err := configured.OnConfig(cfg); err != nil {
			return nil, err
		}
	}

	rmd := reqmeta.NewRequestMetadata()
	rmd.LogWith(
		gokvp.String("app", cfg.Name),
		gokvp.String("sha", cfg.BuildVersion),
		gokvp.String("mu", cfg.MuVersion),
		gokvp.String("host", AppHost()),
	)
	rmd.LogWith(cfg.DefaultLogFields...)

	var lcfg launchconfig.LoggerConfig
	if err := config.Load(&lcfg); err != nil {
		return nil, err
	}

	log := cfg.NewLogger(lcfg)

	statsClient := cfg.NewStatter()
	statsClient.Start()

	s := Service{
		Config:  cfg,
		logger:  log,
		statter: statsClient,
	}

	// This is delayed so the error can be logged by the caller.
	if len(cfg.Name) == 0 {
		return &s, errors.New("app name is required")
	}

	lis, err := setupListeners(cfg, log)
	if err != nil {
		return &s, err
	}
	s.lis = lis

	mux := chi.NewRouter()
	mux.Use(mw.OMG(log))
	s.Mux = mux

	s.PrimaryMux = mux.Group(func(r chi.Router) {
		r.Use(mw.GitHubRequestID)
		r.Use(mw.RequestMetadata(rmd))
		r.Use(mw.MeasureHTTP(log, statsClient))
	})

	if cfg.HTTPAddr == cfg.InternalAddr {
		s.InternalMux = mux.Group(nil)
	} else {
		s.InternalMux = chi.NewRouter()
		s.InternalMux.Use(mw.OMG(log))
	}

	// Primary HTTP service
	s.hserver = newHTTPServer(lis.httpListener, s.Mux)
	s.hservice = newHTTPService(s.PrimaryMux, s.hserver)

	// Internal HTTP service
	if cfg.HTTPAddr == cfg.InternalAddr {
		s.iserver = newHTTPServer(lis.internalListener, s.Mux)
		s.iservice = newHTTPService(s.InternalMux, s.hserver)
	} else {
		s.iserver = newHTTPServer(lis.internalListener, s.InternalMux)
		s.iservice = newHTTPService(s.InternalMux, s.iserver)
	}
	s.RouteInternal(newInternalService(s.healthHandler, s.boomHandler, s.hservice, s.iservice))

	ping := newPingService(cfg.BuildVersion, cfg.MuVersion)
	s.RouteService(ping)
	s.RouteInternal(ping)

	// Chatops
	s.cservice = s.setupChatops()

	s.bootTime = time.Now().UTC()

	return &s, nil
}

// RouteService adds a Servicer's routes to the mux and sets up its ServiceContext.
func (s *Service) RouteService(svc Servicer, middlewares ...func(http.Handler) http.Handler) {
	s.hservice.Mount(svc, middlewares...)
}

// RouteInternal adds a Servicer's routes to the internal mux.
func (s *Service) RouteInternal(svc Servicer, middlewares ...func(http.Handler) http.Handler) {
	s.iservice.Mount(svc, middlewares...)
}

// RegisterChatopsCommand registers a chatops command
func (s *Service) RegisterChatopsCommand(name, help, regex string, handler chatops.CommandFunc) error {
	return s.cservice.Register(name, help, regex, handler)
}

// Logger returns the service's logger
func (s *Service) Logger() logger.Logger {
	return s.logger
}

// Statter returns the service's statter
func (s *Service) Statter() stats.Statter {
	return s.statter
}

// Fatal reports the error to haystack, logs it, and exits with exit code 1.
// This is intended to be used during app boot up.
func (s *Service) Fatal(err error) {
	_ = s.logger.ReportBlocking(context.Background(), err) // nolint: gosec
	s.logger.Log(context.Background(), err.Error())
	os.Exit(1)
}

// Run will start the HTTP/gRPC/multiMux/internal servers (if configured) and block.
//
// ctx will be canceled when the mu application receives a SIGINT or SIGTERM.
func (s *Service) Run(ctx context.Context) error {
	s.logger.Log(ctx, "Starting", configFields(s.Config)...)
	s.statter.Event(ctx, s.Name, "boot", stats.Tags{"service": s.Name})

	// Emit a deprecation warning on startup.
	if _, ok := s.Config.Application.(oldStopper); ok {
		s.logger.Error(ctx, "mu application does not match the updated stopper interface, please update it")
	}

	// This should run first, particularly before any other http
	// routes are added to the primary or internal muxes. This is
	// because the application might directly access the mux and
	// add its own middleware. Chi will panic if middleware are
	// added after routes have been added.
	if err := s.Config.Application.OnStartUp(s); err != nil {
		return err
	}

	s.hservice.MountServices()
	s.iservice.MountServices()

	expvar.Publish("goroutines", expvar.Func(func() interface{} {
		return runtime.NumGoroutine()
	}))

	// ctx will be canceled by an external signal
	rungroup, runctx := errgroup.WithContext(ctx)
	rungroup.Go(s.runHTTPServer(runctx))
	rungroup.Go(s.runMultiMuxServer(runctx))
	rungroup.Go(s.runInternalServer(runctx))

	s.logger.Log(runctx, "Started", configFields(s.Config)...)

	// Main run loop blocks here.
	// Waits for an error or for the context to be canceled.
	<-runctx.Done()

	s.logger.Log(runctx, "Begin shutting down", configFields(s.Config)...)

	// First, call the BeforeShutdown callback to do any remaining work necessary
	// before shutting down the underlying servers.
	if stop, ok := s.Config.Application.(beforeStopper); ok {
		osctx, oscancel := context.WithTimeout(context.Background(), time.Second*10)
		defer oscancel()
		if err := stop.BeforeShutdown(osctx, s); err != nil {
			s.logger.Error(osctx, "error executing before shutdown callback", gokvp.Err(err))
		}
	}

	// Pending requests get 10 seconds before they're stopped. This gets a new
	// context since the main context `ctx` has been canceled at this point by the
	// SIGINT/SIGTERM handler in the mu application.
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), time.Second*10)
	defer shutdownCancel()
	if err := s.Shutdown(shutdownCtx); err != nil {
		// The shutdown timed out, log it and continue
		s.logger.Error(shutdownCtx, "server shutdown timed out", gokvp.Err(err))
	}

	// Finally, call the OnShutdown callback if defined to close out any remaining
	// services managed by the application. This also gets a 10-second timeout.
	if stop, ok := s.Config.Application.(stopper); ok {
		osctx, oscancel := context.WithTimeout(context.Background(), time.Second*10)
		defer oscancel()
		err := stop.OnShutdown(osctx, s)
		if err != nil {
			return fmt.Errorf("error executing shutdown callback: %w", err)
		}
		return nil
	}

	// Support the legacy OnShutDown handler too, if still present:
	if stop, ok := s.Config.Application.(oldStopper); ok {
		osctx, oscancel := context.WithTimeout(context.Background(), time.Second*10)
		defer oscancel()

		// Use errgroup to capture an error from the OnShutDown callback.
		shutdowngroup, _ := errgroup.WithContext(osctx)
		shutdowngroup.Go(func() error {
			return stop.OnShutDown(s)
		})
		err := shutdowngroup.Wait()
		if err != nil {
			return fmt.Errorf("error executing shutdown callback: %w", err)
		}
		return nil
	}

	return nil
}

// Shutdown stops the Server, blocking until all children have finished shutting
// down or the given context has expired.
func (s *Service) Shutdown(ctx context.Context) error {
	if deadline, ok := ctx.Deadline(); ok {
		s.logger.Log(ctx, "shutting down", gokvp.Duration("timeout", time.Until(deadline)))
	} else {
		s.logger.Log(ctx, "shutting down")
	}

	done := make(chan struct{})
	go func() {
		_ = s.hserver.Shutdown(ctx) // nolint: gosec
		_ = s.iserver.Shutdown(ctx) // nolint: gosec
		_ = s.lis.Shutdown()        // nolint: gosec
		s.statter.Stop()
		close(done)
	}()

	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// RunHTTP delegates to Run and is just here for legacy purposes.
// Deprecated: callers should use Run()
func (s *Service) RunHTTP() error {
	return s.Run(context.Background())
}

func (s *Service) runHTTPServer(ctx context.Context) func() error {
	return func() error {
		err := s.hserver.Serve()
		if err != nil && err != http.ErrServerClosed {
			s.logger.Error(ctx, "HTTP server", gokvp.Err(err))
			return err
		}

		return nil
	}
}

func (s *Service) runMultiMuxServer(ctx context.Context) func() error {
	return func() error {
		err := s.lis.Serve()
		if err != nil && err != cmux.ErrListenerClosed {
			s.logger.Error(ctx, "MultiMux server", gokvp.Err(err))
			return err
		}
		return nil
	}
}

func (s *Service) runInternalServer(ctx context.Context) func() error {
	return func() error {
		err := s.iserver.Serve()
		if err != nil && err != http.ErrServerClosed {
			s.logger.Error(ctx, "Internal server", gokvp.Err(err))
			return err
		}
		return nil
	}
}

// HealthStatus returns the service's status for a health check
func (s *Service) HealthStatus() (HealthCheckStatus, map[string]interface{}) {
	var status = HealthCheckOK
	var checks map[string]interface{}
	if health, ok := s.Config.Application.(healthChecker); ok {
		status, checks = health.OnHealthCheck(s)
	}

	if healthStr, ok := s.Config.Application.(healthCheckerStr); ok {
		var statusStr string
		statusStr, checks = healthStr.OnHealthCheck(s)
		status = HealthCheckStatus(statusStr)
	}
	return status, checks
}

// healthHandler reports the service and application's health.
// It's mounted inside InternalService since it contains private information,
// but it operates on Service's configuration and the Application so it's
// defined here.
func (s *Service) healthHandler(w http.ResponseWriter, r *http.Request) {
	now := time.Now().UTC()

	resp := healthCheckResponse{
		HostName:     AppHost(),
		BuildVersion: s.Config.BuildVersion,
		MuVersion:    s.Config.MuVersion,
		Now:          now,
		Boot:         s.bootTime,
		Uptime:       now.Sub(s.bootTime),
	}

	status, checks := s.HealthStatus()

	resp.Status = status
	resp.Checks = checks

	if status == HealthCheckError {
		w.WriteHeader(UnhealthyStatusCode)
	}

	if r.Header.Get("Accept") == "application/json" {
		_ = json.NewEncoder(w).Encode(resp) // nolint: gosec
	} else {
		fmt.Fprintf(w, "%s - %s - build:%s - mu:%s - %s\n", // nolint: errcheck, gosec
			resp.Status,
			resp.HostName,
			resp.BuildVersion,
			resp.MuVersion,
			resp.Now)
		if checks != nil {
			fmt.Fprintf(w, "\n") // nolint: errcheck, gosec
			for k, v := range checks {
				fmt.Fprintf(w, "%s: %s\n", k, v) // nolint: errcheck, gosec
			}
		}
	}
}

// boomHandler panics to test error reporting.
// It's mounted inside InternalService so it's listed in the service map.
func (s *Service) boomHandler(_ http.ResponseWriter, _ *http.Request) {
	panic(fmt.Sprintf("Boomtown from %s:%s (%d)", AppHost(), s.Config.BuildVersion, os.Getpid()))
}

// setupChatops ...
func (s *Service) setupChatops() *chatopsService {
	if s.Config.ChatopsAuthPublicKey == nil || s.Config.ChatopsAuthBaseURL == "" {
		return nil
	}

	chat, err := newChatopsService(&chatopsConfig{
		AuthBaseURL:   s.Config.ChatopsAuthBaseURL,
		AuthPublicKey: s.Config.ChatopsAuthPublicKey,
		Name:          s.Config.Name,
		Mux:           s.InternalMux,
	})
	if err != nil {
		s.logger.Report(context.Background(), err)
		return nil
	}

	return chat
}

// RouteService provides a package level RouteService for quickly adding
// Servicers to a muxer without needing an entire Service. This is useful for
// testing where routing is desired, but the httptest server is sufficient.
// Deprecated: some tests currently use this, nobody else should.
func RouteService(mux chi.Router, svc Servicer, middlewares ...func(http.Handler) http.Handler) {
	for _, route := range svc.Routes() {
		// This assembles the equivalent of:
		// rtr.With(s.ServiceContext).Get("/foo", barHandler)
		// Where the s.ServiceContext is wrapped in a middleware-aware
		// handler, and the appropriate chi method is used depending on
		// the Method of the Route.
		with := mux.With(middlewares...)
		m := route.rtrMethod(with.With(ctxCaller(svc)))
		m(route.Path, route.Handler)
	}
}

// configFields returns a set of fields for logging the mu config at startup.
func configFields(cfg *Config) (fields []kvp.Field) {
	if len(cfg.HTTPAddr) > 0 {
		fields = append(fields, gokvp.String("http_addr", cfg.HTTPAddr))
	}
	if len(cfg.InternalAddr) > 0 {
		fields = append(fields, gokvp.String("internal_addr", cfg.InternalAddr))
	}
	fields = append(fields, gokvp.String("stats_addr", cfg.StatsAddr))
	fields = append(fields, gokvp.Int("pid", os.Getpid()))
	return
}
