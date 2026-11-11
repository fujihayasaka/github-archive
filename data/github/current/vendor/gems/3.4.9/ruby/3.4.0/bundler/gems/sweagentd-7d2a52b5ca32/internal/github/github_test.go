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
	"time"

	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
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
	limiter := limiter.NewRateLimiterV1(&mockClient{}, 10, time.Minute*1)

	appLogin := "github-app-login"
	botLogin := "github-bot-login"

	app := &GitHubApp{
		ID:           123456,
		ClientID:     "client-id",
		ClientSecret: "",
		AppLogin:     appLogin,
		BotLogin:     botLogin,
		PrivateKey:   randomPrivateKey(t),
	}

	t.Run("urls", func(t *testing.T) {
		cf, err := NewClientFactory(obsv, ffClient, limiter, "https://api.github.com/", "", app, "", "", "", config.EnvironmentDevelopment)
		require.NoError(t, err)

		ghcf := cf.(*ClientFactory)

		require.Equal(t, "https://api.github.com/", ghcf.baseUrl.String())
		require.Equal(t, "https://api.github.com/", ghcf.baseInternalURL.String())
		require.Equal(t, "https://api.github.com/graphql", ghcf.graphqlUrl())

		// Test explicitly setting the internal base URL
		cf, err = NewClientFactory(obsv, ffClient, limiter, "https://api.github.com/", "https://internal-api.service.iad.github.net/", app, "", "", "", config.EnvironmentDevelopment)
		require.NoError(t, err)

		ghcf = cf.(*ClientFactory)

		require.Equal(t, "https://api.github.com/", ghcf.baseUrl.String())
		require.Equal(t, "https://internal-api.service.iad.github.net/", ghcf.baseInternalURL.String())
		require.Equal(t, "https://api.github.com/graphql", ghcf.graphqlUrl())
	})

	t.Run("url without ending slash", func(t *testing.T) {
		// Test an input URL that does not end with a slash
		cf, err := NewClientFactory(obsv, ffClient, limiter, "http://api.github.localhost", "", app, "", "", "", config.EnvironmentDevelopment)
		require.NoError(t, err)

		ghcf := cf.(*ClientFactory)
		require.Equal(t, "http://api.github.localhost/", ghcf.baseUrl.String())
		require.Equal(t, "http://api.github.localhost/", ghcf.baseInternalURL.String())
		require.Equal(t, "http://api.github.localhost/graphql", ghcf.graphqlUrl())
	})

	t.Run("user is copilot", func(t *testing.T) {
		cf, err := NewClientFactory(obsv, ffClient, limiter, "https://api.github.com/", "", app, "", "", "", config.EnvironmentDevelopment)
		require.NoError(t, err)

		gh := cf.NewClient("token")

		// Test a user that is not a copilot
		require.False(t, gh.UserIsCopilot("not-copilot"))

		// Test a user that is copilot
		require.True(t, gh.UserIsCopilot(appLogin))
		require.True(t, gh.UserIsCopilot(appLogin+"[bot]"))
		require.True(t, gh.UserIsCopilot(botLogin))
		require.True(t, gh.UserIsCopilot("Copilot"))
	})

	t.Run("key headers are set", func(t *testing.T) {
		tenantIdHeader := "tenant-id"
		tenantSlugHeader := "tenant-slug"
		requestIdHeader := "request-id"
		defaultToken := "token"

		svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, tenantIdHeader, r.Header.Get(headers.TenantID))
			require.Equal(t, tenantSlugHeader, r.Header.Get(headers.Tenant))
			require.Equal(t, requestIdHeader, r.Header.Get(headers.GitHubRequestID))

			authHeader := r.Header.Get("Authorization")
			if len(authHeader) == 0 {
				require.Fail(t, "Authorization header is empty")
			}
			tokenString := strings.Replace(authHeader, "Bearer ", "", 1)
			token, _, err := new(jwt.Parser).ParseUnverified(tokenString, jwt.MapClaims{})
			if err != nil {
				require.Equal(t, defaultToken, tokenString, "token validation failed for github client")
			} else if claims, ok := token.Claims.(jwt.MapClaims); ok {
				verified := claims.VerifyIssuer(strconv.FormatInt(app.ID, 10), true)
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

		cf, err := NewClientFactory(obsv, ffClient, limiter, svr.URL, "", app, "", "", "", config.EnvironmentDevelopment)
		require.NoError(t, err)

		// Verify client sends the headers
		gh := cf.NewClient(defaultToken)

		ctx := tokens.NewContext(context.Background())
		ctx = tenant.TenantIDContext(ctx, tenantIdHeader)
		ctx = tenant.TenantContext(ctx, tenantSlugHeader)
		ctx = requestid.WithGitHubRequestID(ctx, requestIdHeader)
		_, err = gh.CheckIfBranchExists(ctx, "owner", "repo", "branch")
		require.NoError(t, err)

		// Verify app client sends the headers
		ghApp, err := cf.NewClientFromRepo(ctx, 1, 1)
		require.NoError(t, err)

		_, err = ghApp.CheckIfBranchExists(ctx, "owner", "repo", "branch")
		require.NoError(t, err)
	})
}

func TestEnsureUniqueBranchName(t *testing.T) {
	ctx := context.Background()

	t.Run("returns base name when no conflict", func(t *testing.T) {
		noopClient := &NoopClient{
			MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
				return false, nil // No branch exists
			},
		}

		result, err := noopClient.EnsureUniqueBranchName(ctx, "owner", "repo", "fix-bug")
		require.NoError(t, err)
		require.Equal(t, "copilot/fix-bug", result)
	})

	t.Run("uses fun suffixes when conflicts exist", func(t *testing.T) {
		callCount := 0
		expectedNames := []string{
			"copilot/fix-bug",
			"copilot/fix-bug-again",
			"copilot/fix-bug-another-one",
			"copilot/fix-bug-yet-again",
			"copilot/fix-bug-one-more-time",
		}

		noopClient := &NoopClient{
			MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
				// Check that we're being called with expected names
				if callCount < len(expectedNames) {
					require.Equal(t, expectedNames[callCount], branchName)
				}
				callCount++
				// First 5 attempts return true (branch exists), 6th returns false
				return callCount <= 5, nil
			},
		}

		result, err := noopClient.EnsureUniqueBranchName(ctx, "owner", "repo", "fix-bug")
		require.NoError(t, err)
		require.Equal(t, "copilot/fix-bug-please-work", result)
		require.Equal(t, 6, callCount) // Should have tried 6 times total
	})

	t.Run("falls back to predictable suffix after max attempts", func(t *testing.T) {
		noopClient := &NoopClient{
			MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
				// Always return true (branch exists)
				return true, nil
			},
		}

		result, err := noopClient.EnsureUniqueBranchName(ctx, "owner", "repo", "fix-bug")
		require.NoError(t, err)
		// Should use fallback suffix for testing
		require.Equal(t, "copilot/fix-bug-fallback", result)
	})

	t.Run("returns base name when check errors", func(t *testing.T) {
		noopClient := &NoopClient{
			MockCheckIfBranchExists: func(ctx context.Context, ownerLogin, repoName, branchName string) (bool, error) {
				// Return an error checking if branch exists
				return false, fmt.Errorf("branch collision check failed")
			},
		}

		result, err := noopClient.EnsureUniqueBranchName(ctx, "owner", "repo", "fix-bug")
		require.NoError(t, err)
		// Should return the base name when we can't check if it exists
		require.Equal(t, "copilot/fix-bug", result)
	})
}

func randomPrivateKey(t *testing.T) *rsa.PrivateKey {
	// create a new random RSA key pair
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	return key
}
