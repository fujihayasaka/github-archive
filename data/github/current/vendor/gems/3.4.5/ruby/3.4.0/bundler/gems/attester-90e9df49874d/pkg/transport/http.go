package transport

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"net"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-http/v2/middleware/logrequest"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	statshttp "github.com/github/go-stats/http"

	"github.com/github/attester/pkg/auth"
	"github.com/github/attester/pkg/service"
	"github.com/gorilla/mux"
)

type ctxTenantIDKey string

const (
	statusPath                        = "/status"
	TenantID                          = "X-GitHub-Tenant-ID"
	TenantIDCtxKeyName ctxTenantIDKey = "ctx-tenant-request-id"
)

var ErrNoService = errors.New("no service loaded")

// ServerAuthConfig is the top level HMAC config used to construct
// HMAC auth for all support Twirp services
type ServerAuthConfig struct {
	Release auth.HMACKeys
	Boo     auth.HMACKeys
}

// HTTPServer is the instance of our Attester HTTP Server
type HTTPServer struct {
	server     *http.Server
	services   []service.Service // Allow multiple services
	addr       string
	logger     log.Logger
	metrics    stats.Client
	reporter   *exceptions.Reporter
	hmacConfig ServerAuthConfig
	gitCommit  string
}

// HTTPServerOption is a functional option for configuring the HTTPServer
type HTTPServerOption func(*HTTPServer)

// WithLogger sets the logger for the HTTPServer
func WithLogger(logger log.Logger) HTTPServerOption {
	return func(s *HTTPServer) {
		s.logger = logger
	}
}

// WithMetrics sets the metrics client for the HTTPServer
func WithMetrics(metrics stats.Client) HTTPServerOption {
	return func(s *HTTPServer) {
		s.metrics = metrics
	}
}

// WithExceptionReporter sets the exception reporter for the HTTPServer
func WithExceptionReporter(reporter *exceptions.Reporter) HTTPServerOption {
	return func(s *HTTPServer) {
		s.reporter = reporter
	}
}

// WithContext sets the base context for the HTTP server
func WithContext(ctx context.Context) HTTPServerOption {
	return func(s *HTTPServer) {
		s.server.BaseContext = func(_ net.Listener) context.Context {
			return ctx
		}
	}
}

// WithHMACConfig sets the HMAC configuration for the HTTPS
func WithHMACConfig(cfg ServerAuthConfig) HTTPServerOption {
	return func(s *HTTPServer) {
		s.hmacConfig = cfg
	}
}

