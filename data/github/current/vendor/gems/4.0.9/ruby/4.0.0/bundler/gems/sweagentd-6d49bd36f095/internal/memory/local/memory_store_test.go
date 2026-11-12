package local

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var testRepo = NewLocalMemoryStore()

func createTestMemory(nwo string) *core.Memory {
	memoryID := core.MemoryID(uuid.New().String())
	repoNwo, _ := core.NewRepoNWOFromString(nwo)
	return core.NewMemory(memoryID, "Test Subject", "Test Fact", "Test Reason", []string{"source1"}, core.MemorySource{
		InteractionID: "interaction1",
		NWO:           *repoNwo,
		User:          core.User{ID: 1, Login: "testuser"},
	})
}

func TestLocalMemoryStore_Save(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Test successful save
	err := testRepo.SaveForRepository(t.Context(), repoID, memory)
	require.NoError(t, err)

	// Test Save with nil memory should return error
	err = testRepo.SaveForRepository(t.Context(), repoID, nil)
	require.Error(t, err)
}

func TestLocalMemoryStore_FindByRepository(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Save memory first
	err := testRepo.SaveForRepository(t.Context(), repoID, memory)
	require.NoError(t, err)

	memories, err := testRepo.FindByRepository(t.Context(), repoID)
	require.NoError(t, err)
	assert.Greater(t, len(memories), 0) // Should have at least the memory we just saved

	// Find our specific memory in the results
	found := false
	for _, m := range memories {
		if m.ID == memory.ID {
			assert.Equal(t, memory, m)
			found = true
			break
		}
	}
	assert.True(t, found, "Should find the saved memory in results")

	// Test FindByRepository with non-existent repo ID
	nonExistentRepoID := core.RepositoryID(999)
	memories, err = testRepo.FindByRepository(t.Context(), nonExistentRepoID)
	require.NoError(t, err)
	assert.Len(t, memories, 0)
}

func TestLocalMemoryStore_Delete(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Save memory first
	err := testRepo.SaveForRepository(t.Context(), repoID, memory)
	require.NoError(t, err)

	// Test Delete existing memory
	err = testRepo.DeleteForRepository(t.Context(), repoID, memory.ID)
	require.NoError(t, err)

	// Test that memory is actually deleted
	memories, err := testRepo.FindByRepository(t.Context(), repoID)
	require.NoError(t, err)
	for _, m := range memories {
		assert.NotEqual(t, memory.ID, m.ID, "deleted memory should not appear in results")
	}

	// Test Delete non-existent memory (should not error)
	nonExistentID := core.MemoryID(uuid.New().String())
	err = testRepo.DeleteForRepository(t.Context(), repoID, nonExistentID)
	require.ErrorIs(t, err, core.ErrMemoryNotFound) // Expect specific error for not found
}

func TestLocalMemoryStore_FindRecentByRepository(t *testing.T) {
	// Create a fresh repository for this test to avoid interference
	testRepo := NewLocalMemoryStore()
	repoID := core.RepositoryID(1)

	// Create test memories with different timestamps
	memory1 := createTestMemory("test/repo")
	memory1.CreatedAt = time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	memory2 := createTestMemory("test/repo")
	memory2.CreatedAt = time.Date(2023, 1, 2, 0, 0, 0, 0, time.UTC)
	memory3 := createTestMemory("test/repo")
	memory3.CreatedAt = time.Date(2023, 1, 3, 0, 0, 0, 0, time.UTC)

	// Save memories
	err := testRepo.SaveForRepository(t.Context(), repoID, memory1)
	require.NoError(t, err)
	err = testRepo.SaveForRepository(t.Context(), repoID, memory2)
	require.NoError(t, err)
	err = testRepo.SaveForRepository(t.Context(), repoID, memory3)
	require.NoError(t, err)

	// Test FindRecentByRepository with limit
	memories, err := testRepo.FindRecentByRepository(t.Context(), repoID, 2)
	require.NoError(t, err)
	assert.Len(t, memories, 2)

	// Check that memories are returned in descending order by creation time
	assert.True(t, memories[0].CreatedAt.After(memories[1].CreatedAt) || memories[0].CreatedAt.Equal(memories[1].CreatedAt))

	// Test with limit larger than available memories
	memories, err = testRepo.FindRecentByRepository(t.Context(), repoID, 10)
	require.NoError(t, err)
	assert.Len(t, memories, 3)

	// Test with invalid limit (should default to 10)
	memories, err = testRepo.FindRecentByRepository(t.Context(), repoID, 0)
	require.NoError(t, err)
	assert.Len(t, memories, 3) // All memories returned since we only have 3

	// Test with non-existent repository ID
	nonExistentRepoID := core.RepositoryID(999)
	memories, err = testRepo.FindRecentByRepository(t.Context(), nonExistentRepoID, 10)
	require.NoError(t, err)
	assert.Len(t, memories, 0)
}

