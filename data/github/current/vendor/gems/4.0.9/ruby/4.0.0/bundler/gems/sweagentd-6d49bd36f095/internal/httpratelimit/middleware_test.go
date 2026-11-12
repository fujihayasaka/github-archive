package httpratelimit

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	rlstore "github.com/github/go-ratelimit/store"
	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	chi "github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
}

func userCtx(t *testing.T, userID uint64) context.Context {
	t.Helper()
	ctx := requestctx.NewContext(context.Background())
	require.NoError(t, requestctx.AddUser(ctx, &requestctx.UserInfo{ID: userID, Login: "testuser"}))
	return ctx
}

func newTestRateLimiter(t *testing.T, reqPerMin int, flagEnabled bool) *RateLimiter {
	t.Helper()
	return New(
		reqPerMin,
		cache.NewMemoryCacheStore(),
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentHTTPRateLimit: flagEnabled,
		}),
	)
}

func TestMiddleware_AllowsRequestsUnderLimit(t *testing.T) {
	t.Parallel()

	rl := newTestRateLimiter(t, 5, true)
	handler := rl.Middleware(okHandler())
	ctx := userCtx(t, 1)

	for i := range 5 {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx)
		handler.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed", i+1)
	}
}

func TestMiddleware_BlocksExcessRequests(t *testing.T) {
	t.Parallel()

	rl := newTestRateLimiter(t, 3, true)
	handler := rl.Middleware(okHandler())
	ctx := userCtx(t, 2)

	// First 3 should pass
	for i := range 3 {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx)
		handler.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed", i+1)
	}

	// 4th should be rate limited
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx)
	handler.ServeHTTP(w, req)
	assert.Equal(t, http.StatusTooManyRequests, w.Code)
	assert.NotEmpty(t, w.Header().Get("Retry-After"))
	assert.NotEmpty(t, w.Header().Get("X-RateLimit-Limit"))
}

func TestMiddleware_FeatureFlagDisabledAllowsAll(t *testing.T) {
	t.Parallel()

	rl := newTestRateLimiter(t, 1, false) // flag disabled
	handler := rl.Middleware(okHandler())
	ctx := userCtx(t, 4)

	for i := range 10 {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx)
		handler.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed when flag disabled", i+1)
	}
}

func TestMiddleware_PerUserIsolation(t *testing.T) {
	t.Parallel()

	rl := newTestRateLimiter(t, 2, true)
	handler := rl.Middleware(okHandler())

	ctx1 := userCtx(t, 100)
	ctx2 := userCtx(t, 200)

	// User 1: exhaust limit
	for range 2 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx1))
		assert.Equal(t, http.StatusOK, w.Code)
	}

	// User 1: should be blocked
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx1))
	assert.Equal(t, http.StatusTooManyRequests, w.Code)

	// User 2: should still be allowed (independent bucket)
	for range 2 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx2))
		assert.Equal(t, http.StatusOK, w.Code)
	}
}

func TestMiddleware_NoUserAllowsThrough(t *testing.T) {
	t.Parallel()

	rl := newTestRateLimiter(t, 1, true)
	handler := rl.Middleware(okHandler())

	// Request with no user context
	ctx := requestctx.NewContext(context.Background())
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx))
	assert.Equal(t, http.StatusOK, w.Code, "requests without user should pass through")
}

func TestJobMiddleware_FeatureFlagDisabledAllowsAll(t *testing.T) {
	t.Parallel()

	rl := New(
		1,
		cache.NewMemoryCacheStore(),
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentHTTPTokensRateLimit: false,
		}),
	)
	handler := rl.JobMiddleware(okHandler())
	ctx := userCtx(t, 7)

	for i := range 3 {
		w := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/agent/jobs/job-123/tokens", http.NoBody).WithContext(ctx)
		req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, func() *chi.Context {
			rctx := chi.NewRouteContext()
			rctx.URLParams.Add("jobID", "job-123")
			return rctx
		}()))
		handler.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed when tokens flag disabled", i+1)
	}
}

func newTestJobRateLimiter(t *testing.T, reqPerMin int, flagEnabled bool) *RateLimiter {
	t.Helper()
	return New(
		reqPerMin,
		cache.NewMemoryCacheStore(),
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentHTTPTokensRateLimit: flagEnabled,
		}),
	)
}

func jobRequest(ctx context.Context, t *testing.T, jobID string) *http.Request {
	t.Helper()
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("jobID", jobID)
	ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)
	return httptest.NewRequest(http.MethodPost, "/agent/jobs/"+jobID+"/tokens", http.NoBody).WithContext(ctx)
}

