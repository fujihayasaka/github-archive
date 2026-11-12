package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGraphQLClientTenantReplacement(t *testing.T) {
	tests := []struct {
		name          string
		baseURLSuffix string
		tenantSlug    string
		shouldReplace bool
	}{
		{
			name:          "URL with tenant placeholder",
			baseURLSuffix: "/<tenant>",
			tenantSlug:    "test-tenant-123",
			shouldReplace: true,
		},
		{
			name:          "URL with URL-encoded tenant placeholder",
			baseURLSuffix: "/%3Ctenant%3E",
			tenantSlug:    "test-tenant-456",
			shouldReplace: true,
		},
		{
			name:          "URL without tenant placeholder",
			baseURLSuffix: "/graphql",
			tenantSlug:    "test-tenant-789",
			shouldReplace: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			requestReceived := false

			// Mock GraphQL server that captures the request URL
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				requestReceived = true

				if tt.shouldReplace {
					// Verify the URL contains the replaced tenant slug
					assert.Contains(t, r.URL.Path, tt.tenantSlug, "GraphQL request should contain replaced tenant slug")
				} else {
					// Verify the URL doesn't contain any tenant placeholder
					assert.NotContains(t, r.URL.Path, "<tenant>", "GraphQL request should not contain tenant placeholder")
					assert.NotContains(t, r.URL.Path, "%3Ctenant%3E", "GraphQL request should not contain URL-encoded tenant placeholder")
				}

				// Mock a simple GraphQL response
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(`{"data": {}}`))
			}))
			defer server.Close()

			// Create a client factory with the mock server URL
			baseURL := server.URL + tt.baseURLSuffix

			obsv := observability.NewNoopExporters()
			ffClient := featureflags.NewNoopClient(nil)
			copilot := agenticapptest.NewTestCopilot(t)
			target := sweagentd.ClientTargetForInstallationByOwnerID(copilot.AppID(), 123)
			limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

			appProvider := agenticapptest.NewTestProvider(t)

			cf, err := NewClientFactory(obsv, ffClient, limiter, baseURL, "", "", config.EnvironmentDevelopment, appProvider)
			require.NoError(t, err)

			// Create context with tenant slug
			ctx := context.Background()
			ctx = requestctx.AddData(ctx, &requestctx.CtxData{
				TenantSlug: tt.tenantSlug,
			})

			client := cf.newClient(ctx, "test-token", target, copilot)
			require.NoError(t, err)

			// Make a GraphQL request
			ghClient := client.(*Client)
			_ = ghClient.gqlclient.Query(ctx, struct{}{}, nil) // We expect this to fail, but we want to verify the request was made

			// We expect this to fail since it's not a real GraphQL endpoint,
			// but the important thing is that the request was made
			require.True(t, requestReceived, "GraphQL request should have been made to the server")
		})
	}
}
