package http

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
)

// MockMemoryService is a mock implementation of MemoryService for testing.
type MockMemoryService struct {
	CreateMemoryFunc      func(memory *core.Memory) error
	GetMemoriesFunc       func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error)
	GetRecentMemoriesFunc func(user core.User, repoNWO core.RepoNWO, limit uint) ([]*core.Memory, error)
	DeleteMemoryFunc      func(user core.User, repoNWO core.RepoNWO, memoryID core.MemoryID) error
	DeleteAllMemoriesFunc func(user core.User, repoNWO core.RepoNWO) error
}

func (m *MockMemoryService) CreateMemory(ctx context.Context, memory *core.Memory) error {
	return m.CreateMemoryFunc(memory)
}

func (m *MockMemoryService) GetMemories(ctx context.Context, user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
	return m.GetMemoriesFunc(user, repoNWO)
}

func (m *MockMemoryService) GetRecentMemories(ctx context.Context, user core.User, repoNWO core.RepoNWO, limit uint) ([]*core.Memory, error) {
	if m.GetRecentMemoriesFunc != nil {
		return m.GetRecentMemoriesFunc(user, repoNWO, limit)
	}
	return []*core.Memory{}, nil
}

func (m *MockMemoryService) DeleteMemory(ctx context.Context, user core.User, repoNWO core.RepoNWO, memoryID core.MemoryID) error {
	if m.DeleteMemoryFunc != nil {
		return m.DeleteMemoryFunc(user, repoNWO, memoryID)
	}
	return nil
}

func (m *MockMemoryService) DeleteAllMemories(ctx context.Context, user core.User, repoNWO core.RepoNWO) error {
	if m.DeleteAllMemoriesFunc != nil {
		return m.DeleteAllMemoriesFunc(user, repoNWO)
	}
	return nil
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
func createTestRequest(method, path, body string, ctx context.Context) *http.Request {
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
func createTestHandlerAndRouter(mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	// Use NoopClientFactory with a client that returns a proper client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters())
	router := createTestRouter(handler)
	return handler, router
}

// createTestHandlerAndRouterWithInternal creates a handler with mock service and router with /internal prefix
func createTestHandlerAndRouterWithInternal(mockService *MockMemoryService) (*MemoryHandler, *chi.Mux) {
	// Use NoopClientFactory with a client that returns a proper client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}
	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters())
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
func marshalToJSON(t *testing.T, obj interface{}) string {
	bytes, err := json.Marshal(obj)
	assert.NoError(t, err)
	return string(bytes)
}

// TestHandleCreateMemory tests the HandleCreateMemory method of MemoryHandler.
func TestHandleCreateMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			if memory == nil {
				return errors.New("memory cannot be nil")
			}
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest("PUT", "/memory/v0/test/repo", marshalToJSON(t, memoryDTO), ctx)
	rr := executeRequestAndRecord(router, req)

	if status := rr.Code; status != http.StatusCreated {
		t.Errorf("expected status %d, got %d", http.StatusCreated, status)
	}

	// Verify response is MemoryDTO
	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	assert.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)
	assert.Equal(t, memoryDTO.Subject, responseDTO.Subject)
}

// TestHandleInvalidCreateMemory tests the HandleCreateMemory method with invalid input.
func TestHandleInvalidCreateMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			return errors.New("invalid memory data")
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("PUT", "/memory/v0/test/repo", "invalid json", ctx)
	rr := executeRequestAndRecord(router, req)

	if status := rr.Code; status != http.StatusBadRequest {
		t.Errorf("expected status %d, got %d", http.StatusBadRequest, status)
	}
}

