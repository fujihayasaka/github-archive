package experiments

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/github/sweagentd/internal/observability"
)

// Experiment Client Testing
// Using time.Now() feels like it could be flaky, but in practice
// I doubt it's going to matter much since TTL is 5 min

// Test Cache

type MockRoundTripper struct {
	calls int
}

func (m *MockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	m.calls++

	// Return a valid JSON response that matches what the experiments API expects
	mockResponse := map[string]interface{}{
		"Configs": []ConfigEntry{
			{
				ID: "vscode",
				Parameters: map[string]any{
					"feature": "httpValue",
				},
			},
		},
		"AssignmentContext": "httpContext",
	}

	responseBody, err := json.Marshal(mockResponse)
	if err != nil {
		return nil, err
	}

	return &http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(bytes.NewReader(responseBody)),
		Header:     make(http.Header),
	}, nil
}

func TestGetFeatureAssignment_UsesCache(t *testing.T) {
	tests := []struct {
		name               string
		lastCacheTime      time.Time
		expectedHTTPCalls  int
		expectedAssignment *Assignment
	}{
		{
			name:              "Cache expired",
			lastCacheTime:     time.Now().Add(-time.Hour),
			expectedHTTPCalls: 1,
			expectedAssignment: &Assignment{
				Variation: "httpValue",
				Context:   "httpContext",
			},
		},
		{
			name:              "Cache valid",
			lastCacheTime:     time.Now(),
			expectedHTTPCalls: 0,
			expectedAssignment: &Assignment{
				Variation: "cachedValue",
				Context:   "cachedContext",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			randomizationUnit := &TrafficFilter{
				Header: "X-Randomization-Unit",
				Value:  "test-value",
			}

			// Generate the cache key that would be used for this request
			cacheKey := GenerateCacheKey(randomizationUnit, nil)

			// Create a cache with pre-existing assignment for the "Cache valid" test
			cache := NewAssignmentsCache(context.Background(), observability.NewNoopExporters(), CacheConfig{
				TTL:             5 * time.Minute,
				MaxSize:         1000,
				CleanupInterval: 1 * time.Minute,
			})
			cachedAssignment := &Assignments{
				Features: map[string]any{
					"feature": "cachedValue",
				},
				AssignmentContext: "cachedContext",
				lastUpdate:        tt.lastCacheTime,
			}
			cache.Set(cacheKey, cachedAssignment)

			mockRoundTripper := &MockRoundTripper{}

			experimentsClient := &ExperimentsClient{
				AssignmentsCache: cache,
				obsv:             observability.NewNoopExporters(),
				http: &http.Client{
					Transport: mockRoundTripper,
				},
				url:            url.URL{},
				TrafficFilters: &TrafficFilters{},
			}

			assignment, found := experimentsClient.GetFeatureAssignment(context.Background(), "feature", randomizationUnit, nil)
			assert.Equal(t, true, found)
			assert.Equal(t, tt.expectedHTTPCalls, mockRoundTripper.calls)
			assert.Equal(t, tt.expectedAssignment.Variation, assignment.Variation)
			assert.Equal(t, tt.expectedAssignment.Context, assignment.Context)
		})
	}
}
