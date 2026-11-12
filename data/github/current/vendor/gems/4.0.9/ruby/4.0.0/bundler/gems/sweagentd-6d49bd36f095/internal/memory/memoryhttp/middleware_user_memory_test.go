package memoryhttp

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
)

// newUserMemoryCheckHandler builds a MemoryHandler with the given service +
// feature flags wired up so withUserMemoryCheck has all the dependencies it
// needs to run.
func newUserMemoryCheckHandler(
	t *testing.T,
	service *MockMemoryService,
	ffClient featureflags.Client,
) *MemoryHandler {
	t.Helper()
	return NewMemoryHandler(MemoryHandlerOpts{
		Service:           service,
		GHFactory:         &github.NoopClientFactory{},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
	})
}

// runUserRouteWithMiddleware mounts a sentinel handler behind
// withUserMemoryCheck and returns the recorded response.
func runUserRouteWithMiddleware(t *testing.T, handler *MemoryHandler, method, path string, sentinel http.HandlerFunc) *httptest.ResponseRecorder {
	t.Helper()
	r := chi.NewRouter()
	r.Route("/internal/memory/v0/user", func(r chi.Router) {
		r.Use(handler.withMemoryRequest())
		r.Group(func(r chi.Router) {
			r.Use(handler.withUserMemoryCheck())
			r.MethodFunc(method, path, sentinel)
		})
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, method, "/internal/memory/v0/user"+path, "")
	return executeRequestAndRecord(r, req)
}

// TestWithUserMemoryCheckPassesWhenEnabled verifies the middleware allows the
// downstream handler to run when CheckUserMemoryEnabled returns true.
func TestWithUserMemoryCheckPassesWhenEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckUserMemoryEnabledFunc: func(_ int64) (bool, error) { return true, nil },
	}
	handler := newUserMemoryCheckHandler(t, mockService, nil)

	called := false
	rr := runUserRouteWithMiddleware(t, handler, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.True(t, called, "downstream handler should run when user memory is enabled")
	assert.Equal(t, http.StatusNoContent, rr.Code)
}

// TestWithUserMemoryCheckBlocksWhenDisabled verifies the middleware returns
// 404 ErrFeatureNotEnabled when CheckUserMemoryEnabled returns (false, nil).
// Per github/agents#945, the user-affecting layers (Policy, user FFs) gate
// user-scope routes; the repo-admin layer does not.
func TestWithUserMemoryCheckBlocksWhenDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckUserMemoryEnabledFunc: func(_ int64) (bool, error) { return false, nil },
	}
	handler := newUserMemoryCheckHandler(t, mockService, nil)

	called := false
	rr := runUserRouteWithMiddleware(t, handler, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "downstream handler must not run when user memory is disabled")
	assert.Equal(t, http.StatusNotFound, rr.Code, "disabled user memory must return 404 ErrFeatureNotEnabled")
}

// TestWithUserMemoryCheck500OnServiceError verifies that an error from the
// chain (e.g. a Policy Twirp blip) returns 500 rather than silently
// allowing or silently 404ing the request.
func TestWithUserMemoryCheck500OnServiceError(t *testing.T) {
	mockService := &MockMemoryService{
		CheckUserMemoryEnabledFunc: func(_ int64) (bool, error) {
			return false, errors.New("policy lookup failed")
		},
	}
	handler := newUserMemoryCheckHandler(t, mockService, nil)

	called := false
	rr := runUserRouteWithMiddleware(t, handler, "GET", "/probe", func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusNoContent)
	})

	assert.False(t, called, "downstream handler must not run on chain error")
	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}
