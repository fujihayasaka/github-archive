package twirp

import (
	"fmt"
	"net/http"

	"github.com/bufbuild/protovalidate-go"

	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/hosted-compute-core/oidc"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
	"github.com/twitchtv/twirp"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
)

type baseApiHandler struct {
	imageStore        store.IImagesStore
	workerQueueClient queue.IWorkerQueueClient
	manager           resources.IManager
	logger            *telemetry.ReportingLogger
	statter           stats.Client
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

func NewImageManagementServer(imagesStore store.IImagesStore, workerQueueClient queue.IWorkerQueueClient, vssfAuthClient *oidc.AuthClient, manager resources.IManager, cfg *Config, telem *telemetry.Telemetry) (http.Handler, error) {
	baseApiHandler := baseApiHandler{
		imageStore:        imagesStore,
		workerQueueClient: workerQueueClient,
		manager:           manager,
		logger:            telem.Logger,
		statter:           telem.Stats,
	}

	protoValidator, err := protovalidate.New()
	if err != nil {
		return nil, err
	}

	commonIntercepters := twirp.WithServerInterceptors(
		tracerIntercepter(telem),
		ProtoValidateIntercepter(protoValidator, telem.Logger),
	)

	commonHooks := twirp.ChainHooks(
		twhooks.TimingHooks(),             // Log timing information for each request
		twhooks.StoreTwirpErrorHooks(),    // Store twirp errors in the request context
		twlog.DefaultHooks(telem.Logger),  // Log request and response payloads
		twstats.DefaultHooks(telem.Stats), // Log request and response stats
		logReporterHook(telem.Logger),     // Report errors to splunk AND sentry
		statsReporterHook(telem.Stats),    // Report request stats to statsd
	)

	// Add a mux (router) in order to handle other routes against the same server instance
	mux := http.NewServeMux()

	imagesHandler := imagesapi.NewImageManagementServiceServer(&ImagesApiHandler{baseApiHandler}, commonIntercepters, commonHooks)
	mux.Handle(imagesHandler.PathPrefix(), validateAuthHandler(imagesHandler, true, true, cfg, vssfAuthClient, telem.Logger))

	adminImagesHandler := adminapi.NewImageManagementAdminServiceServer(&ImagesAdminApiHandler{baseApiHandler}, commonIntercepters, commonHooks)
	mux.Handle(adminImagesHandler.PathPrefix(), validateAuthHandler(adminImagesHandler, true, false, cfg, vssfAuthClient, telem.Logger))

	internalImagesHandler := internalapi.NewInternalImageManagementServiceServer(&InternalImagesApiHandler{baseApiHandler}, commonIntercepters, commonHooks)
	mux.Handle(internalImagesHandler.PathPrefix(), validateAuthHandler(internalImagesHandler, true, true, cfg, vssfAuthClient, telem.Logger))

	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "pong")
	})

	return mux, nil
}
