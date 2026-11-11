package featureflags

import (
	"context"
	"testing"

	"net/http"

	"github.com/github/feature-management-client-go/vexi/v2"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/require"
)

type testClient struct {
	ff map[string]bool
}

// IsEnabled implements Client.
func (t *testClient) IsEnabled(ctx context.Context, featureFlagName string, actors ...vexi.Actor) bool {
	return t.ff[featureFlagName]
}
func (t *testClient) IsEnabledForUser(ctx context.Context, featureFlagName string, userID int64) bool {
	return t.IsEnabled(ctx, featureFlagName)
}

func (t *testClient) IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool {
	return t.IsEnabled(ctx, featureFlagName)
}
func (t *testClient) IsEnabledForUserOrRepo(ctx context.Context, featureFlagName string, userID, repoID int64) bool {
	return t.IsEnabled(ctx, featureFlagName)
}
func (t *testClient) IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.Repository) bool {
	return t.IsEnabled(ctx, featureFlagName)
}
func (t *testClient) IsEnabledForUserOrRepoOrOwner(ctx context.Context, featureFlagName string, actors sweagentd.RepositoryWithActor) bool {
	return t.IsEnabled(ctx, featureFlagName)
}

func (t *testClient) IsEnabledForGitHubApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return t.IsEnabled(ctx, featureFlagName)
}

func (t *testClient) IsEnabledForOAuthApp(ctx context.Context, featureFlagName string, appID int64) bool {
	return t.IsEnabled(ctx, featureFlagName)
}

var _ Client = &testClient{}

func Test_CachingMiddleware(t *testing.T) {
	var testfeature = "test-feature"
	obsv := observability.NewNoopExporters()

	tc := &testClient{
		ff: make(map[string]bool),
	}
	cachingClient := NewCachingClient(tc, obsv)

	r := chi.NewRouter()
	r.Use(cachingClient.Middleware)

	// Start with disabled feature
	tc.ff[testfeature] = false

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		require.False(t, cachingClient.IsEnabled(r.Context(), testfeature))

		// Enable ff
		tc.ff[testfeature] = true

		// Should still be false
		require.False(t, cachingClient.IsEnabled(r.Context(), testfeature))

		w.WriteHeader(http.StatusOK)
	})

	r.Get("/second", func(w http.ResponseWriter, r *http.Request) {
		// Next request sees it as enabled
		require.True(t, cachingClient.IsEnabled(r.Context(), testfeature))

		w.WriteHeader(http.StatusOK)
	})

	require.HTTPSuccess(t, r.ServeHTTP, http.MethodGet, "/", nil)

	require.HTTPSuccess(t, r.ServeHTTP, http.MethodGet, "/second", nil)
}

func Test_Caching_IsEnabledMiddleware(t *testing.T) {
	var testfeature = "test-feature"
	obsv := observability.NewNoopExporters()

	tc := &testClient{
		ff: make(map[string]bool),
	}
	cachingClient := NewCachingClient(tc, obsv)

	r := chi.NewRouter()
	// Artificially log in the user, by adding the auth data to the request context
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := requestctx.AddData(r.Context(), &requestctx.CtxData{UserInfo: &requestctx.UserInfo{ID: 123, Login: "test", TrackingID: "tracking-id"}})
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	})
	r.Use(cachingClient.Middleware)
	r.Use(cachingClient.IsEnabledMiddleware(testfeature))

	// Start with disabled feature
	tc.ff[testfeature] = false

	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	// 404s with feature flag disabled
	require.HTTPStatusCode(t, r.ServeHTTP, http.MethodGet, "/", nil, http.StatusNotFound)

	// 200s with feature flag enabled
	tc.ff[testfeature] = true
	require.HTTPSuccess(t, r.ServeHTTP, http.MethodGet, "/", nil)
}
