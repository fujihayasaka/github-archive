package oidc

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/go-stats"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
)

// Revoker calls integrator revocation endpoints to invalidate 3rd party access tokens.
type Revoker struct {
	httpClient *http.Client
	obsv       observability.Exporters
}

// NewRevoker creates a Revoker with the given HTTP client and observability exporters.
func NewRevoker(httpClient *http.Client, obsv observability.Exporters) *Revoker {
	return &Revoker{
		httpClient: httpClient,
		obsv:       obsv,
	}
}

// RevokeToken sends a revocation request to the integrator endpoint. Both the original
// OIDC ID token and the exchanged access token are included so the integrator can verify
// the caller and identify which token to revoke. The clientID identifies the agentic
// GitHub app making the request.
func (r *Revoker) RevokeToken(ctx context.Context, endpoint, idToken, accessToken, clientID string) error {
	start := time.Now()

	form := url.Values{
		"token":           {accessToken},
		"token_type_hint": {"access_token"},
		// Subject token is technically optional, but recommended by RFC
		"subject_token":      {idToken},
		"subject_token_type": {tokenTypeIDToken},
	}

	if clientID != "" {
		form.Set("client_id", clientID)
	}

	url, err := sanitizeURL(endpoint)
	if err != nil {
		return goerrors.Errorf("%w: invalid revocation endpoint URL: %w", ErrInvalidURL, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url.String(), strings.NewReader(form.Encode()))
	if err != nil {
		return goerrors.Errorf("%w: failed to create request: %w", ErrTokenRevocationFailed, err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := r.httpClient.Do(req) //nolint:gosec // URL is sanitized before use.
	if err != nil {
		r.recordRevocationMetrics(ctx, "error", time.Since(start))
		return goerrors.Errorf("%w: request failed: %w", ErrNetworkError, err)
	}
	defer resp.Body.Close()

	// Per RFC 7009, the server responds with 200 on success. A 200 response even for
	// invalid tokens is acceptable (the server simply ignores unknown tokens).
	if resp.StatusCode != http.StatusOK {
		r.recordRevocationMetrics(ctx, "error", time.Since(start))
		// We should not log body here given we're interacting with potentially sensitive information.
		return goerrors.Errorf("%w: HTTP %d", ErrTokenRevocationFailed, resp.StatusCode)
	}

	r.recordRevocationMetrics(ctx, "success", time.Since(start))
	return nil
}

func (r *Revoker) recordRevocationMetrics(ctx context.Context, status string, duration time.Duration) {
	tags := stats.Tags{"status": status}
	r.obsv.Increment(ctx, "oidc.token_revocation.count", tags)
	r.obsv.DistributionMs(ctx, "oidc.token_revocation.latency_ms", tags, duration)
}
