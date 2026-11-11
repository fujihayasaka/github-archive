package memorylocal

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

var testRepo = NewLocalMemoryRepository()

func createTestMemory(nwo string) *core.Memory {
	memoryID := core.MemoryID(uuid.New().String())
	repoNwo, _ := core.NewRepoNWOFromString(nwo)
	return core.NewMemory(memoryID, "Test Subject", "Test Fact", "Test Reason", []string{"source1"}, core.MemorySource{
		InteractionID: "interaction1",
		NWO:           *repoNwo,
		User:          core.User{ID: 1, Login: "testuser"},
	})
}

func TestLocalMemoryRepository_Save(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Test successful save
	err := testRepo.Save(t.Context(), repoID, memory)
	assert.NoError(t, err)

	// Test Save with nil memory should return error
	err = testRepo.Save(t.Context(), repoID, nil)
	assert.Error(t, err)
}

func TestLocalMemoryRepository_FindByID(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Save memory first
	err := testRepo.Save(t.Context(), repoID, memory)
	assert.NoError(t, err)

	// Test FindByID with existing memory
	foundMemory, err := testRepo.FindByID(t.Context(), repoID, memory.ID)
	assert.NoError(t, err)
	assert.Equal(t, memory, foundMemory)

	// Test FindByID with non-existent memory
	nonExistentID := core.MemoryID(uuid.New().String())
	_, err = testRepo.FindByID(t.Context(), repoID, nonExistentID)
	assert.Error(t, err)
}

func TestLocalMemoryRepository_FindByRepository(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Save memory first
	err := testRepo.Save(t.Context(), repoID, memory)
	assert.NoError(t, err)

	// Test FindByRepository with existing repository
	memories, err := testRepo.FindByRepository(t.Context(), repoID)
	assert.NoError(t, err)
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
	assert.True(t, found, "Should find the saved memory in repository results")

	// Test FindByRepository with non-existent repository
	nonExistentRepoID := core.RepositoryID(999)
	memories, err = testRepo.FindByRepository(t.Context(), nonExistentRepoID)
	assert.NoError(t, err)
	assert.Len(t, memories, 0)
}

func TestLocalMemoryRepository_Delete(t *testing.T) {
	memory := createTestMemory("test/repo")
	repoID := core.RepositoryID(1)

	// Save memory first
	err := testRepo.Save(t.Context(), repoID, memory)
	assert.NoError(t, err)

	// Test Delete existing memory
	err = testRepo.Delete(t.Context(), repoID, memory.ID)
	assert.NoError(t, err)

	// Test that memory is actually deleted
	_, err = testRepo.FindByID(t.Context(), repoID, memory.ID)
	assert.Error(t, err)

	// Test Delete non-existent memory (should not error)
	nonExistentID := core.MemoryID(uuid.New().String())
	err = testRepo.Delete(t.Context(), repoID, nonExistentID)
	assert.ErrorIs(t, err, core.ErrMemoryNotFound) // Expect specific error for not found
}

func TestLocalMemoryRepository_FindRecentByRepository(t *testing.T) {
	// Create a fresh repository for this test to avoid interference
	testRepo := NewLocalMemoryRepository()
	repoID := core.RepositoryID(1)

	// Create test memories with different timestamps
	memory1 := createTestMemory("test/repo")
	memory1.CreatedAt = time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	memory2 := createTestMemory("test/repo")
	memory2.CreatedAt = time.Date(2023, 1, 2, 0, 0, 0, 0, time.UTC)
	memory3 := createTestMemory("test/repo")
	memory3.CreatedAt = time.Date(2023, 1, 3, 0, 0, 0, 0, time.UTC)

	// Save memories
	err := testRepo.Save(t.Context(), repoID, memory1)
	assert.NoError(t, err)
	err = testRepo.Save(t.Context(), repoID, memory2)
	assert.NoError(t, err)
	err = testRepo.Save(t.Context(), repoID, memory3)
	assert.NoError(t, err)

	// Test FindRecentByRepository with limit
	memories, err := testRepo.FindRecentByRepository(t.Context(), repoID, 2)
	assert.NoError(t, err)
	assert.Len(t, memories, 2)

	// Check that memories are returned in descending order by creation time
	assert.True(t, memories[0].CreatedAt.After(memories[1].CreatedAt) || memories[0].CreatedAt.Equal(memories[1].CreatedAt))

	// Test with limit larger than available memories
	memories, err = testRepo.FindRecentByRepository(t.Context(), repoID, 10)
	assert.NoError(t, err)
	assert.Len(t, memories, 3)

	// Test with invalid limit (should default to 10)
	memories, err = testRepo.FindRecentByRepository(t.Context(), repoID, 0)
	assert.NoError(t, err)
	assert.Len(t, memories, 3) // All memories returned since we only have 3

	// Test with non-existent repository
	nonExistentRepoID := core.RepositoryID(999)
	memories, err = testRepo.FindRecentByRepository(t.Context(), nonExistentRepoID, 10)
	assert.NoError(t, err)
	assert.Len(t, memories, 0)
}
