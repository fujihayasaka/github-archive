package cosmos_test

import (
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/cosmos"
	"github.com/github/sweagentd/internal/memory/cosmos/testcontainer"
	"github.com/github/sweagentd/internal/observability"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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

func newRandomRepoID() core.RepositoryID {
	// random uint64 for testing purposes
	return core.RepositoryID(uuid.New().ID())
}

func TestCosmosMemoryStore_Save(t *testing.T) {
	textContainer := testcontainer.NewCosmosTestContainer(t)
	memoryStore := cosmos.NewCosmosMemoryStoreFromContainerClient(textContainer.Client(), observability.NewNoopExporters())

	t.Run("Save Memory", func(t *testing.T) {
		memory := createTestMemory("test/repo")
		repoID := newRandomRepoID()
		err := memoryStore.SaveForRepository(t.Context(), repoID, memory)
		require.NoError(t, err, "Failed to save memory")

		memories, err := memoryStore.FindByRepository(t.Context(), repoID)
		require.NoError(t, err, "Failed to retrieve saved memory")
		require.Len(t, memories, 1, "Expected exactly one memory")
		assert.Equal(t, memory.ID, memories[0].ID, "Retrieved memory does not match saved memory")
	})

	t.Run("Memory not found", func(t *testing.T) {
		repoID := newRandomRepoID()
		memories, err := memoryStore.FindByRepository(t.Context(), repoID)
		require.NoError(t, err, "FindByRepository should not error for empty repo")
		assert.Len(t, memories, 0, "Expected no memories for non-existent repo")
	})

	t.Run("Find by repository", func(t *testing.T) {
		memory1 := createTestMemory("test/repo1")
		memory2 := createTestMemory("test/repo2")
		repoID1 := newRandomRepoID()
		repoID2 := newRandomRepoID()
		err := memoryStore.SaveForRepository(t.Context(), repoID1, memory1)
		require.NoError(t, err, "Failed to save memory1")
		err = memoryStore.SaveForRepository(t.Context(), repoID2, memory2)
		require.NoError(t, err, "Failed to save memory2")

		memories, err := memoryStore.FindByRepository(t.Context(), repoID1)
		require.NoError(t, err, "Failed to retrieve memories by repository")
		assert.Len(t, memories, 1, "Expected to find one memory for repoID1")
		assert.Equal(t, memory1.ID, memories[0].ID, "Retrieved memory does not match saved memory for repoID1")
	})

	t.Run("Delete Memory", func(t *testing.T) {
		memory := createTestMemory("test/repo3")
		repoID := newRandomRepoID()
		err := memoryStore.SaveForRepository(t.Context(), repoID, memory)
		require.NoError(t, err, "Failed to save memory before deletion")

		err = memoryStore.DeleteForRepository(t.Context(), repoID, memory.ID)
		require.NoError(t, err, "Failed to delete memory")

		memories, err := memoryStore.FindByRepository(t.Context(), repoID)
		require.NoError(t, err, "FindByRepository should not error after delete")
		assert.Len(t, memories, 0, "Expected no memories after deletion")
	})
}
