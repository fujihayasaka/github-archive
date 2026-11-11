package core_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- resolveBillingEntityForCreate (tested via CreateMemory, repo-scoped) ---

func TestCreateMemory_BillingResolution_StampsMemory(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	var savedMemory *core.Memory
	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, m *core.Memory) error {
			savedMemory = m
			return nil
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "repo billing stamps",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, NWO: repoNWO, InteractionID: "i1"},
	}

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.NoError(t, err)
	require.NotNil(t, savedMemory)
	assert.Equal(t, uint64(42), savedMemory.BillingOrganizationID)
	assert.Equal(t, uint64(99), savedMemory.BillingEnterpriseID)
}

func TestCreateMemory_BillingResolution_ResolverError_ReturnsErrBillingEntityResolutionFailed(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{}, errors.New("twirp unavailable")
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "resolver fails",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, NWO: repoNWO, InteractionID: "i1"},
	}

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrBillingEntityResolutionFailed)
}

func TestCreateMemory_BillingResolution_Unresolved_ReturnsErrBillingEntityUnresolved(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{Resolved: false}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "unresolved billing",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, NWO: repoNWO, InteractionID: "i1"},
	}

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrBillingEntityUnresolved)
}

// --- resolveBillingEntityForCreate (tested via CreateUserMemory) ---

func TestCreateUserMemory_BillingResolution_StampsMemory(t *testing.T) {
	memoryStore := &MockMemoryStore{
		CountByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) (int, error) { return 0, nil },
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error { return nil },
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_feature_agentic_memory_user_scoped":         true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		withBillingEntityResolver(resolver),
	)

	user := testUser()
	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "billing stamps work",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, InteractionID: "i1"},
	}

	var savedMemory *core.Memory
	memoryStore.SaveForUserFunc = func(userID uint64, m *core.Memory) error {
		savedMemory = m
		return nil
	}

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.NoError(t, err)
	require.NotNil(t, savedMemory)
	assert.Equal(t, uint64(42), savedMemory.BillingOrganizationID)
	assert.Equal(t, uint64(99), savedMemory.BillingEnterpriseID)
}

func TestCreateUserMemory_BillingResolution_Unresolved_ReturnsErrBillingEntityUnresolved(t *testing.T) {
	memoryStore := &MockMemoryStore{
		CountByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) (int, error) { return 0, nil },
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{Resolved: false}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_feature_agentic_memory_user_scoped":         true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		withBillingEntityResolver(resolver),
	)

	user := testUser()
	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "unresolved billing",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, InteractionID: "i1"},
	}

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.ErrorIs(t, err, core.ErrBillingEntityUnresolved)
}

func TestCreateUserMemory_BillingResolution_ResolverError_ReturnsErrBillingEntityResolutionFailed(t *testing.T) {
	memoryStore := &MockMemoryStore{
		CountByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) (int, error) { return 0, nil },
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{}, errors.New("upstream timeout")
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_feature_agentic_memory_user_scoped":         true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		withBillingEntityResolver(resolver),
	)

	user := testUser()
	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "resolver fails",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, InteractionID: "i1"},
	}

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.ErrorIs(t, err, core.ErrBillingEntityResolutionFailed)
}

func TestCreateUserMemory_BillingResolution_FFDisabled_SkipsSilently(t *testing.T) {
	memoryStore := &MockMemoryStore{
		CountByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) (int, error) { return 0, nil },
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error { return nil },
	}

	resolverCalled := false
	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			resolverCalled = true
			return core.BillingEntity{}, nil
		},
	}

	// FF for billing entity NOT present → should skip resolution
	svc := newTestMemoryService(t, memoryStore,
		withBillingEntityResolver(resolver),
	)

	user := testUser()
	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "no billing FF",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, InteractionID: "i1"},
	}

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.NoError(t, err)
	assert.False(t, resolverCalled, "resolver should not be called when FF is disabled")
	assert.Equal(t, uint64(0), memory.BillingOrganizationID)
}

