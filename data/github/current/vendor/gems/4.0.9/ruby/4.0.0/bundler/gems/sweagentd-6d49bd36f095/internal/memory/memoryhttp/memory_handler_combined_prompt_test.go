package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
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

type mockBillingEntityResolver struct {
	resolveFunc func(ctx context.Context, userID int64) (core.BillingEntity, error)
}

func (m *mockBillingEntityResolver) ResolveBillingEntity(ctx context.Context, userID int64) (core.BillingEntity, error) {
	return m.resolveFunc(ctx, userID)
}

func defaultCombinedHandlerOpts(t *testing.T, mockService *MockMemoryService) MemoryHandlerOpts {
	t.Helper()
	return MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemory: true,
		}),
		GHTwirp: githubtwirp.NewNoopClient(),
	}
}

// createTestCombinedHandlerAndRouter creates a handler with a combined-routes router.
// The default opts enable user-scoped memory with a noop GHTwirp client.
func createTestCombinedHandlerAndRouter(t *testing.T, mockService *MockMemoryService, opts ...MemoryHandlerOpts) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	var handlerOpts MemoryHandlerOpts
	if len(opts) > 0 {
		handlerOpts = opts[0]
	} else {
		handlerOpts = defaultCombinedHandlerOpts(t, mockService)
	}
	handler := NewMemoryHandler(handlerOpts)
	r := chi.NewRouter()
	handler.RegisterCombinedRoutes(r)
	return handler, r
}

func TestHandleGetCombinedPromptBothScopes(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.User{ID: 1, Login: "testuser"}, user)
			assert.Equal(t, core.RepoNWO{Owner: "test", Repo: "repo"}, repository.NWO)
			return repoMemories, nil
		},
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			assert.Equal(t, core.User{ID: 1, Login: "testuser"}, user)
			return userMemories, nil
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Equal(t, "application/json", rr.Header().Get("Content-Type"))

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	// Combined prompt should have both sections
	assert.Contains(t, result.MemoriesContext.Prompt, "Repository memories for `test/repo`")
	assert.Contains(t, result.MemoriesContext.Prompt, "Use vitest")
	assert.Contains(t, result.MemoriesContext.Prompt, "User memories for @")
	assert.Contains(t, result.MemoriesContext.Prompt, "Use dark theme")
	assertMemoryDeletionManualGuidance(t, result.MemoriesContext.Prompt)

	// Counts
	assert.Equal(t, 2, result.MemoriesContext.MemoriesCount)
	require.NotNil(t, result.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.RepoMemoriesCount)
	require.NotNil(t, result.MemoriesContext.UserMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.UserMemoriesCount)

	// Tool definitions — uses user-scoped description since default helper enables user-scoped memory
	expectedDescription, err := resolveStoreToolDescription(true)
	require.NoError(t, err)
	assert.Equal(t, storeMemoryToolName, result.StoreToolDefinition.Name)
	assert.Equal(t, expectedDescription, result.StoreToolDefinition.Description)
	assert.Nil(t, result.VoteToolDefinition)
}

func TestHandleGetCombinedPromptUserOnly(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	// No repo param — user-only
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.NotContains(t, result.MemoriesContext.Prompt, "Repository memories")
	assert.Contains(t, result.MemoriesContext.Prompt, "User memories for @")
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
	// No repo was requested — RepoMemoriesCount should be absent (nil), not 0.
	assert.Nil(t, result.MemoriesContext.RepoMemoriesCount)
	require.NotNil(t, result.MemoriesContext.UserMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.UserMemoriesCount)

	// Verify the JSON omits repoMemoriesCount entirely.
	assert.NotContains(t, rr.Body.String(), `"repoMemoriesCount"`)
}

func TestHandleGetCombinedPromptNoMemories(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.Empty(t, result.MemoriesContext.Prompt)
	assert.Equal(t, 0, result.MemoriesContext.MemoriesCount)
}

func TestHandleGetCombinedPromptInvalidRepoParam(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=invalid", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
}

