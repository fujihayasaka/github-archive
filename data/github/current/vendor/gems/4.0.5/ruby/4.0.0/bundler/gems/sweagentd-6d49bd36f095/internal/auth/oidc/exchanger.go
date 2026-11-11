package oidc

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/go-stats"

	"github.com/github/sweagentd/internal/auth/oidc/oidcconfig"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
)

const (
	// clientAssertionTypeJWTBearer is the assertion type for JWT bearer assertion used in the client credentials flow with federated identity.
	clientAssertionTypeJWTBearer = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer" //nolint:gosec // Not a credential; OAuth 2.0 assertion type URI.

	// RFC 8693 token type identifiers.
	tokenTypeIDToken     = "urn:ietf:params:oauth:token-type:id_token"     //nolint:gosec // Not a credential; RFC 8693 token type URI.
	tokenTypeAccessToken = "urn:ietf:params:oauth:token-type:access_token" //nolint:gosec // Not a credential; RFC 8693 token type URI.
)

// exchangeErrorResponse represents an OAuth 2.0 error response from a token exchange endpoint.
type exchangeErrorResponse struct {
	Error            string `json:"error"`
	ErrorDescription string `json:"error_description"`
}

// Exchanger performs various forms of token exchanges against integrator endpoints.
type Exchanger struct {
	httpClient *http.Client
	obsv       observability.Exporters
}

// NewExchanger creates an Exchanger with the given HTTP client and observability exporters.
func NewExchanger(httpClient *http.Client, obsv observability.Exporters) *Exchanger {
	return &Exchanger{
		httpClient: httpClient,
		obsv:       obsv,
	}
}

// ExchangeIDToken performs an RFC 8693 token exchange, sending the OIDC ID token to the
// integrator's exchange endpoint and returning the access token on success.
// The optional scope and resource parameters are included as form fields when non-empty.
// The clientID identifies the agentic GitHub app making the request.
func (e *Exchanger) ExchangeIDToken(ctx context.Context, endpoint, audience, jwt, scope, resource, clientID string) (*ExchangeResponse, error) {
	start := time.Now()

	form := url.Values{
		"grant_type":           {oidcconfig.GrantTypeTokenExchange},
		"subject_token":        {jwt},
		"subject_token_type":   {tokenTypeIDToken},
		"requested_token_type": {tokenTypeAccessToken},
		"audience":             {audience},
	}

	if clientID != "" {
		form.Set("client_id", clientID)
	}
	if scope != "" {
		form.Set("scope", scope)
	}
	if resource != "" {
		form.Set("resource", resource)
	}

	return e.doExchange(ctx, endpoint, form, start)
}

// ExchangeClientCredentials performs an OAuth 2.0 client credentials exchange
// using the OIDC ID token as a client assertion (JWT bearer). This is the flow
// used by Azure AD workload identity federation.
func (e *Exchanger) ExchangeClientCredentials(ctx context.Context, endpoint, jwt, scope, clientID string) (*ExchangeResponse, error) {
	start := time.Now()

	form := url.Values{
		"grant_type":            {oidcconfig.GrantTypeClientCredentials},
		"client_assertion_type": {clientAssertionTypeJWTBearer},
		"client_assertion":      {jwt},
		"client_id":             {clientID},
	}

	if scope != "" {
		form.Set("scope", scope)
	}

	return e.doExchange(ctx, endpoint, form, start)
}

// ExchangeJWTBearer performs an RFC 7523 JWT Bearer grant exchange, sending
// the OIDC ID token as an assertion to the token endpoint. This is the flow
// used for workload identity federation (SEP-1933) where platform-issued JWTs
// are presented directly as authorization grants.
func (e *Exchanger) ExchangeJWTBearer(ctx context.Context, endpoint, audience, jwt, scope, resource string) (*ExchangeResponse, error) {
	start := time.Now()

	form := url.Values{
		"grant_type":           {oidcconfig.GrantTypeJWTBearer},
		"assertion":            {jwt},
		"requested_token_type": {tokenTypeAccessToken},
		"audience":             {audience},
	}

	if scope != "" {
		form.Set("scope", scope)
	}
	if resource != "" {
		form.Set("resource", resource)
	}

	return e.doExchange(ctx, endpoint, form, start)
}

