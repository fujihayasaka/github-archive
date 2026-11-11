package github

import (
	"context"
	"net/http"
	"net/url"
	"time"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/sweagentd/internal/github/ratelimits"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/hashicorp/go-retryablehttp"
)

// ClientRoundTripper wraps an HTTP RoundTripper to add rate limiting and telemetry.
type ClientRoundTripper struct {
	base http.RoundTripper
	obsv observability.Exporters
}

// newRetryingTransport wraps the given transport with retry logic for transient errors.
// Retries are performed for errors identified by isRetryableError up to 3 times
// with exponential backoff (max wait: 10 seconds).
func newRetryingTransport(inner http.RoundTripper) http.RoundTripper {
	retryClient := retryablehttp.NewClient()
	retryClient.HTTPClient = &http.Client{
		Transport: inner,
	}
	retryClient.RetryMax = 3
	retryClient.RetryWaitMax = 10 * time.Second
	retryClient.CheckRetry = isRetryableError

	return retryClient.StandardClient().Transport
}

// ClientTransport creates a new RoundTripper that applies rate limiting, telemetry,
// and automatic retries to requests made to the GitHub API. Rate limits are tracked
// using [limiter.RateLimiter] and associated with the specific target. The value for
// target should be created using one of: [limiter.NewTarget] (preferred), [limiter.NewTargetWithName]
//
// Retries are performed for certain server errors (for example, HTTP 500) on
// endpoints that have been explicitly marked as retryable, up to 3 times with
// exponential backoff.
//
// If the client does not require rate limiting, use [TelemetryClientTransport]
// instead, which only applies telemetry.
func ClientTransport(base http.RoundTripper, obsv observability.Exporters, limiter limiter.RateLimiter, target sweagentd.ClientTarget, clientName string) *ClientRoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}

	ratelimitTransport := ratelimits.NewRoundTripper(base, limiter, target)
	telemetryTransport := observability.NewTelemetryRoundTripper(ratelimitTransport, obsv, clientName)

	return &ClientRoundTripper{
		base: newRetryingTransport(telemetryTransport),
		obsv: obsv,
	}
}

// TelemetryClientTransport is used by clients that do not require rate limiting.
// Prefer using [ClientTransport] instead.
func TelemetryClientTransport(base http.RoundTripper, obsv observability.Exporters) *ClientRoundTripper {
	if base == nil {
		base = http.DefaultTransport
	}

	telemetryTransport := observability.NewTelemetryRoundTripper(base, obsv, "github-norate")

	return &ClientRoundTripper{
		base: newRetryingTransport(telemetryTransport),
		obsv: obsv,
	}
}

type retryableEndpointCtxKey struct{}

func withRetryableEndpoint(ctx context.Context) context.Context {
	return context.WithValue(ctx, retryableEndpointCtxKey{}, struct{}{})
}

func isRetryableEndpoint(ctx context.Context) bool {
	return ctx.Value(retryableEndpointCtxKey{}) != nil
}

func isRetryableError(ctx context.Context, resp *http.Response, err error) (bool, error) {
	return resp != nil && isRetryableEndpoint(ctx) && resp.StatusCode == http.StatusInternalServerError, nil
}

// RoundTrip implements the http.RoundTripper interface.
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
			return nil, goerrors.Errorf("failed to replace tenant placeholder in URL: %w", err)
		}

		if modifiedURL != originalURL {
			// Parse the modified URL and update the request
			newURL, err := url.Parse(modifiedURL)
			if err == nil {
				req.URL = newURL
				// Update the Host header to match the new URL host to avoid HTTP/2 validation errors
				req.Host = newURL.Host
			}
		}
	}

	return h.base.RoundTrip(req)
}