// TestHandleGetMemories tests the HandleGetMemories method of MemoryHandler.
func TestHandleGetMemories(t *testing.T) {
	expectedMemories := []*core.Memory{createTestCoreMemory()}

	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return expectedMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest("POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var actualMemoryDTOs []*MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&actualMemoryDTOs)
	assert.NoError(t, err)

	// Validate the actual response matches the expected memory data (converted to DTOs)
	assert.Len(t, actualMemoryDTOs, 1)
	assert.Equal(t, expectedMemories[0].ID.String(), actualMemoryDTOs[0].ID)
	assert.Equal(t, expectedMemories[0].Subject, actualMemoryDTOs[0].Subject)
}

// TestHandleGetMemoriesInvalidNWO tests the HandleGetMemories method with an invalid NWO.
func TestHandleGetMemoriesInvalidNWO(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return nil, core.ErrInvalidRepoNWO
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	// Use empty owner to trigger invalid NWO error
	req := createTestRequest("POST", "/memory/v0//repo/search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "repository owner cannot be empty")
}

// TestHandleGetMemoriesEmptyNWO tests the HandleGetMemories method with an empty NWO.
func TestHandleGetMemoriesEmptyNWO(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return nil, core.ErrEmptyRepoNWO
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	// Use empty repo to trigger empty NWO error
	req := createTestRequest("POST", "/memory/v0/test//search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Equal(t, "repository name cannot be empty\n", rr.Body.String())
}

// TestGetMemoriesNotFound tests the HandleGetMemories method when no memories are found.
func TestGetMemoriesNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest("POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Equal(t, "", rr.Body.String()) // Expect empty response
}

// TestUnexpectedError tests the error handling in MemoryHandler.
func TestUnexpectedError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			return errors.New("unexpected error")
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest("PUT", "/memory/v0/test/repo", marshalToJSON(t, memoryDTO), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	assert.Equal(t, "unexpected error\n", rr.Body.String())
}

// TestCreateMemoryUnauthorizedNoUserInfo tests CreateMemory when no user info is in context.
func TestCreateMemoryUnauthorizedNoUserInfo(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			return nil
		},
	}

	_, router := createTestHandlerAndRouterWithInternal(mockService)
	memoryDTO := createTestMemoryDTO()

	// Create context without user information
	ctx := context.Background()
	req := createTestRequest("PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
	assert.Contains(t, rr.Body.String(), "user information not found in request context")
}

// TestCreateMemoryUnauthorizedInsufficientPermissions tests CreateMemory when user lacks push permissions.
func TestCreateMemoryUnauthorizedInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			return nil
		},
	}

	// Create a mock GitHub factory that returns a client with insufficient permissions
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters())
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Create context with a user that has no push permissions (using -read suffix)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-read", // This suffix gives only read permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest("PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestCreateMemoryUnauthorizedGitHubError tests CreateMemory when GitHub client creation fails.
func TestCreateMemoryUnauthorizedGitHubError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			return nil
		},
	}

	// Create a mock GitHub factory that returns an error when creating client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("failed to create GitHub client")
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters())
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest("PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestSearchMemoryUnauthorizedNoUserInfo tests SearchMemory when no user info is in context.
func TestSearchMemoryUnauthorizedNoUserInfo(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return []*core.Memory{createTestCoreMemory()}, nil
		},
	}

	_, router := createTestHandlerAndRouterWithInternal(mockService)
	searchRequest := createTestSearchRequest()

	// Create context without user information
	ctx := context.Background()
	req := createTestRequest("POST", "/internal/memory/v0/test/repo/search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
	assert.Contains(t, rr.Body.String(), "user information not found in request context")
}

// TestSearchMemoryUnauthorizedInsufficientPermissions tests SearchMemory when user lacks pull permissions.
func TestSearchMemoryUnauthorizedInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return []*core.Memory{createTestCoreMemory()}, nil
		},
	}

	// Create a mock GitHub factory that returns a client with insufficient permissions
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters())
	router := createTestRouterWithInternalPrefix(handler)
	searchRequest := createTestSearchRequest()

	// Create context with a user that has no permissions (using -none suffix)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest("POST", "/internal/memory/v0/test/repo/search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestSearchMemoryUnauthorizedGitHubError tests SearchMemory when GitHub client creation fails.
