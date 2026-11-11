package memoryhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newRoutedHandlerWithRepoAdmin builds a handler whose registered routes are
// gated by the memory enablement chain, with the repo-admin Twirp result
// configurable per-test.
func newRoutedHandlerWithRepoAdmin(t *testing.T, repoAdminDisabled bool) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) { return true, nil },
		// No-op write/read funcs so handlers don't panic past the middleware
		// in the "passes when enabled" assertion path.
		CreateMemoryFunc:    func(_ *core.Memory, _ *core.Repository) error { return nil },
		VoteOnMemoryFunc:    func(_ core.User, _ *core.Repository, _ string, _ *core.Vote) error { return nil },
		CountMemoriesFunc:   func(_ core.User, _ *core.Repository) (int, error) { return 0, nil },
		GetUserMemoriesFunc: func(_ core.User, _ core.UserMemoryQuery) ([]*core.Memory, error) { return []*core.Memory{}, nil },
	}
	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return repoAdminDisabled, nil
	}
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     twirp,
	})
	r := chi.NewRouter()
	r.Route("/internal", func(r chi.Router) {
		handler.RegisterAllMemoryRoutes(r)
	})
	return handler, r
}

// repoRouteCases enumerates every repo-scoped endpoint registered under
// /memory/v0/{owner}/{repo}/* so that disable-blocks-all and
// enabled-bypasses-block tests can assert on each route uniformly.
//
// /enabled is intentionally absent from this list — it is the JSON query
// endpoint that must NOT be wrapped by withRepoMemoryCheck.
type repoRouteCase struct {
	name   string
	method string
	path   string
	body   string
}

func gatedRepoRoutes() []repoRouteCase {
	return []repoRouteCase{
		{name: "create", method: http.MethodPut, path: "/internal/memory/v0/owner/repo/", body: `{"id":"x","subject":"s","fact":"f","reason":"r","citations":[],"source":{"interaction_id":"i","agent":"a"}}`},
		{name: "recent", method: http.MethodGet, path: "/internal/memory/v0/owner/repo/recent", body: ""},
		{name: "top", method: http.MethodGet, path: "/internal/memory/v0/owner/repo/top", body: ""},
		{name: "prompt", method: http.MethodGet, path: "/internal/memory/v0/owner/repo/prompt", body: ""},
		{name: "delete-one", method: http.MethodDelete, path: "/internal/memory/v0/owner/repo/abc", body: ""},
		{name: "delete-all", method: http.MethodDelete, path: "/internal/memory/v0/owner/repo/", body: ""},
		{name: "delete-batch", method: http.MethodPost, path: "/internal/memory/v0/owner/repo/delete", body: `{"ids":["abc"]}`},
		{name: "vote", method: http.MethodPost, path: "/internal/memory/v0/owner/repo/vote", body: `{"fact":"f","vote":"up"}`},
	}
}

// TestRegisterAllMemoryRoutes_GatedRoutesReturn404WhenDisabled asserts every
// repo-scoped, gated endpoint returns 404 when the repo admin has disabled
// memory, so callers cannot bypass the disable by hitting another endpoint.
func TestRegisterAllMemoryRoutes_GatedRoutesReturn404WhenDisabled(t *testing.T) {
	_, r := newRoutedHandlerWithRepoAdmin(t, true)

	for _, tc := range gatedRepoRoutes() {
		t.Run(tc.name, func(t *testing.T) {
			ctx := createTestContextWithToken()
			req := createTestRequest(ctx, tc.method, tc.path, tc.body)
			rr := executeRequestAndRecord(r, req)
			assert.Equal(t, http.StatusNotFound, rr.Code, "%s %s expected 404 when repo admin disabled memory", tc.method, tc.path)
		})
	}
}

// TestRegisterAllMemoryRoutes_GatedRoutesPassWhenEnabled asserts every
// repo-scoped, gated endpoint passes through the middleware (i.e. does not
// return 404 from the chain) when memory is enabled. We don't assert exact
// success codes per endpoint — handlers may fail later with 4xx for unrelated
// reasons (auth not in mock, etc.) — but a 404 from the middleware would mean
// the chain incorrectly blocked the request.
func TestRegisterAllMemoryRoutes_GatedRoutesPassWhenEnabled(t *testing.T) {
	_, r := newRoutedHandlerWithRepoAdmin(t, false)

	for _, tc := range gatedRepoRoutes() {
		t.Run(tc.name, func(t *testing.T) {
			ctx := createTestContextWithToken()
			req := createTestRequest(ctx, tc.method, tc.path, tc.body)
			rr := executeRequestAndRecord(r, req)
			assert.NotEqual(t, http.StatusNotFound, rr.Code,
				"%s %s should not be blocked by middleware (got %d)", tc.method, tc.path, rr.Code)
		})
	}
}

// TestRegisterAllMemoryRoutes_EnabledEndpointReturnsJSONWhenDisabled asserts
// the /enabled endpoint is NOT wrapped: when memory is disabled by the repo
// admin, /enabled must still return 200 with {"enabled": false} so clients
// can see the chain result rather than receive a 404.
func TestRegisterAllMemoryRoutes_EnabledEndpointReturnsJSONWhenDisabled(t *testing.T) {
	_, r := newRoutedHandlerWithRepoAdmin(t, true)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(r, req)

	require.Equal(t, http.StatusOK, rr.Code, "/enabled must return 200 even when memory is disabled")
	var resp MemoryEnablementResponse
	require.NoError(t, json.NewDecoder(rr.Body).Decode(&resp))
	assert.False(t, resp.Enabled, "/enabled must report enabled=false when repo admin disabled memory")
}

// TestRegisterAllMemoryRoutes_UserRoutesNotGatedByRepoMiddleware verifies
// user-scoped routes are not blocked by repo-admin opt-out: the repo-level
// setting only applies to repo-scoped memories.
func TestRegisterAllMemoryRoutes_UserRoutesNotGatedByRepoMiddleware(t *testing.T) {
	_, r := newRoutedHandlerWithRepoAdmin(t, true)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/internal/memory/v0/user/recent", "")
	rr := executeRequestAndRecord(r, req)

	// We don't assert 200 (the user handler may fail for other reasons in this
	// minimal mock setup) — only that the response is NOT a 404 originating
	// from the repo middleware.
	assert.NotEqual(t, http.StatusNotFound, rr.Code,
		"user route must not be blocked by repo middleware (got %d)", rr.Code)
}