func TestHandleGetCombinedPromptUnauthenticated(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	// Empty context — no user info
	req := createTestRequest(context.Background(), "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
}

func TestHandleGetCombinedPromptRepoAuthorizationFailure(t *testing.T) {
	mockService := &MockMemoryService{}

	// GitHub factory returns error — simulates app not installed / no access
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("installation not found for repository")
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})

	// Use a context without a token so the user-token fallback also fails,
	// ensuring the authorization error is surfaced.
	ctx := createTestContextWithoutToken()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), http.StatusText(http.StatusNotFound))
}

func TestHandleGetCombinedPromptGracefulDegradationUserError(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound // Simulate unexpected error
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	// Should still contain repo memories
	assert.Contains(t, result.MemoriesContext.Prompt, "Use vitest")
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
}

func TestHandleGetCombinedPromptGracefulDegradationRepoError(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound // Simulate unexpected error
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	// Should still contain user memories
	assert.Contains(t, result.MemoriesContext.Prompt, "Use dark theme")
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
}

func TestHandleGetCombinedPromptWithLimit(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			assert.Equal(t, uint(5), limit)
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?limit=5", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetCombinedPromptWithVoting(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
		GetTopUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assertVoteToolDefinition(t, result.VoteToolDefinition)
	assertMemoryDeletionVotingGuidance(t, result.MemoriesContext.Prompt)
	assert.Equal(t, combinedMemoriesContextPromptVersionWithVoting, result.MemoriesContext.PromptVersion)
}

func TestHandleGetCombinedPromptRouteRegistration(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})

	// Test that the combined route works alongside existing routes (production-like setup)
	r := chi.NewRouter()
	r.Route("/internal", func(r chi.Router) {
		handler.RegisterRepoRoutes(r)
		handler.RegisterUserRoutes(r)
		r.Get("/memory/v0/prompt", handler.HandleGetCombinedPrompt)
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(r, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetCombinedPromptPerScopeCountsInJSON(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
		{ID: "r2", Subject: "style", Fact: "Use tabs", Citations: []string{".editorconfig:2"}},
	}
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	// Parse raw JSON to verify per-scope fields are present
	var rawJSON map[string]any
	err := json.Unmarshal(rr.Body.Bytes(), &rawJSON)
	require.NoError(t, err)

	memoriesCtx, ok := rawJSON["memoriesContext"].(map[string]any)
	require.True(t, ok)

	assert.InDelta(t, float64(3), memoriesCtx["memoriesCount"], 0)
	assert.InDelta(t, float64(2), memoriesCtx["repoMemoriesCount"], 0)
	assert.InDelta(t, float64(1), memoriesCtx["userMemoriesCount"], 0)
}

func TestHandleGetCombinedPromptExistingEndpointsOmitPerScopeCounts(t *testing.T) {
	// Verify that existing endpoints don't include per-scope counts (backward compatibility).
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return []*core.Memory{{ID: "1", Subject: "s", Fact: "f", Citations: []string{}}}, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	rr := executeRequestAndRecord(router, req)

	require.Equal(t, http.StatusOK, rr.Code)

	var rawJSON map[string]any
	err := json.Unmarshal(rr.Body.Bytes(), &rawJSON)
	require.NoError(t, err)

	memoriesCtx, ok := rawJSON["memoriesContext"].(map[string]any)
	require.True(t, ok)

	// Existing endpoints should NOT include per-scope counts
	_, hasRepo := memoriesCtx["repoMemoriesCount"]
	_, hasUser := memoriesCtx["userMemoriesCount"]
	assert.False(t, hasRepo, "existing endpoint should not include repoMemoriesCount")
	assert.False(t, hasUser, "existing endpoint should not include userMemoriesCount")
}

func TestHandleGetCombinedPromptBothFetchesFail(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	// When all scopes fail, propagate the error via handleDomainError.
	// ErrRepositoryNotFound maps to 404.
	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleGetCombinedPromptBillingFailureNoRepo500(t *testing.T) {
	mockService := &MockMemoryService{}

	handlerOpts := defaultCombinedHandlerOpts(t, mockService)
	handlerOpts.FeatureFlagClient = featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory:               true,
		core.FeatureMemoryBillingEnforcedRetrieval: true,
	})
	handlerOpts.BillingEntityResolver = &mockBillingEntityResolver{
		resolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{}, errors.New("twirp unavailable")
		},
	}
	_, router := createTestCombinedHandlerAndRouter(t, mockService, handlerOpts)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}