// Get the X-GitHub-Tenant-ID header from the request
func LogTenantID(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(TenantID)

		if id != "" {
			r = r.WithContext(context.WithValue(r.Context(), TenantIDCtxKeyName, id))
		}

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

// NewHTTPServer creates a new HTTPServer instance
func NewHTTP(services []service.Service, gitCommit string, addr string, opts ...HTTPServerOption) (*HTTPServer, error) {
	logger, err := log.NewFromConfig(log.Config{
		LogConsoleEncoding: "logfmt",
		LogLevel:           log.InfoLevel.String(),
	})
	if err != nil {
		return nil, fmt.Errorf("configuring logger: %w", err)
	}

	s := &HTTPServer{
		services:  services,
		addr:      addr,
		logger:    logger,
		metrics:   stats.NullStatter,
		gitCommit: gitCommit,
	}

	s.server = &http.Server{
		Addr:              s.addr,
		ReadTimeout:       5 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
		ReadHeaderTimeout: 2 * time.Second,
	}

	// eval functional options
	for _, opt := range opts {
		opt(s)
	}

	// set routes after options are evaluated
	routeHandler, err := s.routes()
	if err != nil {
		return nil, fmt.Errorf("NewHTTP: %w", err)
	}
	s.server.Handler = routeHandler

	return s, nil
}

// ListenAndServe starts the HTTP server and handles requests
func (h *HTTPServer) ListenAndServe() error {
	h.logger.Info("listening", kvp.String("addr", h.addr))
	return h.server.ListenAndServe()
}

// Shutdown gracefully shuts down the HTTP server
func (h *HTTPServer) Shutdown() error {
	h.logger.Info("stopping HTTP listener and draining active connections")
	return h.server.Shutdown(context.Background())
}

// used, when testing, to expose the Handler's ServeHTTP fn
func (h *HTTPServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.server.Handler.ServeHTTP(w, r)
}

// Routes sets the routes & handlers for the HTTP server
func (h *HTTPServer) routes() (http.Handler, error) {
	// treat urls with encoded slashes (%2F) as text/variables, not as a slash
	router := mux.NewRouter().UseEncodedPath()
	serviceAdded := false

	// recovery middleware logs panics and sends them to the exception reporter
	rec := recovery.Recovery{
		Report: func(err error, r *http.Request) error {
			h.logger.Error("panic http recovery", kvp.Any("err", err))
			if h.reporter == nil {
				return nil
			}
			_ = h.reporter.Report(r.Context(), fmt.Errorf("panic: %w", err), map[string]string{
				"http.request.method": r.Method,
				"http.request.target": r.URL.String(),
			})
			return nil
		},
	}

	// setup middleware
	router.Use(rec.Handler)
	router.Use(requestid.Handler)
	router.Use(metricsMiddleware(h.metrics))
	router.Use(LogTenantID)
	router.Use(loggerMiddleware(h.logger))

	// Loop through services and mount them dynamically
	for _, svc := range h.services {
		serviceName := svc.GetName()
		var serviceHandler *TwirpService
		var err error

		switch serviceName {
		case "boo":
			serviceHandler, err = NewBooService(svc, h.hmacConfig.Boo, TwirpWithLogger(h.logger), TwirpWithMetrics(h.metrics), TwirpWithErrorReporter(h.reporter))
		case "release":
			serviceHandler, err = NewReleaseService(svc, h.hmacConfig.Release, TwirpWithLogger(h.logger), TwirpWithMetrics(h.metrics), TwirpWithErrorReporter(h.reporter))
		default:
			return nil, fmt.Errorf("unknown service: %s", serviceName)
		}

		if err != nil {
			return nil, fmt.Errorf("failed to create service handler for %s: %w", serviceName, err)
		}

		router.PathPrefix(serviceHandler.PathPrefix).Handler(serviceHandler.Handler)
		serviceAdded = true
		h.logger.Info("enabling", kvp.String("service", svc.GetName()))
	}

	if !serviceAdded {
		return nil, ErrNoService
	}

	// health check endpoint
	router.HandleFunc(statusPath, h.status).Methods("GET")

	// zen
	router.HandleFunc("/", h.zen)

	// 404 handler
	router.NotFoundHandler = http.HandlerFunc(notFound)
	return router, nil
}

func (h *HTTPServer) getVersion() string {
	return h.gitCommit
}

// setup http logger middleware
func loggerMiddleware(logger log.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// do not log requests to /status endpoint
			if r.URL.Path == statusPath {
				next.ServeHTTP(w, r)
				return
			}
			logrequest.Handler(next, logger).ServeHTTP(w, r)
		})
	}
}

// setup metrics middleware (datadog)
func metricsMiddleware(client stats.Client) func(http.Handler) http.Handler {
	return statshttp.WithResponseMetrics(client, statshttp.Options{})
}

// status handler returns the current status of the Attester service
func (h *HTTPServer) status(w http.ResponseWriter, _ *http.Request) {
	// TODO: add more detailed status information
	s := map[string]string{"state": "ok", "version": h.getVersion()}

	w.Header().Add("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	err := enc.Encode(s)
	if err != nil {
		wrapped := fmt.Errorf("HTTPServer#status: %w", err)
		h.logger.Error(wrapped.Error())
	}
}

var ZenPhrases = [...]string{
	"Responsive is better than fast.",
	"It's not fully shipped until it's fast.",
	"Anything added dilutes everything else.",
	"Practicality beats purity.",
	"Approachable is better than simple.",
	"Mind your words, they are important.",
	"Speak like a human.",
	"Half measures are as bad as nothing at all.",
	"Encourage flow.",
	"Non-blocking is better than blocking.",
	"Favor focus over features.",
	"Avoid administrative distraction.",
	"Design for failure.",
	"Keep it logically awesome.",
}

func (h *HTTPServer) zen(w http.ResponseWriter, _ *http.Request) {
	w.Header().Add("Content-Type", "application/json")
	body := map[string]string{"zen": ZenPhrases[rand.Intn(len(ZenPhrases))]} //nolint:gosec

	enc := json.NewEncoder(w)
	err := enc.Encode(body)

	if err != nil {
		wrapped := fmt.Errorf("HTTPServer#status: %w", err)
		h.logger.Error(wrapped.Error())
	}
}

// notFound handler is the default 404 response
func notFound(w http.ResponseWriter, _ *http.Request) {
	http.Error(w, "page not found", http.StatusNotFound)
}
