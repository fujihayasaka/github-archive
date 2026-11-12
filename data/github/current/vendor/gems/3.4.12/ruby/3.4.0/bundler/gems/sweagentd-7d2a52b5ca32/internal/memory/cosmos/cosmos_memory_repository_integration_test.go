package cosmos_test

import (
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/cosmos"
	"github.com/github/sweagentd/internal/memory/cosmos/testcontainer"
	"github.com/github/sweagentd/internal/observability"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func createTestMemory(nwo string) *core.Memory {
	memoryID := core.MemoryID(uuid.New().String())
	repoNWO, _ := core.NewRepoNWOFromString(nwo)
	return core.NewMemory(
		memoryID,
		"Test Subject",
		"Test Fact",
		"Test Reason",
		[]string{"source1"},
		core.MemorySource{
			InteractionID: "interaction1",
			NWO:           *repoNWO,
			User:          core.User{ID: 1, Login: "testuser"},
			Agent:         "test-agent",
		},
	)
}

func newRandomRepositoryID() core.RepositoryID {
	// random uint64 for testing purposes
	return core.RepositoryID(uuid.New().ID())
}

func TestCosmosMemoryRepository_Save(t *testing.T) {
	textContainer := testcontainer.NewCosmosTestContainer(t)
	memoryRepository := cosmos.NewCosmosMemoryRepositoryFromContainerClient(textContainer.Client(), observability.NewNoopExporters())

	t.Run("Save Memory", func(t *testing.T) {
		memory := createTestMemory("test/repo")
		repoID := newRandomRepositoryID()
		err := memoryRepository.Save(t.Context(), repoID, memory)
		assert.NoError(t, err, "Failed to save memory")

		retrievedMemory, err := memoryRepository.FindByID(t.Context(), repoID, memory.ID)
		assert.NoError(t, err, "Failed to retrieve saved memory")
		assert.Equal(t, &memory, &retrievedMemory, "Retrieved memory does not match saved memory")
	})

	t.Run("Memory not found", func(t *testing.T) {
		repoID := newRandomRepositoryID()
		_, err := memoryRepository.FindByID(t.Context(), repoID, core.MemoryID("nonexistent"))
		assert.Error(t, err, "Expected error when retrieving non-existent memory")
		assert.Equal(t, core.ErrMemoryNotFound, err, "Error should be ErrMemoryNotFound")
	})

	t.Run("Find by repository", func(t *testing.T) {
		memory1 := createTestMemory("test/repo1")
		memory2 := createTestMemory("test/repo2")
		repoID1 := newRandomRepositoryID()
		repoID2 := newRandomRepositoryID()
		err := memoryRepository.Save(t.Context(), repoID1, memory1)
		assert.NoError(t, err, "Failed to save memory1")
		err = memoryRepository.Save(t.Context(), repoID2, memory2)
		assert.NoError(t, err, "Failed to save memory2")

		memories, err := memoryRepository.FindByRepository(t.Context(), repoID1)
		assert.NoError(t, err, "Failed to retrieve memories by repository")
		assert.Len(t, memories, 1, "Expected to find one memory for repo1")
		assert.Equal(t, memory1.ID, memories[0].ID, "Retrieved memory does not match saved memory for repo1")
	})

	t.Run("Delete Memory", func(t *testing.T) {
		memory := createTestMemory("test/repo3")
		repoID := newRandomRepositoryID()
		err := memoryRepository.Save(t.Context(), repoID, memory)
		assert.NoError(t, err, "Failed to save memory before deletion")

		err = memoryRepository.Delete(t.Context(), repoID, memory.ID)
		assert.NoError(t, err, "Failed to delete memory")

		memory, err = memoryRepository.FindByID(t.Context(), repoID, memory.ID)
		assert.ErrorIs(t, err, core.ErrMemoryNotFound, "Expected error when retrieving deleted memory")
		assert.Nil(t, memory, "Memory should be nil after deletion")
	})

}
