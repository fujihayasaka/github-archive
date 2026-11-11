// Package capi provides a client for interacting with the GitHub Copilot API.
// It includes HTTP transports for HMAC authentication and user authentication,
// as well as clients for chat completions and session management.
package capi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/hashicorp/go-retryablehttp"
	"github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"go.opentelemetry.io/otel/attribute"
)

// HTTP headers used for GitHub Copilot API requests
const (
	GitHubUserIDHeader     = "X-GitHub-User"
	IntegrationIDHeader    = "Copilot-Integration-Id"
	InteractionIDHeader    = "X-Interaction-Id"
	GitHubAPIVersionHeader = "X-GitHub-Api-Version"
	GitHubAPIVersionValue  = "2025-05-01"
	InteractionTypeHeader  = "X-Interaction-Type"
	InteractionTypeValue   = "conversation-agent"
	InitiatorHeader        = "X-Initiator"

	// Maximum number of retries for rate-limited ChatCompletions requests
	maxRetries = 3
)

var (
	// DefaultSessionTimeout is the default timeout for session client HTTP requests.
	// This is a variable to allow tests to override it.
	DefaultSessionTimeout = 10 * time.Second
)

type baseTransport struct {
	RoundTripper  http.RoundTripper
	integrationID string
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
			return nil, fmt.Errorf("failed to replace tenant placeholder in URL: %w", err)
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

	req.Header.Add(IntegrationIDHeader, ct.integrationID)
	req.Header.Add(GitHubAPIVersionHeader, GitHubAPIVersionValue)
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
	NewSessionClient(userID int64, token string) SessionClient
	ChatCompletions(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error)
}

var _ Client = &HmacClient{}

// HmacClient is a client that uses HMAC authentication for GitHub Copilot API requests.
type HmacClient struct {
	obsv          observability.Exporters
	oai           openai.Client
	baseURL       url.URL
	baseTransport baseTransport
	integrationID string
}

// UserClient is a client that uses user token authentication for GitHub Copilot API requests.
type UserClient struct {
	obsv    observability.Exporters
	http    *http.Client
	baseURL url.URL
	userID  int64
}

// NewClient creates a new HMAC-authenticated client for the GitHub Copilot API.
func NewClient(obsv observability.Exporters, baseURL, integrationID, hmacSecret string) (*HmacClient, error) {
	bt := &baseTransport{
		RoundTripper:  observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, "capi"),
		integrationID: integrationID,
	}
	tr := &HmacTransport{
		base:       *bt,
		hmacSecret: hmacSecret,
	}

	u, err := url.Parse(baseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to parse baseURL: %w", err)
	}
	if u.Path != "" && !strings.HasSuffix(u.Path, "/") {
		u.Path += "/"
	}

	httpClient := &http.Client{
		Transport: tr,
	}

	oai := openai.NewClient(
		option.WithBaseURL(baseURL),
		option.WithHTTPClient(httpClient),
		option.WithHeader(GitHubAPIVersionHeader, GitHubAPIVersionValue),
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
	}, nil
}

// sessionErrorHandler provides detailed error information when session API requests fail after exhausting retries.
func sessionErrorHandler(resp *http.Response, err error, numTries int) (*http.Response, error) {
	// If we have a response, try to extract useful information from it
	if resp != nil {
		statusCode := resp.StatusCode
		var bodyContent string

		if resp.Body != nil {
			body, readErr := io.ReadAll(resp.Body)
			_ = resp.Body.Close() // Ensure the stream gets closed per retryablehttp documentation
			if readErr == nil && len(body) > 0 {
				bodyContent = string(body)
			}
		}

		body := fmt.Sprintf("session API request failed after %d attempts", numTries)
		if bodyContent != "" {
			body += fmt.Sprintf(": %s", bodyContent)
		}

		return resp, &joberrors.SessionResponseError{
			StatusCode: statusCode,
			Body:       body,
		}
	}

	// If we don't have a response, this is likely a network error
	if err != nil {
		return resp, fmt.Errorf("session API request failed after %d attempts due to network error: %w", numTries, err)
	}

	// Fallback case (shouldn't happen in practice)
	return resp, fmt.Errorf("session API request failed after %d attempts (unknown error)", numTries)
}

// NewSessionClient creates a new session client with user authentication.
func (c *HmacClient) NewSessionClient(userID int64, token string) SessionClient {
	ut := &UserTransport{
		base:  c.baseTransport,
		token: token,
	}
	httpClient := &http.Client{
		Transport: ut,
		Timeout:   DefaultSessionTimeout,
	}

	retryableClient := retryablehttp.NewClient()
	retryableClient.HTTPClient = httpClient
	retryableClient.ErrorHandler = sessionErrorHandler
	retryableClient.CheckRetry = func(ctx context.Context, resp *http.Response, err error) (bool, error) {
		// There's some intermittent 401 errors that are returning.  It's possible that this is actually a race
		// condition with valid tokens not being propagated (the error is that the provided token doesn't exist).
		// Therefore, we retry on 401 errors too.
		if err == nil && resp.StatusCode == http.StatusUnauthorized {
			return true, nil
		}

		// There are few scenarios resulting in 404 responses that are worth retrying:
		// 1. Due to consistency configuration for sessions (in Cosmos DB), we can get 404 responses when the session
		//	was newly created. Retry on client side to cope with latency https://github.com/github/sweagentd/issues/3024
		// 2. Session is immediately created after pull request creation, the PUT session API checks pull request existence
		//	and returns 404 if the pull request is not found.
		if err == nil && resp.StatusCode == http.StatusNotFound {
			return true, nil
		}

		return retryablehttp.DefaultRetryPolicy(ctx, resp, err)
	}

	return &UserClient{
		obsv:    c.obsv,
		http:    retryableClient.StandardClient(),
		baseURL: c.baseURL,
		userID:  userID,
	}
}

// ChatCompletions sends a chat completion request to the GitHub Copilot API.
func (c *HmacClient) ChatCompletions(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
	return c.chatCompletionsWithRetry(ctx, userID, interactionID, body, 0)
}

func (c *HmacClient) chatCompletionsWithRetry(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams, retryCount int) (*openai.ChatCompletion, error) {
	// Check if we have exceeded the maximum number of retries
	if retryCount >= maxRetries {
		return nil, fmt.Errorf("exceeded maximum number of retries (%d) for rate-limited requests", maxRetries)
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
	if err != nil {
		if httpResp != nil && httpResp.StatusCode == http.StatusTooManyRequests {
			// Retry-After header is set, so we can use that to retry
			ra := httpResp.Header.Get("Retry-After") // in seconds as a string
			if ra == "" {
				return nil, errors.New("retry-after header not set")
			}

			raInt, err := strconv.Atoi(ra)
			if err != nil {
				return nil, fmt.Errorf("failed to parse retry-after header: %w", err)
			}
			t := time.Now().Add(time.Duration(raInt) * time.Second)
			sleepTill := time.Until(t)
			if sleepTill > 0 {
				time.Sleep(sleepTill)
				return c.chatCompletionsWithRetry(ctx, userID, interactionID, body, retryCount+1)
			}
			return nil, err
		}

		c.obsv.Logger.WithContext(ctx).WithError(err).Error("failed to get chat completions")
		return nil, err
	}
	return res, nil
}
