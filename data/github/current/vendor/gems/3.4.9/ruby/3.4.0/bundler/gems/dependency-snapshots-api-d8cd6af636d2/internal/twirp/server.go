package twirp

import (
	"net/http"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/otel-instrumentation-go/oteltwirp"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/twirp/dependencies"
	"github.com/github/dependency-snapshots-api/internal/twirp/diagnostic"
	"github.com/github/dependency-snapshots-api/internal/twirp/snapshots"
	"github.com/github/dependency-snapshots-api/internal/twirp/snapshotsv2"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	statshttp "github.com/github/go-stats/http"
	"github.com/twitchtv/twirp"
)

// AddHandlers adds HTTP handlers for the Twirp service endpoints.
func AddHandlers(mux *http.ServeMux, hooks *twirp.ServerHooks, statter stats.Client, features features.Client, diagnosticSvc interfaces.DiagnosticService, snapshotSvc interfaces.SnapshotsService, dependenciesSvc interfaces.DependenciesService, cfg *config.Config) {
	diagnosticServer := diagnostic.CreateTwirpServer(hooks, diagnosticSvc)
	snapshotsServer := snapshots.CreateTwirpServer(hooks, statter, features, snapshotSvc)
	dependenciesServer := dependencies.CreateTwirpServer(hooks, statter, features, dependenciesSvc)
	SnapshotsV2Server := snapshotsv2.CreateTwirpServer(hooks, statter)

	muxHandle(mux, diagnosticServer, statter, cfg)
	muxHandle(mux, snapshotsServer, statter, cfg)
	muxHandle(mux, dependenciesServer, statter, cfg)
	muxHandle(mux, SnapshotsV2Server, statter, cfg)
}

func muxHandle(mux *http.ServeMux, server proto.TwirpServer, statter stats.Client, cfg *config.Config) {
	mux.Handle(server.PathPrefix(), applyMiddleware(server, statter, cfg))
}

func applyMiddleware(h http.Handler, statter stats.Client, cfg *config.Config) http.Handler {
	h = requestid.Handler(h)
	h = oteltwirp.Middleware(h)
	if !cfg.IsDevelopment() || cfg.DevForceHmacAuthentication {
		hmacValidator := &hmac.Validator{Secrets: []string{cfg.HMACKey}, Logger: nil}
		h = hmacValidator.Handler(h)
	}
	h = statshttp.WithResponseMetrics(statter, statshttp.Options{})(h)
	h = WithSnapshotRequestHeadersInContext(h)
	return h
}