// doExchange sends a form-encoded POST to the token endpoint and returns the
// parsed ExchangeResponse. It handles error responses, metrics, and validation
// of the access token in the response.
func (e *Exchanger) doExchange(ctx context.Context, endpoint string, form url.Values, start time.Time) (*ExchangeResponse, error) {
	ep, err := sanitizeURL(endpoint)
	if err != nil {
		return nil, goerrors.Errorf("%w: invalid token endpoint URL: %w", ErrInvalidURL, err)
	}

	grantType := form.Get("grant_type")
	ctx, span := e.obsv.Tracer.Start(ctx, "oidc.Exchanger.doExchange")
	defer span.End()
	span.SetAttributes(
		attribute.String("oidc.exchange.host", ep.Host),
		attribute.String("oidc.exchange.grant_type", grantType),
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, ep.String(), strings.NewReader(form.Encode()))
	if err != nil {
		return nil, goerrors.Errorf("%w: failed to create request: %w", ErrTokenExchangeFailed, err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")

	resp, err := e.httpClient.Do(req) //nolint:gosec // URL is sanitized before use.
	if err != nil {
		e.recordExchangeMetrics(ctx, "error", time.Since(start))
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return nil, goerrors.Errorf("%w: request failed: %w", ErrNetworkError, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		e.recordExchangeMetrics(ctx, "error", time.Since(start))
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return nil, goerrors.Errorf("%w: failed to read response body: %w", ErrNetworkError, err)
	}

	span.SetAttributes(attribute.Int("oidc.exchange.http_status", resp.StatusCode))

	if resp.StatusCode != http.StatusOK {
		exchangeErr := e.handleExchangeError(ctx, resp.StatusCode, body, time.Since(start))
		span.RecordError(exchangeErr)
		span.SetStatus(codes.Error, exchangeErr.Error())
		return nil, exchangeErr
	}

	var exchangeResp ExchangeResponse
	err = json.Unmarshal(body, &exchangeResp)
	if err != nil {
		e.recordExchangeMetrics(ctx, "error", time.Since(start))
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return nil, goerrors.Errorf("%w: failed to parse response: %w", ErrIDPError, err)
	}

	if exchangeResp.AccessToken == "" {
		e.recordExchangeMetrics(ctx, "error", time.Since(start))
		missingErr := goerrors.Errorf("%w: response missing access_token", ErrIDPError)
		span.RecordError(missingErr)
		span.SetStatus(codes.Error, missingErr.Error())
		return nil, missingErr
	}

	e.recordExchangeMetrics(ctx, "success", time.Since(start))
	return &exchangeResp, nil
}

func (e *Exchanger) handleExchangeError(ctx context.Context, statusCode int, body []byte, duration time.Duration) error {
	var errResp exchangeErrorResponse
	_ = json.Unmarshal(body, &errResp)

	if errResp.Error == "authorization_required" {
		e.recordExchangeMetrics(ctx, "authorization_required", duration)
		return goerrors.Errorf("%w: %s", ErrAuthorizationRequired, errResp.ErrorDescription)
	}

	if errResp.Error == "unsupported_grant_type" {
		e.recordExchangeMetrics(ctx, "unsupported_grant_type", duration)
		return goerrors.Errorf("%w: %s", ErrUnsupportedGrantType, errResp.ErrorDescription)
	}

	if errResp.Error == "invalid_grant" {
		e.recordExchangeMetrics(ctx, "invalid_grant", duration)
		return goerrors.Errorf("%w: %s", ErrInvalidGrant, errResp.ErrorDescription)
	}

	e.recordExchangeMetrics(ctx, "error", duration)

	if errResp.ErrorDescription != "" {
		return goerrors.Errorf("%w: %s: %s (HTTP %d)", ErrIDPError, errResp.Error, errResp.ErrorDescription, statusCode)
	}
	// We should not log body here given we're interacting with potentially sensitive information.
	return goerrors.Errorf("%w: HTTP %d", ErrIDPError, statusCode)
}

func (e *Exchanger) recordExchangeMetrics(ctx context.Context, status string, duration time.Duration) {
	tags := stats.Tags{"status": status}
	e.obsv.Increment(ctx, "oidc.token_exchange.count", tags)
	e.obsv.DistributionMs(ctx, "oidc.token_exchange.latency_ms", tags, duration)
}
