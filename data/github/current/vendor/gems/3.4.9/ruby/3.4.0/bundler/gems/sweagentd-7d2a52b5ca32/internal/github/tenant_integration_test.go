package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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

func TestGithubClientRoundTripperTenantReplacement(t *testing.T) {
	// Create a test server
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("{}"))
	}))
	defer ts.Close()

	// Create a context with tenant ID
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		TenantSlug: "test-tenant-123",
	})

	limiter := limiter.NewRateLimiterV1(&mockClient{}, 5, time.Minute)

	// Create the round tripper and make a request
	rt := AppClientTransport(http.DefaultTransport, observability.NewNoopExporters(), limiter)

	// Create a request with tenant placeholder - we need to build the URL correctly
	baseURL := ts.URL + "/<tenant>/repos"
	req, err := http.NewRequestWithContext(ctx, "GET", baseURL, nil)
	require.NoError(t, err)

	// Execute the request
	resp, err := rt.RoundTrip(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	// Verify that the tenant placeholder was replaced
	// The URL should be modified to include the tenant ID
	expectedURL := ts.URL + "/test-tenant-123/repos"
	assert.Equal(t, expectedURL, req.URL.String())
}

func TestGithubClientRoundTripperNoTenantInContext(t *testing.T) {
	// Create a test server
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("{}"))
	}))
	defer ts.Close()

	// Create a context without tenant ID
	ctx := context.Background()

	limiter := limiter.NewRateLimiterV1(&mockClient{}, 5, time.Minute)

	// Create the round tripper and make a request
	rt := AppClientTransport(http.DefaultTransport, observability.NewNoopExporters(), limiter)

	// Create a request with tenant placeholder
	baseURL := ts.URL + "/<tenant>/repos"
	req, err := http.NewRequestWithContext(ctx, "GET", baseURL, nil)
	require.NoError(t, err)

	// Execute the request
	_, err = rt.RoundTrip(req)
	require.Error(t, err)
}

func TestGithubClientRoundTripperNoTenantPlaceholder(t *testing.T) {
	// Create a test server
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("{}"))
	}))
	defer ts.Close()

	// Create a context with tenant ID
	ctx := context.Background()
	ctx = tenant.TenantIDContext(ctx, "test-tenant-123")

	limiter := limiter.NewRateLimiterV1(&mockClient{}, 5, time.Minute)

	// Create the round tripper and make a request
	rt := AppClientTransport(http.DefaultTransport, observability.NewNoopExporters(), limiter)

	// Create a request without tenant placeholder
	baseURL := ts.URL + "/normal/repos"
	req, err := http.NewRequestWithContext(ctx, "GET", baseURL, nil)
	require.NoError(t, err)

	// Execute the request
	resp, err := rt.RoundTrip(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	// Verify that the URL was not modified
	assert.Equal(t, baseURL, req.URL.String())
}
