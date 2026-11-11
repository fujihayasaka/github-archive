package observability

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestTelemetryRoundTripper_Integration tests the integration with actual HTTP calls
func TestTelemetryRoundTripper_Integration(t *testing.T) {
	// Create a test server that returns different status codes
	testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/success":
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("success"))
		case "/error":
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte("error"))
		case "/not-found":
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte("not found"))
		default:
			w.WriteHeader(http.StatusBadRequest)
			w.Write([]byte("bad request"))
		}
	}))
	defer testServer.Close()

	// Set up telemetry tracking
	mockStats := &mockStatter{}
	obsv := NewNoopExporters()
	obsv.Statter = mockStats

	// Create HTTP client with telemetry
	client := &http.Client{
		Transport: NewTelemetryRoundTripper(http.DefaultTransport, obsv, "integration-test"),
	}

	// Test successful request
	resp, err := client.Get(testServer.URL + "/success")
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, resp.StatusCode)
	resp.Body.Close()

	// Test error request
	resp, err = client.Get(testServer.URL + "/error")
	require.NoError(t, err)
	require.Equal(t, http.StatusInternalServerError, resp.StatusCode)
	resp.Body.Close()

	// Test not found request
	resp, err = client.Get(testServer.URL + "/not-found")
	require.NoError(t, err)
	require.Equal(t, http.StatusNotFound, resp.StatusCode)
	resp.Body.Close()

	// Verify metrics were recorded (only distribution metrics, no counters)
	assert.Len(t, mockStats.distributionCalls, 3, "Should have 3 duration metrics")
	assert.Len(t, mockStats.counterCalls, 0, "Should have no counter metrics")

	// Verify each request was tracked with correct status
	statusCodes := make(map[string]bool)
	for _, call := range mockStats.distributionCalls {
		assert.Equal(t, "http_request_duration", call.key)
		assert.Equal(t, "GET", call.tags["method"])
		assert.Equal(t, "integration-test", call.tags["client_name"])
		assert.Contains(t, call.tags, "status_code")
		statusCodes[call.tags["status_code"]] = true
	}

	// Should have seen all three status codes
	assert.True(t, statusCodes["200"], "Should have tracked 200 status")
	assert.True(t, statusCodes["500"], "Should have tracked 500 status")
	assert.True(t, statusCodes["404"], "Should have tracked 404 status")
}

// TestTelemetryRoundTripper_WithContext tests that context propagation works correctly
func TestTelemetryRoundTripper_WithContext(t *testing.T) {
	testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify that the context was passed through properly
		// In a real scenario, this might check for trace IDs or other context values
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	}))
	defer testServer.Close()

	obsv := NewNoopExporters()
	client := &http.Client{
		Transport: NewTelemetryRoundTripper(http.DefaultTransport, obsv, "context-test"),
	}

	// Create a request with a custom context
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, testServer.URL, http.NoBody)
	require.NoError(t, err)

	resp, err := client.Do(req)
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, resp.StatusCode)
	resp.Body.Close()

	// The test passes if no panics occurred and the request succeeded
}
