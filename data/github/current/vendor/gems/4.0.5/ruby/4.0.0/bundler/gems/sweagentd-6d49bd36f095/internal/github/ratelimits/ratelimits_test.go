package ratelimits

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockRoundTripper is a mock implementation of http.RoundTripper for testing
type mockRoundTripper struct {
	response *http.Response
	err      error
}

func (m *mockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	return m.response, m.err
}

// mockClient is a mock implementation of limiter.client for testing
type mockClient struct {
	rates map[uint8]limiter.Rate
	err   error
}

func (m *mockClient) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.rates, nil
}

func TestNewRoundTripper(t *testing.T) {
	mockClient := &mockClient{}

	tests := []struct {
		name     string
		base     http.RoundTripper
		limiter  limiter.RateLimiter
		target   sweagentd.ClientTarget
		expected *RoundTripper
	}{
		{
			name:    "with custom base transport",
			base:    &mockRoundTripper{},
			limiter: limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t)),
			target:  sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
		},
		{
			name:    "with nil base transport uses default",
			base:    nil,
			limiter: limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t)),
			target:  sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
		},
		{
			name:    "with nil limiter",
			base:    &mockRoundTripper{},
			limiter: nil,
			target:  sweagentd.ClientTargetForInstallationByOwnerID(0, 123),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rt := NewRoundTripper(tt.base, tt.limiter, tt.target, observability.NewNoopExporters(), nil)

			assert.NotNil(t, rt)
			assert.Equal(t, tt.limiter, rt.limiter)
			assert.Equal(t, tt.target, rt.target)

			if tt.base == nil {
				assert.Equal(t, http.DefaultTransport, rt.base)
			} else {
				assert.Equal(t, tt.base, rt.base)
			}
		})
	}
}

func TestRoundTrip_SuccessfulResponse(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	// Create a successful response with rate limit headers
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Header: http.Header{
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"4999"},
			headerRateUsed:      []string{"1"},
			headerRateReset:     []string{strconv.FormatInt(time.Now().Add(time.Hour).Unix(), 10)},
			headerRateResource:  []string{"core"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte("{}"))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, target, observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.NoError(t, err)
	assert.Equal(t, resp, result)

	// Verify that the rate limit was set in the limiter
	rate, found := l.GetRate(context.Background(), target, uint8(gg.GetRateLimitCategory("GET", "/user")))
	assert.True(t, found)
	assert.Equal(t, 5000, rate.Limit)
	assert.Equal(t, 4999, rate.Remaining)
	assert.Equal(t, 1, rate.Used)
	assert.Equal(t, "core", rate.Resource)
}

func TestRoundTrip_CachedResponse(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	// Create a cached response (should not update rate limits)
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Header: http.Header{
			"X-From-Cache":      []string{"true"},
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"4999"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte("{}"))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, target, observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.NoError(t, err)
	assert.Equal(t, resp, result)

	// Verify that the rate limit was NOT set in the limiter for cached responses
	_, found := l.GetRate(context.Background(), target, uint8(gg.GetRateLimitCategory("GET", "/user")))
	assert.False(t, found)
}