func TestHandleGetCombinedPromptBillingFailureRepoSucceeds(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
	}

	handlerOpts := defaultCombinedHandlerOpts(t, mockService)
	handlerOpts.FeatureFlagClient = featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory:               true,
		core.FeatureMemoryBillingEnforcedRetrieval: true,
	})
	handlerOpts.BillingEntityResolver = &mockBillingEntityResolver{
		resolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{}, errors.New("twirp unavailable")
		},
	}
	_, router := createTestCombinedHandlerAndRouter(t, mockService, handlerOpts)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
	require.NotNil(t, result.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.RepoMemoriesCount)
	assert.Nil(t, result.MemoriesContext.UserMemoriesCount)
}

func TestHandleGetCombinedPromptBillingUnresolvedRepoSucceeds(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
	}

	handlerOpts := defaultCombinedHandlerOpts(t, mockService)
	handlerOpts.FeatureFlagClient = featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory:               true,
		core.FeatureMemoryBillingEnforcedRetrieval: true,
	})
	handlerOpts.BillingEntityResolver = &mockBillingEntityResolver{
		resolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{Resolved: false}, nil
		},
	}
	_, router := createTestCombinedHandlerAndRouter(t, mockService, handlerOpts)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
	require.NotNil(t, result.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.RepoMemoriesCount)
	assert.Nil(t, result.MemoriesContext.UserMemoriesCount)
}

func TestHandleGetCombinedPromptBillingUnresolvedNoRepo422(t *testing.T) {
	mockService := &MockMemoryService{}

	handlerOpts := defaultCombinedHandlerOpts(t, mockService)
	handlerOpts.FeatureFlagClient = featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory:               true,
		core.FeatureMemoryBillingEnforcedRetrieval: true,
	})
	handlerOpts.BillingEntityResolver = &mockBillingEntityResolver{
		resolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{Resolved: false}, nil
		},
	}
	_, router := createTestCombinedHandlerAndRouter(t, mockService, handlerOpts)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnprocessableEntity, rr.Code)
}

func TestHandleGetCombinedPromptBillingSuccessFilterApplied(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	var capturedQuery core.UserMemoryQuery
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			capturedQuery = query
			return userMemories, nil
		},
	}

	handlerOpts := defaultCombinedHandlerOpts(t, mockService)
	handlerOpts.FeatureFlagClient = featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory:               true,
		core.FeatureMemoryBillingEnforcedRetrieval: true,
	})
	handlerOpts.BillingEntityResolver = &mockBillingEntityResolver{
		resolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}
	_, router := createTestCombinedHandlerAndRouter(t, mockService, handlerOpts)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	require.NotNil(t, capturedQuery.BillingFilter, "handler should resolve and pass a billing filter to the service")
	assert.Equal(t, uint64(42), capturedQuery.BillingFilter.OrganizationID)
	assert.Equal(t, uint64(99), capturedQuery.BillingFilter.EnterpriseID)
}

func TestHandleGetCombinedPromptNoBillingEnforcementNoFilter(t *testing.T) {
	// Billing enforcement NOT enabled → no billing filter passed to service.
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	var capturedQuery core.UserMemoryQuery
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			capturedQuery = query
			return userMemories, nil
		},
	}

	// Default handler opts: user scoped enabled but NO billing enforcement flag.
	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Nil(t, capturedQuery.BillingFilter, "billing filter should not be set when enforcement is disabled")
}

func TestHandleGetCombinedPromptInvalidLimitParams(t *testing.T) {
	tests := []struct {
		name          string
		query         string
		expectedLimit uint
	}{
		{"negative limit", "?limit=-1", uint(maxMemoriesForContext)},
		{"non-numeric limit", "?limit=abc", uint(maxMemoriesForContext)},
		{"zero limit", "?limit=0", uint(maxMemoriesForContext)},
		{"exceeds max", "?limit=5000", uint(1000)},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockService := &MockMemoryService{
				GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
					assert.Equal(t, tt.expectedLimit, limit)
					return nil, core.ErrNoMemoriesNotFound
				},
			}

			_, router := createTestCombinedHandlerAndRouter(t, mockService)

			ctx := createTestContext()
			req := createTestRequest(ctx, "GET", "/memory/v0/prompt"+tt.query, "")
			rr := executeRequestAndRecord(router, req)

			assert.Equal(t, http.StatusOK, rr.Code)
		})
	}
}

