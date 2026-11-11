package memoryhttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
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
	CreateMemoryFunc       func(memory *core.Memory, repository *core.Repository) error
	GetMemoriesFunc        func(user core.User, repository *core.Repository) ([]*core.Memory, error)
	GetRecentMemoriesFunc  func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error)
	DeleteMemoryFunc       func(user core.User, repository *core.Repository, memoryID core.MemoryID) error
	DeleteAllMemoriesFunc  func(user core.User, repository *core.Repository) error
	CheckMemoryEnabledFunc func(userID int64) (bool, error)
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

func (m *MockMemoryService) DeleteMemory(ctx context.Context, user core.User, repository *core.Repository, memoryID core.MemoryID) error {
	if m.DeleteMemoryFunc != nil {
		return m.DeleteMemoryFunc(user, repository, memoryID)
	}
	return nil
}

func (m *MockMemoryService) DeleteAllMemories(ctx context.Context, user core.User, repository *core.Repository) error {
	if m.DeleteAllMemoriesFunc != nil {
		return m.DeleteAllMemoriesFunc(user, repository)
	}
	return nil
}

func (m *MockMemoryService) CheckMemoryEnabled(ctx context.Context, userID int64) (bool, error) {
	if m.CheckMemoryEnabledFunc != nil {
		return m.CheckMemoryEnabledFunc(userID)
	}
	return true, nil
}

// createTestContext creates a test context with user information
func createTestContext() context.Context {
	return requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
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
	handler.RegisterRoutes(r)
	return r
}

// createTestRouterWithInternalPrefix creates a test router with /internal prefix like in production
func createTestRouterWithInternalPrefix(handler *MemoryHandler) *chi.Mux {
	r := chi.NewRouter()
	r.Route("/internal", func(r chi.Router) {
		handler.RegisterRoutes(r)
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

// createTestSearchRequest creates a standardized test MemorySearchRequest
func createTestSearchRequest() MemorySearchRequest {
	return MemorySearchRequest{
		Question: "test question",
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
	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), appProvider)
	router := createTestRouter(handler)
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
	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), appProvider)
	router := createTestRouterWithInternalPrefix(handler)
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
