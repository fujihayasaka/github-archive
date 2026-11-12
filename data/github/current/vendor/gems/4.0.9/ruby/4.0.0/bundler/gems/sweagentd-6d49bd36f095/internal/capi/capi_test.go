package capi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/github/go-auth/hmac"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

func TestCapiClient(t *testing.T) {
	obsv := observability.NewNoopExporters()
	integrationID := "integration-id"

	t.Run("includes required headers", func(t *testing.T) {
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.NotEmpty(t, r.Header.Get(hmac.RequestHeader))
			require.Equal(t, "1", r.Header.Get(GitHubUserIDHeader))
			require.Equal(t, integrationID, r.Header.Get(IntegrationIDHeader))
			require.Equal(t, GitHubAPIVersionValue, r.Header.Get(GitHubAPIVersionHeader))
			require.Equal(t, "agent", r.Header.Get(InitiatorHeader))

			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			b := &openai.ChatCompletion{
				ID: "noop",
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{},
					},
				},
			}
			err := json.NewEncoder(w).Encode(b)
			require.NoError(t, err)
		}))
		defer svr.Close()

		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)
		_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
			Messages: []openai.ChatCompletionMessageParamUnion{
				openai.UserMessage("Hello, CAPI!"),
			},
		})
		require.NoError(t, err)
	})

	t.Run("sends 2026-01-09 API version when feature flag is enabled", func(t *testing.T) {
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, GitHubAPIVersionValue20260109, r.Header.Get(GitHubAPIVersionHeader))

			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			err := json.NewEncoder(w).Encode(&openai.ChatCompletion{
				ID:      "noop",
				Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{}}},
			})
			require.NoError(t, err)
		}))
		defer svr.Close()

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentCAPIVersion20260109: true,
		})
		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", ffClient)
		require.NoError(t, err)
		_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
		})
		require.NoError(t, err)
	})

	t.Run("sends old API version when feature flag is disabled", func(t *testing.T) {
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, GitHubAPIVersionValue, r.Header.Get(GitHubAPIVersionHeader))

			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			err := json.NewEncoder(w).Encode(&openai.ChatCompletion{
				ID:      "noop",
				Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{}}},
			})
			require.NoError(t, err)
		}))
		defer svr.Close()

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentCAPIVersion20260109: false,
		})
		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", ffClient)
		require.NoError(t, err)
		_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
		})
		require.NoError(t, err)
	})

	t.Run("retry succeeds after 429", func(t *testing.T) {
		requestCount := 0
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestCount++
			if requestCount == 1 {
				// First request returns 429 with a short retry delay
				w.Header().Add("Retry-After", "1")
				w.WriteHeader(http.StatusTooManyRequests)
				return
			}
			// Second request succeeds
			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			b := &openai.ChatCompletion{
				ID: "retry-success",
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{
							Content: "Hello from retry!",
						},
					},
				},
			}
			err := json.NewEncoder(w).Encode(b)
			require.NoError(t, err)
		}))
		defer svr.Close()

		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)
		res, err := capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
			Messages: []openai.ChatCompletionMessageParamUnion{
				openai.UserMessage("Testing retry success"),
			},
		})

		require.NoError(t, err)
		require.Equal(t, "retry-success", res.ID)
		require.Equal(t, "Hello from retry!", res.Choices[0].Message.Content)
		require.Equal(t, 2, requestCount, "Should have made exactly two requests (429 + success)")
	})

	t.Run("rate limit retries are limited", func(t *testing.T) {
		retryCount := 0
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			retryCount++
			// Return 429 for all requests to ensure we hit the retry limit
			w.Header().Add("Retry-After", "1") // Set a small retry delay for the test
			w.WriteHeader(http.StatusTooManyRequests)
		}))
		defer svr.Close()

		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)
		_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
			Messages: []openai.ChatCompletionMessageParamUnion{
				openai.UserMessage("Testing rate limit retries"),
			},
		})

		// Should fail after the maximum number of retries
		require.Error(t, err)
		require.Contains(t, err.Error(), "exceeded maximum number of retries")
		require.Equal(t, 3, retryCount, "Should have attempted 3 requests (no retry + 2 retries) before failing")
	})

	t.Run("context cancellation during retry wait is respected", func(t *testing.T) {
		requestCount := 0
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requestCount++
			// Return 429 with a retry delay
			w.Header().Add("Retry-After", "5") // 5 seconds retry delay
			w.WriteHeader(http.StatusTooManyRequests)
		}))
		defer svr.Close()

		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)

		// Create a context that we'll cancel during the retry wait
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()

		// Start a goroutine to cancel the context after a short delay
		// This ensures the first request completes and enters retry wait,
		// then we cancel before the 5-second retry delay expires
		go func() {
			time.Sleep(100 * time.Millisecond) // Give time for first request to complete
			cancel()
		}()

		_, err = capiClient.ChatCompletions(ctx, "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
			Messages: []openai.ChatCompletionMessageParamUnion{
				openai.UserMessage("Testing context cancellation"),
			},
		})

		// Should fail with context cancellation error
		require.Error(t, err)
		require.Contains(t, err.Error(), "context cancelled during retry wait")
		require.Equal(t, 1, requestCount, "Should have made exactly one request before context was cancelled")
	})

	t.Run("includes tenant headers when tenant context is present", func(t *testing.T) {
		tenantID := "tenant-id"
		tenantSlug := "tenant"
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, tenantID, r.Header.Get(requestctx.GitHubTenantIDHeader))
			require.Equal(t, tenantSlug, r.Header.Get(requestctx.GitHubTenantHeader))

			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			b := &openai.ChatCompletion{
				ID: "noop",
				Choices: []openai.ChatCompletionChoice{
					{
						Message: openai.ChatCompletionMessage{},
					},
				},
			}
			err := json.NewEncoder(w).Encode(b)
			require.NoError(t, err)
		}))
		defer svr.Close()

		capiClient, err := NewClient(obsv, svr.URL, integrationID, "hmac-secret", featureflags.NewNoopClient(nil))
		require.NoError(t, err)
		ctx := context.Background()
		ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
		err = requestctx.AddTenantID(ctx, tenantID)
		require.NoError(t, err)
		err = requestctx.AddTenantSlug(ctx, tenantSlug)
		require.NoError(t, err)
		_, err = capiClient.ChatCompletions(ctx, "1", "", &openai.ChatCompletionNewParams{
			Model: "gpt-4",
			Messages: []openai.ChatCompletionMessageParamUnion{
				openai.UserMessage("Hello, CAPI with tenant!"),
			},
		})
		require.NoError(t, err)
	})
}