func TestCreateUserMemory_BillingResolution_NilResolver_SkipsSilently(t *testing.T) {
	memoryStore := &MockMemoryStore{
		CountByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) (int, error) { return 0, nil },
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error { return nil },
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                     true,
			"copilot_feature_agentic_memory_user_scoped":         true,
			"copilot_swe_agent_memory_secret_scanning":           true,
			"copilot_feature_agentic_memory_with_billing_entity": true,
			"copilot_swe_agent_memory_voting_coding_agent":       true,
		}),
		// No billing resolver → nil
	)

	user := testUser()
	memory := &core.Memory{
		Subject:   "Test",
		Fact:      "nil resolver",
		Reason:    "testing",
		Citations: []string{"src.go"},
		Source:    core.MemorySource{User: user, InteractionID: "i1"},
	}

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.NoError(t, err)
}

func TestListBillingEntityMemoriesRejectsInvalidFilters(t *testing.T) {
	storeCalled := false
	memoryStore := &MockMemoryStore{
		ListBillingEntityMemoriesFunc: func(filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
			storeCalled = true
			return &core.MemoryPage{}, nil
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
			name:        "missing snapshot time",
			filter:      core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: 42},
			pageRequest: core.MemoryPageRequest{Limit: 10},
			wantErr:     core.ErrInvalidSnapshotTime,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			storeCalled = false

			page, err := svc.ListBillingEntityMemories(t.Context(), tt.filter, tt.pageRequest)

			require.ErrorIs(t, err, tt.wantErr)
			assert.Nil(t, page)
			assert.False(t, storeCalled)
		})
	}
}

// --- backfillUserMemoryBillingEntities (tested via GetRecentUserMemories) ---