func TestLocalMemoryStore_UserScope(t *testing.T) {
	// Test that user and repo scopes work correctly and are isolated
	testRepo := NewLocalMemoryStore()
	var userID uint64 = 42
	repoID := core.RepositoryID(42)

	userMemory := createTestMemory("test/repo")
	repoMemory := createTestMemory("test/repo")

	// Save memory to user scope
	err := testRepo.SaveForUser(t.Context(), userID, userMemory)
	require.NoError(t, err)

	// Save memory to repo scope
	err = testRepo.SaveForRepository(t.Context(), repoID, repoMemory)
	require.NoError(t, err)

	// Retrieve from user scope
	userMemories, err := testRepo.FindByUser(t.Context(), userID, nil)
	require.NoError(t, err)
	assert.Len(t, userMemories, 1)
	assert.Equal(t, userMemory.ID, userMemories[0].ID)

	// Retrieve from repo scope
	repoMemories, err := testRepo.FindByRepository(t.Context(), repoID)
	require.NoError(t, err)
	assert.Len(t, repoMemories, 1)
	assert.Equal(t, repoMemory.ID, repoMemories[0].ID)
}

func TestLocalMemoryStore_ListBillingEntityMemoriesFiltersAndPaginates(t *testing.T) {
	testRepo := NewLocalMemoryStore()
	userID := uint64(42)
	otherUserID := uint64(43)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	orgMemory1 := createTestMemory("test/repo")
	orgMemory1.ID = "org-1"
	orgMemory1.Source.User = core.User{ID: userID, Login: "octo-42"}
	orgMemory1.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	orgMemory1.BillingOrganizationID = 100
	orgMemory1.BillingEnterpriseID = 200

	orgMemory2 := createTestMemory("test/repo")
	orgMemory2.ID = "org-2"
	orgMemory2.Source.User = core.User{ID: userID, Login: "octo-42"}
	orgMemory2.CreatedAt = time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)
	orgMemory2.BillingOrganizationID = 100
	orgMemory2.BillingEnterpriseID = 200

	otherUserMemory := createTestMemory("test/repo")
	otherUserMemory.ID = "other-user"
	otherUserMemory.Source.User = core.User{ID: otherUserID, Login: "octo-43"}
	otherUserMemory.CreatedAt = time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	otherUserMemory.BillingOrganizationID = 100
	otherUserMemory.BillingEnterpriseID = 200

	otherOrgMemory := createTestMemory("test/repo")
	otherOrgMemory.ID = "other-org"
	otherOrgMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	otherOrgMemory.CreatedAt = time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)
	otherOrgMemory.BillingOrganizationID = 101
	otherOrgMemory.BillingEnterpriseID = 200

	legacyMemory := createTestMemory("test/repo")
	legacyMemory.ID = "legacy"
	legacyMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	legacyMemory.CreatedAt = time.Date(2026, 1, 5, 0, 0, 0, 0, time.UTC)

	for _, memory := range []*core.Memory{orgMemory1, orgMemory2, otherOrgMemory, legacyMemory} {
		require.NoError(t, testRepo.SaveForUser(t.Context(), userID, memory))
	}
	require.NoError(t, testRepo.SaveForUser(t.Context(), otherUserID, otherUserMemory))

	page, err := testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: userID}, core.MemoryPageRequest{Limit: 1, SnapshotTime: snapshotTime})
	require.NoError(t, err)
	require.Len(t, page.Memories, 1)
	assert.Equal(t, core.MemoryID("org-2"), page.Memories[0].ID)
	assert.Equal(t, "1", page.ContinuationToken)

	page, err = testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: userID}, core.MemoryPageRequest{Limit: 1, ContinuationToken: page.ContinuationToken, SnapshotTime: snapshotTime})
	require.NoError(t, err)
	require.Len(t, page.Memories, 1)
	assert.Equal(t, core.MemoryID("org-1"), page.Memories[0].ID)
	assert.Empty(t, page.ContinuationToken)

	page, err = testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 100}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})
	require.ErrorIs(t, err, core.ErrInvalidUserFilter)
	assert.Nil(t, page)
}

