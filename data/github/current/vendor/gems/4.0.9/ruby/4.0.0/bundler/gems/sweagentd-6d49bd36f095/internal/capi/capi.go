// Package capi provides a client for interacting with the GitHub Copilot API.
// It includes HTTP transports for HMAC authentication and user authentication,
// as well as clients for chat completions and session management.
package capi

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"go.opentelemetry.io/otel/attribute"
)

// HTTP headers used for GitHub Copilot API requests
const (
	GitHubUserIDHeader            = "X-GitHub-User"
	GitHubActorTypeHeader         = "X-GitHub-Actor-Type"
	IntegrationIDHeader           = "Copilot-Integration-Id"
	InteractionIDHeader           = "X-Interaction-Id"
	GitHubAPIVersionHeader        = "X-GitHub-Api-Version"
	GitHubAPIVersionValue         = "2025-05-01"
	GitHubAPIVersionValue20260109 = "2026-01-09"
	InteractionTypeHeader         = "X-Interaction-Type"
	InteractionTypeValue          = "conversation-agent"
	InitiatorHeader               = "X-Initiator"

	// Maximum number of retries for rate-limited ChatCompletions requests
	maxRetries = 3
)

const (
	// DefaultSessionMaxRetries is the default maximum number of retries for
	// session client retries.
	DefaultSessionMaxRetries = 3
	// DefaultSessionMaxElapsedTime is the default maximum elapsed time for
	// session client retries.
	DefaultSessionMaxElapsedTime = 20 * time.Second
)

var (
	// DefaultClientTimeout is the default timeout for client HTTP requests.
	// This is a variable to allow tests to override it.
	DefaultClientTimeout = 10 * time.Second
	// ChatCompletionsTimeout is the timeout for ChatCompletions requests to CAPI which
	// takes the retry logic into account.
	// This is a variable to allow tests to override it.
	ChatCompletionsTimeout = 30 * time.Second
)

// integrationIDOverrideKey is the context key for carrying a per-request
// Copilot-Integration-Id override so that CAPI /models calls can identify
// the specific agent integration (e.g. claude-code-cloud, codex-cloud).
type integrationIDOverrideKey struct{}

// ContextWithCAPIIntegrationID returns a copy of ctx that carries the given
// Copilot-Integration-Id override. When present, listModels will set this
// as the request's Copilot-Integration-Id header instead of the default.
func ContextWithCAPIIntegrationID(ctx context.Context, integrationID string) context.Context {
	return context.WithValue(ctx, integrationIDOverrideKey{}, integrationID)
}

// IntegrationIDFromContext extracts the Copilot-Integration-Id override
// previously stored with ContextWithCAPIIntegrationID. Returns an empty
// string when no value is present.
func IntegrationIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(integrationIDOverrideKey{}).(string)
	return v
}

type baseTransport struct {
	RoundTripper  http.RoundTripper
	integrationID string
	ffs           featureflags.Client
}

