package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
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

// TestHandleGetMemories tests the HandleGetMemories method of MemoryHandler.
func TestHandleGetMemories(t *testing.T) {
	expectedMemories := []*core.Memory{createTestCoreMemory()}

	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return expectedMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var actualMemoryDTOs []*MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&actualMemoryDTOs)
	require.NoError(t, err)

	// Validate the actual response matches the expected memory data (converted to DTOs)
	assert.Len(t, actualMemoryDTOs, 1)
	assert.Equal(t, expectedMemories[0].ID.String(), actualMemoryDTOs[0].ID)
	assert.Equal(t, expectedMemories[0].Subject, actualMemoryDTOs[0].Subject)
}

// TestHandleGetMemoriesInvalidNWO tests the HandleGetMemories method with an invalid NWO.
func TestHandleGetMemoriesInvalidNWO(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return nil, core.ErrInvalidRepoNWO
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	// Use empty owner to trigger invalid NWO error
	req := createTestRequest(ctx, "POST", "/memory/v0//repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "repository owner cannot be empty")
}

// TestHandleGetMemoriesEmptyNWO tests the HandleGetMemories method with an empty NWO.
func TestHandleGetMemoriesEmptyNWO(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return nil, core.ErrEmptyRepoNWO
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	// Use empty repo to trigger empty NWO error
	req := createTestRequest(ctx, "POST", "/memory/v0/test//search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Equal(t, "repository name cannot be empty\n", rr.Body.String())
}

// TestHandleGetMemoriesRepositoryNotFound tests the HandleGetMemories method when the repository is not found.
func TestHandleGetMemoriesRepositoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Equal(t, "Repository not found\n", rr.Body.String())
}

// TestHandleGetMemoriesRepositoryAccessDenied tests the HandleGetMemories method when access to the repository is denied.
func TestHandleGetMemoriesRepositoryAccessDenied(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryAccessDenied
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Equal(t, "Access to repository denied\n", rr.Body.String())
}

// TestHandleGetMemoriesRepositoryOAuthAccessRestriction tests the HandleGetMemories method when access is denied due to OAuth App access restrictions.
func TestHandleGetMemoriesRepositoryOAuthAccessRestriction(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return nil, core.ErrRepositoryOAuthAccessRestriction
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusForbidden, rr.Code)
	assert.Equal(t, "Access to repository denied due to OAuth App access restrictions. An organization administrator must enable access for the app you're using. For more details, see <https://docs.github.com/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions>.\n", rr.Body.String())
}

// TestGetMemoriesNotFound tests the HandleGetMemories method when no memories are found.
func TestGetMemoriesNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Equal(t, "", rr.Body.String()) // Expect empty response
}

// TestSearchMemoryUnauthorizedNoUserInfo tests SearchMemory when no user info is in context.
func TestSearchMemoryUnauthorizedNoUserInfo(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return []*core.Memory{createTestCoreMemory()}, nil
		},
	}

	_, router := createTestHandlerAndRouterWithInternal(t, mockService)
	searchRequest := createTestSearchRequest()

	// Create context without user information
	ctx := context.Background()
	req := createTestRequest(ctx, "POST", "/internal/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
	assert.Contains(t, rr.Body.String(), "user information not found in request context")
}

// TestSearchMemoryUnauthorizedInsufficientPermissions tests SearchMemory when user lacks pull permissions.
func TestSearchMemoryUnauthorizedInsufficientPermissions(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return []*core.Memory{createTestCoreMemory()}, nil
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
	searchRequest := createTestSearchRequest()

	// Create context with a user that has no permissions (using -none suffix)
	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "POST", "/internal/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestSearchMemoryUnauthorizedGitHubError tests SearchMemory when GitHub client creation fails.
func TestSearchMemoryUnauthorizedGitHubError(t *testing.T) {
	mockService := &MockMemoryService{
		GetMemoriesFunc: func(user core.User, repository *core.Repository) ([]*core.Memory, error) {
			return []*core.Memory{createTestCoreMemory()}, nil
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
	searchRequest := createTestSearchRequest()

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/internal/memory/v0/test/repo/search", marshalToJSON(t, searchRequest))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}
