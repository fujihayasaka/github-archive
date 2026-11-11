package observability

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp/ctxsetters"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// mockRoundTripper implements http.RoundTripper for testing
type mockRoundTripper struct {
	response *http.Response
	err      error
	called   bool
}

func (m *mockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	m.called = true
	if m.err != nil {
		return nil, m.err
	}
	return m.response, nil
}

// mockStatter implements stats.Client for testing
type mockStatter struct {
	stats.NullClient

	distributionCalls []distributionCall
	counterCalls      []counterCall
}

type distributionCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

func (m *mockStatter) WithTags(tags stats.Tags) stats.Client {
	return &taggedMockStatter{
		mockStatter: m,
		tags:        tags,
	}
}

type taggedMockStatter struct {
	*mockStatter

	tags stats.Tags
}

func (tm *taggedMockStatter) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	// Merge tags
	allTags := make(stats.Tags)
	maps.Copy(allTags, tm.tags)
	maps.Copy(allTags, tags)

	tm.distributionCalls = append(tm.distributionCalls, distributionCall{
		key:      key,
		tags:     allTags,
		duration: duration,
	})
}

func (tm *taggedMockStatter) Counter(key string, tags stats.Tags, value int64) {
	// Merge tags
	allTags := make(stats.Tags)
	maps.Copy(allTags, tm.tags)
	maps.Copy(allTags, tags)

	tm.counterCalls = append(tm.counterCalls, counterCall{
		key:   key,
		tags:  allTags,
		value: value,
	})
}

func (tm *taggedMockStatter) Distribution(key string, tags stats.Tags, value float64) {
	// Merge tags
	allTags := make(stats.Tags)
	maps.Copy(allTags, tm.tags)
	maps.Copy(allTags, tags)

	tm.distributionCalls = append(tm.distributionCalls, distributionCall{
		key:  key,
		tags: allTags,
	})
}

func (tm *taggedMockStatter) WithTags(tags stats.Tags) stats.Client {
	allTags := make(stats.Tags)
	maps.Copy(allTags, tm.tags)
	maps.Copy(allTags, tags)
	return &taggedMockStatter{
		mockStatter: tm.mockStatter,
		tags:        allTags,
	}
}

func TestNewTelemetryRoundTripper(t *testing.T) {
	obsv := NewNoopExporters()
	rt := &mockRoundTripper{}

	telemetryRT := NewTelemetryRoundTripper(rt, obsv, "test-service", nil)

	// The round tripper is now wrapped with otelhttp.NewTransport
	assert.NotNil(t, telemetryRT.rt)
	assert.IsType(t, &otelhttp.Transport{}, telemetryRT.rt)
	assert.Equal(t, obsv, telemetryRT.obsv)
	assert.Equal(t, "test-service", telemetryRT.name)
}

func TestNewTelemetryRoundTripper_NilRoundTripper(t *testing.T) {
	obsv := NewNoopExporters()

	telemetryRT := NewTelemetryRoundTripper(nil, obsv, "test-service", nil)

	// The round tripper is now wrapped with otelhttp.NewTransport
	assert.NotNil(t, telemetryRT.rt)
	assert.IsType(t, &otelhttp.Transport{}, telemetryRT.rt)
}

func TestTelemetryRoundTripper_SuccessfulRequest(t *testing.T) {
	// Create mock response
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", nil)

	// Create test request
	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	// Execute request
	result, err := telemetryRT.RoundTrip(req)

	// Verify response
	require.NoError(t, err)
	assert.Equal(t, resp, result)
	assert.True(t, mockRT.called)

	// Verify metrics: 1 legacy duration distribution, 1 API request counter
	assert.GreaterOrEqual(t, len(mockStats.distributionCalls), 1)
	assert.GreaterOrEqual(t, len(mockStats.counterCalls), 1)
	assert.Equal(t, "github.api.request", mockStats.counterCalls[0].key)

	// Check legacy distribution call
	distCall := mockStats.distributionCalls[0]
	assert.Equal(t, "http_request_duration", distCall.key)
	assert.Equal(t, "GET", distCall.tags["method"])
	assert.Equal(t, "api.example.com", distCall.tags["host"])
	assert.Equal(t, "test-service", distCall.tags["client_name"])
	assert.Equal(t, "success", distCall.tags["status"])
	assert.Equal(t, "200", distCall.tags["status_code"])
	assert.Equal(t, "2xx", distCall.tags["status_class"])
}

