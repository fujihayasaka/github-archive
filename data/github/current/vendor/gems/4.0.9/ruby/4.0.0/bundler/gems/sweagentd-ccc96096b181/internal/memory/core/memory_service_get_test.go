package core_test

import (
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetMemoriesNotFound(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return make([]*core.Memory, 0), nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository)

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrNoMemoriesNotFound, "expected no memories found error")
}

func TestGetMemories(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository)

	memories, err := svc.GetMemories(t.Context(), user, repository)
	require.NoError(t, err, "expected no error when getting memories")
	assert.Len(t, memories, 1, "expected one memory to be returned")
	assert.Equal(t, memory, memories[0], "expected returned memory to match the created memory")
}

func TestGetMemoriesRepositoryError(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	expectedError := errors.New("some random error")
	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return nil, expectedError
		},
	}

	svc := newTestMemoryService(t, memoryRepository)

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.Error(t, err, "expected an error when getting memories")
	require.ErrorIs(t, err, expectedError, "expected the returned error to match the simulated error")
}

func TestGetMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository, withDisallowedRepo())

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestGetRecentMemoriesSuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	memories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "recent memory 1"},
		{ID: core.MemoryID("memory2"), Subject: "recent memory 2"},
	}

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			memoryRepository := &MockMemoryRepository{
				FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Equal(t, expectedLimit, limit)
					return memories, nil
				},
			}

			svc := newTestMemoryService(t, memoryRepository)
			repository := testRepository(repoNWO, private)

			result, err := svc.GetRecentMemories(t.Context(), user, repository, expectedLimit)

			require.NoError(t, err)
			assert.Equal(t, memories, result)
		})
	}
}

func TestGetRecentMemoriesFeatureDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{}

	svc := newTestMemoryService(t, memoryRepository,
		withFeatureFlags(map[string]bool{"copilot-feature-agentic-memory": false}))

	result, err := svc.GetRecentMemories(t.Context(), user, repository, expectedLimit)

	require.Error(t, err)
	assert.Equal(t, core.ErrFeatureNotEnabled, err)
	assert.Nil(t, result)
}

func TestGetRecentMemoriesLimitExcludesOldMemories(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	// Create 5 memories, but only return 3 (simulating limit behavior)
	allMemories := []*core.Memory{
		{ID: core.MemoryID("memory1"), Subject: "newest memory"},
		{ID: core.MemoryID("memory2"), Subject: "second newest memory"},
		{ID: core.MemoryID("memory3"), Subject: "third newest memory"},
		{ID: core.MemoryID("memory4"), Subject: "fourth newest memory"},
		{ID: core.MemoryID("memory5"), Subject: "oldest memory"},
	}

	// Repository should return only the first 3 (most recent) when limit=3
	expectedMemories := allMemories[:3]

	memoryRepository := &MockMemoryRepository{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.RepositoryID(1), repoID)
			assert.Equal(t, uint(3), limit)
			return expectedMemories, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository)

	result, err := svc.GetRecentMemories(t.Context(), user, repository, 3)

	require.NoError(t, err)
	assert.Len(t, result, 3, "Should return exactly 3 memories")
	assert.Equal(t, expectedMemories, result)

	// Verify that the older memories (memory4, memory5) are not included
	resultIDs := make([]string, len(result))
	for i, memory := range result {
		resultIDs[i] = string(memory.ID)
	}
	assert.NotContains(t, resultIDs, "memory4")
	assert.NotContains(t, resultIDs, "memory5")
}

func TestGetRecentMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryRepository := &MockMemoryRepository{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			t.Error("FindRecentByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryRepository, withDisallowedRepo())

	result, err := svc.GetRecentMemories(t.Context(), user, repository, expectedLimit)

	require.Error(t, err)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
	assert.Nil(t, result)
}
