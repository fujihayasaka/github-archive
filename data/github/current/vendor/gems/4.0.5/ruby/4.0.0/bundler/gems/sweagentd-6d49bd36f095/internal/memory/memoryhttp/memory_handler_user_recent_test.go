package memoryhttp

import (
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHandleGetRecentUserMemories(t *testing.T) {
	testMemory := createTestCoreMemory()
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return []*core.Memory{testMemory}, nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/recent?limit=5", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var memoryDTOs []*MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&memoryDTOs)
	require.NoError(t, err)
	assert.Len(t, memoryDTOs, 1)
}

func TestHandleGetRecentUserMemoriesDefaultLimit(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			assert.Equal(t, uint(10), limit)
			return []*core.Memory{createTestCoreMemory()}, nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/recent", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetRecentUserMemoriesNoResults(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/recent", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}

func TestHandleGetRecentUserMemoriesServiceError(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentUserMemoriesFunc: func(user core.User, limit uint, query core.UserMemoryQuery) ([]*core.Memory, error) {
			return nil, errors.New("unexpected error")
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/recent", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}
