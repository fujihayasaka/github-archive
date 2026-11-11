package memoryhttp

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHandleGetRecentMemoriesSuccess(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
		{ID: core.MemoryID("memory2"), Subject: "recent memory 2"},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.User{ID: 1, Login: "testuser"}, user)
			assert.Equal(t, core.RepoNWO{Owner: "test", Repo: "repo"}, repository.NWO)
			assert.Equal(t, uint(5), limit)
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent?limit=5", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
	assert.Equal(t, "application/json", rr.Header().Get("Content-Type"))

	var result []*MemoryDTO
	err := json.Unmarshal(rr.Body.Bytes(), &result)
	require.NoError(t, err)
	assert.Len(t, result, 2)
	assert.Equal(t, "memory1", result[0].ID)
	assert.Equal(t, "memory2", result[1].ID)
}

func TestHandleGetRecentMemoriesDefaultLimit(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(10), limit) // Default limit should be 10
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetRecentMemoriesInvalidLimit(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
	}

	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(10), limit) // Invalid limit should default to 10
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent?limit=invalid", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetRecentMemoriesNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		GetRecentMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/recent", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}
