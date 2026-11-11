package observability

import (
	"errors"
	"fmt"
	"maps"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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

func TestNewTelemetryRoundTripper(t *testing.T) {
	obsv := NewNoopExporters()
	rt := &mockRoundTripper{}

	telemetryRT := NewTelemetryRoundTripper(rt, obsv, "test-service")

	// The round tripper is now wrapped with otelhttp.NewTransport
	assert.NotNil(t, telemetryRT.rt)
	assert.IsType(t, &otelhttp.Transport{}, telemetryRT.rt)
	assert.Equal(t, obsv, telemetryRT.obsv)
	assert.Equal(t, "test-service", telemetryRT.name)
}

func TestNewTelemetryRoundTripper_NilRoundTripper(t *testing.T) {
	obsv := NewNoopExporters()

	telemetryRT := NewTelemetryRoundTripper(nil, obsv, "test-service")

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

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service")

	// Create test request
	req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
	require.NoError(t, err)

	// Execute request
	result, err := telemetryRT.RoundTrip(req)

	// Verify response
	require.NoError(t, err)
	assert.Equal(t, resp, result)
	assert.True(t, mockRT.called)

	// Verify metrics were recorded (only distribution metric, no counter)
	assert.Len(t, mockStats.distributionCalls, 1)
	assert.Len(t, mockStats.counterCalls, 0)

	// Check distribution call
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

	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service")

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

	// Verify metrics were recorded (only distribution metric, no counter)
	assert.Len(t, mockStats.distributionCalls, 1)
	assert.Len(t, mockStats.counterCalls, 0)

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

			telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service")

			req, err := http.NewRequest(http.MethodGet, "https://api.example.com/test", http.NoBody)
			require.NoError(t, err)

			result, err := telemetryRT.RoundTrip(req)

			require.NoError(t, err)
			assert.Equal(t, resp, result)

			// Check metrics (only distribution metric)
			assert.Len(t, mockStats.distributionCalls, 1)
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
	telemetryRT := NewTelemetryRoundTripper(mockRT, obsv, "test-service")

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
		w.Write([]byte("test response"))
	}))
	defer server.Close()

	mockStats := &mockStatter{}
	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	telemetryRT := NewTelemetryRoundTripper(http.DefaultTransport, obsv, "integration-test")

	req, err := http.NewRequest(http.MethodGet, server.URL+"/test-path", http.NoBody)
	require.NoError(t, err)

	resp, err := telemetryRT.RoundTrip(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, 200, resp.StatusCode)

	// Verify metrics were recorded (only distribution metric, no counter)
	assert.Len(t, mockStats.distributionCalls, 1)
	assert.Len(t, mockStats.counterCalls, 0)

	distCall := mockStats.distributionCalls[0]
	assert.Equal(t, "GET", distCall.tags["method"])
	assert.Equal(t, "integration-test", distCall.tags["client_name"])
	assert.Equal(t, "success", distCall.tags["status"])
	assert.Equal(t, "200", distCall.tags["status_code"])
}
