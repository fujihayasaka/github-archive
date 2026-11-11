package memoryhttp

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHandleGetTopMemoriesSuccess(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "top memory 1"},
		{ID: core.MemoryID("memory2"), Subject: "top memory 2"},
	}

	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.User{ID: 1, Login: "testuser"}, user)
			assert.Equal(t, core.RepoNWO{Owner: "test", Repo: "repo"}, repository.NWO)
			assert.Equal(t, uint(5), limit)
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/top?limit=5", "")
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

func TestHandleGetTopMemoriesDefaultLimit(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "top memory 1"},
	}

	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(20), limit) // Default limit should be 20
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/top", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetTopMemoriesLimitCappedToMax(t *testing.T) {
	mockMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "top memory 1"},
	}

	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, uint(1000), limit) // Limit above max should be capped to 1000
			return mockMemories, nil
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/top?limit=5000", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)
}

func TestHandleGetTopMemoriesNotFound(t *testing.T) {
	mockService := &MockMemoryService{
		GetTopMemoriesFunc: func(user core.User, repository *core.Repository, limit uint) ([]*core.Memory, error) {
			return nil, core.ErrNoMemoriesNotFound
		},
	}

	_, router := createTestHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/test/repo/top", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNoContent, rr.Code)
}