func TestHandleGetCombinedPromptFeatureNotEnabledUserMemories(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrFeatureNotEnabled
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	// User scope not enabled, but repo scope succeeds — degrade gracefully.
	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)
	assert.Contains(t, result.MemoriesContext.Prompt, "Use vitest")
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
	// User-scope count should be absent (nil) because the scope was disabled.
	assert.Nil(t, result.MemoriesContext.UserMemoriesCount)
	require.NotNil(t, result.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.RepoMemoriesCount)
}

func TestHandleGetCombinedPromptFeatureNotEnabledRepoMemories(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	// Repo scope not enabled, but user scope succeeds — degrade gracefully.
	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)
	assert.Contains(t, result.MemoriesContext.Prompt, "Use dark theme")
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
	// Repo-scope count should be absent (nil) because the scope was disabled.
	assert.Nil(t, result.MemoriesContext.RepoMemoriesCount)
	require.NotNil(t, result.MemoriesContext.UserMemoriesCount)
	assert.Equal(t, 1, *result.MemoriesContext.UserMemoriesCount)
}

func TestHandleGetCombinedPromptFeatureNotEnabledBothScopes(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrFeatureNotEnabled
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	// Both scopes not enabled — propagate as 404.
	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleGetCombinedPromptDualFailurePrefersRepoError(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrFeatureNotEnabled
		},
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	// User error is ErrFeatureNotEnabled but repo error is ErrRepositoryNotFound —
	// the handler should surface the repo error instead of masking it.
	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleGetCombinedPromptUserOnlyFetchFails(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	// No repo param — user is the only scope, and it failed.
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	// ErrRepositoryNotFound maps to 404 via handleDomainError.
	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleGetCombinedPromptNoRepoNoUserScope404(t *testing.T) {
	// No repo param and user-scoped memory is disabled → no writable scope → 404.
	// Regression test: previously this could return 200 with an empty prompt
	// containing tool definitions that would fail on use.
	mockService := &MockMemoryService{}

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: featureflags.NewNoopClient(map[string]bool{
			// user-scoped memory NOT enabled
		}),
		GHTwirp: githubtwirp.NewNoopClient(),
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleGetCombinedPromptVotingDisabledForMismatchedClient(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	// Only the coding agent per-client flag is enabled
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
	})

	ctx := createTestContext()
	// VS Code client should not get voting — only the coding agent flag is enabled
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	req.Header.Set("Copilot-Integration-Id", "vscode-chat")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.Nil(t, result.VoteToolDefinition)
	assert.NotEqual(t, combinedMemoriesContextPromptVersionWithVoting, result.MemoriesContext.PromptVersion)
}

func TestHandleGetCombinedPromptVotingDisabledWithNoIntegrationID(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	// Per-client flags are enabled but no integration ID header will be sent
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
		featureflags.CopilotSWEAgentMemoryVotingCCR:         true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
	})

	ctx := createTestContext()
	// No Copilot-Integration-Id header — voting should be disabled
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.Nil(t, result.VoteToolDefinition)
	assert.NotEqual(t, combinedMemoriesContextPromptVersionWithVoting, result.MemoriesContext.PromptVersion)
}

func TestHandleGetCombinedPromptVotingEnabledForCCRClient(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return repoMemories, nil
		},
		GetTopUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	// Only the CCR per-client flag is enabled
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCCR: true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-pr-reviews")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assertVoteToolDefinition(t, result.VoteToolDefinition)
	assert.Equal(t, combinedMemoriesContextPromptVersionWithVoting, result.MemoriesContext.PromptVersion)
}

func TestHandleGetCombinedPromptVotingEnabledViaUserFlagOnly(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetTopUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
		core.FeatureUserScopedMemory:                        true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
		GHTwirp:           githubtwirp.NewNoopClient(),
	})

	ctx := createTestContext()
	// No repo param — voting should be enabled via user flag
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assertVoteToolDefinition(t, result.VoteToolDefinition)
	assert.Equal(t, combinedMemoriesContextPromptVersionWithVoting, result.MemoriesContext.PromptVersion)
}

