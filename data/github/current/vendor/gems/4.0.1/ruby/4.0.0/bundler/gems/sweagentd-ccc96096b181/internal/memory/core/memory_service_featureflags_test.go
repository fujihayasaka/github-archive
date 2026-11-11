package core_test

import (
	"context"
	"maps"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestFeatureFlagDisabledWhenCreatingMemory(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository,
		withFeatureFlags(nil)) // nil flags = feature disabled

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
}

func TestFeatureFlagDisabledWhenGettingMemory(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository,
		withFeatureFlags(nil)) // nil flags = feature disabled

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
}

// Flag Matrix Tests

func newMemoryServiceForFlagMatrix(t *testing.T, flags map[string]bool) (core.MemoryService, core.User, *core.Repository, *core.Memory) {
	t.Helper()

	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, m *core.Memory) error {
			return nil
		},
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			return nil
		},
	}

	// Ensure secret scanning is off unless explicitly overridden.
	flagConfig := map[string]bool{}
	maps.Copy(flagConfig, flags)
	if _, ok := flagConfig["copilot_swe_agent_memory_secret_scanning"]; !ok {
		flagConfig["copilot_swe_agent_memory_secret_scanning"] = false
	}

	ffClient := featureflags.NewNoopClient(flagConfig)

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
			return nil, nil
		},
	}

	service := core.NewMemoryService(memoryRepository, ffClient, secretScanner, observability.NewNoopExporters(), &MockMemoryEnablementChecker{Enabled: true})

	return service, user, repository, memory
}

func TestMemoryService_NoFlagsSpecified_AllOperationsDisabled(t *testing.T) {
	service, user, repository, memory := newMemoryServiceForFlagMatrix(t, nil)
	ctx := t.Context()

	err := service.CreateMemory(ctx, memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	_, err = service.GetMemories(ctx, user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	_, err = service.GetRecentMemories(ctx, user, repository, expectedLimit)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	err = service.DeleteMemory(ctx, user, repository, memory.ID)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)

	err = service.DeleteAllMemories(ctx, user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestMemoryService_NewFlagOnly_AllOperationsSucceed(t *testing.T) {
	flags := map[string]bool{
		"copilot-feature-agentic-memory": true,
	}

	service, user, repository, memory := newMemoryServiceForFlagMatrix(t, flags)
	ctx := t.Context()

	require.NoError(t, service.CreateMemory(ctx, memory, repository))

	_, err := service.GetMemories(ctx, user, repository)
	require.NoError(t, err)

	_, err = service.GetRecentMemories(ctx, user, repository, expectedLimit)
	require.NoError(t, err)

	require.NoError(t, service.DeleteMemory(ctx, user, repository, memory.ID))
	require.NoError(t, service.DeleteAllMemories(ctx, user, repository))
}
