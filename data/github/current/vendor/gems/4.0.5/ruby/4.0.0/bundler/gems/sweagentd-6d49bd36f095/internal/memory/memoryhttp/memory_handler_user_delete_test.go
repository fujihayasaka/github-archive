package memoryhttp

import (
	"errors"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
)

func TestHandleDeleteUserMemory(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteUserMemoryFunc: func(user core.User, memoryID core.MemoryID) error {
			assert.Equal(t, core.MemoryID("test-memory-id"), memoryID)
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/user/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}

func TestHandleDeleteUserMemoryNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteUserMemoryFunc: func(user core.User, memoryID core.MemoryID) error {
			return core.ErrMemoryNotFound
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/user/test-memory-id", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleDeleteAllUserMemories(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllUserMemoriesFunc: func(user core.User) error {
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/user", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}

func TestHandleDeleteAllUserMemoriesServiceError(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteAllUserMemoriesFunc: func(user core.User) error {
			return errors.New("unexpected error")
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "DELETE", "/memory/v0/user", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}
