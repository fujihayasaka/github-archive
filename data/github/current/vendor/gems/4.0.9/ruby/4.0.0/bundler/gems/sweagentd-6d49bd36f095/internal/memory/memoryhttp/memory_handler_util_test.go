package memoryhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/require"
)

// MockMemoryService is a mock implementation of MemoryService for testing.
type MockMemoryService struct {
	CreateMemoryFunc              func(memory *core.Memory, repository *core.Repository) error
	GetMemoriesFunc               func(user core.User, repository *core.Repository) ([]*core.Memory, error)
	GetRecentMemoriesFunc         func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error)
	GetTopMemoriesFunc            func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error)
	DeleteMemoryFunc              func(user core.User, repository *core.Repository, memoryID core.MemoryID) error
	DeleteMemoriesFunc            func(user core.User, repository *core.Repository, memoryIDs []core.MemoryID) (*core.BatchDeleteResult, error)
	DeleteAllMemoriesFunc         func(user core.User, repository *core.Repository) error
	CheckMemoryEnabledFunc        func(userID int64, repository *core.Repository) (bool, error)
	VoteOnMemoryFunc              func(user core.User, repository *core.Repository, fact string, vote *core.Vote) error
	CreateUserMemoryFunc          func(memory *core.Memory, user core.User) error
	GetUserMemoriesFunc           func(user core.User, query core.UserMemoryQuery) ([]*core.Memory, error)
	GetRecentUserMemoriesFunc     func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error)
	GetTopUserMemoriesFunc        func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error)
	DeleteUserMemoryFunc          func(user core.User, memoryID core.MemoryID) error
	DeleteUserMemoriesFunc        func(user core.User, memoryIDs []core.MemoryID) (*core.BatchDeleteResult, error)
	DeleteAllUserMemoriesFunc     func(user core.User) error
	CheckUserMemoryEnabledFunc    func(userID int64) (bool, error)
	VoteOnUserMemoryFunc          func(user core.User, fact string, vote *core.Vote) error
	CountMemoriesFunc             func(user core.User, repository *core.Repository) (int, error)
	CountUserMemoriesFunc         func(user core.User, query core.UserMemoryQuery) (int, error)
	ListBillingEntityMemoriesFunc func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error)
}

func (m *MockMemoryService) CreateMemory(ctx context.Context, memory *core.Memory, repository *core.Repository) error {
	return m.CreateMemoryFunc(memory, repository)
}

func (m *MockMemoryService) GetMemories(ctx context.Context, user core.User, repository *core.Repository) ([]*core.Memory, error) {
	return m.GetMemoriesFunc(user, repository)
}

