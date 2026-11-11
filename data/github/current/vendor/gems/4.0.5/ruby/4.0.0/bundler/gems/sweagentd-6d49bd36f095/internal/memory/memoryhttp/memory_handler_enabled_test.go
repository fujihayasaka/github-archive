package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockExpClient is a mock ExperimentationClient that returns a preconfigured assignment.
type mockExpClient struct {
	assignment *githubexp.AssignmentResult
}

func (m *mockExpClient) ResilientStart(_ context.Context, _ ...githubexp.ResilientStartOption) error {
	return nil
}

func (m *mockExpClient) GetAssignment(_ context.Context, _ map[string]string, _, _ []string) *githubexp.AssignmentResult {
	return m.assignment
}

// TestHandleCheckMemoryEnabledSuccess tests the CheckMemoryEnabled endpoint with a successful response.
func TestHandleCheckMemoryEnabledSuccess(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			assert.Equal(t, int64(1), userID)
			return true, nil
		},
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
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled)
}

// TestHandleCheckMemoryEnabledDisabled tests the CheckMemoryEnabled endpoint when memory is disabled.
func TestHandleCheckMemoryEnabledDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return false, nil
		},
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
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.False(t, response.Enabled)
}

// TestHandleCheckMemoryEnabledError tests the CheckMemoryEnabled endpoint when an error occurs.
func TestHandleCheckMemoryEnabledError(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return false, errors.New("failed to check enablement")
		},
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
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}

// TestHandleCheckMemoryEnabledUnauthorized tests the CheckMemoryEnabled endpoint without user context.
func TestHandleCheckMemoryEnabledUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
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
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := context.Background()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
}

// TestHandleCheckMemoryEnabledNoExperiment tests that when no experiment is active
// (expClient is nil), the enabled value from CheckMemoryEnabled is returned unchanged.
func TestHandleCheckMemoryEnabledNoExperiment(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	// No ExpClient set — expClient is nil, so getMemoryAssignment returns a noop assignment
	// with an empty assignment context.
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true when no experiment is active")
}

// TestHandleCheckMemoryEnabledExperimentEnabled tests that when an experiment is active
// and the repo is in the enabled group, the enabled value is not overridden.
func TestHandleCheckMemoryEnabledExperimentEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
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
		ExpClient: &mockExpClient{
			assignment: exp.NewAssignmentResult(
				map[string]string{exp.FlagKey(exp.MemoryExperiment): "true"},
				"experiment_memory:enabled",
				1,
			),
		},
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	req.Header.Set(capi.IntegrationIDHeader, copilotDeveloperIntegrationID)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true for enabled variant")
}

// TestHandleCheckMemoryEnabledExperimentDisabled tests that when an experiment is active
// and the repo is in the disabled group, memory is disabled regardless of the service result.
func TestHandleCheckMemoryEnabledExperimentDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil // Service says enabled, but experiment should override
		},
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
		ExpClient: &mockExpClient{
			assignment: exp.NewAssignmentResult(
				map[string]string{exp.FlagKey(exp.MemoryExperiment): "false"},
				"experiment_memory:disabled",
				1,
			),
		},
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	req.Header.Set(capi.IntegrationIDHeader, copilotDeveloperIntegrationID)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.False(t, response.Enabled, "enabled should be false for disabled variant")
}

// TestHandleCheckMemoryEnabledExperimentUnknownVariant tests that when an experiment is active
// but the memory_experiment key is missing or set to an unexpected value, the default behavior
// (enabled) is preserved and memory is not overridden.
func TestHandleCheckMemoryEnabledExperimentUnknownVariant(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
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
		ExpClient: &mockExpClient{
			assignment: exp.NewAssignmentResult(
				map[string]string{}, // no memory_experiment key present
				"experiment_memory:unknown",
				1,
			),
		},
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	req.Header.Set(capi.IntegrationIDHeader, copilotDeveloperIntegrationID)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true when experiment key is missing")
}

// TestHandleCheckMemoryEnabledExperimentSkippedForNonCCA tests that non-CCA callers
// (missing or different Copilot-Integration-Id) skip the experiment block entirely,
// even when the experiment would disable memory.
func TestHandleCheckMemoryEnabledExperimentSkippedForNonCCA(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
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
		ExpClient: &mockExpClient{
			assignment: exp.NewAssignmentResult(
				map[string]string{exp.FlagKey(exp.MemoryExperiment): "false"},
				"experiment_memory:disabled",
				1,
			),
		},
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	// No Copilot-Integration-Id header set — simulates a non-CCA caller
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true for non-CCA callers even when experiment would disable")
}

// TestHandleCheckMemoryEnabledRepoAdminDisabled tests that when the repo admin has disabled
// memory for the repository, the enabled endpoint returns false even when the service says enabled.
func TestHandleCheckMemoryEnabledRepoAdminDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil // Service says enabled, but repo admin disabled it
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return true, nil // Repo admin disabled memory
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     mockTwirp,
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.False(t, response.Enabled, "enabled should be false when repo admin has disabled memory")
}

// TestHandleCheckMemoryEnabledRepoAdminNotDisabled tests that when the repo admin has not disabled
// memory (setting is absent or false), the enabled endpoint returns the service result unchanged.
func TestHandleCheckMemoryEnabledRepoAdminNotDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, nil // Repo admin has NOT disabled memory
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     mockTwirp,
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true when repo admin has not disabled memory")
}

// TestHandleCheckMemoryEnabledRepoAdminCheckError tests that when the repo-level check fails,
// the handler gracefully falls back and preserves the service result (fail-open).
func TestHandleCheckMemoryEnabledRepoAdminCheckError(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		return false, errors.New("failed to reach Dotcom")
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     mockTwirp,
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true when repo-level check fails (fail-open)")
}

// TestHandleCheckMemoryEnabledRepoAdminSkippedWhenAlreadyDisabled tests that the repo-level
// check is not performed when memory is already disabled by the service (feature flags, etc.).
func TestHandleCheckMemoryEnabledRepoAdminSkippedWhenAlreadyDisabled(t *testing.T) {
	repoCheckCalled := false
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return false, nil // Already disabled by feature flags
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	mockTwirp := githubtwirp.NewNoopClient()
	mockTwirp.MockIsMemoryDisabledForRepo = func(_ context.Context, _ int64, _ int64) (bool, error) {
		repoCheckCalled = true
		return false, nil
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: agenticapptest.NewTestProvider(t),
		GHTwirp:     mockTwirp,
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContextWithToken()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.False(t, response.Enabled)
	assert.False(t, repoCheckCalled, "repo-level check should not be called when already disabled")
}

// TestHandleCheckMemoryEnabledNoGHTwirp tests that when ghTwirp is nil (no Twirp client configured),
// the repo-level check is skipped and the service result is returned unchanged.
func TestHandleCheckMemoryEnabledNoGHTwirp(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64, repository *core.Repository) (bool, error) {
			return true, nil
		},
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
		// GHTwirp intentionally not set (nil)
	})
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled, "enabled should remain true when ghTwirp is nil")
}
