package core_test

import (
	"context"
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
)

type MockMemoryRepository struct {
	SaveFunc                   func(repoID core.RepositoryID, memory *core.Memory) error
	FindByIDFunc               func(repoID core.RepositoryID, id core.MemoryID) (*core.Memory, error)
	FindByRepositoryFunc       func(repoID core.RepositoryID) ([]*core.Memory, error)
	FindRecentByRepositoryFunc func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error)
	DeleteFunc                 func(repoID core.RepositoryID, id core.MemoryID) error
}

func (m *MockMemoryRepository) Save(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	return m.SaveFunc(repoID, memory)
}

func (m *MockMemoryRepository) FindByID(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) (*core.Memory, error) {
	return m.FindByIDFunc(repoID, id)
}

func (m *MockMemoryRepository) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	return m.FindByRepositoryFunc(repoID)
}

func (m *MockMemoryRepository) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	if m.FindRecentByRepositoryFunc != nil {
		return m.FindRecentByRepositoryFunc(repoID, limit)
	}
	return []*core.Memory{}, nil // No-op for this mock
}

func (m *MockMemoryRepository) Delete(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	if m.DeleteFunc != nil {
		return m.DeleteFunc(repoID, id)
	}
	return nil // No-op for this mock
}

type MockRepositoryStore struct {
	FindByNWOFunc func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error)
}

func (m *MockRepositoryStore) FindByNWO(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
	return m.FindByNWOFunc(ctx, nwo)
}

type MockSecretScanner struct {
	ScanFunc func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error)
}

func (m *MockSecretScanner) Scan(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
	return m.ScanFunc(ctx, repoNWO, memory)
}

var secretScanner = &MockSecretScanner{
	ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
		return make([]core.MemorySecret, 0), nil // Simulate no secrets found
	},
}

var featureFlagClient = featureflags.NewNoopClient(
	map[string]bool{
		"copilot_swe_agent_memory_service":         true,
		"copilot_swe_agent_memory_secret_scanning": true,
	},
)

func TestCreateMemory(t *testing.T) {
	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil // Simulate successful save
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Simulate repository found
		},
	}

	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           core.RepoNWO{Owner: "test", Repo: "repo"},
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}

	err := memoryService.CreateMemory(t.Context(), memory)
	assert.NoError(t, err, "expected no error when creating memory")
}

func TestGetMemoriesNotFound(t *testing.T) {
	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return make([]*core.Memory, 0), nil // Simulate no memories found
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Simulate repository found
		},
	}

	// Create a memory service with the mock repository
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())
	repoNwo, err := core.NewRepoNWO("test", "random-repo")
	user := core.User{ID: 1, Login: "testuser"}
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	_, err = memoryService.GetMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrNoMemoriesNotFound, "expected no memories found error")
}

func TestGetMemories(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "random-repo")
	user := core.User{ID: 1, Login: "testuser"}
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNwo,
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}
	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{
				memory,
			}, nil // Simulate one memory found
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Simulate repository found
		},
	}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	memories, err := memoryService.GetMemories(t.Context(), user, *repoNwo)
	assert.NoError(t, err, "expected no error when getting memories")
	assert.Len(t, memories, 1, "expected one memory to be returned")
	assert.Equal(t, memory, memories[0], "expected returned memory to match the created memory")
}

func TestGetMemoriesRepositoryError(t *testing.T) {
	expectedError := errors.New("some random error")
	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return nil, expectedError // Simulate an error
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return nil, expectedError // Simulate an error when finding repository
		},
	}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())
	repoNwo, err := core.NewRepoNWO("test", "error-repo")
	user := core.User{ID: 1, Login: "testuser"}
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	_, err = memoryService.GetMemories(t.Context(), user, *repoNwo)
	assert.Error(t, err, "expected an error when getting memories")
	assert.ErrorIs(t, err, expectedError, "expected the returned error to match the simulated error")
}

func TestFeatureFlagDisabledWhenCreatingMemory(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "random-repo")
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNwo,
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}
	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil // Simulate successful save
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo}, nil // Simulate repository found
		},
	}

	// Create a memory service with the mock repository and feature flag client that disables the feature
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureflags.NewNoopClient(nil), secretScanner, observability.NewNoopExporters())

	err = memoryService.CreateMemory(t.Context(), memory)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
}