func TestLocalMemoryStore_ListBillingEntityMemoriesEnterpriseFilter(t *testing.T) {
	testRepo := NewLocalMemoryStore()
	userID := uint64(42)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	enterpriseMemory := createTestMemory("test/repo")
	enterpriseMemory.ID = "enterprise"
	enterpriseMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	enterpriseMemory.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	enterpriseMemory.BillingEnterpriseID = 200

	otherEnterpriseMemory := createTestMemory("test/repo")
	otherEnterpriseMemory.ID = "other-enterprise"
	otherEnterpriseMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	otherEnterpriseMemory.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	otherEnterpriseMemory.BillingEnterpriseID = 201

	require.NoError(t, testRepo.SaveForUser(t.Context(), userID, enterpriseMemory))
	require.NoError(t, testRepo.SaveForUser(t.Context(), userID, otherEnterpriseMemory))

	page, err := testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{EnterpriseID: 200, UserID: userID}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})
	require.NoError(t, err)
	require.Len(t, page.Memories, 1)
	assert.Equal(t, core.MemoryID("enterprise"), page.Memories[0].ID)
}

func TestLocalMemoryStore_ListBillingEntityMemoriesFiltersUserByPartition(t *testing.T) {
	testRepo := NewLocalMemoryStore()
	userID := uint64(42)
	otherUserID := uint64(43)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	memory := createTestMemory("test/repo")
	memory.ID = "partition-user"
	memory.Source.User = core.User{ID: otherUserID, Login: "octo-43"}
	memory.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	memory.BillingOrganizationID = 100

	require.NoError(t, testRepo.SaveForUser(t.Context(), userID, memory))

	page, err := testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: userID}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})
	require.NoError(t, err)
	require.Len(t, page.Memories, 1)
	assert.Equal(t, core.MemoryID("partition-user"), page.Memories[0].ID)

	page, err = testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: otherUserID}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})
	require.NoError(t, err)
	assert.Empty(t, page.Memories)
}

func TestLocalMemoryStore_ListBillingEntityMemoriesRejectsInvalidFilters(t *testing.T) {
	testRepo := NewLocalMemoryStore()
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
			page, err := testRepo.ListBillingEntityMemories(t.Context(), tt.filter, tt.pageRequest)

			require.ErrorIs(t, err, tt.wantErr)
			assert.Nil(t, page)
		})
	}
}

func TestLocalMemoryStore_ListBillingEntityMemoriesRejectsInvalidContinuationToken(t *testing.T) {
	testRepo := NewLocalMemoryStore()

	page, err := testRepo.ListBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{OrganizationID: 100, UserID: 42}, core.MemoryPageRequest{
		Limit:             10,
		ContinuationToken: "not-an-offset",
		SnapshotTime:      time.Now(),
	})

	require.ErrorIs(t, err, core.ErrInvalidContinuation)
	assert.Nil(t, page)
}

