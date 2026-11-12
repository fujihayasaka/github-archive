// Package twirp is our Twirp server implementation
package twirp

import (
	"fmt"
	"net/http"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
	"github.com/twitchtv/twirp"
)

// Server holds the methods for our Twirp Server as well as a few dependencies.
type Server struct {
	app *application.Application
}

var _ proto.LicenseCompliance = (*Server)(nil)

// NewTwirpServer creates a new Twirp server.
func NewTwirpServer(hooks *twirp.ServerHooks, app *application.Application) (http.Handler, error) {
	server := &Server{
		app: app,
	}

	licenseComplianceServer := proto.NewLicenseComplianceServer(server, hooks)

	mux := http.NewServeMux()
	mux.Handle(licenseComplianceServer.PathPrefix(), applyMiddleware(licenseComplianceServer, app))
	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		if server.app.Subsystems != nil && server.app.Subsystems.Storage != nil {
			if err := server.app.Subsystems.Storage.HealthCheck(r.Context()); err != nil {
				http.Error(w, fmt.Sprintf("Health check failed: %v", err), http.StatusServiceUnavailable)
				return
			}
		}

		if _, err := fmt.Fprint(w, "OK"); err != nil {
			// In the rare case this happens we can only log as it's written headers
			log.LogfmtError("Failed to print ok", err)
		}
	})

	return mux, nil
}

func applyMiddleware(h http.Handler, app *application.Application) http.Handler {
	// TODO: apply HMAC authn in staging once we go live with prod
	if (!app.Config.IsDevelopment() && !app.Config.IsStaging()) || app.Config.DevForceHmacAuthentication {
		hmacValidator := &hmac.Validator{Secrets: app.Config.TwirpHMACKeys, Logger: app.Logger}
		h = hmacValidator.Handler(h)
	}

	return h
}
