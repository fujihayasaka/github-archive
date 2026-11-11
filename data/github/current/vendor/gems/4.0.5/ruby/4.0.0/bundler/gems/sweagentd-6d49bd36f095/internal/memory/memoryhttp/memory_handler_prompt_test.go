package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func assertStoreToolDefinition(t *testing.T, toolDefinition ToolDefinition) {
	t.Helper()
	expectedDescription, err := resolveStoreToolDescription(false)
	require.NoError(t, err)
	assert.Equal(t, storeMemoryToolName, toolDefinition.Name)
	assert.Equal(t, expectedDescription, toolDefinition.Description)
	assert.Equal(t, storeToolDefinitionVersion, toolDefinition.DefinitionVersion)
}

func assertVoteToolDefinition(t *testing.T, toolDefinition *ToolDefinition) {
	t.Helper()
	require.NotNil(t, toolDefinition)
	assert.Equal(t, voteMemoryToolName, toolDefinition.Name)
	assert.Equal(t, voteMemoryToolDescription, toolDefinition.Description)
	assert.Equal(t, voteToolDefinitionVersion, toolDefinition.DefinitionVersion)
}

func TestHandleGetPromptSuccess(t *testing.T) {
	mockMemories := []*core.Memory{
		{
			ID:        core.MemoryID("mem1"),
			Subject:   "testing practices",
			Fact:      "Use vitest for unit tests",
			Citations: []string{"vitest.config.ts:5"},
		},
		{
			ID:        core.MemoryID("mem2"),
			Subject:   "code style",
			Fact:      "Use single quotes for strings",
			Citations: []string{"eslintrc.json:10", ".prettierrc:3"},
		},
		{
			ID:        core.MemoryID("mem3"),
			Subject:   "build commands",
			Fact:      "Run npm run build to build the project",
			Citations: []string{},
		},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.User{ID: 1, Login: "testuser"}, user)
			assert.Equal(t, core.RepoNWO{Owner: "test", Repo: "repo"}, repository.NWO)
			assert.Equal(t, uint(maxMemoriesForContext), limit)
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Equal(t, "application/json", rr.Header().Get("Content-Type"))

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	// StoreInstructions
	assert.NotEmpty(t, result.StoreInstructions.Prompt)
	assert.Contains(t, result.StoreInstructions.Prompt, "store_memory")
	assert.Equal(t, storeInstructionsPromptVersion, result.StoreInstructions.PromptVersion)

	// MemoriesContext
	assert.Equal(t, 3, result.MemoriesContext.MemoriesCount)
	assert.Equal(t, memoriesContextPromptVersion, result.MemoriesContext.PromptVersion)

	// Assembled prompt should contain the actual memory facts
	assert.Contains(t, result.MemoriesContext.Prompt, "**testing practices**")
	assert.Contains(t, result.MemoriesContext.Prompt, "Use vitest for unit tests")
	assert.Contains(t, result.MemoriesContext.Prompt, "vitest.config.ts:5")
	assert.Contains(t, result.MemoriesContext.Prompt, "**code style**")
	assert.Contains(t, result.MemoriesContext.Prompt, "eslintrc.json:10, .prettierrc:3")
	assert.Contains(t, result.MemoriesContext.Prompt, "**build commands**")
	assert.Contains(t, result.MemoriesContext.Prompt, "<none>") // empty citations

	// Assembled prompt should contain the wrapper preamble and instructions
	assert.Contains(t, result.MemoriesContext.Prompt, "recent memories from previous agent interactions")
	assert.Contains(t, result.MemoriesContext.Prompt, "store_memory")
	assertMemoryDeletionManualGuidance(t, result.MemoriesContext.Prompt)
	assertStoreToolDefinition(t, result.ToolDefinition)
	assertStoreToolDefinition(t, result.StoreToolDefinition)
	assert.Nil(t, result.VoteToolDefinition)
}

func TestHandleGetPromptCustomLimit(t *testing.T) {
	mockMemories := []*core.Memory{
		{
			ID:      core.MemoryID("mem1"),
			Subject: "testing practices",
			Fact:    "Use vitest for unit tests",
		},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(5), limit)
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt?limit=5", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)
	assert.Equal(t, 1, result.MemoriesContext.MemoriesCount)
}