func TestHandleGetCombinedPromptUserScopedEnabled(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return userMemories, nil
		},
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory: true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		FeatureFlagClient: ffClient,
		GHTwirp:           githubtwirp.NewNoopClient(),
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	// Tool definition version should reflect user-scoped memory enablement.
	assert.Equal(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	assert.Equal(t, combinedStoreInstructionsPromptVersionWithScope, result.StoreInstructions.PromptVersion)
	// Store instructions should mention the "scope" argument.
	assert.Contains(t, result.StoreInstructions.Prompt, `"scope"`)
}

func TestHandleGetCombinedPromptCCRRequiresAdditionalFlag(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	t.Run("CCR with both flags enabled includes user-scoped prompt", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
				return userMemories, nil
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemory:    true,
			core.FeatureUserScopedMemoryCCR: true,
		})

		_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
			Service: mockService,
			GHFactory: &github.NoopClientFactory{
				MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
					return &github.NoopClient{}, nil
				},
			},
			Obsv:              observability.NewNoopExporters(),
			AppProvider:       agenticapptest.NewTestProvider(t),
			FeatureFlagClient: ffClient,
			GHTwirp:           githubtwirp.NewNoopClient(),
		})

		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
		req.Header.Set("Copilot-Integration-Id", "copilot-pr-reviews")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		// User-scoped prompt language should be present
		assert.Contains(t, result.StoreInstructions.Prompt, `"scope"`)
		assert.Equal(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	})

	t.Run("CCR with only general flag enabled omits user-scoped prompt", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
				return []*core.Memory{{ID: "r1", Subject: "test", Fact: "fact", Citations: []string{"f.go"}}}, nil
			},
			GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
				return userMemories, nil
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemory:    true,
			core.FeatureUserScopedMemoryCCR: false,
		})

		_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
			Service: mockService,
			GHFactory: &github.NoopClientFactory{
				MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
					return &github.NoopClient{}, nil
				},
			},
			Obsv:              observability.NewNoopExporters(),
			AppProvider:       agenticapptest.NewTestProvider(t),
			FeatureFlagClient: ffClient,
		})

		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
		req.Header.Set("Copilot-Integration-Id", "copilot-pr-reviews")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		// User-scoped prompt language should NOT be present
		assert.NotContains(t, result.StoreInstructions.Prompt, `"scope"`)
		assert.NotEqual(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	})

	t.Run("non-CCR with only general flag enabled includes user-scoped prompt", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
				return userMemories, nil
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemory: true,
		})

		_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
			Service: mockService,
			GHFactory: &github.NoopClientFactory{
				MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
					return &github.NoopClient{}, nil
				},
			},
			Obsv:              observability.NewNoopExporters(),
			AppProvider:       agenticapptest.NewTestProvider(t),
			FeatureFlagClient: ffClient,
			GHTwirp:           githubtwirp.NewNoopClient(),
		})

		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
		req.Header.Set("Copilot-Integration-Id", "copilot-developer")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		// User-scoped prompt language should be present for non-CCR integrations
		assert.Contains(t, result.StoreInstructions.Prompt, `"scope"`)
		assert.Equal(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	})
}

