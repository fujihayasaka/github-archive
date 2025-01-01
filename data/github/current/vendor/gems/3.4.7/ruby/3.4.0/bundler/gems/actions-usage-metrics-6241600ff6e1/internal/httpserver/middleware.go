package httpserver

import (
	"fmt"
	"net/http"

	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/logrequest"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/go-http/v2/middleware/report"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/justinas/alice"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
)

// DefaultHttpMiddleware is a collection of middleware that should be used for REST HTTP servers.
// Middleware source code: https://github.com/github/go-http/tree/main/middleware
type DefaultHttpMiddleware struct {
	standardHandlers alice.Chain
	Unauthenticated  alice.Chain
	Authenticated    alice.Chain
}

func NewDefaultHttpMiddleware(telem *telemetry.Telemetry) *DefaultHttpMiddleware {
	logger := telem.Logger.Named("http")

	// Sets the context with the trace information from the incoming request.
	traceHandler := func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
			r = r.WithContext(ctx)
			next.ServeHTTP(w, r)
		}
		return http.HandlerFunc(fn)
	}

	// logs the method, path, and ID of the request, if present.
	logRequestHandler := func(next http.Handler) http.Handler {
		return logrequest.Handler(next, logger)
	}

	// stats the method and path of the request.
	statsRequestHandler := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			statsTags := stats.Tags{
				telemetry.HttpTargetKey: r.URL.RequestURI(),
				telemetry.HttpMethodKey: r.Method,
			}
			telem.Stats.Counter(telemetry.HttpRequestCount_StatsKey, statsTags, 1)
			next.ServeHTTP(w, r)
		})
	}

	// recovers from panics, logs the panic (and a backtrace), and returns a HTTP 500 (Internal Server Error) status if possible.
	recoveryMiddleware := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			requestId := requestid.GetGitHubRequestID(req.Context())
			// Errors should automatically be reported to Sentry by the logger
			logger.WithContext(req.Context()).
				WithError(err).
				WithFields(kvp.String(telemetry.GitHubRequestIDKey, requestId)).
				WithFields(kvp.String(telemetry.OtelHttpTarget, req.URL.RequestURI())).
				WithFields(kvp.String(telemetry.OtelHttpMethod, req.Method)).
				Error("http error")
			return nil
		},
	}

	// Report is a middleware that submits statistics about all incoming requests.
	// It will measure the duration of each request, and the active number of
	// requests at any given time, and it will report those to the given interfaces.
	reporter := telemetry.NewReporter(telem)
	reportMiddleware := report.Report{
		Logger:   reporter,
		Recorder: reporter,
	}

	standardHandlers := alice.New(
		traceHandler,
		requestid.Handler, // handles the github request id stuff
		logRequestHandler,
		statsRequestHandler,
		reportMiddleware.Handler,
		recoveryMiddleware.Handler,
	)

	return &DefaultHttpMiddleware{
		standardHandlers: standardHandlers,
		Unauthenticated:  standardHandlers,
	}
}

func (d *DefaultHttpMiddleware) UseHmacAuthentication(cfg config.HttpConfig) {
	hmacValidator := hmac.Validator{
		Secrets: []string{cfg.HMACPrimary, cfg.HMACSecondary},
		Logger:  log.Named("http-server"),
	}

	d.Authenticated = d.standardHandlers.Append(hmacValidator.Handler)
}

func HealthCheckHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "OK")
}