func TestHandleGetPromptDefaultLimit(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(maxMemoriesForContext), limit)
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetPromptInvalidLimit(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(maxMemoriesForContext), limit)
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt?limit=invalid", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetPromptLimitCappedToMax(t *testing.T) {
	t.Skip("Skipping test for limit capped to max - we want to let this be parameterisable for experimentation right now")
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(maxMemoriesForContext), limit)
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt?limit=100", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetPromptNoMemories(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	// StoreInstructions should still be fully populated
	assert.NotEmpty(t, result.StoreInstructions.Prompt)
	assert.Equal(t, storeInstructionsPromptVersion, result.StoreInstructions.PromptVersion)

	// MemoriesContext should have empty prompt and zero count
	assert.Equal(t, 0, result.MemoriesContext.MemoriesCount)
	assert.Equal(t, memoriesContextPromptVersion, result.MemoriesContext.PromptVersion)
	assert.Empty(t, result.MemoriesContext.Prompt)

	// ToolDefinition should still be fully populated
	assertStoreToolDefinition(t, result.ToolDefinition)
	assertStoreToolDefinition(t, result.StoreToolDefinition)
	assert.Nil(t, result.VoteToolDefinition)
}

func TestHandleGetPromptWithMemoryVotingEnabled(t *testing.T) {
	mockMemories := []*core.Memory{
		{
			ID:        core.MemoryID("mem1"),
			Subject:   "testing practices",
			Fact:      "Use vitest for unit tests",
			Citations: []string{"vitest.config.ts:5"},
		},
	}

	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}

	handler, router := createTestHandlerAndRouter(t, mockService)
	handler.featureFlagClient = featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.Contains(t, result.StoreInstructions.Prompt, "vote_memory")
	assert.Contains(t, result.StoreInstructions.Prompt, "genuinely new facts")
	assert.Contains(t, result.StoreInstructions.Prompt, "reflecting the current reality")
	assert.Equal(t, storeInstructionsPromptVersionWithVoting, result.StoreInstructions.PromptVersion)
	assert.Contains(t, result.MemoriesContext.Prompt, "exact string match")
	assert.Contains(t, result.MemoriesContext.Prompt, "reflecting the current reality")
	assert.Contains(t, result.MemoriesContext.Prompt, "vote_memory")
	assertMemoryDeletionVotingGuidance(t, result.MemoriesContext.Prompt)
	assert.Equal(t, memoriesContextPromptVersionWithVoting, result.MemoriesContext.PromptVersion)
	assertStoreToolDefinition(t, result.ToolDefinition)
	assertStoreToolDefinition(t, result.StoreToolDefinition)
	assertVoteToolDefinition(t, result.VoteToolDefinition)
}

func TestHandleGetPromptNoMemoriesWithMemoryVotingEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	handler, router := createTestHandlerAndRouter(t, mockService)
	handler.featureFlagClient = featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
	})

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.NotContains(t, result.StoreInstructions.Prompt, "vote_memory")
	assert.Equal(t, storeInstructionsPromptVersion, result.StoreInstructions.PromptVersion)
	assert.Equal(t, memoriesContextPromptVersion, result.MemoriesContext.PromptVersion)
	assert.Empty(t, result.MemoriesContext.Prompt)
	assert.Equal(t, 0, result.MemoriesContext.MemoriesCount)
	assertStoreToolDefinition(t, result.ToolDefinition)
	assertStoreToolDefinition(t, result.StoreToolDefinition)
	assertVoteToolDefinition(t, result.VoteToolDefinition)
}

func TestHandleGetPromptVotingDisabledForMismatchedClient(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("mem1"), Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}

	handler, router := createTestHandlerAndRouter(t, mockService)
	// Only the coding agent per-client flag is enabled
	handler.featureFlagClient = featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
	})

	ctx := createTestContext()
	// VS Code client should not get voting — only the coding agent flag is enabled
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "vscode-chat")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.Nil(t, result.VoteToolDefinition)
	assert.NotContains(t, result.StoreInstructions.Prompt, "vote_memory")
	assert.Equal(t, storeInstructionsPromptVersion, result.StoreInstructions.PromptVersion)
}

