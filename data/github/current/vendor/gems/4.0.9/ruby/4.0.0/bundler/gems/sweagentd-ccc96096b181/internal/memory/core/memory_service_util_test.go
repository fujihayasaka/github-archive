package core_test

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

// Shared test fixtures for memory service tests

var secretScanner = &MockSecretScanner{
	ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
		return make([]core.MemorySecret, 0), nil // Simulate no secrets found
	},
}

var featureFlagClient = featureflags.NewNoopClient(
	map[string]bool{
		"copilot-feature-agentic-memory":           true,
		"copilot_swe_agent_memory_secret_scanning": true,
	},
)

// expectedLimit represents an upper bound on the number of memories to retrieve
const expectedLimit = uint(5)

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

type MockSecretScanner struct {
	ScanFunc func(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error)
}

func (m *MockSecretScanner) Scan(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
	return m.ScanFunc(ctx, repoNWO, memory)
}

type MockMemoryEnablementChecker struct {
	Enabled    bool
	Err        error
	Called     bool
	LastUserID int64
}

func (m *MockMemoryEnablementChecker) IsMemoryEnabled(ctx context.Context, userID int64) (bool, error) {
	m.Called = true
	m.LastUserID = userID
	return m.Enabled, m.Err
}

// --- Test Fixture Helpers ---

// testUser returns a standard test user
func testUser() core.User {
	return core.NewUser(1, "testuser")
}

// testRepoNWO returns a standard test repository NWO
func testRepoNWO(t *testing.T) core.RepoNWO {
	t.Helper()
	nwo, err := core.NewRepoNWO("test", "repo")
	require.NoError(t, err)
	return *nwo
}

// testMemoryID returns a standard test memory ID
func testMemoryID() core.MemoryID {
	return core.MemoryID("test-memory-id")
}

// testMemory returns a standard test memory with the given repoNWO and user
func testMemory(repoNWO core.RepoNWO, user core.User) *core.Memory {
	return &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           repoNWO,
			User:          user,
		},
	}
}

// --- Memory Service Construction Helpers ---

// memoryServiceConfig holds configuration for building a test MemoryService
type memoryServiceConfig struct {
	ffClient          featureflags.Client
	secretScanner     core.SecretScanner
	enablementChecker core.MemoryEnablementChecker
}

// memoryServiceOption is a functional option for configuring test MemoryService
type memoryServiceOption func(*memoryServiceConfig)

// withDisallowedRepo configures the service to treat the repository as disallowed
func withDisallowedRepo() memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.ffClient = featureflags.NewNoopClient(map[string]bool{
			"copilot-feature-agentic-memory": true,
			"copilot_swe_agent_disallow":     true,
		})
	}
}

// withFeatureFlags configures the service with custom feature flags
func withFeatureFlags(flags map[string]bool) memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.ffClient = featureflags.NewNoopClient(flags)
	}
}

// withSecretScanner configures the service with a custom secret scanner
func withSecretScanner(scanner core.SecretScanner) memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.secretScanner = scanner
	}
}

// withEnablementChecker configures the service with a custom enablement checker
func withEnablementChecker(checker core.MemoryEnablementChecker) memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.enablementChecker = checker
	}
}

// withNilEnablementChecker configures the service with nil enablement checker (feature disabled)
func withNilEnablementChecker() memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.enablementChecker = nil
	}
}

// newTestMemoryService creates a MemoryService with sensible test defaults
func newTestMemoryService(
	t *testing.T,
	repo *MockMemoryRepository,
	opts ...memoryServiceOption,
) core.MemoryService {
	t.Helper()

	cfg := &memoryServiceConfig{
		ffClient:          featureFlagClient,
		secretScanner:     secretScanner,
		enablementChecker: &MockMemoryEnablementChecker{Enabled: true},
	}
	for _, opt := range opts {
		opt(cfg)
	}

	return core.NewMemoryService(
		repo,
		cfg.ffClient,
		cfg.secretScanner,
		observability.NewNoopExporters(),
		cfg.enablementChecker,
	)
}

// --- Repository Helpers ---

// testRepository creates a test repository from a RepoNWO with the given privacy setting
func testRepository(repoNWO core.RepoNWO, private bool) *core.Repository {
	return &core.Repository{ID: 1, NWO: repoNWO, Private: private}
}
