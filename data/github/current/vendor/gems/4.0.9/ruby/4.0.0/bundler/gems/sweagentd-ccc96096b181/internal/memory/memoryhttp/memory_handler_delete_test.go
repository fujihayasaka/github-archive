package memoryhttp

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
)

// TestDeleteMemorySuccess tests successful deletion of a memory.
func TestDeleteMemorySuccess(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repository *core.Repository, memoryID core.MemoryID) error {
			assert.Equal(t, "test-memory-id", memoryID.String())
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
}

// TestDeleteMemoryNotFound tests deletion of a non-existent memory.
func TestDeleteMemoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteMemoryFunc: func(user core.User, repository *core.Repository, memoryID core.MemoryID) error {
			return core.ErrMemoryNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/non-existent-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Memory not found")
}

// TestDeleteMemoryUnauthorized tests deletion with insufficient permissions.
func TestDeleteMemoryUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestDeleteMemoryEmptyID tests deletion with empty memory ID.
func TestDeleteMemoryEmptyID(t *testing.T) {
	mockService := &MockMemoryService{}
	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	// This should route to HandleDeleteAllMemories instead
	assert.Equal(t, http.StatusNoContent, rr.Code)
}

// TestDeleteAllMemoriesSuccess tests successful deletion of all memories.
func TestDeleteAllMemoriesSuccess(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repository *core.Repository) error {
			assert.Equal(t, "test", repository.NWO.Owner)
			assert.Equal(t, "repo", repository.NWO.Repo)
			return nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
	assert.Empty(t, rr.Body.String())
}

// TestDeleteAllMemoriesUnauthorized tests deletion of all memories with insufficient permissions.
func TestDeleteAllMemoriesUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:         1,
			Login:      "testuser-none", // This suffix gives no permissions
			TrackingID: "tracking-id",
		},
	})
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Not Found")
}

// TestDeleteAllMemoriesFeatureNotEnabled tests deletion when feature is disabled.
func TestDeleteAllMemoriesFeatureNotEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllMemoriesFunc: func(user core.User, repository *core.Repository) error {
			return core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/test/repo/", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
	assert.Contains(t, rr.Body.String(), "Resource not found")
}