func TestHandleGetPromptVotingDisabledWithNoIntegrationID(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("mem1"), Subject: "testing", Fact: "Use vitest", Citations: []string{"vitest.config.ts:5"}},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return mockMemories, nil
		},
	}

	handler, router := createTestHandlerAndRouter(t, mockService)
	handler.featureFlagClient = featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentMemoryVotingCodingAgent: true,
		featureflags.CopilotSWEAgentMemoryVotingCCR:         true,
	})

	ctx := createTestContext()
	// No Copilot-Integration-Id header — voting should be disabled
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var result MemoryPromptResponse
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)

	assert.Nil(t, result.VoteToolDefinition)
	assert.NotContains(t, result.StoreInstructions.Prompt, "vote_memory")
	assert.Equal(t, storeInstructionsPromptVersion, result.StoreInstructions.PromptVersion)
}

func TestHandleGetPromptUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	// Create request with no user context
	req := createTestRequest(context.Background(), "GET", "/memory/v0/test/repo/prompt", "")
	rr := executeRequestAndRecord(router, req)

	// Should be 401 since no user is in context
	assert.Equal(t, http.StatusUnauthorized, rr.Code)
}

func TestHandleGetPromptInvalidNWO(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	// Empty owner in the URL will be caught by NWO validation
	req := createTestRequest(ctx, "GET", "/memory/v0//repo/prompt", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
}

func TestHandleGetPromptTotalRepositoryMemoriesCount(t *testing.T) {
	mockMemories := []*core.Memory{
		{
			ID:        core.MemoryID("mem1"),
			Subject:   "testing practices",
			Fact:      "Use vitest for unit tests",
			Citations: []string{"vitest.config.ts:5"},
		},
		{
			ID:        core.MemoryID("mem2"),
			Subject:   "code style",
			Fact:      "Use single quotes for strings",
			Citations: []string{"eslintrc.json:10"},
		},
	}

	t.Run("happy path with count", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
				return mockMemories, nil
			},
			CountMemoriesFunc: func(user core.User, repository *core.Repository) (int, error) {
				return 42, nil
			},
		}

		_, router := createTestHandlerAndRouter(t, mockService)
		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
		req.Header.Set("Copilot-Integration-Id", "copilot-developer")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		assert.Equal(t, 2, result.MemoriesContext.MemoriesCount)
		assert.Equal(t, 42, result.MemoriesContext.TotalRepositoryMemoriesCount)
	})

	t.Run("count failure graceful degradation", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
				return mockMemories, nil
			},
			CountMemoriesFunc: func(user core.User, repository *core.Repository) (int, error) {
				return 0, errors.New("cosmos error")
			},
		}

		_, router := createTestHandlerAndRouter(t, mockService)
		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
		req.Header.Set("Copilot-Integration-Id", "copilot-developer")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		assert.Equal(t, 2, result.MemoriesContext.MemoriesCount)
		assert.Equal(t, 0, result.MemoriesContext.TotalRepositoryMemoriesCount)
	})

	t.Run("zero memories", func(t *testing.T) {
		mockService := &MockMemoryService{
			GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
				return nil, core.ErrNoMemoriesNotFound
			},
			CountMemoriesFunc: func(user core.User, repository *core.Repository) (int, error) {
				return 0, nil
			},
		}

		_, router := createTestHandlerAndRouter(t, mockService)
		ctx := createTestContext()
		req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
		req.Header.Set("Copilot-Integration-Id", "copilot-developer")
		rr := executeRequestAndRecord(router, req)

		assert.Equal(t, http.StatusOK, rr.Code)

		var result MemoryPromptResponse
		err := json.Unmarshal(rr.Body.Bytes(), &result)
		require.NoError(t, err)

		assert.Equal(t, 0, result.MemoriesContext.MemoriesCount)
		assert.Equal(t, 0, result.MemoriesContext.TotalRepositoryMemoriesCount)
		assert.Empty(t, result.MemoriesContext.Prompt)
	})
}

func TestHandleGetPromptServiceError(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/prompt", "")
	req.Header.Set("Copilot-Integration-Id", "copilot-developer")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
}

