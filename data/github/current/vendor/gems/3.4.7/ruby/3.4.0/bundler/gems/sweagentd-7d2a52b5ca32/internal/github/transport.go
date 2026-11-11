package github

import (
	"fmt"
	"net/http"
	"net/url"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/github/ratelimits"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
)

type ClientRoundTripper struct {
	base http.RoundTripper
	obsv observability.Exporters
}

// ClientTransport creates a new RoundTripper that applies rate limiting and telemetry
// to requests made to the GitHub API. Rate limits are tracked using [limiter.RateLimiter]
// and associated with the specific target. The value for target should be created using
// one of: [limiter.TargetForOwnerID], [limiter.TargetForOwnerName], [limiter.TargetForUserID]
//
// If the client is a GitHub App client, use [AppClientTransport] instead, which does
// not require a target since GitHub Apps do not have per-organization rate limits.
//
// If the client does not require rate limiting, use [TelemetryClientTransport]
// instead, which only applies telemetry.
func ClientTransport(base http.RoundTripper, obsv observability.Exporters, limiter limiter.RateLimiter, target, clientName string) *ClientRoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}

	ratelimitTransport := ratelimits.NewRoundTripper(base, limiter, target)
	telemetryTransport := observability.NewTelemetryRoundTripper(ratelimitTransport, obsv, clientName)

	return &ClientRoundTripper{
		base: telemetryTransport,
		obsv: obsv,
	}
}

// AppClientTransport creates a new RoundTripper for GitHub App clients that applies
// telemetry to requests made to the GitHub API. The transport uses the limiter to
// track secondary rate limits, but does not track primary rate limits.
func AppClientTransport(base http.RoundTripper, obsv observability.Exporters, limiter limiter.RateLimiter) *ClientRoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}

	ratelimitTransport := ratelimits.NewRoundTripper(base, limiter, "")
	telemetryTransport := observability.NewTelemetryRoundTripper(ratelimitTransport, obsv, "github-app")

	return &ClientRoundTripper{
		base: telemetryTransport,
		obsv: obsv,
	}
}

// TelemetryClientTransport is used by clients that do not require rate limiting.
// Prefer using [ClientTransport] or [AppClientTransport] instead.
func TelemetryClientTransport(base http.RoundTripper, obsv observability.Exporters) *ClientRoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}

	telemetryTransport := observability.NewTelemetryRoundTripper(base, obsv, "github-norate")

	return &ClientRoundTripper{
		base: telemetryTransport,
		obsv: obsv,
	}
}

func (h *ClientRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	slug := requestctx.TenantSlug(req.Context())
	if slug != "" {
		req.Header.Set(requestctx.GitHubTenantHeader, slug)
		req.Header.Set(requestctx.GitHubTenantIDHeader, requestctx.TenantID(req.Context()))
	}

	requestid.Forward(req)

	// Add X-Forwarded-For and X_REAL_IP headers with user's IP address if available
	if user, ok := requestctx.User(req.Context()); ok && user.RequestIP != "" {
		req.Header.Set("X-Forwarded-For", user.RequestIP)
		req.Header.Set("X-REAL-IP", user.RequestIP)
		req.Header.Set("X-Client-IP", user.RequestIP)
	}

	// Replace <tenant> placeholder in URL with actual tenant ID from context
	if req.URL != nil {
		originalURL := req.URL.String()
		modifiedURL, err := proxima.ReplaceTenantPlaceholder(req.Context(), originalURL)
		if err != nil {
			return nil, fmt.Errorf("failed to replace tenant placeholder in URL: %w", err)
		}

		if modifiedURL != originalURL {
			// Parse the modified URL and update the request
			if newURL, err := url.Parse(modifiedURL); err == nil {
				req.URL = newURL
				// Update the Host header to match the new URL host to avoid HTTP/2 validation errors
				req.Host = newURL.Host
			}
		}
	}

	return h.base.RoundTrip(req)
}
