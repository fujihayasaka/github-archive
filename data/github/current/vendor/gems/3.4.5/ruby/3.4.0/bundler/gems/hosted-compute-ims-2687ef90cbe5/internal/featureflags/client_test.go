package featureflags

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestNewFeatureFlagClient(t *testing.T) {
	ctx := context.Background()
	apiIsAvailableResponse, err := proto.Marshal(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false})
	require.NoError(t, err)

	t.Run("returns local client if api client is not configured and fallback to local is allowed", func(t *testing.T) {
		cfg := &Config{
			DotcomTwirpApiUrl:    "",
			DotcomTwirpApiHmac:   "",
			AllowFallbackToLocal: true,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.NoError(t, err)
		require.IsType(t, &localClient{}, client)
	})

	t.Run("returns error if api is not configured and fallback to local is not allowed", func(t *testing.T) {
		cfg := &Config{
			DotcomTwirpApiUrl:    "",
			DotcomTwirpApiHmac:   "",
			AllowFallbackToLocal: false,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.ErrorContains(t, err, "failed to initialize feature flag client because features API is not configured")
		require.Nil(t, client)
	})

	t.Run("returns error if api client is not fully configured", func(t *testing.T) {
		cfg := &Config{
			DotcomTwirpApiUrl:    "http://localhost/feature-flags",
			DotcomTwirpApiHmac:   "",
			AllowFallbackToLocal: false,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.ErrorContains(t, err, "secret is required")
		require.Nil(t, client)
	})

	t.Run("returns api client if api client is available and fallback to local is not allowed", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(apiIsAvailableResponse)
		}))
		defer server.Close()

		cfg := &Config{
			DotcomTwirpApiUrl:    server.URL,
			DotcomTwirpApiHmac:   "hmac",
			AllowFallbackToLocal: false,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.NoError(t, err)
		require.IsType(t, &apiClient{}, client)
	})

	t.Run("returns api client if api client is available and fallback to local is allowed", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(apiIsAvailableResponse)
		}))
		defer server.Close()

		cfg := &Config{
			DotcomTwirpApiUrl:    server.URL,
			DotcomTwirpApiHmac:   "hmac",
			AllowFallbackToLocal: true,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.NoError(t, err)
		require.IsType(t, &apiClient{}, client)
	})

	t.Run("returns api client if api client is not available and fallback to local is not allowed", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusNotFound)
		}))
		defer server.Close()

		cfg := &Config{
			DotcomTwirpApiUrl:    server.URL,
			DotcomTwirpApiHmac:   "hmac",
			AllowFallbackToLocal: false,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.NoError(t, err)
		require.IsType(t, &apiClient{}, client)
	})

	t.Run("returns local client if api client is not available and fallback to local is allowed", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusNotFound)
		}))
		defer server.Close()

		cfg := &Config{
			DotcomTwirpApiUrl:    server.URL,
			DotcomTwirpApiHmac:   "hmac",
			AllowFallbackToLocal: true,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, "")
		require.NoError(t, err)
		require.IsType(t, &localClient{}, client)
	})
}

func TestConfig_GetTwirpApiUrlForStamp(t *testing.T) {
	config := &Config{DotcomTwirpApiUrl: "https://internal-api.service.{{stamp}}.github.net/internal"}
	tests := []struct {
		Stamp       string
		ExpectedUrl string
	}{
		{
			Stamp:       "prod-weu-01",
			ExpectedUrl: "https://internal-api.service.prod-weu-01.github.net/internal",
		},
		{
			Stamp:       "staff-wus2-01",
			ExpectedUrl: "https://internal-api.service.staff-wus2-01.github.net/internal",
		},
		{
			Stamp:       "prod-sdc-01",
			ExpectedUrl: "https://internal-api.service.prod-sdc-01.github.net/internal",
		},
		{
			Stamp:       "dotcom",
			ExpectedUrl: "https://internal-api.service.iad.github.net/internal",
		},
	}
	for _, test := range tests {
		t.Run(fmt.Sprintf("env %s", test.Stamp), func(t *testing.T) {
			assert.Equal(t, test.ExpectedUrl, config.GetTwirpApiUrlForStamp(test.Stamp))
		})
	}
}
