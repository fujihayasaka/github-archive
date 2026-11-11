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

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/githubtwirp"
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
	mockResponse := map[string]any{
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

func TestNewTrafficFiltersDefaults_ReturnsPopulatedFilters(t *testing.T) {
	// This test ensures that NewTrafficFiltersDefaults returns correctly populated
	// traffic filters using the factory functions.

	experimentsClient := &ExperimentsClient{
		obsv: observability.NewNoopExporters(),
	}

	filterProps := &FilterProps{
		RepoID: 12345,
		OrgID:  67890,
		UserID: 11111,
	}

	// Create a noop client with a mock that returns a valid visibility
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
		var repositories []*repositoriesTwirp.RepositoryListItem
		for _, id := range req.Ids {
			repositories = append(repositories, &repositoriesTwirp.RepositoryListItem{
				Id:         id,
				OwnerId:    int64(456),
				Name:       "test-repo",
				OwnerLogin: "test-owner",
				Visibility: repositoriesTwirp.Visibility_VISIBILITY_PRIVATE,
			})
		}
		return &repositoriesTwirp.FindRepositoriesResponse{
			Repositories: repositories,
		}, nil
	}

	trafficFilters, err := experimentsClient.NewTrafficFiltersDefaults(context.Background(), noopClient, filterProps)
	require.NoError(t, err)

	// Verify that the returned traffic filters were populated with the correct values
	assert.Equal(t, "12345", trafficFilters[0].Value, "Returned repoFilter should have the correct value")
	assert.Equal(t, "67890", trafficFilters[1].Value, "Returned orgsFilter should have the correct value")
	assert.Equal(t, CopilotRepositoryHeader, trafficFilters[0].Header, "Returned repoFilter should have the correct header")
	assert.Equal(t, CopilotOrgsHeader, trafficFilters[1].Header, "Returned orgsFilter should have the correct header")
	assert.Equal(t, UserKindHeader, trafficFilters[2].Header, "Returned userKindFilter should have the correct header")
	assert.Equal(t, RepoVisibilityHeader, trafficFilters[3].Header, "Returned repoVisibilityFilter should have the correct header")
	assert.Equal(t, "private", trafficFilters[3].Value, "Returned repoVisibilityFilter should have the correct value")
}

func TestTrafficFilterFactoryFunctions_ReturnFreshInstances(t *testing.T) {
	// This test ensures that the factory functions return fresh instances each time,
	// preventing race conditions when multiple goroutines use the filters concurrently.

	// Get two instances from each factory
	repoFilter1 := NewRepositoryFilter()
	repoFilter2 := NewRepositoryFilter()

	orgsFilter1 := NewOrgsFilter()
	orgsFilter2 := NewOrgsFilter()

	userKindFilter1 := NewUserKindFilter()
	userKindFilter2 := NewUserKindFilter()

	repoVisibilityFilter1 := NewRepositoryVisibilityFilter()
	repoVisibilityFilter2 := NewRepositoryVisibilityFilter()

	// Mutate the first instance of each
	repoFilter1.Value = "12345"
	orgsFilter1.Value = "67890"
	userKindFilter1.Value = "user-kind-hash"
	repoVisibilityFilter1.Value = "private"

	// Verify that the second instances were not affected
	assert.Empty(t, repoFilter2.Value, "Second repoFilter should not be affected by mutation of first")
	assert.Empty(t, orgsFilter2.Value, "Second orgsFilter should not be affected by mutation of first")
	assert.Empty(t, userKindFilter2.Value, "Second userKindFilter should not be affected by mutation of first")
	assert.Empty(t, repoVisibilityFilter2.Value, "Second repoVisibilityFilter should not be affected by mutation of first")

	// Verify the headers are correctly set
	assert.Equal(t, CopilotRepositoryHeader, repoFilter1.Header)
	assert.Equal(t, CopilotOrgsHeader, orgsFilter1.Header)
	assert.Equal(t, UserKindHeader, userKindFilter1.Header)
	assert.Equal(t, RepoVisibilityHeader, repoVisibilityFilter1.Header)
}
