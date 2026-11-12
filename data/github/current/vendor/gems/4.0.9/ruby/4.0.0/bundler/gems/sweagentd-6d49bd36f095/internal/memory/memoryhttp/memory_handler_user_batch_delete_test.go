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

func TestHandleDeleteUserMemories(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteUserMemoriesFunc: func(user core.User, memoryIDs []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{Deleted: memoryIDs}, nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	batchReq := BatchDeleteRequest{IDs: []string{"id1", "id2"}}

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/user/delete", marshalToJSON(t, batchReq))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp BatchDeleteResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.Len(t, resp.Deleted, 2)
}

func TestHandleDeleteUserMemoriesEmptyIDs(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	batchReq := BatchDeleteRequest{IDs: []string{}}

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/user/delete", marshalToJSON(t, batchReq))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
}

func TestHandleDeleteUserMemoriesPartialFailure(t *testing.T) {
	mockService := &MockMemoryService{
		DeleteUserMemoriesFunc: func(user core.User, memoryIDs []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{
				Deleted: []core.MemoryID{"id1"},
				Failed:  []core.MemoryID{"id2"},
			}, errors.New("partial failure")
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	batchReq := BatchDeleteRequest{IDs: []string{"id1", "id2"}}

	ctx := createTestContext()
	req := createTestRequest(ctx, "POST", "/memory/v0/user/delete", marshalToJSON(t, batchReq))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp BatchDeleteResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.Len(t, resp.Deleted, 1)
	assert.Len(t, resp.Failed, 1)
}
