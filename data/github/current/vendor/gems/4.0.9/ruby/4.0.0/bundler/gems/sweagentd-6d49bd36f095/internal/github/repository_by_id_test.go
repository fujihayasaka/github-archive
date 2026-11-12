package github

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
)

func TestGetRepositoryByID_MemoizesPerRequestContext(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	limiterClient := limiter.NewCacheRateLimiter(&mockClient{}, observability.NewNoopExporters(), cache.NewMemoryCacheStore(), agenticapptest.NewTestProvider(t))
	copilot := agenticapp.NewCopilot(0, "github-app-login", 0, "github-bot-login", "commit-login", "commit@email.com")
	appProvider := agenticapp.NewProvider(copilot, nil)

	var calls int32
	svr := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/repositories/") {
			atomic.AddInt32(&calls, 1)
			w.Header().Add("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			require.NoError(t, json.NewEncoder(w).Encode(map[string]any{"id": 42, "name": "hello"}))
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	defer svr.Close()

	cf, err := NewClientFactory(obsv, ffClient, limiterClient, svr.URL, "", "", config.EnvironmentDevelopment, appProvider, WithTwirpClient(newNoopTwirpClientWithToken("token")))
	require.NoError(t, err)

	ctx := requestctx.NewContext(tokens.NewContext(context.Background()))
	gh, err := cf.NewClientFromRepo(ctx, copilot, 1, 1)
	require.NoError(t, err)

	repo1, err := gh.GetRepositoryByID(ctx, 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), repo1.GetID())
	require.Equal(t, int32(1), atomic.LoadInt32(&calls))

	// Second call within the same context should be served from the cache.
	repo2, err := gh.GetRepositoryByID(ctx, 42)
	require.NoError(t, err)
	require.Same(t, repo1, repo2)
	require.Equal(t, int32(1), atomic.LoadInt32(&calls), "expected GetRepositoryByID to be memoized on second call within the same context")

	// A fresh context should NOT be served from the previous cache.
	freshCtx := requestctx.NewContext(tokens.NewContext(context.Background()))
	_, err = gh.GetRepositoryByID(freshCtx, 42)
	require.NoError(t, err)
	require.Equal(t, int32(2), atomic.LoadInt32(&calls), "expected GetRepositoryByID to refetch when called in a fresh request context")
}
