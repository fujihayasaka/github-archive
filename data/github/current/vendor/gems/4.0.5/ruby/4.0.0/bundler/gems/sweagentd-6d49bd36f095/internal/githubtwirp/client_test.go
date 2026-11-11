package githubtwirp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentHttp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestNewClient(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	t.Run("successful client creation", func(t *testing.T) {
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, nil)

		require.NoError(t, err)
		require.NotNil(t, client)

		// Verify interface implementation
		require.Implements(t, (*ClientInterface)(nil), client)
	})

	t.Run("invalid github HMAC key causes error", func(t *testing.T) {
		// Empty key should cause an error
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", "", "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, nil)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to create HMAC signer for github twirp client")
		require.Nil(t, client)
	})

	t.Run("invalid limiter HMAC key causes error", func(t *testing.T) {
		// Empty key should cause an error
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", "", 1, "https://unused.com", validHMACKey, obsv, ffClient, nil)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to create HMAC signer for limiter twirp client")
		require.Nil(t, client)
	})

	t.Run("invalid billing platform HMAC key causes error", func(t *testing.T) {
		// Empty key should cause an error
		validHMACKey := "test-hmac-key-16bytes"
		client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", "", obsv, ffClient, nil)
		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to create billing client")
		require.Nil(t, client)
	})
}

func TestClientMethods(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	validHMACKey := "test-hmac-key-16bytes"
	client, err := NewClient("https://unused.com", validHMACKey, "https://unused.com", validHMACKey, 1, "https://unused.com", validHMACKey, obsv, ffClient, nil)
	require.NoError(t, err)

	t.Run("UserDetailAPI returns expected client", func(t *testing.T) {
		userDetailAPI := client.UserDetailAPI()
		require.NotNil(t, userDetailAPI)
	})

	t.Run("SweagentdAPI returns expected client", func(t *testing.T) {
		sweagentdAPI := client.SweagentdAPI()
		require.NotNil(t, sweagentdAPI)
	})

	t.Run("LimiterAPI returns expected client", func(t *testing.T) {
		limiterAPI := client.LimiterAPI()
		require.NotNil(t, limiterAPI)
	})
}

// TestClientForwardsHeaders tests that the client forwards tenant and request IDs
func TestClientForwardsHeaders(t *testing.T) {
	// Create a test server that captures headers
	headersCaptured := make(chan http.Header, 1)
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		headersCaptured <- r.Header
		w.Header().Set("Content-Type", "application/protobuf")
		w.WriteHeader(http.StatusOK)
		// We need to create a real protobuf message and marshal it
		resp := &sweagentHttp.ConfigurationForRepositoryResponse{}
		respBytes, err := proto.Marshal(resp)
		require.NoError(t, err)

		w.Write(respBytes)
	}))
	defer ts.Close()

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	validHMACKey := "test-hmac-key-16bytes"
	client, err := NewClient(ts.URL, validHMACKey, ts.URL, validHMACKey, 1, ts.URL, validHMACKey, obsv, ffClient, nil)
	require.NoError(t, err)

	// Test that the client is properly created
	require.NotNil(t, client)

	ctx := requestid.WithNewGitHubRequestID(context.Background())
	ctx = tenant.TenantContext(ctx, "test-tenant")
	client.SweagentdAPI().ConfigurationForRepository(ctx, &sweagentHttp.ConfigurationForRepositoryRequest{})

	// Check that the headers were forwarded correctly
	headers := <-headersCaptured
	require.Equal(t, "sweagentd", headers.Get("User-Agent"))
	require.Equal(t, "test-tenant", headers.Get("X-GitHub-Tenant"))
	require.Equal(t, requestid.GetGitHubRequestID(ctx), headers.Get("X-GitHub-Request-ID"))
}