func TestRoundTrip_PrimaryRateLimitError(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	resetTime := time.Now().Add(time.Hour)

	// Create a rate limit error response
	resp := &http.Response{
		StatusCode: http.StatusForbidden,
		Header: http.Header{
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"0"},
			headerRateUsed:      []string{"5000"},
			headerRateReset:     []string{strconv.FormatInt(resetTime.Unix(), 10)},
			headerRateResource:  []string{"core"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte(`{
			"message": "API rate limit exceeded",
			"documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
		}`))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, target, observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.NoError(t, err) // RoundTrip itself should not return error
	assert.Equal(t, resp, result)

	// Verify that the rate limit was set in the limiter
	rate, found := l.GetRate(context.Background(), target, uint8(gg.GetRateLimitCategory("GET", "/user")))
	assert.True(t, found)
	assert.Equal(t, 5000, rate.Limit)
	assert.Equal(t, 0, rate.Remaining)
	assert.Equal(t, 5000, rate.Used)
	assert.Equal(t, "core", rate.Resource)
}

func TestRoundTrip_RateLimitExceededMetricUsesLowCardinalityTags(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	resp := &http.Response{
		StatusCode: http.StatusForbidden,
		Header: http.Header{
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"0"},
			headerRateUsed:      []string{"5000"},
			headerRateReset:     []string{strconv.FormatInt(time.Now().Add(time.Hour).Unix(), 10)},
			headerRateResource:  []string{"core"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte(`{
			"message": "API rate limit exceeded",
			"documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
		}`))),
	}

	var counterCalls []struct {
		key   string
		tags  stats.Tags
		value int64
	}
	obsv := observability.NewNoopExporters()
	obsv = obsv.WithTelemetryFunc(requestctx.ToTelemetry)
	obsv.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, value int64) {
			tagsCopy := stats.Tags{}
			for k, v := range tags {
				tagsCopy[k] = v
			}
			counterCalls = append(counterCalls, struct {
				key   string
				tags  stats.Tags
				value int64
			}{key: key, tags: tagsCopy, value: value})
		},
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, target, obsv, func(_ *http.Request) stats.Tags {
		return stats.Tags{
			"auth_type":  "installation",
			"api_target": "public_rest",
		}
	})

	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddUser(ctx, &requestctx.UserInfo{ID: 123456789}))
	require.NoError(t, requestctx.AddRepo(ctx, requestctx.CtxRepo{ID: 987654321}))
	prID := int64(111222333)
	require.NoError(t, requestctx.AddPullRequest(ctx, requestctx.CtxPullRequest{ID: &prID}))
	require.NoError(t, requestctx.AddAqueductJob(ctx, &requestctx.CtxAqueductJob{Queue: "github", DeliveryAttempt: 2}))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)
	require.NoError(t, err)
	assert.Equal(t, resp, result)

	require.Len(t, counterCalls, 1)
	assert.Equal(t, "github.api.rate_limit_exceeded", counterCalls[0].key)
	assert.Equal(t, int64(1), counterCalls[0].value)
	assert.Equal(t, "primary", counterCalls[0].tags["type"])
	assert.Equal(t, "GET", counterCalls[0].tags["method"])
	assert.Equal(t, "public_rest", counterCalls[0].tags["api_target"])
	assert.Equal(t, "installation", counterCalls[0].tags["auth_type"])
	assert.NotContains(t, counterCalls[0].tags, "user_bucket")
	assert.NotContains(t, counterCalls[0].tags, "repo_bucket")
	assert.NotContains(t, counterCalls[0].tags, "pr_bucket")
	assert.NotContains(t, counterCalls[0].tags, "aqueduct.queue")
	assert.NotContains(t, counterCalls[0].tags, "aqueduct.delivery_attempt")
}

