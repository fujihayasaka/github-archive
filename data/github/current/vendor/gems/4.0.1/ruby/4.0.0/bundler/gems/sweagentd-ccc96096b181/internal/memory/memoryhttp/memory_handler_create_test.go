package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHandleCreateMemory tests the HandleCreateMemory method of MemoryHandler.
func TestHandleCreateMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			if memory == nil {
				return errors.New("memory cannot be nil")
			}
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	if status := rr.Code; status != http.StatusCreated {
		t.Errorf("expected status %d, got %d", http.StatusCreated, status)
	}

	// Verify response is MemoryDTO
	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	require.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)
	assert.Equal(t, memoryDTO.Subject, responseDTO.Subject)
}

// TestHandleInvalidCreateMemory tests the HandleCreateMemory method with invalid input.
func TestHandleInvalidCreateMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return errors.New("invalid memory data")
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/test/repo", "invalid json")
	rr := executeRequestAndRecord(router, req)

	if status := rr.Code; status != http.StatusBadRequest {
		t.Errorf("expected status %d, got %d", http.StatusBadRequest, status)
	}
}

// TestUnexpectedError tests the error handling in MemoryHandler.
func TestUnexpectedError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return errors.New("unexpected error")
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	assert.Equal(t, "unexpected error\n", rr.Body.String())
}

// TestCreateMemoryUnauthorizedNoUserInfo tests CreateMemory when no user info is in context.
func TestCreateMemoryUnauthorizedNoUserInfo(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	_, router := createTestHandlerAndRouterWithInternal(t, mockService)
	memoryDTO := createTestMemoryDTO()

	// Create context without user information
	ctx := context.Background()
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
	assert.Contains(t, rr.Body.String(), "user information not found in request context")
}

// TestCreateMemoryUnauthorizedInsufficientPermissions tests CreateMemory when user lacks push permissions.
func TestCreateMemoryUnauthorizedInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that returns a client with insufficient permissions
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
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
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestCreateMemoryUnauthorizedGitHubError tests CreateMemory when GitHub client creation fails.
func TestCreateMemoryUnauthorizedGitHubError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that returns an error when creating client
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("failed to create GitHub client")
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestCreateMemoryFallbackToUserToken tests that CreateMemory falls back to user token
// when the Copilot app installation is not found on the repository.
func TestCreateMemoryFallbackToUserToken(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that:
	// 1. Fails NewClientFromRepoName (simulating app not installed)
	// 2. Returns a working client for NewClientForUser (user token fallback)
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("installation not found for repository")
		},
		// NewClientForUser uses the default implementation which returns a NoopClient
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Create context with user that has a token (this enables fallback)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo: &requestctx.TokenInfo{
				Token: "user-token-123",
			},
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should succeed because we fell back to user token
	assert.Equal(t, http.StatusCreated, rr.Code)

	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	require.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)
}

// TestCreateMemoryFallbackFailsNoUserToken tests that CreateMemory fails when
// the Copilot app installation is not found and the user has no token to fall back to.
func TestCreateMemoryFallbackFailsNoUserToken(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Create a mock GitHub factory that fails NewClientFromRepoName (simulating app not installed)
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return nil, errors.New("installation not found for repository")
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()

	// Create context with user that has NO token (fallback will fail)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser",
			TrackingID: "tracking-id",
			TokenInfo:  nil, // No token available for fallback
		},
	})
	req := createTestRequest(ctx, "PUT", "/internal/memory/v0/test/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	// Should fail with 404 because app installation failed and no user token fallback available
	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestCreateMemoryWithSecrets tests CreateMemory when the memory contains secrets.
func TestCreateMemoryWithSecrets(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return core.ErrMemoryContainsSecrets
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/testuser/repo", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "Memory contains secrets and cannot be saved")
}

// TestCreateMemoryPermissionMatrix verifies create memory authorization across roles.
func TestCreateMemoryPermissionMatrix(t *testing.T) {
	mockService := &MockMemoryService{
		CreateMemoryFunc: func(memory *core.Memory, repository *core.Repository) error {
			return nil
		},
	}

	// Factory returning our custom client.
	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &CustomPermsClient{&github.NoopClient{}}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)
	memoryDTO := createTestMemoryDTO()
	body := marshalToJSON(t, memoryDTO)

	testCases := []struct {
		login       string
		expectCode  int
		shouldPass  bool
		description string
	}{
		{"matrix-read", http.StatusNotFound, false, "read-only user should fail (no push/admin/maintain)"},
		{"matrix-push", http.StatusCreated, true, "push user succeeds"},
		{"matrix-admin", http.StatusCreated, true, "admin user succeeds"},
		{"matrix-maintain", http.StatusCreated, true, "maintain user succeeds"},
	}

	for _, tc := range testCases {
		t.Run(tc.description, func(t *testing.T) {
			ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
				UserInfo: &requestctx.UserInfo{
					ID:         42,
					Login:      tc.login,
					TrackingID: "tracking-id",
				},
			})

			req := createTestRequest(ctx, "PUT", fmt.Sprintf("/internal/memory/v0/%s/repo", tc.login), body)
			rr := executeRequestAndRecord(router, req)

			assert.Equal(t, tc.expectCode, rr.Code)

			if tc.shouldPass {
				var resp MemoryDTO
				err := json.NewDecoder(rr.Body).Decode(&resp)
				require.NoError(t, err)
				assert.Equal(t, memoryDTO.ID, resp.ID)
			}
		})
	}
}
