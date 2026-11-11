package memoryhttp

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newRepoMemoryCheckHandler builds a MemoryHandler with the given service +
// twirp + feature flags wired up so withRepoMemoryCheck has all the
// dependencies it needs to run.
func newRepoMemoryCheckHandler(
	t *testing.T,
	service *MockMemoryService,
	twirp *githubtwirp.NoopClient,
	ffClient featureflags.Client,
) *MemoryHandler {
	t.Helper()
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	return NewMemoryHandler(MemoryHandlerOpts{
		Service:           service,
		GHFactory:         mockGHFactory,
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
		GHTwirp:           twirp,
	})
}

// runRouteWithMiddleware mounts a sentinel handler behind withRepoMemoryCheck
// and returns the recorded response.
func runRouteWithMiddleware(t *testing.T, handler *MemoryHandler, perm permissionCheck, method, path string, sentinel http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	r := chi.NewRouter()
	r.Route("/internal/memory/v0/{owner}/{repo}", func(r chi.Router) {
		r.Use(handler.withMemoryRequest())
		r.Group(func(r chi.Router) {
			r.Use(handler.withRepoMemoryCheck(perm))
			r.MethodFunc(method, path, sentinel)
		})
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, method, "/internal/memory/v0/owner/repo"+path, "")
	return executeRequestAndRecord(r, req)
}

// TestWithRepoMemoryCheckPassesWhenEnabled verifies the middleware allows the
// downstream handler to run and stashes auth in ctx when memory is enabled.
func TestWithRepoMemoryCheckPassesWhenEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) { return true, nil },
	}
	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, nil
	}
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, nil)

	called := false
	rr := runRouteWithMiddleware(t, handler, readPermission, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		userInfo, repository, repoNWO, err := handler.requireRepoAuth(r.Context())
		require.NoError(t, err, "ctx must carry repo auth")
		require.NotNil(t, userInfo)
		require.NotNil(t, repository)
		require.NotNil(t, repoNWO)
		assert.Equal(t, "owner", repoNWO.Owner)
		assert.Equal(t, "repo", repoNWO.Repo)
		w.WriteHeader(http.StatusNoContent)
	})

	assert.True(t, called, "downstream handler should run when memory is enabled")
	assert.Equal(t, http.StatusNoContent, rr.Code)
}

// TestWithRepoMemoryCheckBlocksOnUserKillSwitch verifies the user-level kill
// switch short-circuits the middleware before any GitHub API call.
func TestWithRepoMemoryCheckBlocksOnUserKillSwitch(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			t.Fatal("service.CheckMemoryEnabled must not be called when user kill switch is on")
			return true, nil
		},
	}
	twirp := githubtwirp.NewNoopClient()

	ff := featureflags.NewNoopClient(map[string]bool{
		core.FeatureMemoryDisabled: true,
	})
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, ff)

	called := false
	rr := runRouteWithMiddleware(t, handler, readPermission, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "downstream handler must not run when user kill switch is active")
	assert.Equal(t, http.StatusNotFound, rr.Code, "kill switch should map to 404 ErrFeatureNotEnabled")
}

// TestWithRepoMemoryCheckBlocksOnRepoAdminDisabled verifies the middleware
// returns 404 when the repo admin has disabled memory.
func TestWithRepoMemoryCheckBlocksOnRepoAdminDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) { return true, nil },
	}
	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return true, nil // repo admin disabled
	}
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, nil)

	called := false
	rr := runRouteWithMiddleware(t, handler, readPermission, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "downstream handler must not run when repo admin disabled memory")
	assert.Equal(t, http.StatusNotFound, rr.Code, "repo-admin disabled should map to 404 ErrFeatureNotEnabled")
}

// TestWithRepoMemoryCheckBlocksOnServiceFalse verifies that when the service
// chain (Policy + repo/owner FF) returns disabled, the middleware blocks
// the request with 404.
func TestWithRepoMemoryCheckBlocksOnServiceFalse(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return false, nil
		},
	}
	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		t.Fatal("repo-admin check must not run when service already says disabled")
		return false, nil
	}
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, nil)

	called := false
	rr := runRouteWithMiddleware(t, handler, readPermission, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "downstream handler must not run when service says disabled")
	assert.Equal(t, http.StatusNotFound, rr.Code)
}

// TestWithRepoMemoryCheckFailOpenOnRepoAdminError verifies that read routes
// stay enabled when the repo-admin Twirp call fails (fail-open), so a
// transient Dotcom outage doesn't break memory reads across all repos.
// Writes get the opposite treatment — see
// TestWithRepoMemoryCheckFailClosedOnRepoAdminErrorForWrites.
func TestWithRepoMemoryCheckFailOpenOnRepoAdminError(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) { return true, nil },
	}
	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, errors.New("dotcom unreachable")
	}
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, nil)

	called := false
	rr := runRouteWithMiddleware(t, handler, readPermission, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.True(t, called, "downstream handler should run when repo-admin check errors (fail-open)")
	assert.Equal(t, http.StatusNoContent, rr.Code)
}

// TestWithRepoMemoryCheckFailClosedOnRepoAdminErrorForWrites verifies that
// write routes return 500 (not silently allowed through) when the repo-admin
// Twirp call fails. Writes are exactly what the opt-out is meant to prevent,
// so a brief 500 blast is preferable to silently writing memories to a
// possibly-opted-out repo during a Dotcom blip.
func TestWithRepoMemoryCheckFailClosedOnRepoAdminErrorForWrites(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) { return true, nil },
	}
	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, errors.New("dotcom unreachable")
	}
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, nil)

	called := false
	rr := runRouteWithMiddleware(t, handler, writePermission, "POST", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "write handler must not run when repo-admin check errors (fail-closed)")
	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}

// TestWithRepoMemoryCheck500OnServiceError verifies that errors from the
// service-level chain (Policy/FF) are surfaced as 500s — those represent
// harder upstream failures that should not be silently treated as enabled.
func TestWithRepoMemoryCheck500OnServiceError(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return false, errors.New("policy lookup failed")
		},
	}
	twirp := githubtwirp.NewNoopClient()
	handler := newRepoMemoryCheckHandler(t, mockService, twirp, nil)

	called := false
	rr := runRouteWithMiddleware(t, handler, readPermission, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "downstream handler must not run on service chain error")
	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}

// TestRequireRepoAuthMissing verifies the defensive helper returns an error
// when ctx does not carry repo auth (i.e. handler was wired without the
// middleware), so a misconfiguration is loud rather than silent.
func TestRequireRepoAuthMissing(t *testing.T) {
	handler := newRepoMemoryCheckHandler(t, &MockMemoryService{}, githubtwirp.NewNoopClient(), nil)
	_, _, _, err := handler.requireRepoAuth(context.Background())
	require.Error(t, err, "requireRepoAuth must error when middleware did not run")
}