func TestLocalMemoryStore_SaveBatchForRepository(t *testing.T) {
	store := NewLocalMemoryStore()
	repoID := core.RepositoryID(100)

	// Test successful batch save
	m1 := createTestMemory("test/repo")
	m2 := createTestMemory("test/repo")
	m3 := createTestMemory("test/repo")

	err := store.SaveBatchForRepository(t.Context(), repoID, []*core.Memory{m1, m2, m3})
	require.NoError(t, err)

	// Verify all memories were saved
	memories, err := store.FindByRepository(t.Context(), repoID)
	require.NoError(t, err)
	assert.Len(t, memories, 3)

	// Test empty batch
	err = store.SaveBatchForRepository(t.Context(), repoID, []*core.Memory{})
	require.NoError(t, err)

	// Test batch with nil memory returns error
	err = store.SaveBatchForRepository(t.Context(), repoID, []*core.Memory{createTestMemory("test/repo"), nil})
	require.Error(t, err)

	// Verify that the valid memory from the failed batch was NOT saved (atomicity)
	memories, err = store.FindByRepository(t.Context(), repoID)
	require.NoError(t, err)
	assert.Len(t, memories, 3, "failed batch should not have saved any new memories")
}

func TestLocalMemoryStore_SaveBatchForUser(t *testing.T) {
	store := NewLocalMemoryStore()
	var userID uint64 = 200

	m1 := createTestMemory("test/repo")
	m2 := createTestMemory("test/repo")

	err := store.SaveBatchForUser(t.Context(), userID, []*core.Memory{m1, m2})
	require.NoError(t, err)

	memories, err := store.FindByUser(t.Context(), userID, nil)
	require.NoError(t, err)
	assert.Len(t, memories, 2)
}

func TestLocalMemoryStore_DeleteBillingEntityMemoriesFiltersAndDeletes(t *testing.T) {
	testRepo := NewLocalMemoryStore()
	userID := uint64(42)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	// Memory that matches org filter and is before snapshot
	orgMemory1 := createTestMemory("test/repo")
	orgMemory1.ID = "org-1"
	orgMemory1.Source.User = core.User{ID: userID, Login: "octo-42"}
	orgMemory1.CreatedAt = time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC)
	orgMemory1.BillingOrganizationID = 100
	orgMemory1.BillingEnterpriseID = 200

	orgMemory2 := createTestMemory("test/repo")
	orgMemory2.ID = "org-2"
	orgMemory2.Source.User = core.User{ID: userID, Login: "octo-42"}
	orgMemory2.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	orgMemory2.BillingOrganizationID = 100
	orgMemory2.BillingEnterpriseID = 200

	// Memory that belongs to a different org — should NOT be deleted
	otherOrgMemory := createTestMemory("test/repo")
	otherOrgMemory.ID = "other-org"
	otherOrgMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	otherOrgMemory.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	otherOrgMemory.BillingOrganizationID = 999

	// Memory created after snapshot — should NOT be deleted
	futureMemory := createTestMemory("test/repo")
	futureMemory.ID = "future"
	futureMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	futureMemory.CreatedAt = time.Date(2026, 1, 5, 0, 0, 0, 0, time.UTC)
	futureMemory.BillingOrganizationID = 100

	for _, memory := range []*core.Memory{orgMemory1, orgMemory2, otherOrgMemory, futureMemory} {
		require.NoError(t, testRepo.SaveForUser(t.Context(), userID, memory))
	}

	// Delete with limit=1 to test pagination
	result, err := testRepo.DeleteBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{
		OrganizationID: 100,
		UserID:         userID,
	}, core.MemoryPageRequest{Limit: 1, SnapshotTime: snapshotTime})

	require.NoError(t, err)
	require.Equal(t, uint(1), result.DeletedCount)
	require.NotEmpty(t, result.ContinuationToken, "should have more to delete")

	// Delete the next page using the returned continuation token
	result, err = testRepo.DeleteBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{
		OrganizationID: 100,
		UserID:         userID,
	}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime, ContinuationToken: result.ContinuationToken})

	require.NoError(t, err)
	require.Equal(t, uint(1), result.DeletedCount)
	require.Empty(t, result.ContinuationToken, "no more to delete")

	// Verify only the non-matching memories remain
	remaining, err := testRepo.FindByUser(t.Context(), userID, nil)
	require.NoError(t, err)
	require.Len(t, remaining, 2)

	remainingIDs := []core.MemoryID{remaining[0].ID, remaining[1].ID}
	assert.Contains(t, remainingIDs, core.MemoryID("other-org"))
	assert.Contains(t, remainingIDs, core.MemoryID("future"))
}