func (ct *baseTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	slug := requestctx.TenantSlug(req.Context())
	if slug != "" {
		req.Header.Set(requestctx.GitHubTenantHeader, slug)
		req.Header.Set(requestctx.GitHubTenantIDHeader, requestctx.TenantID(req.Context()))
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

	// Set the default integration ID unless the caller has already set an
	// agent-specific override (e.g. for /models calls).
	if req.Header.Get(IntegrationIDHeader) == "" {
		req.Header.Set(IntegrationIDHeader, ct.integrationID)
	}

	apiVersion := GitHubAPIVersionValue
	if userIDStr := req.Header.Get(GitHubUserIDHeader); userIDStr != "" {
		uid, err := strconv.ParseInt(userIDStr, 10, 64)
		if err == nil && ct.ffs.IsEnabledForUser(req.Context(), featureflags.CodingAgentCAPIVersion20260109, uid) {
			apiVersion = GitHubAPIVersionValue20260109
		}
	}
	req.Header.Add(GitHubAPIVersionHeader, apiVersion)
	githubRequestID := requestid.GetGitHubRequestID(req.Context())
	if githubRequestID != "" {
		req.Header.Set(headers.GitHubRequestID, githubRequestID)
	}

	return ct.RoundTripper.RoundTrip(req)
}

// HmacTransport is an HTTP transport that adds HMAC authentication headers to requests.
type HmacTransport struct {
	base       baseTransport
	hmacSecret string
}

// RoundTrip implements the http.RoundTripper interface, adding HMAC authentication.
func (ct *HmacTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req.Header.Add(hmac.RequestHeader, hmac.NewRequestHMAC(ct.hmacSecret).String())
	return ct.base.RoundTrip(req)
}

// UserTransport is an HTTP transport that adds user authentication headers to requests.
type UserTransport struct {
	base  baseTransport
	token string
}

// RoundTrip implements the http.RoundTripper interface, adding user authentication.
func (ct *UserTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", ct.token))
	return ct.base.RoundTrip(req)
}

// Client provides methods for interacting with the GitHub Copilot API.
type Client interface {
	NewSessionClient(userID int64, token string, config SessionClientConfig) SessionClient
	ChatCompletions(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error)
	ListCodingAgentModels(ctx context.Context, userID uint64, actorType string) ([]Model, error)
	CreateModelSession(ctx context.Context, userID uint64, modelHints []string, existingToken string) (*ModelSessionResponse, error)
	CreateModelSessionIntent(ctx context.Context, userID uint64, sessionToken string, intentReq ModelSessionIntentRequest) (*ModelSessionIntentResponse, error)
}

var _ Client = &HmacClient{}

// HmacClient is a client that uses HMAC authentication for GitHub Copilot API requests.
type HmacClient struct {
	obsv          observability.Exporters
	oai           openai.Client
	baseURL       url.URL
	baseTransport baseTransport
	integrationID string
	http          *http.Client
}

// UserClient is a client that uses user token authentication for GitHub Copilot API requests.
type UserClient struct {
	obsv    observability.Exporters
	http    *http.Client
	baseURL url.URL
	userID  int64
	config  SessionClientConfig
}

// NewClient creates a new HMAC-authenticated client for the GitHub Copilot API.
func NewClient(obsv observability.Exporters, baseURL, integrationID, hmacSecret string, ffs featureflags.Client) (*HmacClient, error) {
	capiTagsFn := observability.MetricTagsFn(func(req *http.Request) stats.Tags {
		if !ffs.IsEnabled(req.Context(), featureflags.CodingAgentAPIMetricTags) {
			return nil
		}
		return stats.Tags{"api_target": "internal_capi"}
	})
	bt := &baseTransport{
		RoundTripper:  observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, "capi", capiTagsFn),
		integrationID: integrationID,
		ffs:           ffs,
	}
	tr := &HmacTransport{
		base:       *bt,
		hmacSecret: hmacSecret,
	}

	u, err := url.Parse(baseURL)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse baseURL: %w", err)
	}
	if u.Path != "" && !strings.HasSuffix(u.Path, "/") {
		u.Path += "/"
	}

	httpClient := &http.Client{
		Transport: tr,
		Timeout:   DefaultClientTimeout,
	}

	oai := openai.NewClient(
		option.WithBaseURL(baseURL),
		option.WithHTTPClient(httpClient),
		// OpenAI's retry logic doesn't seem to work with CAPI's retry-after header
		option.WithMaxRetries(0),
		// These headers tell CAPI that this is a conversation agent interaction
		// and to rate-limit it according to agent behaviors.
		option.WithHeader(InteractionTypeHeader, InteractionTypeValue),
		option.WithHeader("Openai-Intent", InteractionTypeValue),
		// This header is used to bill the request according to the right multiplier.
		// We should mostly bill requests originated from the sweagentd runtime.
		// Use agent here to not bill the request originated from the sweagentd service by default.
		option.WithHeader(InitiatorHeader, "agent"),
	)

	return &HmacClient{
		obsv:          obsv,
		oai:           oai,
		baseURL:       *u,
		baseTransport: *bt,
		integrationID: integrationID,
		http:          httpClient,
	}, nil
}

