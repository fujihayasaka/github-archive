package main

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeBillingEntityMemoryService struct {
	page *core.MemoryPage
}

func (s *fakeBillingEntityMemoryService) ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
	return s.page, nil
}

func (s *fakeBillingEntityMemoryService) DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
	return &core.BillingEntityDeleteResult{}, nil
}

func TestLazyMemoryServiceInitializesOnFirstRequest(t *testing.T) {
	calls := 0
	expectedPage := &core.MemoryPage{ContinuationToken: "next"}
	service := &lazyMemoryService{
		obsv: observability.NewNoopExporters(),
		init: func() (billingEntityMemoryService, error) {
			calls++
			return &fakeBillingEntityMemoryService{page: expectedPage}, nil
		},
	}

	page, err := service.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 1, UserID: 2}, core.MemoryPageRequest{Limit: 10, SnapshotTime: time.Now()})

	require.NoError(t, err)
	assert.Equal(t, expectedPage, page)
	assert.Equal(t, 1, calls)

	page, err = service.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 1, UserID: 2}, core.MemoryPageRequest{Limit: 10, SnapshotTime: time.Now()})

	require.NoError(t, err)
	assert.Equal(t, expectedPage, page)
	assert.Equal(t, 1, calls)
}

func TestLazyMemoryServiceRetriesAfterInitializationFailure(t *testing.T) {
	calls := 0
	expectedPage := &core.MemoryPage{ContinuationToken: "next"}
	service := &lazyMemoryService{
		obsv: observability.NewNoopExporters(),
		init: func() (billingEntityMemoryService, error) {
			calls++
			if calls == 1 {
				return nil, errors.New("cosmos unavailable")
			}
			return &fakeBillingEntityMemoryService{page: expectedPage}, nil
		},
	}

	page, err := service.ListBillingEntityMemories(context.Background(), core.BillingEntityMemoryFilter{OrganizationID: 1, UserID: 2}, core.MemoryPageRequest{Limit: 10, SnapshotTime: time.Now()})

	require.Error(t, err)
	assert.Nil(t, page)
	assert.Equal(t, 1, calls)

	page, err = service.ListBillingEntityMemories(context.Background(), core.BillingEntityMemoryFilter{OrganizationID: 1, UserID: 2}, core.MemoryPageRequest{Limit: 10, SnapshotTime: time.Now()})

	require.NoError(t, err)
	assert.Equal(t, expectedPage, page)
	assert.Equal(t, 2, calls)
}
