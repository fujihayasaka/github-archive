package automations

import (
	"context"
	"net/http"
	"time"

	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	cmcautomationsv1 "github.com/github/sweagentd/internal/proto/twirp/automations/v1"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/hashicorp/go-retryablehttp"
	"github.com/twitchtv/twirp"
)

const cmcTwirpClientName = "copilot-mission-control-twirp"

// NewCMCAutomationsClientFromConfig creates an HMAC-authenticated Twirp client
// for CMC's automations runtime lookup API.
func NewCMCAutomationsClientFromConfig(cfg *config.Config, obsv observability.Exporters) (cmcautomationsv1.AutomationsAPI, error) {
	if cfg.CopilotMissionControlTwirpURL == "" {
		return nil, goerrors.New("copilot mission control twirp url is required")
	}
	if cfg.CopilotMissionControlTwirpHMACKey == "" {
		return nil, goerrors.New("copilot mission control twirp hmac key is required")
	}

	timeout := time.Duration(cfg.CopilotMissionControlTwirpRequestTimeoutMs) * time.Millisecond
	httpClient := retryablehttp.NewClient()
	httpClient.HTTPClient = &http.Client{
		Timeout: timeout,
		Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, cmcTwirpClientName, func(_ *http.Request) stats.Tags {
			return stats.Tags{"api_target": "cmc_automations"}
		}),
	}
	httpClient.RetryMax = 2
	httpClient.RetryWaitMax = timeout
	httpClient.Logger = nil

	hmacClient, err := twirpAuth.NewRequestHMACSigner(cfg.CopilotMissionControlTwirpHMACKey, httpClient.StandardClient())
	if err != nil {
		return nil, goerrors.Errorf("failed to create HMAC signer for CMC automations twirp client: %w", err)
	}

	clientHooks := &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			req.Header.Set("User-Agent", "sweagentd")
			req.Header.Set(headers.GLBVia, "true")
			requestid.Forward(req)

			if slug := requestctx.TenantSlug(ctx); slug != "" {
				req.Header.Set(requestctx.GitHubTenantHeader, slug)
			}
			if tenantID := requestctx.TenantID(ctx); tenantID != "" {
				req.Header.Set(requestctx.GitHubTenantIDHeader, tenantID)
			}

			return ctx, nil
		},
	}

	return cmcautomationsv1.NewAutomationsAPIProtobufClient(cfg.CopilotMissionControlTwirpURL, hmacClient, twirp.WithClientHooks(clientHooks)), nil
}