func TestHandleGetCombinedPromptCFIPlanBasedRouting(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	t.Run("CfI Pro user with CFI flag enabled gets user-scoped prompt", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
				return userMemories, nil
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemoryCFI: true,
			core.FeatureUserScopedMemory:    false,
		})

		mockTwirp := githubtwirp.NewNoopClient()
		mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:            req.Id,
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess: true,
				},
			}, nil
		}

		_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
			Service: mockService,
			GHFactory: &github.NoopClientFactory{
				MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
					return &github.NoopClient{}, nil
				},
			},
			Obsv:              observability.NewNoopExporters(),
			AppProvider:       agenticapptest.NewTestProvider(t),
			FeatureFlagClient: ffClient,
			GHTwirp:           mockTwirp,
		})

		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		assert.Contains(t, result.StoreInstructions.Prompt, `"scope"`)
		assert.Equal(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	})

	t.Run("CfI Pro user with only standard flag gets no user-scoped prompt", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
				return []*core.Memory{{ID: "r1", Subject: "test", Fact: "fact", Citations: []string{"f.go"}}}, nil
			},
			GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
				return userMemories, nil
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemoryCFI: false,
			core.FeatureUserScopedMemory:    true,
		})

		mockTwirp := githubtwirp.NewNoopClient()
		mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:            req.Id,
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess: true,
				},
			}, nil
		}

		_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
			Service: mockService,
			GHFactory: &github.NoopClientFactory{
				MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
					return &github.NoopClient{}, nil
				},
			},
			Obsv:              observability.NewNoopExporters(),
			AppProvider:       agenticapptest.NewTestProvider(t),
			FeatureFlagClient: ffClient,
			GHTwirp:           mockTwirp,
		})

		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/prompt?repo=test/repo", "")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		assert.NotContains(t, result.StoreInstructions.Prompt, `"scope"`)
		assert.NotEqual(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	})

	t.Run("CfB user with standard flag gets user-scoped prompt", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
				return userMemories, nil
			},
		}

		ffClient := featureflags.NewNoopClient(map[string]bool{
			core.FeatureUserScopedMemory:    true,
			core.FeatureUserScopedMemoryCFI: false,
		})

		mockTwirp := githubtwirp.NewNoopClient()
		mockTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					Id:            req.Id,
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
					HasPaidAccess: true,
				},
			}, nil
		}

		_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
			Service: mockService,
			GHFactory: &github.NoopClientFactory{
				MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
					return &github.NoopClient{}, nil
				},
			},
			Obsv:              observability.NewNoopExporters(),
			AppProvider:       agenticapptest.NewTestProvider(t),
			FeatureFlagClient: ffClient,
			GHTwirp:           mockTwirp,
		})

		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/prompt", "")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		assert.Contains(t, result.StoreInstructions.Prompt, `"scope"`)
		assert.Equal(t, storeToolDefinitionVersionWithScope, result.StoreToolDefinition.DefinitionVersion)
	})
}

// TestHandleGetCombinedPromptRepoAdminDisabledDropsRepoScopeOnly verifies that
// when the repo admin has disabled memory at the repository level via the
// repo_memory_disabled setting AND user-scope memory is enabled for the caller,
// the combined-prompt endpoint drops the repo scope only — user-scoped
// memories still flow through, because per the memory opt-out matrix
// (github/agents#945) the repo-admin opt-out gates only repo memories. User
// memories follow the user across repos by design.
//
// The companion case — repo-admin disabled but user-scope memory NOT enabled
// — is covered by TestHandleGetCombinedPromptRepoAdminDisabledNoWritableScope404,
// which exercises the 404 path.
func TestHandleGetCombinedPromptRepoAdminDisabledDropsRepoScopeOnly(t *testing.T) {
	repoMemories := []*core.Memory{
		{ID: "r1", Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	repoFetched := false
	userFetched := false
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return true, nil
		},
		GetRecentMemoriesFunc: func(_ core.User, _ *core.Repository, _ uint) ([]*core.Memory, error) {
			repoFetched = true
			return repoMemories, nil
		},
		GetRecentUserMemoriesFunc: func(_ core.User, _ uint, _ core.UserMemoryQuery) ([]*core.Memory, error) {
			userFetched = true
			return userMemories, nil
		},
	}

	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return true, nil // repo admin has disabled memory
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory: true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(_ context.Context, _ sweagentd.AgenticApp, _, _ string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		GHTwirp:           twirp,
		FeatureFlagClient: ffClient,
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	require.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &result))

	assert.False(t, repoFetched, "repo memories must not be fetched when repo admin has disabled memory")
	assert.True(t, userFetched, "user memories must still be fetched when repo admin has disabled memory (matrix: user scope unaffected)")
	assert.NotContains(t, result.MemoriesContext.Prompt, "Use vitest", "repo memories must not appear in the response")
	assert.Contains(t, result.MemoriesContext.Prompt, "Use dark theme", "user memories must appear in the response despite repo-admin opt-out")
	assert.NotContains(t, result.MemoriesContext.Prompt, "Repository memories for", "repo section must be absent")

	// Per-scope counts: repo absent (nil), user present.
	assert.Nil(t, result.MemoriesContext.RepoMemoriesCount, "repo count must be absent when repo scope is dropped")
	require.NotNil(t, result.MemoriesContext.UserMemoriesCount, "user count must be present when only repo scope is dropped")
	assert.Equal(t, 1, *result.MemoriesContext.UserMemoriesCount)
}