func TestFeatureFlagDisabledWhenGettingMemory(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "random-repo")
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	user := core.User{ID: 1, Login: "testuser"}
	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return nil, nil // Simulate no memories found
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo}, nil // Simulate repository found
		},
	}

	// Create a memory service with the mock repository and feature flag client that disables the feature
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureflags.NewNoopClient(nil), secretScanner, observability.NewNoopExporters())

	_, err = memoryService.GetMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
}

func TestCreateMemoryThatContainsSecrets(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "random-repo")
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact with secret",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNwo,
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}
	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil // Simulate successful save
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Simulate repository found
		},
	}

	// Create a memory service with the mock repository and a secret scanner that detects secrets
	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil // Simulate finding a secret
		},
	}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.CreateMemory(t.Context(), memory)
	assert.ErrorIs(t, err, core.ErrMemoryContainsSecrets, "expected error when creating memory that contains secrets")
}

func TestCreateMemoryWithSecretScanningDisabled(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "random-repo")
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact with secret",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNwo,
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}
	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil // Simulate successful save
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Simulate repository found
		},
	}

	// Create a memory service with the secret scanning feature flag disabled
	featureFlagClientWithSecretScanningDisabled := featureflags.NewNoopClient(
		map[string]bool{
			"copilot_swe_agent_memory_service":         true,
			"copilot_swe_agent_memory_secret_scanning": false, // Disable secret scanning
		},
	)
	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil // Simulate finding a secret (but should not be called)
		},
	}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClientWithSecretScanningDisabled, secretScanner, observability.NewNoopExporters())

	err = memoryService.CreateMemory(t.Context(), memory)
	assert.NoError(t, err, "expected no error when creating memory with secret scanning disabled")
}

func TestDeleteMemorySuccess(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")
	memoryID := core.MemoryID("test-memory-id")

	deleteCalled := false
	memoryRepository := &MockMemoryRepository{
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			deleteCalled = true
			assert.Equal(t, core.RepositoryID(1), repoID)
			assert.Equal(t, memoryID, id)
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": true,
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteMemory(t.Context(), user, *repoNwo, memoryID)
	assert.NoError(t, err)
	assert.True(t, deleteCalled, "expected Delete to be called on repository")
}

func TestDeleteMemoryFeatureDisabled(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")
	memoryID := core.MemoryID("test-memory-id")

	memoryRepository := &MockMemoryRepository{
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called when feature is disabled")
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": false, // Deletion disabled
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteMemory(t.Context(), user, *repoNwo, memoryID)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestDeleteAllMemoriesSuccess(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")

	memories := []*core.Memory{
		{ID: "memory1", Subject: "Subject1", Fact: "Fact1"},
		{ID: "memory2", Subject: "Subject2", Fact: "Fact2"},
	}

	deletedIDs := []core.MemoryID{}
	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			assert.Equal(t, core.RepositoryID(1), repoID)
			return memories, nil
		},
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			deletedIDs = append(deletedIDs, id)
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": true,
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteAllMemories(t.Context(), user, *repoNwo)
	assert.NoError(t, err)
	assert.Len(t, deletedIDs, 2, "expected 2 memories to be deleted")
	assert.Contains(t, deletedIDs, core.MemoryID("memory1"))
	assert.Contains(t, deletedIDs, core.MemoryID("memory2"))
}

func TestDeleteAllMemoriesFeatureDisabled(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called when feature is disabled")
			return nil, nil
		},
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called when feature is disabled")
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": false, // Deletion disabled
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteAllMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestGetRecentMemoriesSuccess(t *testing.T) {
	user := core.NewUser(123, "testuser")
	repoNWO, err := core.NewRepoNWO("testowner", "testrepo")
	assert.NoError(t, err)
	repository := &core.Repository{ID: 1, NWO: *repoNWO, Private: true}

	memories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
		{ID: core.MemoryID("memory2"), Subject: "recent memory 2"},
	}

	memoryRepository := &MockMemoryRepository{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, repository.ID, repoID)
			assert.Equal(t, uint(5), limit)
			return memories, nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return repository, nil
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service": true,
	})

	secretScanner := &MockSecretScanner{}
	service := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	result, err := service.GetRecentMemories(t.Context(), user, *repoNWO, 5)

	assert.NoError(t, err)
	assert.Equal(t, memories, result)
}