func TestLocalMemoryStore_DeleteBillingEntityMemoriesPerUserPartition(t *testing.T) {
	testRepo := NewLocalMemoryStore()
	userID := uint64(42)
	otherUserID := uint64(43)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	// Same org, but stored under different user partitions
	userMemory := createTestMemory("test/repo")
	userMemory.ID = "user-42-mem"
	userMemory.Source.User = core.User{ID: userID, Login: "octo-42"}
	userMemory.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	userMemory.BillingOrganizationID = 100

	otherUserMemory := createTestMemory("test/repo")
	otherUserMemory.ID = "user-43-mem"
	otherUserMemory.Source.User = core.User{ID: otherUserID, Login: "octo-43"}
	otherUserMemory.CreatedAt = time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	otherUserMemory.BillingOrganizationID = 100

	require.NoError(t, testRepo.SaveForUser(t.Context(), userID, userMemory))
	require.NoError(t, testRepo.SaveForUser(t.Context(), otherUserID, otherUserMemory))

	// Delete only for user 42
	result, err := testRepo.DeleteBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{
		OrganizationID: 100,
		UserID:         userID,
	}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})

	require.NoError(t, err)
	require.Equal(t, uint(1), result.DeletedCount)

	// User 42's memories are gone
	remaining42, err := testRepo.FindByUser(t.Context(), userID, nil)
	require.NoError(t, err)
	assert.Empty(t, remaining42)

	// User 43's memories are untouched
	remaining43, err := testRepo.FindByUser(t.Context(), otherUserID, nil)
	require.NoError(t, err)
	require.Len(t, remaining43, 1)
	assert.Equal(t, core.MemoryID("user-43-mem"), remaining43[0].ID)
}

func TestLocalMemoryStore_DeleteBillingEntityMemoriesEmptyResults(t *testing.T) {
	testRepo := NewLocalMemoryStore()
	userID := uint64(42)
	snapshotTime := time.Date(2026, 1, 4, 0, 0, 0, 0, time.UTC)

	// No memories stored at all
	result, err := testRepo.DeleteBillingEntityMemories(t.Context(), core.BillingEntityMemoryFilter{
		OrganizationID: 100,
		UserID:         userID,
	}, core.MemoryPageRequest{Limit: 10, SnapshotTime: snapshotTime})

	require.NoError(t, err)
	require.Equal(t, uint(0), result.DeletedCount)
	require.Empty(t, result.ContinuationToken)
}

func TestLocalMemoryStore_DeleteBillingEntityMemoriesRejectsInvalidFilters(t *testing.T) {
	testRepo := NewLocalMemoryStore()
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
			result, err := testRepo.DeleteBillingEntityMemories(t.Context(), tt.filter, tt.pageRequest)

			require.ErrorIs(t, err, tt.wantErr)
			assert.Nil(t, result)
		})
	}
}