func TestGetRecentUserMemories_BackfillBilling_StampsLegacyMemories(t *testing.T) {
	legacyMemory := &core.Memory{
		ID:      "legacy-1",
		Subject: "Test",
		Fact:    "fact",
		Source:  core.MemorySource{User: testUser(), InteractionID: "i1"},
		// Zero billing IDs — needs backfill.
		BillingOrganizationID: 0,
		BillingEnterpriseID:   0,
	}

	var savedMemory *core.Memory
	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{legacyMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			savedMemory = memory
			return nil
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                                     true,
			"copilot_feature_agentic_memory_user_scoped":                         true,
			"copilot_feature_agentic_memory_backfill_user_memory_billing_entity": true,
			"copilot_feature_agentic_memory_with_billing_entity":                 true,
			"copilot_swe_agent_memory_secret_scanning":                           true,
			"copilot_swe_agent_memory_voting_coding_agent":                       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	// Memory should be stamped in the response.
	assert.Equal(t, uint64(42), memories[0].BillingOrganizationID)
	assert.Equal(t, uint64(99), memories[0].BillingEnterpriseID)

	// And persisted.
	require.NotNil(t, savedMemory)
	assert.Equal(t, uint64(42), savedMemory.BillingOrganizationID)
	assert.Equal(t, uint64(99), savedMemory.BillingEnterpriseID)
}

func TestGetRecentUserMemories_BackfillBilling_SkipsAlreadyStamped(t *testing.T) {
	stampedMemory := &core.Memory{
		ID:                    "stamped-1",
		Subject:               "Test",
		Fact:                  "fact",
		Source:                core.MemorySource{User: testUser(), InteractionID: "i1"},
		BillingOrganizationID: 10,
		BillingEnterpriseID:   20,
	}

	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{stampedMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                                     true,
			"copilot_feature_agentic_memory_user_scoped":                         true,
			"copilot_feature_agentic_memory_backfill_user_memory_billing_entity": true,
			"copilot_feature_agentic_memory_with_billing_entity":                 true,
			"copilot_swe_agent_memory_secret_scanning":                           true,
			"copilot_swe_agent_memory_voting_coding_agent":                       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	// Should remain unchanged — no save needed.
	assert.Equal(t, uint64(10), memories[0].BillingOrganizationID)
	assert.Equal(t, uint64(20), memories[0].BillingEnterpriseID)
	assert.False(t, saveCalled, "save should not be called for already-stamped memories")
}

func TestGetRecentUserMemories_BackfillBilling_FFDisabled_Skips(t *testing.T) {
	legacyMemory := &core.Memory{
		ID:      "legacy-1",
		Subject: "Test",
		Fact:    "fact",
		Source:  core.MemorySource{User: testUser(), InteractionID: "i1"},
	}

	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{legacyMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	// Backfill FF is NOT enabled.
	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":               true,
			"copilot_feature_agentic_memory_user_scoped":   true,
			"copilot_swe_agent_memory_secret_scanning":     true,
			"copilot_swe_agent_memory_voting_coding_agent": true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	assert.Equal(t, uint64(0), memories[0].BillingOrganizationID)
	assert.False(t, saveCalled, "save should not be called when FF disabled")
}

func TestGetRecentUserMemories_BackfillBilling_PersistFailure_RevertsInMemory(t *testing.T) {
	legacyMemory := &core.Memory{
		ID:      "legacy-1",
		Subject: "Test",
		Fact:    "fact",
		Source:  core.MemorySource{User: testUser(), InteractionID: "i1"},
	}

	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{legacyMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			return errors.New("cosmos error")
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                                     true,
			"copilot_feature_agentic_memory_user_scoped":                         true,
			"copilot_feature_agentic_memory_backfill_user_memory_billing_entity": true,
			"copilot_feature_agentic_memory_with_billing_entity":                 true,
			"copilot_swe_agent_memory_secret_scanning":                           true,
			"copilot_swe_agent_memory_voting_coding_agent":                       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	// Billing IDs should be reverted to zero in the response.
	assert.Equal(t, uint64(0), memories[0].BillingOrganizationID)
	assert.Equal(t, uint64(0), memories[0].BillingEnterpriseID)
}

func TestGetRecentUserMemories_BackfillBilling_ConcurrencyConflict_RevertsGracefully(t *testing.T) {
	legacyMemory := &core.Memory{
		ID:      "legacy-1",
		Subject: "Test",
		Fact:    "fact",
		Source:  core.MemorySource{User: testUser(), InteractionID: "i1"},
	}

	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{legacyMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			return core.ErrConcurrencyConflict
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                                     true,
			"copilot_feature_agentic_memory_user_scoped":                         true,
			"copilot_feature_agentic_memory_backfill_user_memory_billing_entity": true,
			"copilot_feature_agentic_memory_with_billing_entity":                 true,
			"copilot_swe_agent_memory_secret_scanning":                           true,
			"copilot_swe_agent_memory_voting_coding_agent":                       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	// Billing IDs should be reverted on concurrency conflict.
	assert.Equal(t, uint64(0), memories[0].BillingOrganizationID)
	assert.Equal(t, uint64(0), memories[0].BillingEnterpriseID)
}

func TestGetRecentUserMemories_BackfillBilling_UnresolvedBilling_Skips(t *testing.T) {
	legacyMemory := &core.Memory{
		ID:      "legacy-1",
		Subject: "Test",
		Fact:    "fact",
		Source:  core.MemorySource{User: testUser(), InteractionID: "i1"},
	}

	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{legacyMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	// User has unresolved billing entity (CfI user).
	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 0, EnterpriseID: 0, Resolved: false}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                                     true,
			"copilot_feature_agentic_memory_user_scoped":                         true,
			"copilot_feature_agentic_memory_backfill_user_memory_billing_entity": true,
			"copilot_feature_agentic_memory_with_billing_entity":                 true,
			"copilot_swe_agent_memory_secret_scanning":                           true,
			"copilot_swe_agent_memory_voting_coding_agent":                       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	assert.Equal(t, uint64(0), memories[0].BillingOrganizationID)
	assert.False(t, saveCalled, "save should not be called for unresolved billing entity")
}

func TestGetTopUserMemories_BackfillBilling_StampsLegacyMemories(t *testing.T) {
	legacyMemory := &core.Memory{
		ID:      "legacy-1",
		Subject: "Test",
		Fact:    "fact",
		Source:  core.MemorySource{User: testUser(), InteractionID: "i1"},
		// Zero billing IDs — needs backfill.
		BillingOrganizationID: 0,
		BillingEnterpriseID:   0,
	}

	var savedMemory *core.Memory
	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{legacyMemory}, nil
		},
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			savedMemory = memory
			return nil
		},
	}

	resolver := &MockBillingEntityResolver{
		ResolveFunc: func(ctx context.Context, userID int64) (core.BillingEntity, error) {
			return core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":                                     true,
			"copilot_feature_agentic_memory_user_scoped":                         true,
			"copilot_feature_agentic_memory_backfill_user_memory_billing_entity": true,
			"copilot_feature_agentic_memory_with_billing_entity":                 true,
			"copilot_swe_agent_memory_secret_scanning":                           true,
			"copilot_swe_agent_memory_voting_coding_agent":                       true,
		}),
		withBillingEntityResolver(resolver),
	)

	memories, err := svc.GetTopUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 1)

	// Memory should be stamped in the response.
	assert.Equal(t, uint64(42), memories[0].BillingOrganizationID)
	assert.Equal(t, uint64(99), memories[0].BillingEnterpriseID)

	// And persisted.
	require.NotNil(t, savedMemory)
	assert.Equal(t, uint64(42), savedMemory.BillingOrganizationID)
	assert.Equal(t, uint64(99), savedMemory.BillingEnterpriseID)
}