func TestTelemetryRoundTripper_ErrorRequest(t *testing.T) {
	// Create mock error
	testErr := errors.New("connection failed")
	mockRT := &mockRoundTripper{err: testErr}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", nil)

	// Create test request
	req, err := http.NewRequest(http.MethodPost, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	// Execute request
	result, err := telemetryRT.RoundTrip(req)

	// Verify error response
	require.Error(t, err)
	assert.Equal(t, testErr, err)
	assert.Nil(t, result)
	assert.True(t, mockRT.called)

	// Verify metrics: request counter + error counter
	assert.GreaterOrEqual(t, len(mockStats.counterCalls), 2)
	assert.Equal(t, "github.api.request", mockStats.counterCalls[0].key)
	assert.Equal(t, "github.api.error", mockStats.counterCalls[1].key)

	// Check distribution call
	distCall := mockStats.distributionCalls[0]
	assert.Equal(t, "http_request_duration", distCall.key)
	assert.Equal(t, "POST", distCall.tags["method"])
	assert.Equal(t, "api.example.com", distCall.tags["host"])
	assert.Equal(t, "test-service", distCall.tags["client_name"])
	assert.Equal(t, "error", distCall.tags["status"])
	assert.Equal(t, "0", distCall.tags["status_code"])
}

func TestTelemetryRoundTripper_ErrorStatusCodes(t *testing.T) {
	testCases := []struct {
		name           string
		statusCode     int
		expectedStatus string
		expectedClass  string
	}{
		{"Bad Request", 400, "success", "4xx"},
		{"Unauthorized", 401, "success", "4xx"},
		{"Not Found", 404, "success", "4xx"},
		{"Internal Server Error", 500, "success", "5xx"},
		{"Bad Gateway", 502, "success", "5xx"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			resp := &http.Response{
				StatusCode: tc.statusCode,
				Status:     fmt.Sprintf("%d %s", tc.statusCode, http.StatusText(tc.statusCode)),
			}
			mockRT := &mockRoundTripper{response: resp}
			mockStats := &mockStatter{}

			obsv := NewNoopExporters()
			obsv.Statter = mockStats

			telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", nil)

			req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
			require.NoError(t, err)

			result, err := telemetryRT.RoundTrip(req)

			require.NoError(t, err)
			assert.Equal(t, resp, result)

			// Check legacy distribution metric
			require.GreaterOrEqual(t, len(mockStats.distributionCalls), 1)
			distCall := mockStats.distributionCalls[0]
			assert.Equal(t, tc.expectedStatus, distCall.tags["status"])
			assert.Equal(t, fmt.Sprintf("%d", tc.statusCode), distCall.tags["status_code"])
			assert.Equal(t, tc.expectedClass, distCall.tags["status_class"])
		})
	}
}

func TestTelemetryRoundTripper_ContextPropagation(t *testing.T) {
	// Test that the span is created and context is updated
	mockRT := &mockRoundTripper{
		response: &http.Response{StatusCode: http.StatusOK},
	}

	obsv := NewNoopExporters()
	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	// The test just verifies that the round tripper doesn't panic
	// and properly handles context. With noop tracer, context may
	// not actually change, so we just verify it works.
	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)
	assert.True(t, mockRT.called)
}

func TestTelemetryRoundTripper_RealHTTPServer(t *testing.T) {
	// Create a test HTTP server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("test response"))
	}))
	defer server.Close()

	mockStats := &mockStatter{}
	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(http.DefaultTransport, obsv, "integration-test", nil)

	req, err := http.NewRequest(http.MethodGet, server.URL+"/test-path", http.NoBody)
	require.NoError(t, err)

	resp, err := telemetryRT.RoundTrip(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, 200, resp.StatusCode)

	// Verify metrics: 1 request counter, 1+ distribution (legacy http_request_duration)
	assert.GreaterOrEqual(t, len(mockStats.counterCalls), 1)
	assert.Equal(t, "github.api.request", mockStats.counterCalls[0].key)

	distCall := mockStats.distributionCalls[0]
	assert.Equal(t, "GET", distCall.tags["method"])
	assert.Equal(t, "integration-test", distCall.tags["client_name"])
	assert.Equal(t, "success", distCall.tags["status"])
	assert.Equal(t, "200", distCall.tags["status_code"])
}

func TestTelemetryRoundTripper_GitHubAPITags(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", func(_ *http.Request) stats.Tags {
		return stats.Tags{
			"auth_type":  "installation",
			"api_target": "public_rest",
		}
	})

	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)

	var requestMetric *counterCall
	for i := range mockStats.counterCalls {
		if mockStats.counterCalls[i].key == "github.api.request" {
			requestMetric = &mockStats.counterCalls[i]
			break
		}
	}

	require.NotNil(t, requestMetric, "expected github.api.request counter to be emitted")
	assert.Equal(t, "public_rest", requestMetric.tags["api_target"])
	assert.Equal(t, "installation", requestMetric.tags["auth_type"])
}