func TestClientRetriesOnEOF(t *testing.T) {
	requestCount := 0

	// Create a test server that simulates network failures
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++

		// Check that this is a Twirp API call
		if r.URL.Path != "/twirp/sweagentd.sweagentd_api.v1.SweagentdAPI/ConfigurationForRepository" {
			t.Errorf("Unexpected path: %s", r.URL.Path)
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		if requestCount < 4 {
			// Hijack connection to force EOF
			hj, ok := w.(http.Hijacker)
			require.True(t, ok, "ResponseWriter doesn't support hijacking")
			conn, _, err := hj.Hijack()
			require.NoError(t, err)
			conn.Close() // Force EOF by closing connection
			return
		}

		// Return successful response for subsequent requests
		w.Header().Set("Content-Type", "application/protobuf")
		w.WriteHeader(http.StatusOK)
		// Create a properly formatted protobuf response
		// We need to create a real protobuf message and marshal it
		resp := &sweagentHttp.ConfigurationForRepositoryResponse{
			// Set the fields you need in the response
			// Empty response is fine for the test
		}

		// Marshal the protobuf response
		respBytes, err := proto.Marshal(resp)
		require.NoError(t, err)

		w.Write(respBytes)
	}))
	defer ts.Close()

	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	fakeHMACKey := "test-hmac-key-16bytes"
	client, err := NewClientWithTimeout(ts.URL, fakeHMACKey, ts.URL, fakeHMACKey, ts.URL, fakeHMACKey, obsv, ffClient, 10*time.Millisecond, 10, nil)
	require.NoError(t, err)

	// Make a request that should trigger the retry logic
	// Use the actual Twirp API client method that would use the retry-enabled HTTP client
	ctx := context.Background()
	_, err = client.SweagentdAPI().ConfigurationForRepository(ctx, &sweagentHttp.ConfigurationForRepositoryRequest{})

	// Verify request succeeds after retry
	require.NoError(t, err, "Request should eventually succeed with retries")

	// Verify that multiple requests were made (at least 2)
	require.Equal(t, requestCount, 4, "Expected retry on EOF")
}

// TestTenantHeaderSetting tests the specific header setting logic in RequestPrepared hook
func TestTenantHeaderSetting(t *testing.T) {

	t.Run("sets tenant headers when tenant slug is present", func(t *testing.T) {
		req, err := http.NewRequest("GET", "https://example.com", nil)
		require.NoError(t, err)

		ctx := context.Background()
		ctx = tenant.TenantContext(ctx, "test-tenant")
		// Add tenant ID to context through requestctx
		ctx = requestid.WithNewGitHubRequestID(ctx)

		// Simulate the RequestPrepared hook
		slug := requestctx.TenantSlug(ctx)
		if slug != "" {
			req.Header.Set(requestctx.GitHubTenantHeader, slug)
			req.Header.Set(requestctx.GitHubTenantIDHeader, requestctx.TenantID(ctx))
		}

		// Verify headers are set correctly
		require.Equal(t, "test-tenant", req.Header.Get(requestctx.GitHubTenantHeader))
		require.Equal(t, requestctx.TenantID(ctx), req.Header.Get(requestctx.GitHubTenantIDHeader))
	})

	t.Run("does not set tenant headers when tenant slug is empty", func(t *testing.T) {
		req, err := http.NewRequest("GET", "https://example.com", nil)
		require.NoError(t, err)

		ctx := context.Background()
		// No tenant in context

		// Simulate the RequestPrepared hook
		slug := requestctx.TenantSlug(ctx)
		if slug != "" {
			req.Header.Set(requestctx.GitHubTenantHeader, slug)
			req.Header.Set(requestctx.GitHubTenantIDHeader, requestctx.TenantID(ctx))
		}

		// Verify headers are not set
		require.Empty(t, req.Header.Get(requestctx.GitHubTenantHeader))
		require.Empty(t, req.Header.Get(requestctx.GitHubTenantIDHeader))
	})
}

type counterMetricCall struct {
	key   string
	tags  stats.Tags
	value int64
}