func TestBaseTransport_TenantPlaceholderReplacement(t *testing.T) {
	// Create a test server first to get a valid host
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	// Parse server URL to get host and scheme
	serverURL, err := url.Parse(server.URL)
	require.NoError(t, err)

	tests := []struct {
		name         string
		originalURL  string
		tenantSlug   string
		expectedURL  string
		expectedHost string
		expectError  bool
	}{
		{
			name:         "URL with tenant placeholder gets replaced",
			originalURL:  serverURL.Scheme + "://" + serverURL.Host + "/<tenant>/chat/completions",
			tenantSlug:   "test-org",
			expectedURL:  serverURL.Scheme + "://" + serverURL.Host + "/test-org/chat/completions",
			expectedHost: serverURL.Host,
		},
		{
			name:         "URL with encoded tenant placeholder gets replaced",
			originalURL:  serverURL.Scheme + "://" + serverURL.Host + "/%3Ctenant%3E/chat/completions",
			tenantSlug:   "test-org",
			expectedURL:  serverURL.Scheme + "://" + serverURL.Host + "/test-org/chat/completions",
			expectedHost: serverURL.Host,
		},
		{
			name:         "URL without tenant placeholder remains unchanged",
			originalURL:  serverURL.Scheme + "://" + serverURL.Host + "/chat/completions",
			tenantSlug:   "test-org",
			expectedURL:  serverURL.Scheme + "://" + serverURL.Host + "/chat/completions",
			expectedHost: serverURL.Host,
		},
		{
			name:        "URL with tenant placeholder but no tenant in context causes error",
			originalURL: serverURL.Scheme + "://" + serverURL.Host + "/<tenant>/chat/completions",
			tenantSlug:  "",
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create base transport
			bt := &baseTransport{
				RoundTripper:  http.DefaultTransport,
				integrationID: "test-integration",
			}

			// Create request with the original URL
			req, err := http.NewRequest(http.MethodPost, tt.originalURL, http.NoBody)
			require.NoError(t, err)

			// Set up context with tenant slug if provided
			ctx := context.Background()
			if tt.tenantSlug != "" {
				ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
				err = requestctx.AddTenantSlug(ctx, tt.tenantSlug)
				require.NoError(t, err)
			}
			req = req.WithContext(ctx)

			// Execute the round trip
			resp, err := bt.RoundTrip(req)

			if tt.expectError {
				require.Error(t, err)
				require.Contains(t, err.Error(), "failed to replace tenant placeholder in URL")
				return
			}

			require.NoError(t, err)
			require.NotNil(t, resp)

			// Verify the request URL was updated correctly
			require.Equal(t, tt.expectedURL, req.URL.String())
			require.Equal(t, tt.expectedHost, req.Host)

			// Verify integration ID header was added
			require.Equal(t, "test-integration", req.Header.Get(IntegrationIDHeader))
		})
	}
}