func TestTelemetryRoundTripper_TwirpMethodTags(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", func(_ *http.Request) stats.Tags {
		return stats.Tags{"api_target": "cmc_automations"}
	})

	ctx := ctxsetters.WithMethodName(context.Background(), "HasRepositoryAutomation")
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.example.com/twirp/missioncontrol.automations.v1.AutomationsAPI/HasRepositoryAutomation", http.NoBody)
	require.NoError(t, err)
	req.Header.Set("Request-HMAC", "example-hmac")

	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)

	var durationMetric *distributionCall
	for i := range mockStats.distributionCalls {
		if mockStats.distributionCalls[i].key == "http_request_duration" {
			durationMetric = &mockStats.distributionCalls[i]
			break
		}
	}
	require.NotNil(t, durationMetric, "expected http_request_duration distribution to be emitted")
	assert.Equal(t, "cmc_automations", durationMetric.tags["api_target"])
	assert.Equal(t, "hmac", durationMetric.tags["auth_type"])
	assert.Equal(t, "HasRepositoryAutomation", durationMetric.tags["rpc_method"])

	var requestMetric *counterCall
	for i := range mockStats.counterCalls {
		if mockStats.counterCalls[i].key == "github.api.request" {
			requestMetric = &mockStats.counterCalls[i]
			break
		}
	}
	require.NotNil(t, requestMetric, "expected github.api.request counter to be emitted")
	assert.Equal(t, "cmc_automations", requestMetric.tags["api_target"])
	assert.Equal(t, "hmac", requestMetric.tags["auth_type"])
	assert.Equal(t, "HasRepositoryAutomation", requestMetric.tags["rpc_method"])
}

func TestTelemetryRoundTripper_GitHubAPITagsDoNotIncludeRequestContextTags(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusInternalServerError,
		Status:     "500 Internal Server Error",
		Header: http.Header{
			"X-Ratelimit-Remaining": []string{"42"},
			"X-Ratelimit-Resource":  []string{"core"},
		},
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", func(_ *http.Request) stats.Tags {
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

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)

	var durationMetric *distributionCall
	for i := range mockStats.distributionCalls {
		if mockStats.distributionCalls[i].key == "http_request_duration" {
			durationMetric = &mockStats.distributionCalls[i]
			break
		}
	}
	require.NotNil(t, durationMetric, "expected legacy duration metric to be emitted")
	assert.Contains(t, durationMetric.tags, "user_bucket")
	assert.Contains(t, durationMetric.tags, "repo_bucket")
	assert.Contains(t, durationMetric.tags, "pr_bucket")
	assert.Contains(t, durationMetric.tags, "aqueduct.queue")
	assert.Contains(t, durationMetric.tags, "url.route")

	var requestMetric *counterCall
	for i := range mockStats.counterCalls {
		if mockStats.counterCalls[i].key == "github.api.request" {
			requestMetric = &mockStats.counterCalls[i]
			break
		}
	}
	require.NotNil(t, requestMetric, "expected github.api.request counter to be emitted")
	assert.Equal(t, "GET", requestMetric.tags["method"])
	assert.Equal(t, "test-service", requestMetric.tags["client_name"])
	assert.Equal(t, "500", requestMetric.tags["status_code"])
	assert.Equal(t, "5xx", requestMetric.tags["status_class"])
	assert.Equal(t, "public_rest", requestMetric.tags["api_target"])
	assert.Equal(t, "installation", requestMetric.tags["auth_type"])

	var errorMetric *counterCall
	for i := range mockStats.counterCalls {
		if mockStats.counterCalls[i].key == "github.api.error" {
			errorMetric = &mockStats.counterCalls[i]
			break
		}
	}
	require.NotNil(t, errorMetric, "expected github.api.error counter to be emitted")
	assert.Equal(t, "GET", errorMetric.tags["method"])
	assert.Equal(t, "test-service", errorMetric.tags["client_name"])
	assert.Equal(t, "500", errorMetric.tags["status_code"])
	assert.Equal(t, "5xx", errorMetric.tags["status_class"])
	assert.Equal(t, "public_rest", errorMetric.tags["api_target"])
	assert.Equal(t, "installation", errorMetric.tags["auth_type"])

	var rlMetric *distributionCall
	for i := range mockStats.distributionCalls {
		if mockStats.distributionCalls[i].key == "github.api.rate_limit_remaining" {
			rlMetric = &mockStats.distributionCalls[i]
			break
		}
	}
	require.NotNil(t, rlMetric, "expected github.api.rate_limit_remaining distribution to be emitted")
	assert.Equal(t, "test-service", rlMetric.tags["client_name"])
	assert.Equal(t, "core", rlMetric.tags["resource"])
	assert.Equal(t, "public_rest", rlMetric.tags["api_target"])
	assert.Equal(t, "installation", rlMetric.tags["auth_type"])

	for _, metricTags := range []stats.Tags{requestMetric.tags, errorMetric.tags, rlMetric.tags} {
		assert.NotContains(t, metricTags, "user_bucket")
		assert.NotContains(t, metricTags, "repo_bucket")
		assert.NotContains(t, metricTags, "pr_bucket")
		assert.NotContains(t, metricTags, "aqueduct.queue")
		assert.NotContains(t, metricTags, "aqueduct.delivery_attempt")
		assert.NotContains(t, metricTags, "url.route")
		assert.NotContains(t, metricTags, "http.request.method")
	}
}

