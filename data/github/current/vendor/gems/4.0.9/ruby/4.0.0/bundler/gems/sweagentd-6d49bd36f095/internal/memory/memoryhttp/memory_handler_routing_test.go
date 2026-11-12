package memoryhttp

import (
	"net/http"
	"sync/atomic"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
)

// TestCombinedRouting verifies that when both repo-scoped and user-scoped routes
// are registered on the same router (as in production), chi correctly disambiguates
// /memory/v0/user/... from /memory/v0/{owner}/{repo}/....
// This prevents the literal "user" segment from being captured by the {owner} wildcard.
func TestCombinedRouting(t *testing.T) {
	var userHandlerCalled atomic.Bool
	var repoHandlerCalled atomic.Bool

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			userHandlerCalled.Store(true)
			return []*core.Memory{}, nil
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			repoHandlerCalled.Store(true)
			return []*core.Memory{}, nil
		},
	}

	// createTestHandlerAndRouterWithInternal only registers repo routes, so we
	// need a combined router instead.
	handler, _ := createTestHandlerAndRouterWithInternal(t, mockService)
	router := createTestCombinedRouter(handler)

	ctx := createTestContext()

	t.Run("user route is routed to user handler", func(t *testing.T) {
		userHandlerCalled.Store(false)
		repoHandlerCalled.Store(false)

		req := createTestRequest(ctx, "GET", "/internal/memory/v0/user/recent", "")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)
		assert.True(t, userHandlerCalled.Load(), "expected user handler to be called")
		assert.False(t, repoHandlerCalled.Load(), "expected repo handler NOT to be called")
	})

	t.Run("repo route is routed to repo handler", func(t *testing.T) {
		userHandlerCalled.Store(false)
		repoHandlerCalled.Store(false)

		req := createTestRequest(ctx, "GET", "/internal/memory/v0/myorg/myrepo/recent", "")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)
		assert.False(t, userHandlerCalled.Load(), "expected user handler NOT to be called")
		assert.True(t, repoHandlerCalled.Load(), "expected repo handler to be called")
	})
}

// TestCombinedRoutingAllUserEndpoints verifies that each user-scoped endpoint
// is reachable when both route groups are registered together.
func TestCombinedRoutingAllUserEndpoints(t *testing.T) {
	mockService := &MockMemoryService{}
	handler, _ := createTestHandlerAndRouterWithInternal(t, mockService)
	router := createTestCombinedRouter(handler)
	ctx := createTestContext()

	endpoints := []struct {
		method string
		path   string
	}{
		{"PUT", "/internal/memory/v0/user/"},
		{"GET", "/internal/memory/v0/user/recent"},
		{"GET", "/internal/memory/v0/user/top"},
		{"DELETE", "/internal/memory/v0/user/mem123"},
		{"DELETE", "/internal/memory/v0/user/"},
		{"POST", "/internal/memory/v0/user/delete"},
		{"POST", "/internal/memory/v0/user/vote"},
		{"GET", "/internal/memory/v0/user/enabled"},
	}

	for _, ep := range endpoints {
		t.Run(ep.method+" "+ep.path, func(t *testing.T) {
			req := createTestRequest(ctx, ep.method, ep.path, "{}")
			rr := executeRequestAndRecord(router, req)
			// Any status other than 404/405 means the route was matched.
			assert.NotEqual(t, http.StatusNotFound, rr.Code, "route should be registered")
			assert.NotEqual(t, http.StatusMethodNotAllowed, rr.Code, "method should be allowed")
		})
	}
}

// TestUserLiteralNotCapturedAsOwner verifies that a request to /memory/v0/user/...
// is NOT matched by the repo-scoped {owner}/{repo} wildcard pattern.
func TestUserLiteralNotCapturedAsOwner(t *testing.T) {
	var repoHandlerCalled atomic.Bool

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			repoHandlerCalled.Store(true)
			return []*core.Memory{}, nil
		},
	}

	handler, _ := createTestHandlerAndRouterWithInternal(t, mockService)
	router := createTestCombinedRouter(handler)
	ctx := createTestContext()

	// "user" should match the literal /user/ route, not {owner}/{repo}
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/user/recent", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.False(t, repoHandlerCalled.Load(),
		"repo handler must not be called when path starts with /memory/v0/user/")
}