func TestGetRecentMemoriesFeatureDisabled(t *testing.T) {
	user := core.NewUser(123, "testuser")
	repoNWO, err := core.NewRepoNWO("testowner", "testrepo")
	assert.NoError(t, err)
	repository := &core.Repository{ID: 1, NWO: *repoNWO}

	memoryRepository := &MockMemoryRepository{}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return repository, nil
		},
	}

	// Feature flag disabled
	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service": false,
	})

	secretScanner := &MockSecretScanner{}
	service := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	result, err := service.GetRecentMemories(t.Context(), user, *repoNWO, 5)

	assert.Error(t, err)
	assert.Equal(t, core.ErrFeatureNotEnabled, err)
	assert.Nil(t, result)
}

func TestGetRecentMemoriesLimitExcludesOldMemories(t *testing.T) {
	user := core.NewUser(123, "testuser")
	repoNWO, err := core.NewRepoNWO("testowner", "testrepo")
	assert.NoError(t, err)
	repository := &core.Repository{ID: 1, NWO: *repoNWO, Private: true}

	// Create 5 memories, but only return 3 (simulating limit behavior)
	allMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "newest memory"},
		{ID: core.MemoryID("memory2"), Subject: "second newest memory"},
		{ID: core.MemoryID("memory3"), Subject: "third newest memory"},
		{ID: core.MemoryID("memory4"), Subject: "fourth newest memory"},
		{ID: core.MemoryID("memory5"), Subject: "oldest memory"},
	}

	// Repository should return only the first 3 (most recent) when limit=3
	expectedMemories := allMemories[:3]

	memoryRepository := &MockMemoryRepository{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, repository.ID, repoID)
			assert.Equal(t, uint(3), limit)
			// Simulate repository behavior: return only the limit number of memories
			return expectedMemories, nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return repository, nil
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service": true,
	})

	secretScanner := &MockSecretScanner{}
	service := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	result, err := service.GetRecentMemories(t.Context(), user, *repoNWO, 3)

	assert.NoError(t, err)
	assert.Len(t, result, 3, "Should return exactly 3 memories")
	assert.Equal(t, expectedMemories, result)

	// Verify that the older memories (memory4, memory5) are not included
	resultIDs := make([]string, len(result))
	for i, memory := range result {
		resultIDs[i] = string(memory.ID)
	}
	assert.NotContains(t, resultIDs, "memory4")
	assert.NotContains(t, resultIDs, "memory5")
}

// Tests for public repository behavior (Private: false)

func TestCreateMemoryPublicRepositoryFailure(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "public-repo")
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNwo,
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}

	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			t.Error("Save should not be called for public repository")
			return nil
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: false}, nil // Public repository
		},
	}

	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.CreateMemory(t.Context(), memory)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for public repository")
}

func TestGetMemoriesPublicRepositoryFailure(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "public-repo")
	user := core.User{ID: 1, Login: "testuser"}
	assert.NoError(t, err, "expected no error when creating RepoNWO")

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for public repository")
			return nil, nil
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: false}, nil // Public repository
		},
	}

	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	_, err = memoryService.GetMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for public repository")
}

func TestGetRecentMemoriesPublicRepositoryFailure(t *testing.T) {
	user := core.NewUser(123, "testuser")
	repoNWO, err := core.NewRepoNWO("testowner", "public-repo")
	assert.NoError(t, err)

	memoryRepository := &MockMemoryRepository{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			t.Error("FindRecentByRepository should not be called for public repository")
			return nil, nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: false}, nil // Public repository
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service": true,
	})

	secretScanner := &MockSecretScanner{}
	service := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	result, err := service.GetRecentMemories(t.Context(), user, *repoNWO, 5)

	assert.Error(t, err)
	assert.Equal(t, core.ErrFeatureNotEnabled, err, "expected feature not enabled error for public repository")
	assert.Nil(t, result)
}