// TestHandleGetCombinedPromptRepoAdminDisabledNoWritableScope404 verifies the
// companion to TestHandleGetCombinedPromptRepoAdminDisabledDropsRepoScopeOnly:
// when the repo admin has disabled memory AND user-scope memory is NOT enabled
// for the caller, the combined-prompt endpoint returns 404 ErrFeatureNotEnabled.
// There is no writable scope left, so emitting a prompt with store/vote tool
// definitions would just lure the agent into calls that 404. Symmetric with
// /enabled and the per-scope withRepoMemoryCheck middleware.
func TestHandleGetCombinedPromptRepoAdminDisabledNoWritableScope404(t *testing.T) {
	repoFetched := false
	userFetched := false
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return true, nil
		},
		GetRecentMemoriesFunc: func(_ core.User, _ *core.Repository, _ uint) ([]*core.Memory, error) {
			repoFetched = true
			return nil, nil
		},
		GetRecentUserMemoriesFunc: func(_ core.User, _ uint, _ core.UserMemoryQuery) ([]*core.Memory, error) {
			userFetched = true
			return nil, nil
		},
	}

	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return true, nil // repo admin has disabled memory
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(_ context.Context, _ sweagentd.AgenticApp, _, _ string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     twirp,
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code, "no writable scope must surface as 404 ErrFeatureNotEnabled")
	assert.False(t, repoFetched, "repo memories must not be fetched when repo admin has disabled memory")
	assert.False(t, userFetched, "user memories must not be fetched when no writable scope remains")
}

// TestHandleGetCombinedPromptChainErrorReturns404 verifies that when the
// user-scope chain (Policy + repo/owner FF + featureDisallowed) errors while
// evaluating enablement for a repo-scoped request, the combined-prompt
// endpoint fails closed and returns 404 ErrFeatureNotEnabled. Per the memory
// opt-out matrix (github/agents#945), the user-affecting layers gate both
// scopes, so an error there leaves no writable scope — serving a prompt
// with store/vote tool definitions would just lure the agent into calls
// that 404.
func TestHandleGetCombinedPromptChainErrorReturns404(t *testing.T) {
	repoFetched := false
	userFetched := false
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return false, errors.New("policy lookup failed")
		},
		GetRecentMemoriesFunc: func(_ core.User, _ *core.Repository, _ uint) ([]*core.Memory, error) {
			repoFetched = true
			return nil, nil
		},
		GetRecentUserMemoriesFunc: func(_ core.User, _ uint, _ core.UserMemoryQuery) ([]*core.Memory, error) {
			userFetched = true
			return nil, nil
		},
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(_ context.Context, _ sweagentd.AgenticApp, _, _ string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code, "user-scope chain error must surface as 404 (fail closed; no writable scope)")
	assert.False(t, repoFetched, "repo memories must not be fetched when chain evaluation errors")
	assert.False(t, userFetched, "user memories must not be fetched when the user-scope chain errors (fail closed; user-scope chain gates both scopes)")
}