// --- CCA Memory Limit Experiment Tests ---

// createTestHandlerWithExpClient creates a handler with a mock experiment client for testing.
func createTestHandlerWithExpClient(t *testing.T, mockService *MockMemoryService, expClient exp.ExperimentationClient) (*MemoryHandler, *chi.Mux) {
	t.Helper()
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
		ExpClient:   expClient,
	})
	router := createTestRouter(handler)
	return handler, router
}

func TestHandleGetPromptExperimentMemoryLimit(t *testing.T) {
	tests := []struct {
		name          string
		flagValue     string // empty string means flag not set in assignment
		assignmentCtx string // empty string means no experiment active
		integrationID string // empty means no header set (non-CCA)
		queryLimit    string // optional ?limit= query param
		expectedLimit uint
	}{
		{
			name:          "no experiment active uses default",
			assignmentCtx: "",
			integrationID: copilotDeveloperIntegrationID,
			expectedLimit: uint(maxMemoriesForContext),
		},
		{
			name:          "control variant preserves default",
			flagValue:     strconv.Itoa(maxMemoriesForContext),
			assignmentCtx: "experiment_memory_limit:control",
			integrationID: copilotDeveloperIntegrationID,
			expectedLimit: uint(maxMemoriesForContext),
		},
		{
			name:          "treatment B sets limit to 50",
			flagValue:     "50",
			assignmentCtx: "experiment_memory_limit:treatment_b",
			integrationID: copilotDeveloperIntegrationID,
			expectedLimit: 50,
		},
		{
			name:          "treatment C sets limit to 100",
			flagValue:     "100",
			assignmentCtx: "experiment_memory_limit:treatment_c",
			integrationID: copilotDeveloperIntegrationID,
			expectedLimit: 100,
		},
		{
			name:          "non-CCA caller skips experiment and uses default",
			flagValue:     "100",
			assignmentCtx: "experiment_memory_limit:treatment_c",
			integrationID: "", // no integration ID header
			expectedLimit: uint(maxMemoriesForContext),
		},
		{
			name:          "experiment overrides query param for CCA",
			flagValue:     "100",
			assignmentCtx: "experiment_memory_limit:treatment_c",
			integrationID: copilotDeveloperIntegrationID,
			queryLimit:    "5",
			expectedLimit: 100,
		},
		{
			name:          "assignment context present but cca_memory_limit flag absent uses default",
			flagValue:     "", // flag not in assignment
			assignmentCtx: "other_experiment:variant_a",
			integrationID: copilotDeveloperIntegrationID,
			expectedLimit: uint(maxMemoriesForContext),
		},
		{
			name:          "experiment can set limit to 0 for testing no memories",
			flagValue:     "0",
			assignmentCtx: "experiment_memory_limit:treatment_zero",
			integrationID: copilotDeveloperIntegrationID,
			expectedLimit: 0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			called := false
			mockService := &MockMemoryService{
				GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
					called = true
					assert.Equal(t, tc.expectedLimit, limit, "unexpected memory limit")
					return nil, core.ErrNoMemoriesNotFound
				},
			}

			var router *chi.Mux
			if tc.assignmentCtx != "" {
				featureVars := map[string]string{}
				if tc.flagValue != "" {
					featureVars[exp.FlagKey(exp.CCAMemoryLimitExperiment)] = tc.flagValue
				}
				_, router = createTestHandlerWithExpClient(t, mockService, &mockExpClient{
					assignment: exp.NewAssignmentResult(
						featureVars,
						tc.assignmentCtx,
						1,
					),
				})
			} else {
				_, router = createTestHandlerAndRouter(t, mockService)
			}

			path := "/memory/v0/test/repo/prompt"
			if tc.queryLimit != "" {
				path += "?limit=" + tc.queryLimit
			}

			ctx := createTestContext()
			req := createTestRequest(ctx, "GET", path, "")
			if tc.integrationID != "" {
				req.Header.Set(capi.IntegrationIDHeader, tc.integrationID)
			}
			rr := executeRequestAndRecord(router, req)

			assert.Equal(t, http.StatusOK, rr.Code)
			assert.True(t, called, "GetRecentMemories was not called — limit assertion was never evaluated")
		})
	}
}