func TestDeleteMemoryPublicRepositoryFailure(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "public-repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")
	memoryID := core.MemoryID("test-memory-id")

	memoryRepository := &MockMemoryRepository{
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for public repository")
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: false}, nil // Public repository
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": true,
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteMemory(t.Context(), user, *repoNwo, memoryID)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for public repository")
}

func TestDeleteAllMemoriesPublicRepositoryFailure(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "public-repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for public repository")
			return nil, nil
		},
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for public repository")
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: false}, nil // Public repository
		},
	}

	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": true,
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteAllMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for public repository")
}

// Tests for disallowed repositories

func TestCreateMemoryDisallowedRepository(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "disallowed-repo")
	assert.NoError(t, err, "expected no error when creating RepoNWO")
	memory := &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNwo,
			User:          core.User{ID: 1, Login: "testuser"},
		},
	}

	memoryRepository := &MockMemoryRepository{
		SaveFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			t.Error("Save should not be called for disallowed repository")
			return nil
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Private repository but disallowed
		},
	}

	// Enable disallowed repos feature flag
	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":         true,
		"copilot_swe_agent_memory_secret_scanning": true,
		"copilot_swe_agent_disallow":               true, // Repository is disallowed
	})

	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.CreateMemory(t.Context(), memory)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestGetMemoriesDisallowedRepository(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "disallowed-repo")
	user := core.User{ID: 1, Login: "testuser"}
	assert.NoError(t, err, "expected no error when creating RepoNWO")

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}
	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Private repository but disallowed
		},
	}

	// Enable disallowed repos feature flag
	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":         true,
		"copilot_swe_agent_memory_secret_scanning": true,
		"copilot_swe_agent_disallow":               true, // Repository is disallowed
	})

	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	_, err = memoryService.GetMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestGetRecentMemoriesDisallowedRepository(t *testing.T) {
	user := core.NewUser(123, "testuser")
	repoNWO, err := core.NewRepoNWO("testowner", "disallowed-repo")
	assert.NoError(t, err)

	memoryRepository := &MockMemoryRepository{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			t.Error("FindRecentByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Private repository but disallowed
		},
	}

	// Enable disallowed repos feature flag
	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service": true,
		"copilot_swe_agent_disallow":       true, // Repository is disallowed
	})

	secretScanner := &MockSecretScanner{}
	service := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	result, err := service.GetRecentMemories(t.Context(), user, *repoNWO, 5)

	assert.Error(t, err)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
	assert.Nil(t, result)
}

func TestDeleteMemoryDisallowedRepository(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "disallowed-repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")
	memoryID := core.MemoryID("test-memory-id")

	memoryRepository := &MockMemoryRepository{
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for disallowed repository")
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Private repository but disallowed
		},
	}

	// Enable disallowed repos feature flag
	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": true,
		"copilot_swe_agent_disallow":        true, // Repository is disallowed
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteMemory(t.Context(), user, *repoNwo, memoryID)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestDeleteAllMemoriesDisallowedRepository(t *testing.T) {
	repoNwo, err := core.NewRepoNWO("test", "disallowed-repo")
	assert.NoError(t, err)

	user := core.NewUser(1, "testuser")

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for disallowed repository")
			return nil, nil
		},
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for disallowed repository")
			return nil
		},
	}

	repositoryStore := &MockRepositoryStore{
		FindByNWOFunc: func(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
			return &core.Repository{ID: 1, NWO: nwo, Private: true}, nil // Private repository but disallowed
		},
	}

	// Enable disallowed repos feature flag
	featureFlagClient := featureflags.NewNoopClient(map[string]bool{
		"copilot_swe_agent_memory_service":  true,
		"copilot_swe_agent_memory_deletion": true,
		"copilot_swe_agent_disallow":        true, // Repository is disallowed
	})

	secretScanner := &MockSecretScanner{}
	memoryService := core.NewMemoryService(memoryRepository, repositoryStore, featureFlagClient, secretScanner, observability.NewNoopExporters())

	err = memoryService.DeleteAllMemories(t.Context(), user, *repoNwo)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}
