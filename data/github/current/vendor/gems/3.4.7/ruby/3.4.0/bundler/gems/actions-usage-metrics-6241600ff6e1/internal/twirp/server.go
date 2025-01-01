package twirp

import (
	"net/http"

	"github.com/github/actions-usage-metrics/internal/api"
	"github.com/github/actions-usage-metrics/internal/config"
	"github.com/github/actions-usage-metrics/internal/kusto"
	"github.com/github/actions-usage-metrics/internal/telemetry"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
	twirpauth "github.com/github/go-twirp/v2/server/hooks/auth"
	"github.com/twitchtv/twirp"
)

func NewTwirpUsageServer(telem *telemetry.Telemetry, apiServerCfg config.ApiServerConfig, kustoClient *kusto.Client) *http.ServeMux {
	defaultHooks := NewDefaultHooks(telem.Logger.Named("twirp"), telem.Stats)
	hooks := twirp.ChainHooks(
		defaultHooks,
		// verifies HMAC signature of request
		// We also have this on the HTTP server wrapper but we should have it directly on the Twirp server to make sure it's always checked
		twirpauth.VerifyRequestHMACHooks(apiServerCfg.Http.HMACPrimary, apiServerCfg.Http.HMACSecondary),
	)

	usageApi := api.NewUsageApi(apiServerCfg, kustoClient, telem)

	usageProtoServer := proto.NewUsageApiServer(usageApi, hooks)

	mux := http.NewServeMux()
	mux.Handle(usageProtoServer.PathPrefix(), usageProtoServer)

	return mux
}
