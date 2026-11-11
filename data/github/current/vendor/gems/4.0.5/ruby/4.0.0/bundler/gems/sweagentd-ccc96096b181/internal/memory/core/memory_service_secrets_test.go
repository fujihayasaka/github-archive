package core_test

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/require"
)

func TestCreateMemoryThatContainsSecrets(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	memory.Fact = "Test Fact with secret"
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
	}

	// Create a secret scanner that detects secrets
	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository, withSecretScanner(secretScanner))

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrMemoryContainsSecrets, "expected error when creating memory that contains secrets")
}

func TestCreateMemoryWithSecretScanningDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	memory.Fact = "Test Fact with secret"
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
	}

	// Scanner that would find a secret (but should not be called)
	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository,
		withSecretScanner(secretScanner),
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":           true,
			"copilot_swe_agent_memory_secret_scanning": false, // Disable secret scanning
		}))

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.NoError(t, err, "expected no error when creating memory with secret scanning disabled")
}
