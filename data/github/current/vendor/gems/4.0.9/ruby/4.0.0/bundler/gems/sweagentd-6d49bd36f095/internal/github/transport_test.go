package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTransportSetsUserAgent(t *testing.T) {
	uaCh := make(chan string, 1)
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		uaCh <- r.Header.Get("User-Agent")
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	target := sweagentd.ClientTargetForApp(0)
	lim := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	rt := ClientTransport(http.DefaultTransport, observability.NewNoopExporters(), lim, target, "github-app", nil)

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, ts.URL+"/test", http.NoBody)
	require.NoError(t, err)

	resp, err := rt.RoundTrip(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, "sweagentd", <-uaCh)
}

func TestTransportRetryBehavior(t *testing.T) {
	tests := []struct {
		name               string
		useRetry           bool
		failuresBeforeOK   int // number of 500s before returning 200; -1 means always fail
		failureStatusCode  int
		expectedCallCount  int32
		expectedStatusCode int
	}{
		{
			name:               "retries on 500 with retryable endpoint",
			useRetry:           true,
			failuresBeforeOK:   1,
			failureStatusCode:  http.StatusInternalServerError,
			expectedCallCount:  2,
			expectedStatusCode: http.StatusOK,
		},
		{
			name:               "no retry on 500 without retryable endpoint",
			useRetry:           false,
			failuresBeforeOK:   -1,
			failureStatusCode:  http.StatusInternalServerError,
			expectedCallCount:  1,
			expectedStatusCode: http.StatusInternalServerError,
		},
		{
			name:               "no retry on non-500 errors",
			useRetry:           true,
			failuresBeforeOK:   -1,
			failureStatusCode:  http.StatusNotFound,
			expectedCallCount:  1,
			expectedStatusCode: http.StatusNotFound,
		},
		{
			name:               "retry eventually succeeds after multiple failures",
			useRetry:           true,
			failuresBeforeOK:   2,
			failureStatusCode:  http.StatusInternalServerError,
			expectedCallCount:  3,
			expectedStatusCode: http.StatusOK,
		},
		{
			name:               "retries on 502 without retryable endpoint",
			useRetry:           false,
			failuresBeforeOK:   1,
			failureStatusCode:  http.StatusBadGateway,
			expectedCallCount:  2,
			expectedStatusCode: http.StatusOK,
		},
		{
			name:               "retries on 502 with retryable endpoint",
			useRetry:           true,
			failuresBeforeOK:   1,
			failureStatusCode:  http.StatusBadGateway,
			expectedCallCount:  2,
			expectedStatusCode: http.StatusOK,
		},
		{
			name:               "retries on 504 without retryable endpoint",
			useRetry:           false,
			failuresBeforeOK:   1,
			failureStatusCode:  http.StatusGatewayTimeout,
			expectedCallCount:  2,
			expectedStatusCode: http.StatusOK,
		},
		{
			name:               "retries on 504 with retryable endpoint",
			useRetry:           true,
			failuresBeforeOK:   1,
			failureStatusCode:  http.StatusGatewayTimeout,
			expectedCallCount:  2,
			expectedStatusCode: http.StatusOK,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var callCount atomic.Int32

			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				count := callCount.Add(1)
				if tc.failuresBeforeOK == -1 || int(count) <= tc.failuresBeforeOK {
					w.WriteHeader(tc.failureStatusCode)
					w.Write([]byte(`{"message": "error"}`))
				} else {
					w.WriteHeader(http.StatusOK)
					w.Write([]byte(`{"status": "ok"}`))
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			if tc.useRetry {
				ctx = withRetryableEndpoint(ctx)
			}

			target := sweagentd.ClientTargetForApp(0)
			lim := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
			rt := ClientTransport(http.DefaultTransport, observability.NewNoopExporters(), lim, target, "github-app", nil)

			req, err := http.NewRequestWithContext(ctx, http.MethodGet, ts.URL+"/test", http.NoBody)
			require.NoError(t, err)

			resp, err := rt.RoundTrip(req)
			require.NoError(t, err)
			defer resp.Body.Close()

			assert.Equal(t, tc.expectedCallCount, callCount.Load())
			assert.Equal(t, tc.expectedStatusCode, resp.StatusCode)
		})
	}
}