func TestJobMiddleware_BlocksExcessRequests(t *testing.T) {
	t.Parallel()

	rl := newTestJobRateLimiter(t, 3, true)
	handler := rl.JobMiddleware(okHandler())
	ctx := userCtx(t, 10)

	// First 3 should pass
	for i := range 3 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, jobRequest(ctx, t, "job-abc"))
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed", i+1)
	}

	// 4th should be rate limited with proper headers
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, jobRequest(ctx, t, "job-abc"))
	assert.Equal(t, http.StatusTooManyRequests, w.Code)
	assert.NotEmpty(t, w.Header().Get("Retry-After"))
	assert.Equal(t, "3", w.Header().Get("X-RateLimit-Limit"))
}

func TestJobMiddleware_PerJobIsolation(t *testing.T) {
	t.Parallel()

	rl := newTestJobRateLimiter(t, 2, true)
	handler := rl.JobMiddleware(okHandler())
	ctx := userCtx(t, 11)

	// Exhaust limit for job-1
	for range 2 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, jobRequest(ctx, t, "job-1"))
		assert.Equal(t, http.StatusOK, w.Code)
	}

	// job-1 should be blocked
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, jobRequest(ctx, t, "job-1"))
	assert.Equal(t, http.StatusTooManyRequests, w.Code)

	// job-2 should still be allowed (independent bucket)
	for range 2 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, jobRequest(ctx, t, "job-2"))
		assert.Equal(t, http.StatusOK, w.Code)
	}
}

func TestJobMiddleware_MissingJobIDPassesThrough(t *testing.T) {
	t.Parallel()

	rl := newTestJobRateLimiter(t, 1, true)
	handler := rl.JobMiddleware(okHandler())
	ctx := userCtx(t, 12)

	// Request with empty jobID URL param
	req := httptest.NewRequest(http.MethodPost, "/agent/jobs//tokens", http.NoBody).WithContext(ctx)
	rctx := chi.NewRouteContext()
	// No jobID param added
	req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

	for i := range 5 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code, "request %d should pass through with no jobID", i+1)
	}
}

func TestJobMiddleware_FailOpen_BrokenCache(t *testing.T) {
	t.Parallel()

	rl := New(
		1,
		&brokenCache{},
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentHTTPTokensRateLimit: true,
		}),
	)
	handler := rl.JobMiddleware(okHandler())
	ctx := userCtx(t, 13)

	for i := range 5 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, jobRequest(ctx, t, "job-broken"))
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed via fail-open behavior", i+1)
	}
}

func TestMiddleware_FailOpen_BrokenCache(t *testing.T) {
	t.Parallel()

	rl := New(
		1,
		&brokenCache{},
		observability.NewNoopExporters(),
		featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentHTTPRateLimit: true,
		}),
	)
	handler := rl.Middleware(okHandler())
	ctx := userCtx(t, 5)

	// With best-effort Incr, a broken cache means the counter is never
	// incremented, so Get always returns 0 and all requests are allowed.
	for i := range 5 {
		w := httptest.NewRecorder()
		handler.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/models", http.NoBody).WithContext(ctx))
		assert.Equal(t, http.StatusOK, w.Code, "request %d should be allowed via fail-open behavior", i+1)
	}
}

func TestStoreAdapter_Get_MissingKeys(t *testing.T) {
	t.Parallel()

	store := newStoreAdapter(cache.NewMemoryCacheStore())
	vals, err := store.Get(context.Background(), []string{"missing1", "missing2"})
	require.NoError(t, err)
	assert.Equal(t, []int64{0, 0}, vals)
}

func TestStoreAdapter_IncrAndGet(t *testing.T) {
	t.Parallel()

	memCache := cache.NewMemoryCacheStore()
	store := newStoreAdapter(memCache)
	ctx := context.Background()

	err := store.Incr(ctx, []rlstore.KeysValue{
		{Keys: []rlstore.KeyExp{{Key: "test_key", Exp: time.Minute}}, Value: 5},
	})
	require.NoError(t, err)

	vals, err := store.Get(ctx, []string{"test_key"})
	require.NoError(t, err)
	assert.Equal(t, []int64{5}, vals)
}

// brokenCache always fails on Incr (for testing fail-open behavior).
type brokenCache struct{}

func (b *brokenCache) Get(key string) (string, bool)                           { return "", false }
func (b *brokenCache) Set(key, value string, ttl time.Duration)                {}
func (b *brokenCache) GetMultiple(keys []string) (map[string]string, bool)     { return nil, false }
func (b *brokenCache) SetMultiple(values map[string]string, ttl time.Duration) {}
func (b *brokenCache) Incr(key string, delta int64, ttl time.Duration) (int64, bool) {
	return 0, false
}
func (b *brokenCache) Decr(key string, delta int64, ttl time.Duration) (int64, bool) {
	return 0, false
}
func (b *brokenCache) Delete(key string) {}
