// this handles the twirp ceremony and calls the actual api
package twirp

import (
	"errors"
	"fmt"
	"net/http"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/internal/featureflag"
	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/lib/api"
	"github.com/github/billing-platform/lib/azure/kusto"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/usage"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	stats "github.com/github/go-stats"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/trace"
)

// NewTwirpServer creates a new Twirp server.
func NewTwirpServer(
	hooks *twirp.ServerHooks, cfg *config.Config,
	errorReporter *exceptions.Reporter, logger log.Logger,
	statter stats.Client, flagger featureflag.FlagChecker,
	db interfaces.Database, aqueductClient aqueduct.Client,
	monolithClient *monolith.Client, tracer trace.Tracer) (http.Handler, error) {

	kustoService, _ := kusto.New(cfg, statter, logger)
	engineParams := engines.NewEngineParams(aqueductClient, cfg, db, flagger, statter, monolithClient, tracer)
	costCenterEngine := engines.NewCostCenterEngine(engineParams)
	customerEngine := engines.NewCustomerEngine(engineParams)
	invoiceEngine := engines.NewInvoiceEngine(engineParams)
	pricingEngine := engines.NewPricingEngine(engineParams)
	productEngine := engines.NewProductEngine(engineParams)
	usageEngine := engines.NewUsageEngine(engineParams)
	adminEngine := engines.NewAdminEngine(engineParams)
	usageReportEngine := engines.NewUsageReportEngine(engineParams)
	azureEmissionEngine := engines.NewAzureEmissionEngine(engineParams)
	totalPatching := engines.NewTotalPatchingEngine(engineParams)

	subscriptionsEngine := engines.NewSubscriptionsEngine(engineParams, totalPatching, logger)
	usageService := usage.NewUsageService(kustoService, usageEngine, logger, statter)

	costCenterApi := api.NewCostCenterAPI(costCenterEngine, customerEngine, logger, tracer)
	customerApi := api.NewCustomerAPI(customerEngine, logger, statter, tracer)
	pricingApi := api.NewPricingAPI(pricingEngine, logger)
	productApi := api.NewProductAPI(productEngine, logger)
	usageApi := api.NewUsageAPI(invoiceEngine, usageEngine, pricingEngine, customerEngine, costCenterEngine, logger, statter, kustoService, usageService)
	adminAPI := api.NewAdminAPI(adminEngine, azureEmissionEngine, customerEngine, logger, pricingEngine)
	invoiceAPI := api.NewInvoiceAPI(invoiceEngine, logger)
	subscriptionsApi := api.NewSubscriptionsApi(subscriptionsEngine, logger, cfg, statter)
	usageReportAPI := api.NewUsageReportAPI(costCenterEngine, usageEngine, pricingEngine, customerEngine, usageReportEngine, logger)

	costCenterProtoServer := proto.NewCostCenterApiServer(costCenterApi, hooks)
	customerProtoServer := proto.NewCustomerApiServer(customerApi, hooks)
	pricingProtoServer := proto.NewPricingApiServer(pricingApi, hooks)
	productProtoServer := proto.NewProductApiServer(productApi, hooks)
	usageProtoServer := proto.NewUsageApiServer(usageApi, hooks)
	adminProtoServer := proto.NewAdminApiServer(adminAPI, hooks)
	invoiceProtoServer := proto.NewInvoiceAPIServer(invoiceAPI, hooks)
	subscriptionProtoServer := proto.NewSubscriptionsApiServer(subscriptionsApi, hooks)
	usageReportProtoServer := proto.NewUsageReportApiServer(usageReportAPI, hooks)

	mux := http.NewServeMux()

	mux.Handle(costCenterProtoServer.PathPrefix(), costCenterProtoServer)
	mux.Handle(customerProtoServer.PathPrefix(), customerProtoServer)
	mux.Handle(pricingProtoServer.PathPrefix(), pricingProtoServer)
	mux.Handle(productProtoServer.PathPrefix(), productProtoServer)
	mux.Handle(usageProtoServer.PathPrefix(), usageProtoServer)
	mux.Handle(adminProtoServer.PathPrefix(), adminProtoServer)
	mux.Handle(invoiceProtoServer.PathPrefix(), invoiceProtoServer)
	mux.Handle(subscriptionProtoServer.PathPrefix(), subscriptionProtoServer)
	mux.Handle(usageReportProtoServer.PathPrefix(), usageReportProtoServer)

	logger.Info("proto server path prefixes",
		kvp.String("gh.billing_platform.twirp.cost_center_api_path", costCenterProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.customer_api_path", customerProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.pricing_api_path", pricingProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.product_api_path", productProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.usage_api_path", usageProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.admin_api_path", adminProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.invoice_api_path", invoiceProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.subscription_api_path", subscriptionProtoServer.PathPrefix()),
		kvp.String("gh.billing_platform.twirp.usage_report_api_path", usageReportProtoServer.PathPrefix()),
	)

	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		logger.Info("ping")
		fmt.Fprintf(w, "OK - %s - DONE", cfg.Sha)
	})
	mux.HandleFunc("/_boom", func(writer http.ResponseWriter, request *http.Request) {
		logger.Info("boom")
		err := errorReporter.Report(request.Context(), errors.New("this is an error"), map[string]string{"location": "/_boom"})
		if err != nil {
			logger.WithError(err).Error("boom error")
		}
		panic("boom!")
	})

	return mux, nil
}
