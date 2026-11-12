package memoryhttp

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHandleCheckUserMemoryEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckUserMemoryEnabledFunc: func(userID int64) (bool, error) {
			return true, nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.True(t, resp.Enabled)
}

func TestHandleCheckUserMemoryEnabledFalse(t *testing.T) {
	mockService := &MockMemoryService{
		CheckUserMemoryEnabledFunc: func(userID int64) (bool, error) {
			return false, nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/memory/v0/user/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var resp MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&resp)
	require.NoError(t, err)
	assert.False(t, resp.Enabled)
}