func (m *MockMemoryService) GetRecentMemories(ctx context.Context, user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
	if m.GetRecentMemoriesFunc != nil {
		return m.GetRecentMemoriesFunc(user, repository, limit)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryService) GetTopMemories(ctx context.Context, user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
	if m.GetTopMemoriesFunc != nil {
		return m.GetTopMemoriesFunc(user, repository, limit)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryService) DeleteMemory(ctx context.Context, user core.User, repository *core.Repository, memoryID core.MemoryID) error {
	if m.DeleteMemoryFunc != nil {
		return m.DeleteMemoryFunc(user, repository, memoryID)
	}
	return nil
}

func (m *MockMemoryService) DeleteMemories(ctx context.Context, user core.User, repository *core.Repository, memoryIDs []core.MemoryID) (*core.BatchDeleteResult, error) {
	if m.DeleteMemoriesFunc != nil {
		return m.DeleteMemoriesFunc(user, repository, memoryIDs)
	}
	return &core.BatchDeleteResult{Deleted: memoryIDs}, nil
}

func (m *MockMemoryService) DeleteAllMemories(ctx context.Context, user core.User, repository *core.Repository) error {
	if m.DeleteAllMemoriesFunc != nil {
		return m.DeleteAllMemoriesFunc(user, repository)
	}
	return nil
}

func (m *MockMemoryService) CheckMemoryEnabled(ctx context.Context, userID int64, repository *core.Repository) (bool, error) {
	if m.CheckMemoryEnabledFunc != nil {
		return m.CheckMemoryEnabledFunc(userID, repository)
	}
	return true, nil
}

func (m *MockMemoryService) VoteOnMemory(ctx context.Context, user core.User, repository *core.Repository, fact string, vote *core.Vote) error {
	if m.VoteOnMemoryFunc != nil {
		return m.VoteOnMemoryFunc(user, repository, fact, vote)
	}
	return nil
}

func (m *MockMemoryService) CreateUserMemory(ctx context.Context, memory *core.Memory, user core.User) error {
	if m.CreateUserMemoryFunc != nil {
		return m.CreateUserMemoryFunc(memory, user)
	}
	return nil
}

func (m *MockMemoryService) GetUserMemories(ctx context.Context, user core.User, query core.UserMemoryQuery) ([]*core.Memory, error) {
	if m.GetUserMemoriesFunc != nil {
		return m.GetUserMemoriesFunc(user, query)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryService) GetRecentUserMemories(ctx context.Context, user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
	if m.GetRecentUserMemoriesFunc != nil {
		return m.GetRecentUserMemoriesFunc(user, limit, query)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryService) GetTopUserMemories(ctx context.Context, user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
	if m.GetTopUserMemoriesFunc != nil {
		return m.GetTopUserMemoriesFunc(user, limit, query)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryService) DeleteUserMemory(ctx context.Context, user core.User, memoryID core.MemoryID) error {
	if m.DeleteUserMemoryFunc != nil {
		return m.DeleteUserMemoryFunc(user, memoryID)
	}
	return nil
}

func (m *MockMemoryService) DeleteUserMemories(ctx context.Context, user core.User, memoryIDs []core.MemoryID) (*core.BatchDeleteResult, error) {
	if m.DeleteUserMemoriesFunc != nil {
		return m.DeleteUserMemoriesFunc(user, memoryIDs)
	}
	return &core.BatchDeleteResult{Deleted: memoryIDs}, nil
}

func (m *MockMemoryService) DeleteAllUserMemories(ctx context.Context, user core.User) error {
	if m.DeleteAllUserMemoriesFunc != nil {
		return m.DeleteAllUserMemoriesFunc(user)
	}
	return nil
}

func (m *MockMemoryService) CheckUserMemoryEnabled(ctx context.Context, userID int64) (bool, error) {
	if m.CheckUserMemoryEnabledFunc != nil {
		return m.CheckUserMemoryEnabledFunc(userID)
	}
	return true, nil
}

func (m *MockMemoryService) VoteOnUserMemory(ctx context.Context, user core.User, fact string, vote *core.Vote) error {
	if m.VoteOnUserMemoryFunc != nil {
		return m.VoteOnUserMemoryFunc(user, fact, vote)
	}
	return nil
}

func (m *MockMemoryService) CountMemories(ctx context.Context, user core.User, repository *core.Repository) (int, error) {
	if m.CountMemoriesFunc != nil {
		return m.CountMemoriesFunc(user, repository)
	}
	return 0, nil
}

func (m *MockMemoryService) CountUserMemories(ctx context.Context, user core.User, query core.UserMemoryQuery) (int, error) {
	if m.CountUserMemoriesFunc != nil {
		return m.CountUserMemoriesFunc(user, query)
	}
	return 0, nil
}

func (m *MockMemoryService) ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
	if m.ListBillingEntityMemoriesFunc != nil {
		return m.ListBillingEntityMemoriesFunc(filter, pageRequest)
	}
	return &core.MemoryPage{}, nil
}

func (m *MockMemoryService) DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
	return &core.BillingEntityDeleteResult{}, nil
}

// createTestContext creates a test context with user information
func createTestContext() context.Context {
	return requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
			},
		},
	})
}

// createTestContextWithoutToken creates a test context without a token,
// useful for testing authorization failure when user-token fallback should not succeed.
func createTestContextWithoutToken() context.Context {
	return requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
		},
	})
}

// createTestContextWithToken creates a test context with user info that includes a token,
// needed for tests that set GHTwirp (which triggers token access verification).
func createTestContextWithToken() context.Context {
	return requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
			},
		},
	})
}

// createTestRequest creates a test request with the specified parameters
func createTestRequest(ctx context.Context, method, path, body string) *http.Request {
	req, _ := http.NewRequestWithContext(ctx, method, path, strings.NewReader(body))
	return req
}

// createTestRouter creates a test router with the specified handler
func createTestRouter(handler *MemoryHandler) *chi.Mux {
	r := chi.NewRouter()
	handler.RegisterRepoRoutes(r)
	return r
}

// createTestUserRouter creates a test router with user-scoped routes
func createTestUserRouter(handler *MemoryHandler) *chi.Mux {
	r := chi.NewRouter()
	handler.RegisterUserRoutes(r)
	return r
}

// createTestRouterWithInternalPrefix creates a test router with /internal prefix like in production
func createTestRouterWithInternalPrefix(handler *MemoryHandler) *chi.Mux {
	r := chi.NewRouter()
	r.Route("/internal", func(r chi.Router) {
		handler.RegisterRepoRoutes(r)
	})
	return r
}

