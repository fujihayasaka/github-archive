package twirp

import (
	"context"
	"fmt"
	"net/http"

	"github.com/bufbuild/protovalidate-go"

	coreosoidc "github.com/coreos/go-oidc/v3/oidc"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	"github.com/github/hosted-compute-core/asymmjwt"
	"github.com/github/hosted-compute-core/oidc"
	hostedComputeTelemetry "github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/reporter"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/twitchtv/twirp"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
)

type baseApiHandler struct {
	imageStore           store.IImagesStore
	promotionClient      promotion.IImagePromotionClient
	promotionStartClient promotion.IImagePromotionStartClient
}

// ImagesApiHandler is our implementation of the generated rpc.ImageManagementService interface
type ImagesApiHandler struct {
	baseApiHandler
}

// ImagesAdminApiHandler is our implementation of the generated rpc.ImageManagementAdminService interface
type ImagesAdminApiHandler struct {
	baseApiHandler
}

// InternalImagesApiHandler is our implementation of the generated rpc.InternalImageManagementService interface
type InternalImagesApiHandler struct {
	baseApiHandler
}

func NewImageManagementServer(ctx context.Context, imagesStore store.IImagesStore, promotionClient promotion.IImagePromotionClient, twirpCfg *Config, vssfAuthCfg oidc.Config) (http.Handler, error) {
	vssfAuthClient, err := oidc.NewAuthClient(ctx,
		vssfAuthCfg,
		// hosted-compute-core/oidc has strict dependency on hosted-compute-core/telemetry
		hostedComputeTelemetry.NewReportingLogger(logger.GetBaseLogger(), reporter.GetBaseReporter(), statter.GetBaseStatter()),
		coreosoidc.NewProvider,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize vssf auth client")
	}

	baseApiHandler := baseApiHandler{
		imageStore:           imagesStore,
		promotionClient:      promotionClient,
		promotionStartClient: promotionClient.PromotionStartClient(),
	}

	protoValidator, err := protovalidate.New()
	if err != nil {
		return nil, err
	}

	commonIntercepters := twirp.WithServerInterceptors(
		requestValidatorIntercepter(protoValidator),
		requestTracerIntercepter(),
	)

	commonHooks := twirp.ChainHooks(
		requestTwirpMetadataHook(), // Add twirp metadata to the context
		twhooks.TimingHooks(),      // Log timing information for each request
		requestLoggerHook(),        // Report errors to splunk AND sentry
		requestStatterHook(),       // Report request stats to statsd
	)

	wrapHandler := func(handler http.Handler) http.Handler {
		handler = validateAuthHandler(handler, true, true, twirpCfg, vssfAuthClient)
		handler = requestMetadataHandler(handler)
		return handler
	}

	// Add a mux (router) in order to handle other routes against the same server instance
	mux := http.NewServeMux()

	imagesHandler := imagesapi.NewImageManagementServiceServer(&ImagesApiHandler{baseApiHandler}, commonIntercepters, commonHooks)
	mux.Handle(imagesHandler.PathPrefix(), wrapHandler(imagesHandler))

	adminImagesHandler := adminapi.NewImageManagementAdminServiceServer(&ImagesAdminApiHandler{baseApiHandler}, commonIntercepters, commonHooks)
	mux.Handle(adminImagesHandler.PathPrefix(), wrapHandler(adminImagesHandler))

	internalImagesHandler := internalapi.NewInternalImageManagementServiceServer(&InternalImagesApiHandler{baseApiHandler}, commonIntercepters, commonHooks)
	mux.Handle(internalImagesHandler.PathPrefix(), wrapHandler(internalImagesHandler))

	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "pong")
	})

	mux.HandleFunc("/.well-known/jwks", asymmjwt.GetJWKSHandler(&twirpCfg.JWTConfig))
	mux.HandleFunc("/.well-known/openid-configuration", asymmjwt.GetConfigurationHandler(&twirpCfg.JWTConfig, twirpCfg.InternalURL))

	return mux, nil
}