func TestLimiterAttemptRequestLogHookEmitsAttemptMetric(t *testing.T) {
	obsv := observability.NewNoopExporters()
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)
	var counterCalls []counterMetricCall
	obsv.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			tagsCopy := stats.Tags{}
			for k, v := range tags {
				tagsCopy[k] = v
			}
			counterCalls = append(counterCalls, counterMetricCall{
				key:   key,
				tags:  tagsCopy,
				value: value,
			})
		},
	}

	hook := limiterAttemptRequestLogHook(obsv, limiterMaxAttempts)
	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddUser(ctx, &requestctx.UserInfo{ID: 123456789}))
	require.NoError(t, requestctx.AddRepo(ctx, requestctx.CtxRepo{ID: 987654321}))
	require.NoError(t, requestctx.AddAqueductJob(ctx, &requestctx.CtxAqueductJob{Queue: "github", DeliveryAttempt: 2}))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://example.com", nil)
	require.NoError(t, err)

	hook(nil, req, 0)
	require.Len(t, counterCalls, 0)

	hook(nil, req, 1)
	require.Len(t, counterCalls, 1)
	require.Equal(t, "github.api.retry", counterCalls[0].key)
	require.Equal(t, int64(1), counterCalls[0].value)
	require.Equal(t, limiterTwirpClientName, counterCalls[0].tags["client_name"])
	require.Equal(t, "2", counterCalls[0].tags["attempt"])
	require.Equal(t, strconv.Itoa(limiterMaxAttempts), counterCalls[0].tags["max_attempts"])
	require.NotContains(t, counterCalls[0].tags, "user_bucket")
	require.NotContains(t, counterCalls[0].tags, "repo_bucket")
	require.NotContains(t, counterCalls[0].tags, "aqueduct.queue")
	require.NotContains(t, counterCalls[0].tags, "aqueduct.delivery_attempt")
}

func TestLimiterAttemptRequestLogHookExhaustedAttemptsUseMaxAttemptMetric(t *testing.T) {
	obsv := observability.NewNoopExporters()
	var counterCalls []counterMetricCall
	obsv.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			tagsCopy := stats.Tags{}
			for k, v := range tags {
				tagsCopy[k] = v
			}
			counterCalls = append(counterCalls, counterMetricCall{
				key:   key,
				tags:  tagsCopy,
				value: value,
			})
		},
	}

	hook := limiterAttemptRequestLogHook(obsv, limiterMaxAttempts)
	req, err := http.NewRequest(http.MethodGet, "https://example.com", nil)
	require.NoError(t, err)

	hook(nil, req, 1)
	hook(nil, req, limiterMaxRetries)

	require.Len(t, counterCalls, 2)
	require.Equal(t, "2", counterCalls[0].tags["attempt"])
	require.Equal(t, limiterAttemptMetric, counterCalls[1].key)
	require.Equal(t, limiterTwirpClientName, counterCalls[1].tags["client_name"])
	require.Equal(t, strconv.Itoa(limiterMaxAttempts), counterCalls[1].tags["attempt"])
	require.Equal(t, strconv.Itoa(limiterMaxAttempts), counterCalls[1].tags["max_attempts"])
}

func TestTwirpMetricTagsFn(t *testing.T) {
	t.Run("includes agent_slug when job context is present and flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		fn := twirpMetricTagsFn(ffClient)("internal_twirp_api")

		ctx := requestctx.NewContext(context.Background())
		require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
			EmitAgentSlugStats: true,
			Agent:              requestctx.CtxAgent{Slug: "copilot"},
		}))

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://example.com", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		require.Equal(t, "internal_twirp_api", tags["api_target"])
		require.Equal(t, "copilot", tags["agent_slug"])
	})

	t.Run("excludes agent_slug when EmitAgentSlugStats is false", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		fn := twirpMetricTagsFn(ffClient)("internal_twirp_api")

		ctx := requestctx.NewContext(context.Background())
		require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
			EmitAgentSlugStats: false,
			Agent:              requestctx.CtxAgent{Slug: "copilot"},
		}))

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://example.com", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		require.Equal(t, "internal_twirp_api", tags["api_target"])
		_, exists := tags["agent_slug"]
		require.False(t, exists)
	})

	t.Run("excludes agent_slug when no job in context", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: true,
		})
		fn := twirpMetricTagsFn(ffClient)("internal_twirp_api")

		req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, "https://example.com", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.NotNil(t, tags)
		require.Equal(t, "internal_twirp_api", tags["api_target"])
		_, exists := tags["agent_slug"]
		require.False(t, exists)
	})

	t.Run("returns nil when flag is off", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentAPIMetricTags: false,
		})
		fn := twirpMetricTagsFn(ffClient)("internal_twirp_api")

		ctx := requestctx.NewContext(context.Background())
		require.NoError(t, requestctx.AddJob(ctx, &requestctx.CtxJob{
			EmitAgentSlugStats: true,
			Agent:              requestctx.CtxAgent{Slug: "copilot"},
		}))

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://example.com", http.NoBody)
		require.NoError(t, err)

		tags := fn(req)
		require.Nil(t, tags)
	})
}
