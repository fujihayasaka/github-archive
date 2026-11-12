package twirp

import (
	"net/http"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/twirp/dependabot"
	"github.com/github/dependency-snapshots-api/internal/twirp/dependencies"
	"github.com/github/dependency-snapshots-api/internal/twirp/diagnostic"
	"github.com/github/dependency-snapshots-api/internal/twirp/snapshots"
	"github.com/github/dependency-snapshots-api/pkg/proto"

	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/otel-instrumentation-go/oteltwirp"

	"github.com/twitchtv/twirp"
)

// AddHandlers adds HTTP handlers for the Twirp service endpoints.
func AddHandlers(
	mux *http.ServeMux,
	hooks *twirp.ServerHooks,
	statter stats.Client,
	features features.Client,
	diagnosticSvc interfaces.DiagnosticService,
	snapshotSvc interfaces.SnapshotsService,
	dependenciesSvc interfaces.DependenciesService,
	dependabotEventSvc interfaces.DependabotEventService,
	publisher hydro.Publisher,
	cfg *config.Config,
) {
	diagnosticServer := diagnostic.CreateTwirpServer(hooks, diagnosticSvc)
	snapshotsServer := snapshots.CreateTwirpServer(hooks, statter, features, snapshotSvc, publisher)
	dependenciesServer := dependencies.CreateTwirpServer(hooks, statter, features, dependenciesSvc)
	dependabotServer := dependabot.CreateTwirpServer(hooks, statter, features, snapshotSvc, dependabotEventSvc, publisher)

	muxHandle(mux, diagnosticServer, cfg)
	muxHandle(mux, snapshotsServer, cfg)
	muxHandle(mux, dependenciesServer, cfg)
	muxHandle(mux, dependabotServer, cfg)
}

func muxHandle(mux *http.ServeMux, server proto.TwirpServer, cfg *config.Config) {
	mux.Handle(server.PathPrefix(), applyMiddleware(server, cfg))
}

func applyMiddleware(h http.Handler, cfg *config.Config) http.Handler {
	h = requestid.Handler(h)
	h = oteltwirp.Middleware(h)
	if !cfg.IsDevelopment() || cfg.DevForceHmacAuthentication {
		hmacValidator := &hmac.Validator{Secrets: []string{cfg.HMACKey}, Logger: nil}
		h = hmacValidator.Handler(h)
	}
	h = WithSnapshotRequestHeadersInContext(h)
	return h
}