func TestTelemetryRoundTripper_NilMetricTagsFn(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", nil)

	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)
	req.Header.Set("Request-HMAC", "example-hmac")

	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)

	var requestMetric *counterCall
	for i := range mockStats.counterCalls {
		if mockStats.counterCalls[i].key == "github.api.request" {
			requestMetric = &mockStats.counterCalls[i]
			break
		}
	}

	require.NotNil(t, requestMetric, "expected github.api.request counter to be emitted")
	assert.Empty(t, requestMetric.tags["api_target"], "api_target should not be set when metricTagsFn is nil")
	assert.Empty(t, requestMetric.tags["auth_type"], "auth_type should not leak when metricTagsFn is nil")
}

func TestTelemetryRoundTripper_RateLimitRemainingTags(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
		Header: http.Header{
			"X-Ratelimit-Remaining": []string{"42"},
			"X-Ratelimit-Resource":  []string{"core"},
		},
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", func(_ *http.Request) stats.Tags {
		return stats.Tags{
			"auth_type":  "installation",
			"api_target": "public_rest",
		}
	})

	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)

	var rlMetric *distributionCall
	for i := range mockStats.distributionCalls {
		if mockStats.distributionCalls[i].key == "github.api.rate_limit_remaining" {
			rlMetric = &mockStats.distributionCalls[i]
			break
		}
	}

	require.NotNil(t, rlMetric, "expected rate_limit_remaining distribution to be emitted")
	assert.Equal(t, "public_rest", rlMetric.tags["api_target"])
	assert.Equal(t, "installation", rlMetric.tags["auth_type"])
	assert.Equal(t, "core", rlMetric.tags["resource"])
}

func TestTelemetryRoundTripper_TagsDoNotLeakAcrossRequests(t *testing.T) {
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	callCount := 0
	telemetryRT := NewTelemetryRoundTripper(
		&mockRoundTripper{response: &http.Response{StatusCode: http.StatusOK, Status: "200 OK"}},
		obsv, "test-service",
		func(req *http.Request) stats.Tags {
			callCount++
			tags := stats.Tags{"api_target": "public_rest"}
			if req.Header.Get("Request-HMAC") != "" {
				tags["auth_type"] = "hmac"
			} else {
				tags["auth_type"] = "installation"
			}
			return tags
		},
	)

	// First request with HMAC
	req1, _ := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	req1.Header.Set("Request-HMAC", "test-hmac")
	_, err := telemetryRT.RoundTrip(req1)
	require.NoError(t, err)

	// Second request without HMAC
	req2, _ := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	_, err = telemetryRT.RoundTrip(req2)
	require.NoError(t, err)

	// Find both request metrics
	var metrics []counterCall
	for _, c := range mockStats.counterCalls {
		if c.key == "github.api.request" {
			metrics = append(metrics, c)
		}
	}

	require.Len(t, metrics, 2)
	assert.Equal(t, "hmac", metrics[0].tags["auth_type"], "first request should have hmac")
	assert.Equal(t, "installation", metrics[1].tags["auth_type"], "second request should have installation, not hmac leak")
	assert.Equal(t, 2, callCount, "metricTagsFn should be called per-request")
}

func TestTelemetryRoundTripper_HMACOverrideAppliedByRoundTrip(t *testing.T) {
	resp := &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
	}
	mockRT := &mockRoundTripper{response: resp}
	mockStats := &mockStatter{}

	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	// Simulate a Twirp/CAPI-style closure that only sets api_target (no auth_type).
	// HMAC override should be applied by RoundTrip centrally.
	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service", func(_ *http.Request) stats.Tags {
		return stats.Tags{"api_target": "internal_twirp_api"}
	})

	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)
	req.Header.Set("Request-HMAC", "example-hmac")

	_, err = telemetryRT.RoundTrip(req)
	require.NoError(t, err)

	var requestMetric *counterCall
	for i := range mockStats.counterCalls {
		if mockStats.counterCalls[i].key == "github.api.request" {
			requestMetric = &mockStats.counterCalls[i]
			break
		}
	}

	require.NotNil(t, requestMetric)
	assert.Equal(t, "internal_twirp_api", requestMetric.tags["api_target"])
	assert.Equal(t, "hmac", requestMetric.tags["auth_type"], "HMAC override should be applied by RoundTrip even when closure does not set auth_type")
}
