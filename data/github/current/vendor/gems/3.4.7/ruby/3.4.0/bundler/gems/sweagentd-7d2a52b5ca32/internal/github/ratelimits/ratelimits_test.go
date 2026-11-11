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

	"github.com/github/sweagentd/internal/limiter"
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

func (m *mockClient) RateLimitsForRepo(ctx context.Context, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
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
		target   string
		expected *RoundTripper
	}{
		{
			name:    "with custom base transport",
			base:    &mockRoundTripper{},
			limiter: limiter.NewRateLimiterV1(mockClient, 100, time.Hour),
			target:  "test-target",
		},
		{
			name:    "with nil base transport uses default",
			base:    nil,
			limiter: limiter.NewRateLimiterV1(mockClient, 100, time.Hour),
			target:  "test-target",
		},
		{
			name:    "with nil limiter",
			base:    &mockRoundTripper{},
			limiter: nil,
			target:  "test-target",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rt := NewRoundTripper(tt.base, tt.limiter, tt.target)

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
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)
	target := "test-target"

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
	rt := NewRoundTripper(mockTransport, l, target)

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.NoError(t, err)
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
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)
	target := "test-target"

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
	rt := NewRoundTripper(mockTransport, l, target)

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.NoError(t, err)
	assert.Equal(t, resp, result)

	// Verify that the rate limit was NOT set in the limiter for cached responses
	_, found := l.GetRate(context.Background(), target, uint8(gg.GetRateLimitCategory("GET", "/user")))
	assert.False(t, found)
}

func TestRoundTrip_PrimaryRateLimitError(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)
	target := "test-target"

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
	rt := NewRoundTripper(mockTransport, l, target)

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.NoError(t, err) // RoundTrip itself should not return error
	assert.Equal(t, resp, result)

	// Verify that the rate limit was set in the limiter
	rate, found := l.GetRate(context.Background(), target, uint8(gg.GetRateLimitCategory("GET", "/user")))
	assert.True(t, found)
	assert.Equal(t, 5000, rate.Limit)
	assert.Equal(t, 0, rate.Remaining)
	assert.Equal(t, 5000, rate.Used)
	assert.Equal(t, "core", rate.Resource)
}

func TestRoundTrip_SecondaryRateLimitError(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)
	target := "test-target"

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
	rt := NewRoundTripper(mockTransport, l, target)

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.NoError(t, err) // RoundTrip itself should not return error
	assert.Equal(t, resp, result)

	// Verify that secondary rate limit was set
	waitDuration, shouldWait := l.WaitToReceive(context.Background())
	assert.True(t, shouldWait)
	assert.True(t, waitDuration > 50*time.Second) // Should be close to 60 seconds
	assert.True(t, waitDuration < 70*time.Second) // But account for timing variance
}

func TestRoundTrip_TransportError(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)
	target := "test-target"

	expectedErr := errors.New("transport error")
	mockTransport := &mockRoundTripper{err: expectedErr}
	rt := NewRoundTripper(mockTransport, l, target)

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.Error(t, err)
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
	rt := NewRoundTripper(mockTransport, nil, "test-target")

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.NoError(t, err)
	assert.Equal(t, resp, result)
	// Should not panic even with nil limiter
}

func TestRoundTrip_EmptyTarget(t *testing.T) {
	mockClient := &mockClient{}
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)

	resp := &http.Response{
		StatusCode: http.StatusOK,
		Header: http.Header{
			headerRateLimit:     []string{"5000"},
			headerRateRemaining: []string{"4999"},
		},
		Body: io.NopCloser(bytes.NewReader([]byte("{}"))),
	}

	mockTransport := &mockRoundTripper{response: resp}
	rt := NewRoundTripper(mockTransport, l, "")

	req, err := http.NewRequest("GET", "https://api.github.com/user", nil)
	require.NoError(t, err)

	result, err := rt.RoundTrip(req)

	assert.NoError(t, err)
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

			if tt.name == "rate-reset header present" {
				// Special handling for the rate-reset test case
				assert.NotNil(t, result)
				assert.True(t, *result > 50*time.Second)
				assert.True(t, *result < 70*time.Second)
			} else if tt.name == "invalid retry-after" {
				// Invalid retry-after results in 0 duration
				require.NotNil(t, result)
				assert.Equal(t, 0*time.Second, *result)
			} else if tt.name == "invalid rate-reset" {
				// Invalid rate-reset results in time.Until(time.Unix(0, 0)) which is negative
				require.NotNil(t, result)
				assert.True(t, *result < 0) // Should be a large negative duration
			} else if tt.expected == nil {
				assert.Nil(t, result)
			} else {
				require.NotNil(t, result)
				assert.Equal(t, *tt.expected, *result)
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
	l := limiter.NewRateLimiterV1(mockClient, 100, time.Hour)
	target := "test-target"

	rt := NewRoundTripper(nil, l, target)
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