// createTestCombinedRouter creates a test router with both repo-scoped and user-scoped routes
// registered under /internal, mirroring the production configuration in cmd/http/main.go.
func createTestCombinedRouter(handler *MemoryHandler) *chi.Mux {
	r := chi.NewRouter()
	r.Route("/internal", func(r chi.Router) {
		handler.RegisterRepoRoutes(r)
		handler.RegisterUserRoutes(r)
	})
	return r
}

// Test data factory functions

// createTestMemoryDTO creates a standardized test MemoryDTO
func createTestMemoryDTO() *MemoryDTO {
	return &MemoryDTO{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: MemorySourceDTO{
			InteractionID: "interaction1",
			Agent:         "test-agent",
		},
	}
}

// createTestCoreMemory creates a standardized test core.Memory
func createTestCoreMemory() *core.Memory {
	return &core.Memory{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"source1"},
		Source: core.MemorySource{
			InteractionID: "interaction1",
			Agent:         "test-agent",
			NWO: core.RepoNWO{
				Owner: "test",
				Repo:  "repo",
			},
			User: core.User{
				ID:    1,
				Login: "testuser",
			},
		},
	}
}

// createTestHandlerAndRouter creates a handler with mock service and router for testing
func createTestHandlerAndRouter(t *testing.T, mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	// Use NoopClientFactory with a client that returns a proper client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	appProvider := agenticapptest.NewTestProvider(t)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: appProvider,
	})
	router := createTestRouter(handler)
	return handler, router
}

// createTestUserHandlerAndRouter creates a handler with mock service and user-scoped router for testing
func createTestUserHandlerAndRouter(t *testing.T, mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	appProvider := agenticapptest.NewTestProvider(t)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: appProvider,
	})
	router := createTestUserRouter(handler)
	return handler, router
}

// createTestHandlerAndRouterWithInternal creates a handler with mock service and router with /internal prefix
func createTestHandlerAndRouterWithInternal(t *testing.T, mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	// Use NoopClientFactory with a client that returns a proper client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	appProvider := agenticapptest.NewTestProvider(t)
	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:     mockService,
		GHFactory:   mockGHFactory,
		Obsv:        observability.NewNoopExporters(),
		AppProvider: appProvider,
	})
	router := createTestRouterWithInternalPrefix(handler)
	return handler, router
}

// createTestHandlerAndRouterWithObsv creates a handler with custom observability exporters for testing hydro events.
func createTestHandlerAndRouterWithObsv(t *testing.T, mockService *MockMemoryService, obsv observability.Exporters, ffClient ...featureflags.Client) (*MemoryHandler, *chi.Mux) {
	t.Helper()
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	appProvider := agenticapptest.NewTestProvider(t)

	var fc featureflags.Client
	if len(ffClient) > 0 {
		fc = ffClient[0]
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service:           mockService,
		GHFactory:         mockGHFactory,
		Obsv:              obsv,
		AppProvider:       appProvider,
		FeatureFlagClient: fc,
	})
	router := createTestRouter(handler)
	return handler, router
}

// executeRequestAndRecord executes a request and returns the response recorder
func executeRequestAndRecord(router *chi.Mux, req *http.Request) *httptest.ResponseRecorder {
	rr := httptest.NewRecorder()
	router.ServeHTTP(rr, req)
	return rr
}

// marshalToJSON marshals an object to JSON string for test requests
func marshalToJSON(t *testing.T, obj any) string {
	bytes, err := json.Marshal(obj)
	require.NoError(t, err)
	return string(bytes)
}

// CustomPermsClient embeds NoopClient and overrides permissions to expose distinct roles.
type CustomPermsClient struct {
	*github.NoopClient
}

func (c *CustomPermsClient) GetUserPermissionsForRepository(ctx context.Context, owner, repo, username string) (*github.RepositoryPermissions, error) {
	switch {
	case strings.HasSuffix(username, "-admin"):
		return &github.RepositoryPermissions{
			Admin:    true,
			Maintain: true,
			Push:     true,
			Triage:   true,
			Pull:     true,
		}, nil
	case strings.HasSuffix(username, "-maintain"):
		return &github.RepositoryPermissions{
			Admin:    false,
			Maintain: true,
			Push:     true, // maintain includes push capability
			Triage:   true,
			Pull:     true,
		}, nil
	case strings.HasSuffix(username, "-push"):
		return &github.RepositoryPermissions{
			Push:   true,
			Triage: true,
			Pull:   true,
		}, nil
	case strings.HasSuffix(username, "-read"):
		return &github.RepositoryPermissions{
			// Read / triage user: only pull (and optionally triage if you want, but leaving triage false enforces failure)
			Pull: true,
		}, nil
	default:
		// Default to write/push
		return &github.RepositoryPermissions{
			Push:   true,
			Triage: true,
			Pull:   true,
		}, nil
	}
}
