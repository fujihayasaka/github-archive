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

	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-http/v2/middleware/logrequest"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	statshttp "github.com/github/go-stats/http"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"

	"github.com/github/trust-metadata-api/pkg/hydro"
	"github.com/gorilla/mux"
)

const (
	statusPath = "/status"
)

var ErrNoService = errors.New("no service loaded")

// ServerAuthConfig is the top level HMAC config used to construct
// HMAC auth for all support Twirp services
type ServerAuthConfig struct {
	PkgWrite  []auth.ClientConfig
	PkgRead   []auth.ClientConfig
	LegacyTMA []auth.ClientConfig
	Dotcom    []auth.ClientConfig
}

// HTTPServer is the instance of our TMA HTTP Server
type HTTPServer struct {
	server      *http.Server
	tma         service.TMAService
	addr        string
	logger      log.Logger
	metrics     stats.Client
	reporter    *exceptions.Reporter
	hmacConfig  ServerAuthConfig
	hydroClient *hydro.Client
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

// WithHydroClient sets the hydro client for the HTTP server
func WithHydroClient(hydroClient *hydro.Client) HTTPServerOption {
	return func(s *HTTPServer) {
		s.hydroClient = hydroClient
	}
}

// LogNPMRequestID gets the NPM Request ID from the request header
func LogNPMRequestID(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(service.NpmRequestID)
		if id != "" {
			r = r.WithContext(context.WithValue(r.Context(), service.NpmCtxKeyName, id))
		}

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

// LogClientIPAddr gets the client's IP address and includes it in
// the context to generate a SAS URL
func LogClientIPAddr(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		// check if the X-Forwarded-For header is populated
		// and use the first value, since this should be the
		// original client IP address
		headerVal := r.Header.Get("X-Forwarded-For")
		// if not populated, use RemoteAddr
		if headerVal == "" {
			ipAddr, _, err := net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				http.Error(w, "Invalid IP address", http.StatusBadRequest)
				return
			}
			r = r.WithContext(context.WithValue(r.Context(), azureblob.ClientIPAddrCtxKeyName, ipAddr))
			next.ServeHTTP(w, r)
		} else {
			r = r.WithContext(context.WithValue(r.Context(), azureblob.ClientIPAddrCtxKeyName, headerVal))
			next.ServeHTTP(w, r)
		}
	}
	return http.HandlerFunc(fn)
}

// Get the X-GitHub-Tenant-ID header from the request
func LogTenantID(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(service.TenantID)

		if id != "" {
			r = r.WithContext(context.WithValue(r.Context(), service.TenantIDCtxKeyName, id))
		}

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

// NewHTTPServer creates a new HTTPServer instance
func NewHTTP(tma service.TMAService, addr string, opts ...HTTPServerOption) (*HTTPServer, error) {
	logger, err := log.NewFromConfig(log.Config{
		LogConsoleEncoding: "logfmt",
		LogLevel:           log.InfoLevel.String(),
	})
	if err != nil {
		return nil, fmt.Errorf("Configuring logger: %w", err)
	}

	s := &HTTPServer{
		tma:     tma,
		addr:    addr,
		logger:  logger,
		metrics: stats.NullStatter,
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
	router.Use(LogClientIPAddr)
	router.Use(LogNPMRequestID)
	router.Use(LogTenantID)
	router.Use(loggerMiddleware(h.logger))
	router.Use(traceMiddleware())

	// mount legacy PoC TMA Twirp server
	if len(h.hmacConfig.LegacyTMA) > 0 {
		legacyTwirpService, err := NewTMATwirpService(
			h.tma,
			h.hmacConfig.LegacyTMA,
			TwirpWithLogger(h.logger),
			TwirpWithMetrics(h.metrics),
		)
		if err != nil {
			return nil, fmt.Errorf("routes: %w", err)
		}
		router.PathPrefix(legacyTwirpService.PathPrefix).Handler(legacyTwirpService.Handler)
		serviceAdded = true
		h.logger.Info("enabling",
			kvp.String("service", "legacy-twirp"))
	}

	// NPM: mount PackageInfoRead Twirp server
	if len(h.hmacConfig.PkgRead) > 0 {
		readOnlyService, err := NewPackageInfoReadService(
			h.tma,
			h.hmacConfig.PkgRead,
			TwirpWithLogger(h.logger),
			TwirpWithMetrics(h.metrics),
		)
		if err != nil {
			return nil, fmt.Errorf("routes: %w", err)
		}

		router.PathPrefix(readOnlyService.PathPrefix).Handler(readOnlyService.Handler)
		serviceAdded = true
		h.logger.Info("enabling",
			kvp.String("service", "package-info-read"))
	}

	// NPM: mount PackageInfoWrite Twirp server
	if len(h.hmacConfig.PkgWrite) > 0 {
		writeService, err := NewPackageInfoWriteService(
			h.tma,
			h.hmacConfig.PkgWrite,
			TwirpWithLogger(h.logger),
			TwirpWithMetrics(h.metrics),
		)
		if err != nil {
			return nil, fmt.Errorf("routes: %w", err)
		}

		router.PathPrefix(writeService.PathPrefix).Handler(writeService.Handler)
		serviceAdded = true
		h.logger.Info("enabling",
			kvp.String("service", "package-info-write"))
	}

	// GitHubAPI: mount Dotcom Twirp server
	if len(h.hmacConfig.Dotcom) > 0 {
		dotcomService, err := NewDotcomService(
			h.tma,
			h.hmacConfig.Dotcom,
			TwirpWithLogger(h.logger),
			TwirpWithMetrics(h.metrics),
			TwirpWithHydro(h.hydroClient),
		)
		if err != nil {
			return nil, fmt.Errorf("routes: %w", err)
		}

		router.PathPrefix(dotcomService.PathPrefix).Handler(dotcomService.Handler)
		serviceAdded = true
		h.logger.Info("enabling",
			kvp.String("service", "dotcom"))
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

// setup distributed tracing middleware  (datadog)
func traceMiddleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Ignore send trace requests for /status endpoint, since it's not critical and we calling /status a lot. This will reduce the number of traces sent to datadog.
			if r.URL.Path == statusPath {
				next.ServeHTTP(w, r)
				return
			}

			ctx := propagation.TraceContext{}.Extract(r.Context(), propagation.HeaderCarrier(r.Header))
			_, span := o11y.NamedSpan(ctx, r.URL.Path)
			defer span.End()

			r = r.WithContext(trace.ContextWithSpan(r.Context(), span))

			next.ServeHTTP(w, r)
		})
	}
}

// setup metrics middleware (datadog)
func metricsMiddleware(client stats.Client) func(http.Handler) http.Handler {
	return statshttp.WithResponseMetrics(client, statshttp.Options{})
}

// status handler returns the current status of the TMA service
func (h *HTTPServer) status(w http.ResponseWriter, _ *http.Request) {
	s := map[string]string{"state": "ok", "version": h.tma.GetGitCommit()}

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