func TestBaseTransport_RequestHeaders(t *testing.T) {
	// Create a test server to capture headers
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	bt := &baseTransport{
		RoundTripper:  http.DefaultTransport,
		integrationID: "test-integration-123",
	}

	t.Run("adds required headers without tenant", func(t *testing.T) {
		req, err := http.NewRequest(http.MethodGet, server.URL, http.NoBody)
		require.NoError(t, err)

		_, err = bt.RoundTrip(req)
		require.NoError(t, err)

		// Verify headers
		require.Equal(t, "test-integration-123", req.Header.Get(IntegrationIDHeader))
		require.Equal(t, GitHubAPIVersionValue, req.Header.Get(GitHubAPIVersionHeader))
		require.Empty(t, req.Header.Get(requestctx.GitHubTenantHeader))
		require.Empty(t, req.Header.Get(requestctx.GitHubTenantIDHeader))
	})

	t.Run("adds tenant headers when context has tenant data", func(t *testing.T) {
		req, err := http.NewRequest(http.MethodGet, server.URL, http.NoBody)
		require.NoError(t, err)

		ctx := context.Background()
		ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
		err = requestctx.AddTenantSlug(ctx, "test-tenant")
		require.NoError(t, err)
		err = requestctx.AddTenantID(ctx, "tenant-id-123")
		require.NoError(t, err)

		req = req.WithContext(ctx)

		_, err = bt.RoundTrip(req)
		require.NoError(t, err)

		// Verify tenant headers were added
		require.Equal(t, "test-tenant", req.Header.Get(requestctx.GitHubTenantHeader))
		require.Equal(t, "tenant-id-123", req.Header.Get(requestctx.GitHubTenantIDHeader))
	})
}

func TestDefaultOpenAITimeout(t *testing.T) {
	// Save original timeout and restore after test
	originalTimeout := DefaultClientTimeout
	defer func() { DefaultClientTimeout = originalTimeout }()

	// Set a very short timeout for testing
	DefaultClientTimeout = 10 * time.Millisecond
	// Create a server that delays longer than our timeout
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(100 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	defer svr.Close()

	obsv := observability.NewNoopExporters()
	capiClient, err := NewClient(obsv, svr.URL, "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
		Model: "gpt-4",
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.UserMessage("Testing timeout"),
		},
	})

	// Should fail with a timeout error
	require.Error(t, err)
	isTimeout := os.IsTimeout(err) || errors.Is(err, context.DeadlineExceeded)
	require.True(t, isTimeout, "expected timeout error, got: %v", err)
}

