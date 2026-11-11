package github

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"strings"
	"sync/atomic"
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
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/golang-jwt/jwt/v4"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestGitHubClient(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	limiter := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))

	copilot := agenticapp.NewCopilot(0, "github-app-login", 0, "github-bot-login", "commit-login", "commit@email.com")
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

		cf, err := NewClientFactory(obsv, ffClient, limiter, svr.URL, "", "", config.EnvironmentDevelopment, appProvider, WithTwirpClient(newNoopTwirpClientWithToken(defaultToken)))
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

	t.Run("token refresh updates REST auth and client token", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentClientTokenRefreshOn401: true,
		})

		var oldTokenRequests int32
		var newTokenRequests int32
		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			auth := r.Header.Get("Authorization")
			switch auth {
			case "Bearer old-token":
				atomic.AddInt32(&oldTokenRequests, 1)
				w.WriteHeader(http.StatusUnauthorized)
			case "Bearer new-token":
				atomic.AddInt32(&newTokenRequests, 1)
				w.Header().Set("Content-Type", "application/json")
				_, err := w.Write([]byte(`{}`))
				require.NoError(t, err)
			default:
				t.Fatalf("unexpected auth header: %q", auth)
			}
		}))
		defer svr.Close()

		cf, err := NewClientFactory(
			obsv,
			ffClient,
			limiter,
			svr.URL,
			"",
			"",
			config.EnvironmentDevelopment,
			appProvider,
			WithTwirpClient(newNoopTwirpClientWithTokenSequence("old-token", "new-token")),
		)
		require.NoError(t, err)

		ctx := tokens.NewContext(context.Background())
		gh, err := cf.NewClientFromRepo(ctx, copilot, 1, 1)
		require.NoError(t, err)

		_, err = gh.GetIssue(ctx, "owner", "repo", 1)
		require.NoError(t, err)

		_, err = gh.GetIssue(ctx, "owner", "repo", 2)
		require.NoError(t, err)

		require.Equal(t, int32(1), atomic.LoadInt32(&oldTokenRequests))
		require.Equal(t, int32(2), atomic.LoadInt32(&newTokenRequests))
		require.Equal(t, "new-token", gh.Token())
	})
}

func newNoopTwirpClientWithToken(token string) githubtwirp.ClientInterface {
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.MockMintServerToServerTokenForRepo = func(_ context.Context, _ *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
		return &sweagentdTwirp.MintServerToServerTokenForRepoResponse{
			Token: token,
		}, nil
	}
	return noopClient
}

func newNoopTwirpClientWithTokenSequence(tokensByCall ...string) githubtwirp.ClientInterface {
	noopClient := githubtwirp.NewNoopClient()
	if len(tokensByCall) == 0 {
		tokensByCall = []string{""}
	}
	callCount := 0
	noopClient.NoopSweagentdAPI.MockMintServerToServerTokenForRepo = func(_ context.Context, _ *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
		var token string
		if callCount < len(tokensByCall) {
			token = tokensByCall[callCount]
		} else {
			token = tokensByCall[len(tokensByCall)-1]
		}
		callCount++
		return &sweagentdTwirp.MintServerToServerTokenForRepoResponse{
			Token: token,
		}, nil
	}
	return noopClient
}

func newNoopTwirpClientWithNotFoundError() githubtwirp.ClientInterface {
	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.MockMintServerToServerTokenForRepo = func(_ context.Context, _ *sweagentdTwirp.MintServerToServerTokenForRepoRequest) (*sweagentdTwirp.MintServerToServerTokenForRepoResponse, error) {
		return nil, twirp.NotFoundError("repository not found")
	}
	return noopClient
}

func TestClientFactory_NotFoundErrorPropagation(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	limiterClient := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	copilot := agenticapp.NewCopilot(0, "github-app-login", 0, "github-bot-login", "commit-login", "commit@email.com")
	appProvider := agenticapp.NewProvider(copilot, nil)

	cf, err := NewClientFactory(
		obsv,
		ffClient,
		limiterClient,
		"https://api.github.com/",
		"",
		"",
		config.EnvironmentDevelopment,
		appProvider,
		WithTwirpClient(newNoopTwirpClientWithNotFoundError()),
	)
	require.NoError(t, err)

	ctx := tokens.NewContext(context.Background())

	t.Run("NewClientFromRepo returns not_found", func(t *testing.T) {
		_, err := cf.NewClientFromRepo(ctx, copilot, 1, 1)
		require.Error(t, err)

		twerr, ok := err.(twirp.Error)
		require.True(t, ok, "expected top-level twirp error")
		require.Equal(t, twirp.NotFound, twerr.Code())
	})

	t.Run("NewClientForRepo returns not_found", func(t *testing.T) {
		_, err := cf.NewClientForRepo(ctx, copilot, &testRepository{repoID: 1, ownerID: 1})
		require.Error(t, err)

		twerr, ok := err.(twirp.Error)
		require.True(t, ok, "expected top-level twirp error")
		require.Equal(t, twirp.NotFound, twerr.Code())
	})
}

// testRepository is a minimal sweagentd.Repository implementation for testing.
type testRepository struct {
	repoID  int64
	ownerID int64
}

func (r *testRepository) GetRepositoryID() int64 { return r.repoID }
func (r *testRepository) GetOwnerID() int64      { return r.ownerID }
