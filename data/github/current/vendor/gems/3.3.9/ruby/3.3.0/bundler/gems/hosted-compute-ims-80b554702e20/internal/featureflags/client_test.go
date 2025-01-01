package featureflags

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestNewFeatureFlagClient(t *testing.T) {
	ctx := context.Background()
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)
	apiIsAvailableResponse, err := proto.Marshal(&twirpFeatures.CheckGlobalFeatureResponse{IsEnabled: false})
	require.NoError(t, err)

	t.Run("returns local client if api client is not configured and fallback to local is allowed", func(t *testing.T) {
		cfg := &Config{
			DotcomTwirpApiUrl:    "",
			DotcomTwirpApiHmac:   "",
			AllowFallbackToLocal: true,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
		require.NoError(t, err)
		require.IsType(t, &localClient{}, client)
	})

	t.Run("returns error if api is not configured and fallback to local is not allowed", func(t *testing.T) {
		cfg := &Config{
			DotcomTwirpApiUrl:    "",
			DotcomTwirpApiHmac:   "",
			AllowFallbackToLocal: false,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
		require.ErrorContains(t, err, "failed to initialize feature flag client because features API is not configured")
		require.Nil(t, client)
	})

	t.Run("returns error if api client is not fully configured", func(t *testing.T) {
		cfg := &Config{
			DotcomTwirpApiUrl:    "http://localhost/feature-flags",
			DotcomTwirpApiHmac:   "",
			AllowFallbackToLocal: false,
		}

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
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

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
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

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
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

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
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

		client, err := NewFeatureFlagsClient(ctx, cfg, logger)
		require.NoError(t, err)
		require.IsType(t, &localClient{}, client)
	})
}
