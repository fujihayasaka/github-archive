package githubtwirp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestTwirpClientHookTenantReplacement(t *testing.T) {
	// Create a test server that captures the request URL
	var capturedURL string
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedURL = r.URL.String()
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("{}"))
	}))
	defer ts.Close()

	// Create a context with tenant ID
	ctx := context.Background()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		TenantSlug: "test-tenant-123",
	})

	// Create the client hook
	clientHooks := &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			tenant.Forward(req)

			// Replace <tenant> placeholder in URL with actual tenant ID from context
			if req.URL != nil {
				originalURL := req.URL.String()
				modifiedURL, _ := proxima.ReplaceTenantPlaceholder(ctx, originalURL)
				if modifiedURL != originalURL {
					// Parse the modified URL and update the request
					if newURL, err := url.Parse(modifiedURL); err == nil {
						req.URL = newURL
					}
				}
			}

			return ctx, nil
		},
	}

	// Create a request with tenant placeholder
	req, err := http.NewRequestWithContext(ctx, "GET", ts.URL+"/<tenant>/twirp/service", nil)
	require.NoError(t, err)

	// Execute the request prepared hook
	_, err = clientHooks.RequestPrepared(ctx, req)
	require.NoError(t, err)

	// Execute the request
	resp, err := http.DefaultClient.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	// Verify that the tenant placeholder was replaced
	assert.Equal(t, "/test-tenant-123/twirp/service", capturedURL)
}