func TestRoundTrip_SecondaryRateLimitError(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	// Create a secondary rate limit error response
	resp := &http.Response{
		StatusCode: http.StatusForbidden,
		Header: http.Header{
			headerRetryAfter: []string{"60"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte(`{
			"message": "You have exceeded a secondary rate limit",
			"documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#secondary-rate-limits"
		}`))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, target, observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.NoError(t, err) // RoundTrip itself should not return error
	assert.Equal(t, resp, result)

	// Verify that secondary rate limit was set
	waitDuration, shouldWait := l.WaitToReceive(context.Background(), 0)
	assert.True(t, shouldWait)
	assert.Greater(t, waitDuration, 50*time.Second) // Should be close to 60 seconds
	assert.Less(t, waitDuration, 70*time.Second)    // But account for timing variance
}

func TestRoundTrip_TransportError(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	expectedErr := errors.New("transport error")
	mockTransport := &mockRoundTripper{err: expectedErr}
	rt := NewRoundTripper(mockTransport, l, target, observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.Error(t, err)
	assert.Equal(t, expectedErr, err)
	assert.Nil(t, result)
}

func TestRoundTrip_NilLimiter(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Header: http.Header{
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"4999"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte("{}"))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, nil, sweagentd.ClientTargetForInstallationByOwnerID(0, 123), observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.NoError(t, err)
	assert.Equal(t, resp, result)
	// Should not panic even with nil limiter
}

func TestRoundTrip_AppTarget(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForApp(0)

	resp := &http.Response{
		StatusCode: http.StatusOK,
		Header: http.Header{
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"4999"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte("{}"))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, target, observability.NewNoopExporters(), nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.github.com/user", http.NoBody)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	require.NoError(t, err)
	assert.Equal(t, resp, result)
	// Should not set rate limits with empty target
}

func TestParseRate(t *testing.T) {
	tests := []struct {
		name     string
		headers  http.Header
		expected limiter.Rate
	}{
		{
			name: "all headers present",
			headers: http.Header{
				headerRateLimit:     []string{"5000"},
				headerRateRemaining: []string{"4999"},
				headerRateUsed:      []string{"1"},
				headerRateReset:     []string{"1609459200"}, // 2021-01-01 00:00:00 UTC
				headerRateResource:  []string{"core"},
			},
			expected: limiter.Rate{
				Limit:     5000,
				Remaining: 4999,
				Used:      1,
				Reset:     time.Unix(1609459200, 0),
				Resource:  "core",
			},
		},
		{
			name: "partial headers",
			headers: http.Header{
				headerRateLimit:     []string{"1000"},
				headerRateRemaining: []string{"999"},
			},
			expected: limiter.Rate{
				Limit:     1000,
				Remaining: 999,
				Used:      0,
				Reset:     time.Time{},
				Resource:  "",
			},
		},
		{
			name:    "no headers",
			headers: http.Header{},
			expected: limiter.Rate{
				Limit:     0,
				Remaining: 0,
				Used:      0,
				Reset:     time.Time{},
				Resource:  "",
			},
		},
		{
			name: "invalid numeric values",
			headers: http.Header{
				headerRateLimit:     []string{"invalid"},
				headerRateRemaining: []string{"also-invalid"},
				headerRateUsed:      []string{"not-a-number"},
				headerRateReset:     []string{"not-unix-time"},
			},
			expected: limiter.Rate{
				Limit:     0,
				Remaining: 0,
				Used:      0,
				Reset:     time.Time{},
				Resource:  "",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp := &http.Response{Header: tt.headers}
			result := parseRate(resp)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestParseSecondaryRate(t *testing.T) {
	tests := []struct {
		name     string
		headers  http.Header
		expected *time.Duration
	}{
		{
			name: "retry-after header present",
			headers: http.Header{
				headerRetryAfter: []string{"60"},
			},
			expected: func() *time.Duration { d := 60 * time.Second; return &d }(),
		},
		{
			name: "rate-reset header present",
			headers: http.Header{
				headerRateReset: []string{strconv.FormatInt(time.Now().Add(60*time.Second).Unix(), 10)},
			},
			expected: func() *time.Duration {
				// We expect roughly 60 seconds, but need to be flexible due to timing
				return nil // We'll check the approximate value in the test
			}(),
		},
		{
			name:     "no relevant headers",
			headers:  http.Header{},
			expected: nil,
		},
		{
			name: "invalid retry-after",
			headers: http.Header{
				headerRetryAfter: []string{"invalid"},
			},
			expected: func() *time.Duration { d := 0 * time.Second; return &d }(), // Parse error results in 0
		},
		{
			name: "invalid rate-reset",
			headers: http.Header{
				headerRateReset: []string{"invalid"},
			},
			expected: func() *time.Duration {
				// Parse error results in 0, so time.Until(time.Unix(0, 0))
				// which is a large negative duration from 1970
				return nil // We'll handle this specially in the test
			}(),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp := &http.Response{Header: tt.headers}
			result := parseSecondaryRate(resp)

			switch tt.name {
			case "rate-reset header present":
				// Special handling for the rate-reset test case
				require.NotNil(t, result)
				assert.Greater(t, *result, 50*time.Second)
				assert.Less(t, *result, 70*time.Second)
			case "invalid retry-after":
				// Invalid retry-after results in 0 duration
				require.NotNil(t, result)
				assert.Equal(t, 0*time.Second, *result)
			case "invalid rate-reset":
				// Invalid rate-reset results in time.Until(time.Unix(0, 0)) which is negative
				require.NotNil(t, result)
				assert.Less(t, *result, time.Duration(0)) // Should be a large negative duration
			default:
				if tt.expected == nil {
					assert.Nil(t, result)
				} else {
					require.NotNil(t, result)
					assert.Equal(t, *tt.expected, *result)
				}
			}
		})
	}
}

func TestLimiterRate(t *testing.T) {
	resetTime := time.Unix(1609459200, 0) // 2021-01-01 00:00:00 UTC

	ghRate := gg.Rate{
		Limit:     5000,
		Remaining: 4999,
		Used:      1,
		Reset:     gg.Timestamp{Time: resetTime},
		Resource:  "core",
	}

	expected := limiter.Rate{
		Limit:     5000,
		Remaining: 4999,
		Used:      1,
		Reset:     resetTime,
		Resource:  "core",
	}

	result := ToLimiterRate(ghRate)
	assert.Equal(t, expected, result)
}

func TestIntegration_RealHTTPServer(t *testing.T) {
	// Create a test HTTP server that simulates GitHub API responses
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Simulate rate limit headers in response
		w.Header().Set(headerRateLimit, "5000")
		w.Header().Set(headerRateRemaining, "4999")
		w.Header().Set(headerRateUsed, "1")
		w.Header().Set(headerRateReset, strconv.FormatInt(time.Now().Add(time.Hour).Unix(), 10))
		w.Header().Set(headerRateResource, "core")

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"login": "testuser"}`))
	}))
	defer server.Close()

	mockClient := &mockClient{}
	l := limiter.NewCacheRateLimiter(mockClient, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	target := sweagentd.ClientTargetForInstallationByOwnerID(0, 123)

	rt := NewRoundTripper(nil, l, target, observability.NewNoopExporters(), nil)
	client := &http.Client{Transport: rt}

	resp, err := client.Get(server.URL)
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)

	// Verify rate limit was captured
	rate, found := l.GetRate(context.Background(), target, uint8(gg.GetRateLimitCategory("GET", "/")))
	assert.True(t, found)
	assert.Equal(t, 5000, rate.Limit)
	assert.Equal(t, 4999, rate.Remaining)
	assert.Equal(t, 1, rate.Used)
	assert.Equal(t, "core", rate.Resource)
}
