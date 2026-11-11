package core_test

import (
	"context"
	"maps"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

// codingAgentCtx returns a context with the copilot-developer integration ID,
// which maps to the coding agent per-client feature flag.
func codingAgentCtx(t *testing.T) context.Context {
	t.Helper()
	return featureflags.ContextWithIntegrationID(t.Context(), "copilot-developer")
}

// Shared test fixtures for memory service tests

var secretScanner = &MockSecretScanner{
	ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
		return make([]core.MemorySecret, 0), nil // Simulate no secrets found
	},
}

var featureFlagClient = featureflags.NewNoopClient(
	map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_feature_agentic_memory_user_scoped":   true,
		"copilot_swe_agent_memory_secret_scanning":     true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
	},
)

// expectedLimit represents an upper bound on the number of memories to retrieve
const expectedLimit = uint(5)

type distributionCall struct {
	key   string
	tags  stats.Tags
	value float64
}

type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

type metricsCapturingStatter struct {
	stats.NullClient

	distributionCalls []distributionCall
	counterCalls      []counterCall
}

func (m *metricsCapturingStatter) Distribution(key string, tags stats.Tags, value float64) {
	copiedTags := make(stats.Tags, len(tags))
	maps.Copy(copiedTags, tags)

	m.distributionCalls = append(m.distributionCalls, distributionCall{
		key:   key,
		tags:  copiedTags,
		value: value,
	})
}

func (m *metricsCapturingStatter) Counter(key string, tags stats.Tags, value int64) {
	copiedTags := make(stats.Tags, len(tags))
	maps.Copy(copiedTags, tags)

	m.counterCalls = append(m.counterCalls, counterCall{
		key:   key,
		tags:  copiedTags,
		value: value,
	})
}

func findDistributionCall(calls []distributionCall, key string) (distributionCall, bool) {
	for _, call := range calls {
		if call.key == key {
			return call, true
		}
	}

	return distributionCall{}, false
}

func findCounterCall(calls []counterCall, key string) (counterCall, bool) {
	for _, call := range calls {
		if call.key == key {
			return call, true
		}
	}

	return counterCall{}, false
}

type MockMemoryStore struct {
	SaveForRepositoryFunc           func(repoID core.RepositoryID, memory *core.Memory) error
	SaveBatchForRepositoryFunc      func(repoID core.RepositoryID, memories []*core.Memory) error
	FindByRepositoryFunc            func(repoID core.RepositoryID) ([]*core.Memory, error)
	FindByFactForRepositoryFunc     func(repoID core.RepositoryID, fact string) ([]*core.Memory, error)
	FindRecentByRepositoryFunc      func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error)
	DeleteForRepositoryFunc         func(repoID core.RepositoryID, id core.MemoryID) error
	DeleteBatchForRepoFunc          func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error)
	DeleteAllForRepositoryFunc      func(repoID core.RepositoryID) error
	CountByRepositoryFunc           func(repoID core.RepositoryID) (int, error)
	CountByUserFunc                 func(userID uint64, billingFilter *core.BillingEntity) (int, error)
	SaveForUserFunc                 func(userID uint64, memory *core.Memory) error
	SaveBatchForUserFunc            func(userID uint64, memories []*core.Memory) error
	FindByUserFunc                  func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error)
	FindByFactForUserFunc           func(userID uint64, fact string) ([]*core.Memory, error)
	FindRecentByUserFunc            func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error)
	DeleteForUserFunc               func(userID uint64, id core.MemoryID) error
	DeleteBatchForUserFunc          func(userID uint64, ids []core.MemoryID) (*core.BatchDeleteResult, error)
	DeleteAllForUserFunc            func(userID uint64) error
	ListBillingEntityMemoriesFunc   func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error)
	DeleteBillingEntityMemoriesFunc func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error)
}

func (m *MockMemoryStore) SaveForRepository(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	return m.SaveForRepositoryFunc(repoID, memory)
}

