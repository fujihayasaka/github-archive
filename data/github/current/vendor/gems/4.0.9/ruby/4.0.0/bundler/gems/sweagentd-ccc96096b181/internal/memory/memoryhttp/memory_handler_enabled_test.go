package memoryhttp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHandleCheckMemoryEnabledSuccess tests the CheckMemoryEnabled endpoint with a successful response.
func TestHandleCheckMemoryEnabledSuccess(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64) (bool, error) {
			assert.Equal(t, int64(1), userID)
			return true, nil
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.True(t, response.Enabled)
}

// TestHandleCheckMemoryEnabledDisabled tests the CheckMemoryEnabled endpoint when memory is disabled.
func TestHandleCheckMemoryEnabledDisabled(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64) (bool, error) {
			return false, nil
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusOK, rr.Code)

	var response MemoryEnablementResponse
	err := json.NewDecoder(rr.Body).Decode(&response)
	require.NoError(t, err)
	assert.False(t, response.Enabled)
}

// TestHandleCheckMemoryEnabledError tests the CheckMemoryEnabled endpoint when an error occurs.
func TestHandleCheckMemoryEnabledError(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64) (bool, error) {
			return false, errors.New("failed to check enablement")
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)

	ctx := createTestContext()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}

// TestHandleCheckMemoryEnabledUnauthorized tests the CheckMemoryEnabled endpoint without user context.
func TestHandleCheckMemoryEnabledUnauthorized(t *testing.T) {
	mockService := &MockMemoryService{
		CheckMemoryEnabledFunc: func(userID int64) (bool, error) {
			return true, nil
		},
	}

	mockGHFactory := &github.NoopClientFactory{
		MockNewClientFromRepoName: func(ctx context.Context, _ sweagentd.AgenticApp, repoName, ownerName string) (github.ClientInterface, error) {
			return &github.NoopClient{}, nil
		},
	}

	handler := NewMemoryHandler(mockService, mockGHFactory, observability.NewNoopExporters(), agenticapptest.NewTestProvider(t))
	router := createTestRouterWithInternalPrefix(handler)

	ctx := context.Background()
	req := createTestRequest(ctx, "GET", "/internal/memory/v0/owner/repo/enabled", "")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnauthorized, rr.Code)
}
