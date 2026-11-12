package core_test

import (
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGetMemoriesNotFound(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return make([]*core.Memory, 0), nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrNoMemoriesNotFound, "expected no memories found error")
}

func TestGetMemories(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

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
	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return nil, expectedError
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetMemories(t.Context(), user, repository)
	require.Error(t, err, "expected an error when getting memories")
	require.ErrorIs(t, err, expectedError, "expected the returned error to match the simulated error")
}

func TestGetMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

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
			memoryStore := &MockMemoryStore{
				FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Equal(t, expectedLimit, limit)
					return memories, nil
				},
			}

			svc := newTestMemoryService(t, memoryStore)
			repository := testRepository(repoNWO, private)

			result, err := svc.GetRecentMemories(codingAgentCtx(t), user, repository, expectedLimit)

			require.NoError(t, err)
			assert.Equal(t, memories, result)
		})
	}
}

func TestGetRecentMemoriesFeatureDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{"copilot-feature-agentic-memory": false}))

	result, err := svc.GetRecentMemories(codingAgentCtx(t), user, repository, expectedLimit)

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

	memoryStore := &MockMemoryStore{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			assert.Equal(t, core.RepositoryID(1), repoID)
			assert.Equal(t, uint(3), limit)
			return expectedMemories, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	result, err := svc.GetRecentMemories(codingAgentCtx(t), user, repository, 3)

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

	memoryStore := &MockMemoryStore{
		FindRecentByRepositoryFunc: func(repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
			t.Error("FindRecentByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

	result, err := svc.GetRecentMemories(codingAgentCtx(t), user, repository, expectedLimit)

	require.Error(t, err)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
	assert.Nil(t, result)
}

func TestGetMemories_SortedByScore(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	now := time.Now().UTC()

	zeroScore := &core.Memory{
		ID:        "zero",
		CreatedAt: now,
		Votes:     []core.Vote{},
	}
	highScore := &core.Memory{
		ID:        "high",
		CreatedAt: now,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
			{Direction: core.UpVote, Timestamp: now},
		},
	}

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			// Return in wrong order: zero score first
			return []*core.Memory{zeroScore, highScore}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())
	ctx := featureflags.ContextWithIntegrationID(t.Context(), "copilot-developer")
	memories, err := svc.GetMemories(ctx, user, repository)

	require.NoError(t, err)
	require.Len(t, memories, 2)
	assert.Equal(t, core.MemoryID("high"), memories[0].ID, "highest score should be first")
	assert.Equal(t, core.MemoryID("zero"), memories[1].ID, "zero score should be last")
}

func TestGetMemories_SortedByScoreWithPerClientFlag(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	now := time.Now().UTC()

	zeroScore := &core.Memory{ID: "zero", CreatedAt: now, Votes: []core.Vote{}}
	highScore := &core.Memory{
		ID: "high", CreatedAt: now,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
			{Direction: core.UpVote, Timestamp: now},
		},
	}

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{zeroScore, highScore}, nil
		},
	}

	// Only coding agent per-client flag enabled
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
	}))

	// CCA client → coding agent flag enabled → memories should be sorted
	ctx := featureflags.ContextWithIntegrationID(t.Context(), "copilot-developer")
	memories, err := svc.GetMemories(ctx, user, repository)
	require.NoError(t, err)
	require.Len(t, memories, 2)
	assert.Equal(t, core.MemoryID("high"), memories[0].ID, "highest score should be first")
}

func TestGetMemories_NotSortedWhenPerClientFlagDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	now := time.Now().UTC()

	zeroScore := &core.Memory{ID: "zero", CreatedAt: now, Votes: []core.Vote{}}
	highScore := &core.Memory{
		ID: "high", CreatedAt: now,
		Votes: []core.Vote{
			{Direction: core.UpVote, Timestamp: now},
			{Direction: core.UpVote, Timestamp: now},
		},
	}

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			// Return in store order: zero first
			return []*core.Memory{zeroScore, highScore}, nil
		},
	}

	// coding agent flag enabled but we're a VSCode client with no VSCode flag
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
	}))

	// VSCode client → VSCode flag not enabled → memories should NOT be sorted
	ctx := featureflags.ContextWithIntegrationID(t.Context(), "vscode-chat")
	memories, err := svc.GetMemories(ctx, user, repository)
	require.NoError(t, err)
	require.Len(t, memories, 2)
	assert.Equal(t, core.MemoryID("zero"), memories[0].ID, "store order preserved when flag disabled")
}

func TestGetTopMemoriesSuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	now := time.Now().UTC()

	low := &core.Memory{ID: "low", CreatedAt: now, Votes: []core.Vote{{Direction: core.UpVote, Timestamp: now}}}
	mid := &core.Memory{ID: "mid", CreatedAt: now, Votes: []core.Vote{
		{Direction: core.UpVote, Timestamp: now},
		{Direction: core.UpVote, Timestamp: now},
	}}
	high := &core.Memory{ID: "high", CreatedAt: now, Votes: []core.Vote{
		{Direction: core.UpVote, Timestamp: now},
		{Direction: core.UpVote, Timestamp: now},
		{Direction: core.UpVote, Timestamp: now},
	}}

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{low, mid, high}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	memories, err := svc.GetTopMemories(t.Context(), user, repository, 2)

	require.NoError(t, err)
	require.Len(t, memories, 2, "should return only top 2")
	assert.Equal(t, core.MemoryID("high"), memories[0].ID)
	assert.Equal(t, core.MemoryID("mid"), memories[1].ID)
}

func TestGetTopMemoriesFiltersNegativeScores(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	now := time.Now().UTC()

	good := &core.Memory{ID: "good", CreatedAt: now, Votes: []core.Vote{{Direction: core.UpVote, Timestamp: now}}}
	bad := &core.Memory{ID: "bad", CreatedAt: now, Votes: []core.Vote{
		{Direction: core.DownVote, Timestamp: now},
		{Direction: core.DownVote, Timestamp: now},
	}}

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{bad, good}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	memories, err := svc.GetTopMemories(t.Context(), user, repository, 10)

	require.NoError(t, err)
	require.Len(t, memories, 1, "negative score memory should be filtered out")
	assert.Equal(t, core.MemoryID("good"), memories[0].ID)
}

func TestGetTopMemoriesNotFound(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	_, err := svc.GetTopMemories(t.Context(), user, repository, 10)

	require.ErrorIs(t, err, core.ErrNoMemoriesNotFound)
}

func TestGetTopMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			t.Error("FindByRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())
	_, err := svc.GetTopMemories(t.Context(), user, repository, 10)

	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}
