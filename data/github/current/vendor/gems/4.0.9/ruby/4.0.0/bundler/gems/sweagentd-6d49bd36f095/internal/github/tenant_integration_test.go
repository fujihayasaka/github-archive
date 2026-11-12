package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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

	target := sweagentd.ClientTargetForApp(0)
	limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

	// Create the round tripper and make a request
	rt := ClientTransport(http.DefaultTransport, observability.NewNoopExporters(), limiter, target, "github-app", nil)

	// Create a request with tenant placeholder - we need to build the URL correctly
	baseURL := ts.URL + "/<tenant>/repos"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL, http.NoBody)
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

	target := sweagentd.ClientTargetForApp(0)
	limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

	// Create the round tripper and make a request
	rt := ClientTransport(http.DefaultTransport, observability.NewNoopExporters(), limiter, target, "github-app", nil)

	// Create a request with tenant placeholder
	baseURL := ts.URL + "/<tenant>/repos"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL, http.NoBody)
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

	target := sweagentd.ClientTargetForApp(0)
	limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

	// Create the round tripper and make a request
	rt := ClientTransport(http.DefaultTransport, observability.NewNoopExporters(), limiter, target, "github-app", nil)

	// Create a request without tenant placeholder
	baseURL := ts.URL + "/normal/repos"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL, http.NoBody)
	require.NoError(t, err)

	// Execute the request
	resp, err := rt.RoundTrip(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	// Verify that the URL was not modified
	assert.Equal(t, baseURL, req.URL.String())
}