// NewSessionClient creates a new session client with user authentication.
func (c *HmacClient) NewSessionClient(userID int64, token string, config SessionClientConfig) SessionClient {
	return c.newSessionClient(userID, token, config)
}

// ChatCompletions sends a chat completion request to the GitHub Copilot API.
func (c *HmacClient) ChatCompletions(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
	// This operation is known to potentially take a long time due to retries on rate limiting.
	// We need to make sure we don't wait indefinitely, so we set an additional timeout here.
	ctx, cancel := context.WithTimeout(ctx, ChatCompletionsTimeout)
	defer cancel()
	return c.chatCompletionsWithRetry(ctx, userID, interactionID, body, 0)
}

// newSessionClient creates a new session client with user authentication.
func (c *HmacClient) newSessionClient(userID int64, token string, config SessionClientConfig) SessionClient {
	ut := &UserTransport{
		base:  c.baseTransport,
		token: token,
	}
	httpClient := &http.Client{
		Transport: ut,
		Timeout:   DefaultClientTimeout,
	}

	return &UserClient{
		obsv:    c.obsv,
		http:    httpClient,
		baseURL: c.baseURL,
		userID:  userID,
		config:  config,
	}
}

func (c *HmacClient) chatCompletionsWithRetry(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams, retryCount int) (*openai.ChatCompletion, error) {
	// Check if we have exceeded the maximum number of retries
	if retryCount >= maxRetries {
		return nil, goerrors.Errorf("exceeded maximum number of retries (%d) for rate-limited requests", maxRetries)
	}

	ctx, span := c.obsv.Tracer.Start(ctx, "capi.ChatCompletions")
	span.SetAttributes(attribute.String("gh.capi.model", body.Model))
	defer span.End()

	var httpResp *http.Response
	options := []option.RequestOption{
		option.WithHeader(GitHubUserIDHeader, userID),
		option.WithHeader(InteractionIDHeader, interactionID),
		option.WithResponseInto(&httpResp),
	}

	res, err := c.oai.Chat.Completions.New(ctx, *body, options...)
	if err != nil && httpResp != nil && httpResp.StatusCode == http.StatusTooManyRequests {
		// Retry-After header is set, so we can use that to retry
		ra := httpResp.Header.Get("Retry-After") // in seconds as a string
		if ra == "" {
			return nil, goerrors.New("retry-after header not set")
		}

		raInt, err := strconv.Atoi(ra)
		if err != nil {
			return nil, goerrors.Errorf("failed to parse retry-after header: %w", err)
		}

		span.SetAttributes(attribute.Int("gh.capi.retry_after_seconds", raInt))

		t := time.Now().Add(time.Duration(raInt) * time.Second)
		sleepTill := time.Until(t)

		// If the retry-after duration exceeds the remaining context deadline,
		// don't bother waiting — we'd just get cancelled anyway.
		if deadline, ok := ctx.Deadline(); ok && deadline.Before(t) {
			return nil, goerrors.Errorf("rate limited: retry-after duration (%ds) exceeds remaining context deadline", raInt)
		}

		if sleepTill > 0 {
			// Respect context cancellation during sleep
			timer := time.NewTimer(sleepTill)
			defer timer.Stop()
			select {
			case <-timer.C:
				// Timer expired, proceed with retry
				return c.chatCompletionsWithRetry(ctx, userID, interactionID, body, retryCount+1)
			case <-ctx.Done():
				// Context was cancelled during sleep
				return nil, goerrors.Errorf("context cancelled during retry wait: %w", ctx.Err())
			}
		}
		return nil, err
	} else if err != nil {
		c.obsv.Logger.WithContext(ctx).WithError(err).Error("failed to get chat completions")
		return nil, err
	}

	return res, nil
}