// TestHandleGetCombinedPromptRepoAdminTwirpErrorDropsRepoScopeOnly verifies that
// when the repo-admin ConfigurationForRepository Twirp call errors during a
// repo-scoped combined-prompt request AND user-scope memory is enabled for
// the caller, the handler drops ONLY the repo scope.
//
// Per the memory opt-out matrix (github/agents#945), the repo-admin layer
// only affects repo memories. Even fail-closed, an error here cannot
// suppress user memories — they are gated only by the user-affecting
// layers. This is the per-caller fail-closed mode (failClosedOnError=true)
// at the data-flow injection point: a transient Dotcom blip drops the repo
// scope rather than silently surfacing repo memories from a possibly
// opted-out repo.
//
// The companion case — repo-admin Twirp error but user-scope memory NOT
// enabled — is covered by
// TestHandleGetCombinedPromptRepoAdminTwirpErrorNoWritableScope404.
func TestHandleGetCombinedPromptRepoAdminTwirpErrorDropsRepoScopeOnly(t *testing.T) {
	userMemories := []*core.Memory{
		{ID: "u1", Subject: "preferences", Fact: "Use dark theme", Citations: []string{}},
	}

	repoFetched := false
	userFetched := false
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return true, nil
		},
		GetRecentMemoriesFunc: func(_ core.User, _ *core.Repository, _ uint) ([]*core.Memory, error) {
			repoFetched = true
			return nil, nil
		},
		GetRecentUserMemoriesFunc: func(_ core.User, _ uint, _ core.UserMemoryQuery) ([]*core.Memory, error) {
			userFetched = true
			return userMemories, nil
		},
	}

	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, errors.New("Dotcom Twirp transient failure")
	}

	ffClient := featureflags.NewNoopClient(map[string]bool{
		core.FeatureUserScopedMemory: true,
	})

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(_ context.Context, _ sweagentd.AgenticApp, _, _ string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:              observability.NewNoopExporters(),
		AppProvider:       agenticapptest.NewTestProvider(t),
		GHTwirp:           twirp,
		FeatureFlagClient: ffClient,
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	require.Equal(t, http.StatusOK, rr.Code, "repo-admin Twirp error must not 500 the combined prompt")

	var result MemoryPromptResponse
	require.NoError(t, json.Unmarshal(rr.Body.Bytes(), &result))

	assert.False(t, repoFetched, "repo memories must not be fetched when repo-admin Twirp errors (fail closed at data-flow injection point)")
	assert.True(t, userFetched, "user memories must still be fetched when repo-admin Twirp errors (matrix: user scope unaffected by repo-admin layer)")
	assert.Contains(t, result.MemoriesContext.Prompt, "Use dark theme", "user memories must appear in the response even when repo-admin Twirp errors")
	assert.Nil(t, result.MemoriesContext.RepoMemoriesCount, "repo count must be absent when repo-admin Twirp errors")
	require.NotNil(t, result.MemoriesContext.UserMemoriesCount, "user count must be present when only repo scope is dropped")
	assert.Equal(t, 1, *result.MemoriesContext.UserMemoriesCount)
}

// TestHandleGetCombinedPromptRepoAdminTwirpErrorNoWritableScope404 verifies the
// companion to TestHandleGetCombinedPromptRepoAdminTwirpErrorDropsRepoScopeOnly:
// when the repo-admin Twirp call errors AND user-scope memory is NOT enabled
// for the caller, the combined-prompt endpoint returns 404 ErrFeatureNotEnabled.
// There is no writable scope left, so emitting a prompt with store/vote tool
// definitions would just lure the agent into calls that 404.
func TestHandleGetCombinedPromptRepoAdminTwirpErrorNoWritableScope404(t *testing.T) {
	repoFetched := false
	userFetched := false
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(_ int64, _ *core.Repository) (bool, error) {
			return true, nil
		},
		GetRecentMemoriesFunc: func(_ core.User, _ *core.Repository, _ uint) ([]*core.Memory, error) {
			repoFetched = true
			return nil, nil
		},
		GetRecentUserMemoriesFunc: func(_ core.User, _ uint, _ core.UserMemoryQuery) ([]*core.Memory, error) {
			userFetched = true
			return nil, nil
		},
	}

	twirp := githubtwirp.NewNoopClient()
	twirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, errors.New("Dotcom Twirp transient failure")
	}

	_, router := createTestCombinedHandlerAndRouter(t, mockService, MemoryHandlerOpts{
		Service: mockService,
		GHFactory: &github.NoopClientFactory{
			MockNewClientFromRepoName: func(_ context.Context, _ sweagentd.AgenticApp, _, _ string) (github.ClientInterface, error) {
				return &github.NoopClient{}, nil
			},
		},
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     twirp,
	})

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, http.MethodGet, "/memory/v0/prompt?repo=test/repo", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code, "no writable scope must surface as 404 ErrFeatureNotEnabled")
	assert.False(t, repoFetched, "repo memories must not be fetched when repo-admin Twirp errors")
	assert.False(t, userFetched, "user memories must not be fetched when no writable scope remains")
}