func TestSearchMemoryUnauthorizedGitHubError(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) ([]*core.Memory, error) {
			return []*core.Memory{createTestCoreMemory()}, nil
		},
	}

	// Create a mock GitHub factory that returns an error when creating client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("failed to create GitHub client")
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters())
	router := createTestRouterWithInternalPrefix(handler)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest("POST", "/internal/memory/v0/test/repo/search", marshalToJSON(t, searchRequest), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestCreateMemoryWithSecrets tests CreateMemory when the memory contains secrets.
func TestCreateMemoryWithSecrets(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory) error {
			return core.ErrMemoryContainsSecrets
		},
	}

	_, router := createTestHandlerAndRouter(mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest("PUT", "/memory/v0/test/repo", marshalToJSON(t, memoryDTO), ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "Memory contains secrets and cannot be saved")
}

// TestDeleteMemorySuccess tests successful deletion of a memory.
func TestDeleteMemorySuccess(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repoNWO core.RepoNWO, memoryID core.MemoryID) error {
			assert.Equal(t, "test-memory-id", memoryID.String())
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("DELETE", "/memory/v0/test/repo/test-memory-id", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
}

// TestDeleteMemoryNotFound tests deletion of a non-existent memory.
func TestDeleteMemoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repoNWO core.RepoNWO, memoryID core.MemoryID) error {
			return core.ErrMemoryNotFound
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("DELETE", "/memory/v0/test/repo/non-existent-id", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Memory not found")
}

// TestDeleteMemoryUnauthorized tests deletion with insufficient permissions.
func TestDeleteMemoryUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest("DELETE", "/memory/v0/test/repo/test-memory-id", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestDeleteMemoryEmptyID tests deletion with empty memory ID.
func TestDeleteMemoryEmptyID(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("DELETE", "/memory/v0/test/repo/", "", ctx)
	rr := executeRequestAndRecord(router, req)

	// This should route to HandleDeleteAllMemories instead
	assert.Equal(t, http.StatusNoContent, rr.Code)
}

// TestDeleteAllMemoriesSuccess tests successful deletion of all memories.
func TestDeleteAllMemoriesSuccess(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) error {
			assert.Equal(t, "test", repoNWO.Owner)
			assert.Equal(t, "repo", repoNWO.Repo)
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("DELETE", "/memory/v0/test/repo/", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
}

// TestDeleteAllMemoriesUnauthorized tests deletion of all memories with insufficient permissions.
func TestDeleteAllMemoriesUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest("DELETE", "/memory/v0/test/repo/", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestDeleteAllMemoriesFeatureNotEnabled tests deletion when feature is disabled.
func TestDeleteAllMemoriesFeatureNotEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repoNWO core.RepoNWO) error {
			return core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("DELETE", "/memory/v0/test/repo/", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Resource not found")
}

func TestHandleGetRecentMemoriesSuccess(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
		{ID: core.MemoryID("memory2"), Subject: "recent memory 2"},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repoNWO core.RepoNWO, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.User{ID: 1, Login: "testuser"}, user)
			assert.Equal(t, core.RepoNWO{Owner: "test", Repo: "repo"}, repoNWO)
			assert.Equal(t, uint(5), limit)
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("GET", "/memory/v0/test/repo/recent?limit=5", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Equal(t, "application/json", rr.Header().Get("Content-Type"))

	var result []*MemoryDTO
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	assert.NoError(t, err)
	assert.Len(t, result, 2)
	assert.Equal(t, "memory1", result[0].ID)
	assert.Equal(t, "memory2", result[1].ID)
}

func TestHandleGetRecentMemoriesDefaultLimit(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repoNWO core.RepoNWO, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(10), limit) // Default limit should be 10
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("GET", "/memory/v0/test/repo/recent", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetRecentMemoriesInvalidLimit(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repoNWO core.RepoNWO, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(10), limit) // Invalid limit should default to 10
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("GET", "/memory/v0/test/repo/recent?limit=invalid", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetRecentMemoriesNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repoNWO core.RepoNWO, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(mockService)

	ctx := createTestContext()
	req := createTestRequest("GET", "/memory/v0/test/repo/recent", "", ctx)
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}
