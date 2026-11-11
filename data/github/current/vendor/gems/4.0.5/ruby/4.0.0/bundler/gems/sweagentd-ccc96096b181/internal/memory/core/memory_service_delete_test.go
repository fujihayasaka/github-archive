package core_test

import (
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDeleteMemorySuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryID := testMemoryID()

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			deleteCalled := false
			memoryRepository := &MockMemoryRepository{
				DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
					deleteCalled = true
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Equal(t, memoryID, id)
					return nil
				},
			}

			svc := newTestMemoryService(t, memoryRepository)
			repository := testRepository(repoNWO, private)

			err := svc.DeleteMemory(t.Context(), user, repository, memoryID)
			require.NoError(t, err)
			assert.True(t, deleteCalled, "expected Delete to be called on repository")
		})
	}
}

func TestDeleteAllMemoriesSuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	memories := []*core.Memory{
		{ID: "memory1", Subject: "Subject1", Fact: "Fact1"},
		{ID: "memory2", Subject: "Subject2", Fact: "Fact2"},
	}

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			deletedIDs := []core.MemoryID{}
			memoryRepository := &MockMemoryRepository{
				FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
					assert.Equal(t, core.RepositoryID(1), repoID)
					return memories, nil
				},
				DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
					deletedIDs = append(deletedIDs, id)
					return nil
				},
			}

			svc := newTestMemoryService(t, memoryRepository)
			repository := testRepository(repoNWO, private)

			err := svc.DeleteAllMemories(t.Context(), user, repository)
			require.NoError(t, err)
			assert.Len(t, deletedIDs, 2, "expected 2 memories to be deleted")
			assert.Contains(t, deletedIDs, core.MemoryID("memory1"))
			assert.Contains(t, deletedIDs, core.MemoryID("memory2"))
		})
	}
}

func TestDeleteMemoryDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryID := testMemoryID()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for disallowed repository")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository, withDisallowedRepo())

	err := svc.DeleteMemory(t.Context(), user, repository, memoryID)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestDeleteAllMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for disallowed repository")
			return nil, nil
		},
		DeleteFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for disallowed repository")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository, withDisallowedRepo())

	err := svc.DeleteAllMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}
