package github

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"testing"

	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/golang-jwt/jwt/v4"
	"github.com/stretchr/testify/require"
)

func TestGitHubClient(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

	privateKey := randomPrivateKey(t)
	copilot := agenticapp.NewCopilot(0, privateKey, "github-app-login", 0, "github-bot-login", "commit-login", "commit@email.com", "client-id", "client-secret")
	appProvider := agenticapp.NewProvider(copilot, nil)

	t.Run("urls", func(t *testing.T) {
		ghcf, err := NewClientFactory(obsv, ffClient, limiter, "https://api.github.com/", "", "", config.EnvironmentDevelopment, appProvider)
		require.NoError(t, err)

		require.Equal(t, "https://api.github.com/", ghcf.baseURL.String())
		require.Equal(t, "https://api.github.com/", ghcf.baseInternalURL.String())
		require.Equal(t, "https://api.github.com/graphql", ghcf.graphqlURL())
		require.Equal(t, "https://api.github.com/graphql", ghcf.internalGraphqlURL())

		// Test explicitly setting the internal base URL
		ghcf, err = NewClientFactory(obsv, ffClient, limiter, "https://api.github.com/", "https://internal-api.service.iad.github.net/", "", config.EnvironmentDevelopment, appProvider)
		require.NoError(t, err)

		require.Equal(t, "https://api.github.com/", ghcf.baseURL.String())
		require.Equal(t, "https://internal-api.service.iad.github.net/", ghcf.baseInternalURL.String())
		require.Equal(t, "https://api.github.com/graphql", ghcf.graphqlURL())
		require.Equal(t, "https://internal-api.service.iad.github.net/graphql", ghcf.internalGraphqlURL())
	})

	t.Run("url without ending slash", func(t *testing.T) {
		// Test an input URL that does not end with a slash
		ghcf, err := NewClientFactory(obsv, ffClient, limiter, "http://api.github.localhost", "", "", config.EnvironmentDevelopment, appProvider)
		require.NoError(t, err)

		require.Equal(t, "http://api.github.localhost/", ghcf.baseURL.String())
		require.Equal(t, "http://api.github.localhost/", ghcf.baseInternalURL.String())
		require.Equal(t, "http://api.github.localhost/graphql", ghcf.graphqlURL())
	})

	t.Run("key headers are set", func(t *testing.T) {
		tenantIDHeader := "tenant-id"
		tenantSlugHeader := "tenant-slug"
		requestIDHeader := "request-id"
		defaultToken := "token"

		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, tenantIDHeader, r.Header.Get(headers.TenantID))
			require.Equal(t, tenantSlugHeader, r.Header.Get(headers.Tenant))
			require.Equal(t, requestIDHeader, r.Header.Get(headers.GitHubRequestID))

			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				require.Fail(t, "Authorization header is empty")
			}
			tokenString := strings.Replace(authHeader, "Bearer ", "", 1)
			token, _, err := new(jwt.Parser).ParseUnverified(tokenString, jwt.MapClaims{})
			if err != nil {
				require.Equal(t, defaultToken, tokenString, "token validation failed for github client")
			} else if claims, ok := token.Claims.(jwt.MapClaims); ok {
				verified := claims.VerifyIssuer(strconv.FormatInt(0, 10), true)
				require.True(t, verified, "token validation failed for github app client")
			} else {
				require.Fail(t, "failed to parse token claims")
			}

			// Make sure the GLBVia header is set too, see: https://github.com/github/go-http/blob/5760243997dbe5ff7e943def5dc8239cc6e3ac26/middleware/requestid/requestid.go#L95-L98
			host, err := os.Hostname()
			require.NoError(t, err)
			require.Contains(t, r.Header.Get(headers.GLBVia), fmt.Sprintf("hostname=%s t=", host))

			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			// Necessary mock for the app client
			resp := map[string]any{"Token": defaultToken}
			err = json.NewEncoder(w).Encode(resp)
			require.NoError(t, err)
		}))
		defer svr.Close()

		cf, err := NewClientFactory(obsv, ffClient, limiter, svr.URL, "", "", config.EnvironmentDevelopment, appProvider)
		require.NoError(t, err)

		ctx := tokens.NewContext(context.Background())
		ctx = tenant.TenantIDContext(ctx, tenantIDHeader)
		ctx = tenant.TenantContext(ctx, tenantSlugHeader)
		ctx = requestid.WithGitHubRequestID(ctx, requestIDHeader)

		// Verify client sends the headers
		gh, err := cf.NewClientFromRepo(ctx, copilot, 1, 1)
		require.NoError(t, err)
		_, err = gh.GetIssue(ctx, "owner", "repo", 1)
		require.NoError(t, err)

		// Verify app client sends the headers
		ghApp, err := cf.NewClientFromRepo(ctx, copilot, 1, 1)
		require.NoError(t, err)

		_, err = ghApp.GetIssue(ctx, "owner", "repo", 1)
		require.NoError(t, err)
	})
}

func randomPrivateKey(t *testing.T) *rsa.PrivateKey {
	// create a new random RSA key pair
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	return key
}
