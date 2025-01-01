// Package twirpserver provides a Twirp server for the Licensify service.
package twirpserver

import (
	"context"
	"fmt"
	"net/http"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/api"
	"github.com/github/licensify/internal/config"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/engines"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/trace"
)

// NewTwirpServer creates a new Twirp server with handlers for the Licensify service.
func NewTwirpServer(ctx context.Context, cfg *config.Config, logger log.Logger,
	statter stats.Client, tracer trace.Tracer, dbConnection *cosmos.DatabaseConnection,
	hooks *twirp.ServerHooks, aqueductClient aqueduct.Client) (http.Handler, error) {
	mux := http.NewServeMux()

	productEnablementEngine := engines.NewProductEnablementEngine(statter, tracer, dbConnection)
	customerLicenseEngine := engines.NewCustomerLicenseEngine(statter, tracer, dbConnection)
	customerEngine := engines.NewCustomerEngine(statter, tracer, dbConnection)
	licenseeLicenseEngine := engines.NewLicenseeLicenseEngine(statter, tracer, dbConnection)

	productEnablementAPI := api.NewProductEnablementAPI(productEnablementEngine, logger)
	customerLicenseAPI := api.NewCustomerLicenseAPI(customerLicenseEngine, licenseeLicenseEngine, aqueductClient, logger, cfg)
	customerAPI := api.NewCustomerAPI(customerEngine, aqueductClient, logger, cfg)

	productEnablementProtoServer := proto.NewProductEnablementServiceServer(productEnablementAPI, hooks)
	customerLicenseProtoServer := proto.NewCustomerLicenseServiceServer(customerLicenseAPI, hooks)
	customerProtoServer := proto.NewCustomerServiceServer(customerAPI, hooks)

	mux.Handle(productEnablementProtoServer.PathPrefix(), productEnablementProtoServer)
	mux.Handle(customerLicenseProtoServer.PathPrefix(), customerLicenseProtoServer)
	mux.Handle(customerProtoServer.PathPrefix(), customerProtoServer)

	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		logger.Info("ping")
		_, _ = fmt.Fprintf(w, "OK - %s - DONE", cfg.Sha)
	})

	return mux, nil
}