func (m *MockMemoryStore) SaveBatchForRepository(ctx context.Context, repoID core.RepositoryID, memories []*core.Memory) error {
	if m.SaveBatchForRepositoryFunc != nil {
		return m.SaveBatchForRepositoryFunc(repoID, memories)
	}
	return nil
}

func (m *MockMemoryStore) SaveForUser(ctx context.Context, userID uint64, memory *core.Memory) error {
	if m.SaveForUserFunc != nil {
		return m.SaveForUserFunc(userID, memory)
	}
	return nil
}

func (m *MockMemoryStore) SaveBatchForUser(ctx context.Context, userID uint64, memories []*core.Memory) error {
	if m.SaveBatchForUserFunc != nil {
		return m.SaveBatchForUserFunc(userID, memories)
	}
	return nil
}

func (m *MockMemoryStore) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	return m.FindByRepositoryFunc(repoID)
}

func (m *MockMemoryStore) FindByFactForRepository(ctx context.Context, repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
	if m.FindByFactForRepositoryFunc != nil {
		return m.FindByFactForRepositoryFunc(repoID, fact)
	}
	return nil, nil
}

func (m *MockMemoryStore) FindByUser(ctx context.Context, userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
	if m.FindByUserFunc != nil {
		return m.FindByUserFunc(userID, billingFilter)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryStore) FindByFactForUser(ctx context.Context, userID uint64, fact string) ([]*core.Memory, error) {
	if m.FindByFactForUserFunc != nil {
		return m.FindByFactForUserFunc(userID, fact)
	}
	return nil, nil
}

func (m *MockMemoryStore) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	if m.FindRecentByRepositoryFunc != nil {
		return m.FindRecentByRepositoryFunc(repoID, limit)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryStore) FindRecentByUser(ctx context.Context, userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
	if m.FindRecentByUserFunc != nil {
		return m.FindRecentByUserFunc(userID, limit, billingFilter)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryStore) DeleteForRepository(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	if m.DeleteForRepositoryFunc != nil {
		return m.DeleteForRepositoryFunc(repoID, id)
	}
	return nil
}

func (m *MockMemoryStore) DeleteForUser(ctx context.Context, userID uint64, id core.MemoryID) error {
	if m.DeleteForUserFunc != nil {
		return m.DeleteForUserFunc(userID, id)
	}
	return nil
}

func (m *MockMemoryStore) DeleteBatchForRepository(ctx context.Context, repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	if m.DeleteBatchForRepoFunc != nil {
		return m.DeleteBatchForRepoFunc(repoID, ids)
	}
	return &core.BatchDeleteResult{Deleted: ids}, nil
}

func (m *MockMemoryStore) DeleteBatchForUser(ctx context.Context, userID uint64, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	if m.DeleteBatchForUserFunc != nil {
		return m.DeleteBatchForUserFunc(userID, ids)
	}
	return &core.BatchDeleteResult{Deleted: ids}, nil
}

func (m *MockMemoryStore) DeleteAllForRepository(ctx context.Context, repoID core.RepositoryID) error {
	if m.DeleteAllForRepositoryFunc != nil {
		return m.DeleteAllForRepositoryFunc(repoID)
	}
	return nil
}

func (m *MockMemoryStore) CountByRepository(ctx context.Context, repoID core.RepositoryID) (int, error) {
	if m.CountByRepositoryFunc != nil {
		return m.CountByRepositoryFunc(repoID)
	}
	return 0, nil
}

func (m *MockMemoryStore) CountByUser(ctx context.Context, userID uint64, billingFilter *core.BillingEntity) (int, error) {
	if m.CountByUserFunc != nil {
		return m.CountByUserFunc(userID, billingFilter)
	}
	return 0, nil
}

func (m *MockMemoryStore) DeleteAllForUser(ctx context.Context, userID uint64) error {
	if m.DeleteAllForUserFunc != nil {
		return m.DeleteAllForUserFunc(userID)
	}
	return nil
}

func (m *MockMemoryStore) ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
	if m.ListBillingEntityMemoriesFunc != nil {
		return m.ListBillingEntityMemoriesFunc(filter, pageRequest)
	}
	return &core.MemoryPage{}, nil
}

func (m *MockMemoryStore) DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
	if m.DeleteBillingEntityMemoriesFunc != nil {
		return m.DeleteBillingEntityMemoriesFunc(filter, pageRequest)
	}
	return &core.BillingEntityDeleteResult{}, nil
}

