// Package apiservice constructs an API service
package apiservice

import (
	"context"
	"fmt"
	"net/http"

	pkgclock "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/twitchtv/twirp"

	"github.com/github/notifyd/internal/api"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/exceptions"
	"github.com/github/notifyd/internal/pkg/process"
	"github.com/github/notifyd/internal/pkg/shutdown"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Service represents an API Service
type Service struct {
	*http.Server
	telem *telemetry.Provider
}

// Server describes an entity that is able to return and HTTP handler for its own.
type Server interface {
	Handler(hooks *twirp.ServerHooks) api.Handler
}

// NewService creates a service to handle the twirp API endpoints.
func NewService(
	cfg Config,
	tenant tenancy.Tenant,
	clock pkgclock.Clock,
	telem *telemetry.Provider,
	reporter exceptions.Reporter,
	twirpHooks *twirp.ServerHooks,
	hmacValidator *hmac.Validator,
	servers ...Server,
) Service {
	mux := http.NewServeMux()

	for _, s := range servers {
		handler := s.Handler(twirpHooks)
		mux.Handle(
			handler.PathPrefix(),
			oteltwirp.Middleware(hmacValidator.Handler(handler)),
		)
	}

	mux.HandleFunc("/_ping", func(writer http.ResponseWriter, request *http.Request) {
		_, _ = fmt.Fprintf(writer, "OK - %s - DONE", clock.Now())
	})

	handler := secureHeadersHandler(mux)

	tenantMid := &tenantMiddleware{logger: telem.Logger, tenant: tenant}
	handler = tenantMid.Handler(handler)
	handler = requestid.Handler(handler)

	// timeout handler returns 503 Service Unavailable after the configured timeout
	handler = http.TimeoutHandler(handler, cfg.Timeout, fmt.Sprintf("timeout of %v exceeded", cfg.Timeout))

	handler = recoverableHandler(handler, reporter)

	return Service{
		Server: &http.Server{
			Addr:              cfg.Addr,
			Handler:           handler,
			ReadHeaderTimeout: cfg.Timeout,
			ReadTimeout:       cfg.Timeout,
			WriteTimeout:      cfg.Timeout,
		},
		telem: telem,
	}
}

// Run starts the service and returns the cleanup function.
func (s Service) Run(ctx context.Context) shutdown.Cleanup {
	s.telem.Logger.WithContext(ctx).Info("API server starting")
	go func() {
		if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.telem.Logger.WithError(err).Error("error starting the api server")
			process.Exit(process.APIServerError)
		}
	}()
	return s.Shutdown
}

// secureHeadersMiddleware unconditionally adds "Strict-Transport-Security",
// "Content-Security-Policy" headers to all responses.
func secureHeadersHandler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, req *http.Request) {
		rw.Header().Set("Strict-Transport-Security", "max-age=31536000")
		rw.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox")
		next.ServeHTTP(rw, req)
	})
}

// recoverableHandler makes the next handler recover from a panic, reports the
// panic and writes an http.StatusInternalServerError with a redacted message.
func recoverableHandler(next http.Handler, reporter exceptions.Reporter) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, req *http.Request) {
		defer func(ctx context.Context) {
			if err := recover(); err != nil {
				_ = reporter.Report(ctx, fmt.Errorf("panic: %+v", err), map[string]string{
					"method": req.Method,
					"url":    req.URL.String(),
				})

				http.Error(rw, "exception handler has recovered from panic", http.StatusInternalServerError)
				return
			}
		}(req.Context())
		next.ServeHTTP(rw, req)
	})
}