func TestChatCompletionsTimeout(t *testing.T) {
	// Save original timeouts and restore after test
	originalClientTimeout := DefaultClientTimeout
	originalChatCompletionsTimeout := ChatCompletionsTimeout
	defer func() {
		DefaultClientTimeout = originalClientTimeout
		ChatCompletionsTimeout = originalChatCompletionsTimeout
	}()

	// Set client timeout high so we test the ChatCompletions timeout specifically
	DefaultClientTimeout = 1 * time.Second
	// Set ChatCompletions timeout short for testing, but long enough to be stable in CI
	ChatCompletionsTimeout = 200 * time.Millisecond

	// Create a server that returns 429 with a long Retry-After header
	// The ChatCompletions timeout should trigger before the retry wait completes
	requestCount := 0
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		// Return 429 with a retry delay longer than our ChatCompletions timeout
		w.Header().Add("Retry-After", "60") // 60 seconds, much longer than 50ms timeout
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer svr.Close()

	obsv := observability.NewNoopExporters()
	capiClient, err := NewClient(obsv, svr.URL, "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
		Model: "gpt-4",
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.UserMessage("Testing ChatCompletions timeout with long retry-wait"),
		},
	})

	// Should fail fast because the retry-after duration exceeds the ChatCompletionsTimeout deadline
	require.Error(t, err)
	require.Contains(t, err.Error(), "retry-after duration")
	require.Contains(t, err.Error(), "exceeds remaining context deadline")
	require.Equal(t, 1, requestCount, "Should have made exactly one request before timeout")
}

func TestChatCompletionsRetryAfterExceedsDeadlineOnSecondRequest(t *testing.T) {
	// Save original timeouts and restore after test
	originalClientTimeout := DefaultClientTimeout
	originalChatCompletionsTimeout := ChatCompletionsTimeout
	defer func() {
		DefaultClientTimeout = originalClientTimeout
		ChatCompletionsTimeout = originalChatCompletionsTimeout
	}()

	DefaultClientTimeout = 1 * time.Second
	// Enough time for the first retry (1s wait) but not the second (60s wait)
	ChatCompletionsTimeout = 3 * time.Second

	// First request returns 429 with a short Retry-After that fits within the deadline.
	// Second request returns 429 with a long Retry-After that exceeds the deadline.
	requestCount := 0
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		if requestCount == 1 {
			w.Header().Add("Retry-After", "1") // 1 second, fits within 3s deadline
		} else {
			w.Header().Add("Retry-After", "60") // 60 seconds, exceeds remaining deadline
		}
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer svr.Close()

	obsv := observability.NewNoopExporters()
	capiClient, err := NewClient(obsv, svr.URL, "integration-id", "hmac-secret", featureflags.NewNoopClient(nil))
	require.NoError(t, err)

	_, err = capiClient.ChatCompletions(context.Background(), "1", "", &openai.ChatCompletionNewParams{
		Model: "gpt-4",
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.UserMessage("Testing retry-after exceeds deadline on second request"),
		},
	})

	// Should have retried once, then failed fast on the second 429
	require.Error(t, err)
	require.Contains(t, err.Error(), "retry-after duration")
	require.Contains(t, err.Error(), "exceeds remaining context deadline")
	require.Equal(t, 2, requestCount, "Should have made exactly two requests")
}

func TestBaseTransport_MalformedURL(t *testing.T) {
	bt := &baseTransport{
		RoundTripper: roundTripFunc(func(req *http.Request) (*http.Response, error) {
			return &http.Response{
				StatusCode: http.StatusOK,
				Body:       http.NoBody,
				Header:     make(http.Header),
				Request:    req,
			}, nil
		}),
		integrationID: "test-integration",
	}

	t.Run("handles invalid URL after replacement gracefully", func(t *testing.T) {
		// This test simulates a scenario where tenant replacement produces an invalid URL
		// that cannot be parsed. In such cases, the original URL should be preserved.

		// Create a request with a URL that would become invalid after replacement
		req, err := http.NewRequest(http.MethodPost, "https://api.github.com/chat/completions", http.NoBody)
		require.NoError(t, err)

		// Manually set a URL that could cause parsing issues
		// This simulates edge cases where URL parsing might fail
		originalURL := req.URL.String()

		ctx := context.Background()
		ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
		err = requestctx.AddTenantSlug(ctx, "valid-tenant")
		require.NoError(t, err)
		req = req.WithContext(ctx)

		_, err = bt.RoundTrip(req)
		require.NoError(t, err)

		// URL should remain unchanged since it didn't have placeholder
		require.Equal(t, originalURL, req.URL.String())
	})
}
