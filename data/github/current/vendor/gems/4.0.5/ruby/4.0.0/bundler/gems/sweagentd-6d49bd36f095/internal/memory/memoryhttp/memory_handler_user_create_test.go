package memoryhttp

import (
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHandleCreateUserMemory(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			assert.Equal(t, core.RepoNWO{}, memory.Source.NWO, "user-scoped create should not attach a repo context")
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusCreated, rr.Code)

	var responseDTO MemoryDTO
	err := json.NewDecoder(rr.Body).Decode(&responseDTO)
	require.NoError(t, err)
	assert.Equal(t, memoryDTO.ID, responseDTO.ID)
	assert.Equal(t, memoryDTO.Subject, responseDTO.Subject)
}

func TestHandleCreateUserMemoryInvalidBody(t *testing.T) {
	mockService := &MockMemoryService{}

	_, router := createTestUserHandlerAndRouter(t, mockService)

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", "invalid json")
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
}

func TestHandleCreateUserMemory_MissingCitations(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			t.Fatal("service should not be called for invalid DTO")
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)
	memoryDTO := &MemoryDTO{
		ID:      "1",
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Reason:  "Test Reason",
		Source: MemorySourceDTO{
			InteractionID: "interaction1",
			Agent:         "test-agent",
		},
	}

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "citations cannot be empty")
}

func TestHandleCreateUserMemory_AllEmptyCitations(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			t.Fatal("service should not be called for invalid DTO")
			return nil
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)
	memoryDTO := &MemoryDTO{
		ID:        "1",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Reason:    "Test Reason",
		Citations: []string{"", "  "},
		Source: MemorySourceDTO{
			InteractionID: "interaction1",
			Agent:         "test-agent",
		},
	}

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusBadRequest, rr.Code)
	assert.Contains(t, rr.Body.String(), "citations must not all be empty strings")
}

func TestHandleCreateUserMemoryServiceError(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			return errors.New("unexpected error")
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
}

func TestHandleCreateUserMemoryFeatureNotEnabled(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			return core.ErrFeatureNotEnabled
		},
	}

	_, router := createTestUserHandlerAndRouter(t, mockService)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusNotFound, rr.Code)
}

func TestHandleCreateUserMemoryBillingEntityUnresolved(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			return core.ErrBillingEntityUnresolved
		},
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service: mockService,
		Obsv:    observability.NewNoopExporters(),
	})
	router := createTestUserRouter(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusUnprocessableEntity, rr.Code)
	assert.Contains(t, rr.Body.String(), "billing entity has not been selected")
}

func TestHandleCreateUserMemoryBillingEntityResolutionFailed(t *testing.T) {
	mockService := &MockMemoryService{
		CreateUserMemoryFunc: func(memory *core.Memory, user core.User) error {
			return core.ErrBillingEntityResolutionFailed
		},
	}

	handler := NewMemoryHandler(MemoryHandlerOpts{
		Service: mockService,
		Obsv:    observability.NewNoopExporters(),
	})
	router := createTestUserRouter(handler)
	memoryDTO := createTestMemoryDTO()

	ctx := createTestContext()
	req := createTestRequest(ctx, "PUT", "/memory/v0/user", marshalToJSON(t, memoryDTO))
	rr := executeRequestAndRecord(router, req)

	assert.Equal(t, http.StatusInternalServerError, rr.Code)
	assert.Contains(t, rr.Body.String(), "failed to resolve billing entity")
}