type MockSecretScanner struct {
	ScanFunc func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error)
}

func (m *MockSecretScanner) Scan(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
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
	ffClient              featureflags.Client
	secretScanner         core.SecretScanner
	enablementChecker     core.MemoryEnablementChecker
	obsv                  observability.Exporters
	billingEntityResolver core.BillingEntityResolver
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

// withVoting configures the service with memory voting enabled
func withVoting() memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.ffClient = featureflags.NewNoopClient(map[string]bool{
			"copilot-feature-agentic-memory":               true,
			"copilot_feature_agentic_memory_user_scoped":   true,
			"copilot_swe_agent_memory_voting_coding_agent": true,
			"copilot_swe_agent_memory_secret_scanning":     true,
		})
	}
}

// withAsyncVoting configures the service with async voting enabled.
// The async feature flag moves secret scanning and Cosmos storage off the HTTP
// critical path into a background goroutine.
func withAsyncVoting() memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.ffClient = featureflags.NewNoopClient(map[string]bool{
			"copilot-feature-agentic-memory":               true,
			"copilot_feature_agentic_memory_user_scoped":   true,
			"copilot_swe_agent_memory_voting_coding_agent": true,
			"copilot_swe_agent_memory_secret_scanning":     true,
			"copilot_swe_agent_memory_async_voting":        true,
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

func withStatter(statter stats.Client) memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.obsv.Statter = statter
	}
}

// withNilEnablementChecker configures the service with nil enablement checker (feature disabled)
func withNilEnablementChecker() memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.enablementChecker = nil
	}
}

// withBillingEntityResolver configures the service with a custom billing entity resolver
func withBillingEntityResolver(resolver core.BillingEntityResolver) memoryServiceOption {
	return func(c *memoryServiceConfig) {
		c.billingEntityResolver = resolver
	}
}

// MockBillingEntityResolver is a test double for core.BillingEntityResolver
type MockBillingEntityResolver struct {
	ResolveFunc func(ctx context.Context, userID int64) (core.BillingEntity, error)
}

func (m *MockBillingEntityResolver) ResolveBillingEntity(ctx context.Context, userID int64) (core.BillingEntity, error) {
	return m.ResolveFunc(ctx, userID)
}

// newTestMemoryService creates a MemoryService with sensible test defaults
func newTestMemoryService(
	t *testing.T,
	repo *MockMemoryStore,
	opts ...memoryServiceOption,
) core.MemoryService {
	t.Helper()

	cfg := &memoryServiceConfig{
		ffClient:          featureFlagClient,
		secretScanner:     secretScanner,
		enablementChecker: &MockMemoryEnablementChecker{Enabled: true},
		obsv:              observability.NewNoopExporters(),
	}
	for _, opt := range opts {
		opt(cfg)
	}

	return core.NewMemoryService(
		repo,
		cfg.ffClient,
		cfg.secretScanner,
		cfg.obsv,
		cfg.enablementChecker,
		cfg.billingEntityResolver,
	)
}

// --- Repository Helpers ---

// testRepository creates a test repository from a RepoNWO with the given privacy setting
func testRepository(repoNWO core.RepoNWO, private bool) *core.Repository {
	return &core.Repository{ID: 1, NWO: repoNWO, Private: private, OwnerID: 999}
}