func TestGithubAPIMetricTagsFn(t *testing.T) {
	tests := []struct {
		name          string
		flagEnabled   bool
		targetType    sweagentd.ClientTargetType
		apiTarget     string
		hmacHeader    bool
		wantNil       bool
		wantAuthType  string
		wantAPITarget string
	}{
		{
			name:        "flag off returns nil",
			flagEnabled: false,
			targetType:  sweagentd.ClientTargetTypeApp,
			apiTarget:   "public_rest",
			wantNil:     true,
		},
		{
			name:        "flag off with HMAC returns nil",
			flagEnabled: false,
			targetType:  sweagentd.ClientTargetTypeApp,
			apiTarget:   "public_rest",
			hmacHeader:  true,
			wantNil:     true,
		},
		{
			name:          "app target maps to integration",
			flagEnabled:   true,
			targetType:    sweagentd.ClientTargetTypeApp,
			apiTarget:     "public_rest",
			wantAuthType:  "integration",
			wantAPITarget: "public_rest",
		},
		{
			name:          "installation target maps to installation",
			flagEnabled:   true,
			targetType:    sweagentd.ClientTargetTypeInstallation,
			apiTarget:     "internal_rest",
			wantAuthType:  "installation",
			wantAPITarget: "internal_rest",
		},
		{
			name:          "user target maps to user",
			flagEnabled:   true,
			targetType:    sweagentd.ClientTargetTypeUser,
			apiTarget:     "public_graphql",
			wantAuthType:  "user",
			wantAPITarget: "public_graphql",
		},
		{
			name:          "HMAC header does not override at function level",
			flagEnabled:   true,
			targetType:    sweagentd.ClientTargetTypeInstallation,
			apiTarget:     "internal_graphql",
			hmacHeader:    true,
			wantAuthType:  "installation",
			wantAPITarget: "internal_graphql",
		},
		{
			name:          "unknown target type defaults to unknown",
			flagEnabled:   true,
			targetType:    sweagentd.ClientTargetType(99),
			apiTarget:     "public_rest",
			wantAuthType:  "unknown",
			wantAPITarget: "public_rest",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(map[string]bool{
				featureflags.CodingAgentAPIMetricTags: tc.flagEnabled,
			})

			target := sweagentd.ClientTarget{Type: tc.targetType}
			fn := githubAPIMetricTagsFn(ffClient, target, tc.apiTarget)

			req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, "https://api.example.com/test", http.NoBody)
			require.NoError(t, err)
			if tc.hmacHeader {
				req.Header.Set("Request-HMAC", "test-hmac")
			}

			tags := fn(req)

			if tc.wantNil {
				assert.Nil(t, tags, "expected nil tags when flag is off")
				return
			}

			require.NotNil(t, tags)
			assert.Equal(t, tc.wantAuthType, tags["auth_type"])
			assert.Equal(t, tc.wantAPITarget, tags["api_target"])
		})
	}
}

func TestGithubAPIMetricTagsFn_AgentSlug(t *testing.T) {
	t.Run("includes agent_slug when EmitAgentSlugStats is true and slug is set", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		target := sweagentd.ClientTarget{Type: sweagentd.ClientTargetTypeInstallation}
		fn := githubAPIMetricTagsFn(ffClient, target, "public_rest")

		ctx := requestctx.NewContext(context.Background())
		require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
			EmitAgentSlugStats: true,
			Agent:              requestctx.CtxAgent{Slug: "copilot"},
		}))

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.example.com/test", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		assert.Equal(t, "copilot", tags["agent_slug"])
		assert.Equal(t, "installation", tags["auth_type"])
		assert.Equal(t, "public_rest", tags["api_target"])
	})

	t.Run("excludes agent_slug when EmitAgentSlugStats is false", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		target := sweagentd.ClientTarget{Type: sweagentd.ClientTargetTypeInstallation}
		fn := githubAPIMetricTagsFn(ffClient, target, "public_rest")

		ctx := requestctx.NewContext(context.Background())
		require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
			EmitAgentSlugStats: false,
			Agent:              requestctx.CtxAgent{Slug: "copilot"},
		}))

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.example.com/test", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		_, exists := tags["agent_slug"]
		assert.False(t, exists, "agent_slug should not be present when EmitAgentSlugStats is false")
	})

	t.Run("excludes agent_slug when slug is empty", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		target := sweagentd.ClientTarget{Type: sweagentd.ClientTargetTypeInstallation}
		fn := githubAPIMetricTagsFn(ffClient, target, "public_rest")

		ctx := requestctx.NewContext(context.Background())
		require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
			EmitAgentSlugStats: true,
			Agent:              requestctx.CtxAgent{Slug: ""},
		}))

		req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.example.com/test", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		_, exists := tags["agent_slug"]
		assert.False(t, exists, "agent_slug should not be present when slug is empty")
	})

	t.Run("excludes agent_slug when no job in context", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		target := sweagentd.ClientTarget{Type: sweagentd.ClientTargetTypeInstallation}
		fn := githubAPIMetricTagsFn(ffClient, target, "public_rest")

		req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, "https://api.example.com/test", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		_, exists := tags["agent_slug"]
		assert.False(t, exists, "agent_slug should not be present when no job in context")
	})
}