func TestGetUserMemories_BillingFilter_PassesToStore(t *testing.T) {
	explicitFilter := &core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}

	var capturedFilter *core.BillingEntity
	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			capturedFilter = billingFilter
			return []*core.Memory{{ID: "m1", Subject: "test", Fact: "fact", Source: core.MemorySource{User: testUser(), InteractionID: "i1"}}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetUserMemories(codingAgentCtx(t), testUser(), core.UserMemoryQuery{BillingFilter: explicitFilter})
	require.NoError(t, err)
	require.NotNil(t, capturedFilter)
	assert.Equal(t, uint64(42), capturedFilter.OrganizationID)
	assert.Equal(t, uint64(99), capturedFilter.EnterpriseID)
	assert.True(t, capturedFilter.Resolved)
}

func TestGetUserMemories_NoBillingFilter_PassesNilFilter(t *testing.T) {
	var capturedFilter *core.BillingEntity
	filterCaptured := false
	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			capturedFilter = billingFilter
			filterCaptured = true
			return []*core.Memory{{ID: "m1", Subject: "test", Fact: "fact", Source: core.MemorySource{User: testUser(), InteractionID: "i1"}}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetUserMemories(codingAgentCtx(t), testUser(), core.UserMemoryQuery{})
	require.NoError(t, err)
	require.True(t, filterCaptured, "FindByUser should have been called")
	assert.Nil(t, capturedFilter, "billing filter should be nil when not provided")
}

func TestGetRecentUserMemories_BillingFilter_PassesToStore(t *testing.T) {
	explicitFilter := &core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}

	var capturedFilter *core.BillingEntity
	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			capturedFilter = billingFilter
			return []*core.Memory{{ID: "m1", Subject: "test", Fact: "fact", Source: core.MemorySource{User: testUser(), InteractionID: "i1"}}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetRecentUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{BillingFilter: explicitFilter})
	require.NoError(t, err)
	require.NotNil(t, capturedFilter)
	assert.Equal(t, uint64(42), capturedFilter.OrganizationID)
	assert.Equal(t, uint64(99), capturedFilter.EnterpriseID)
	assert.True(t, capturedFilter.Resolved)
}

func TestGetTopUserMemories_BillingFilter_PassesToStore(t *testing.T) {
	explicitFilter := &core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}

	var capturedFilter *core.BillingEntity
	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			capturedFilter = billingFilter
			return []*core.Memory{{ID: "m1", Subject: "test", Fact: "fact", Source: core.MemorySource{User: testUser(), InteractionID: "i1"}}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetTopUserMemories(t.Context(), testUser(), expectedLimit, core.UserMemoryQuery{BillingFilter: explicitFilter})
	require.NoError(t, err)
	require.NotNil(t, capturedFilter)
	assert.Equal(t, uint64(42), capturedFilter.OrganizationID)
}

func TestCountUserMemories_BillingFilter_PassesToStore(t *testing.T) {
	explicitFilter := &core.BillingEntity{OrganizationID: 42, EnterpriseID: 99, Resolved: true}

	var capturedFilter *core.BillingEntity
	memoryStore := &MockMemoryStore{
		CountByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) (int, error) {
			capturedFilter = billingFilter
			return 5, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	count, err := svc.CountUserMemories(t.Context(), testUser(), core.UserMemoryQuery{BillingFilter: explicitFilter})
	require.NoError(t, err)
	assert.Equal(t, 5, count)
	require.NotNil(t, capturedFilter)
	assert.Equal(t, uint64(42), capturedFilter.OrganizationID)
}
