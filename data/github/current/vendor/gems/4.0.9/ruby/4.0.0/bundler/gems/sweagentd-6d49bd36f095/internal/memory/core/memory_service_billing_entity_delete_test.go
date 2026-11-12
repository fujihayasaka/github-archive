package core_test

import (
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDeleteBillingEntityMemoriesRejectsInvalidFilters(t *testing.T) {
	storeCalled := false
	memoryStore := &MockMemoryStore{
		DeleteBillingEntityMemoriesFunc: func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
			storeCalled = true
			return &core.BillingEntityDeleteResult{}, nil
		},
	}
	svc := newTestMemoryService(t, memoryStore)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	tests := []struct {
		name        string
		filter      core.BillingEntityMemoryFilter
		pageRequest core.MemoryPageRequest
		wantErr     error
	}{
		{
			name:        "missing billing scope",
			filter:      core.BillingEntityMemoryFilter{UserID: 42},
			pageRequest: core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime},
			wantErr:     core.ErrInvalidBillingFilter,
		},
		{
			name:        "missing user_id",
			filter:      core.BillingEntityMemoryFilter{OrganizationID: 100},
			pageRequest: core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime},
			wantErr:     core.ErrInvalidUserFilter,
		},
		{
			name:        "missing snapshot time",
			filter:      core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: 42},
			pageRequest: core.MemoryPageRequest{Limit: 10},
			wantErr:     core.ErrInvalidSnapshotTime,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			storeCalled = false

			result, err := svc.DeleteBillingEntityMemories(t.Context(), tt.filter, tt.pageRequest)

			require.ErrorIs(t, err, tt.wantErr)
			assert.Nil(t, result)
			assert.False(t, storeCalled)
		})
	}
}

func TestDeleteBillingEntityMemoriesCallsStore(t *testing.T) {
	expectedResult := &core.BillingEntityDeleteResult{
		DeletedCount:      3,
		ContinuationToken: "next-token",
	}
	var capturedFilter core.BillingEntityMemoryFilter
	var capturedPageRequest core.MemoryPageRequest

	memoryStore := &MockMemoryStore{
		DeleteBillingEntityMemoriesFunc: func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
			capturedFilter = filter
			capturedPageRequest = pageRequest
			return expectedResult, nil
		},
	}
	svc := newTestMemoryService(t, memoryStore)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	filter := core.BillingEntityMemoryFilter{OrganizationID: 100, EnterpriseID: 200, UserID: 42}
	pageRequest := core.MemoryPageRequest{Limit: 50, ContinuationToken: "prev-token", SnapshotTime: snapshotTime}

	result, err := svc.DeleteBillingEntityMemories(t.Context(), filter, pageRequest)

	require.NoError(t, err)
	require.Equal(t, expectedResult, result)
	assert.Equal(t, filter, capturedFilter)
	assert.Equal(t, pageRequest, capturedPageRequest)
}

func TestDeleteBillingEntityMemoriesWrapsStoreError(t *testing.T) {
	storeErr := errors.New("cosmos unavailable")
	memoryStore := &MockMemoryStore{
		DeleteBillingEntityMemoriesFunc: func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
			return nil, storeErr
		},
	}
	svc := newTestMemoryService(t, memoryStore)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	result, err := svc.DeleteBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{
		OrganizationID: 100,
		UserID:         42,
	}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})

	require.Error(t, err)
	require.ErrorIs(t, err, storeErr)
	assert.Nil(t, result)
}
