package mux

import (
	"fmt"
	"net/http"

	"github.com/github/authnd/internal/api/middleware"
	"github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/common/feature"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	httphmac "github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/otel-instrumentation-go/oteltwirp"

	"github.com/justinas/alice"
)

// PrefixHandler represents a http.Handler bound to a path prefix.
type PrefixHandler interface {
	http.Handler

	// PathPrefix returns the HTTP URL path prefix for all methods
	// handled by this handler.
	PathPrefix() string
}

type prefixHandler struct {
	prefix string
	http.Handler
}

func (p *prefixHandler) PathPrefix() string {
	return p.prefix
}

// handlePrefix converts a http.Handler into a PrefixHandler for the supplied prefix.
func HandlePrefix(prefix string, h http.Handler) *prefixHandler {
	return &prefixHandler{
		prefix:  prefix,
		Handler: h,
	}
}

// handlePrefixFunc converts a http.HandlerFunc to a PrefixHandler for the supplied prefix.
func handlePrefixFunc(prefix string, h http.HandlerFunc) *prefixHandler {
	return HandlePrefix(prefix, h)
}

// ping returns a PrefixHandler which responds with 200 OK on /_ping.
func Ping() *prefixHandler {
	return handlePrefixFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "OK")
	})
}

// boom returns PrefixHandler which panics on requests to /_boom.
func Boom() *prefixHandler {
	return handlePrefixFunc("/_boom", func(w http.ResponseWriter, r *http.Request) {
		panic("boom!")
	})
}

// NewMux returns a http.Handler for the supplied PrefixHandlers via the HMAC handler.
func NewMux(logger log.Logger, statter stats.Client, isProxima bool, resolver tenancy.Resolver, prefixHandlers ...PrefixHandler) http.Handler {
	mux := http.NewServeMux()
	for _, ph := range prefixHandlers {
		// TODO(chriskirkland): change this to debug or remove it
		logger.Info("registering handler", kvp.String("gh.authnd.mux.prefix", ph.PathPrefix()))
		mux.Handle(ph.PathPrefix(), ph)
	}

	return alice.New(
		oteltwirp.Middleware,
		httphmac.Handler, //nolint:all TODO(zacharysierakowski): remove deprecated HMAC handler
		requestid.Handler,
		middleware.DiagnosticHandler(logger, statter),
		feature.Handler,
		middleware.TenantContextHandler(isProxima, resolver), // no-op handler behavior if env is not Proxima
	).Then(mux)
}
