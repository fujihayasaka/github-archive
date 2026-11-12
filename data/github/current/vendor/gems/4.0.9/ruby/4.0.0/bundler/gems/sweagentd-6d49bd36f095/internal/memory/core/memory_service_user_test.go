package core_test

import (
	"errors"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCreateUserMemory(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	memoryStore := &MockMemoryStore{
		SaveForUserFunc: func(userID uint64, m *core.Memory) error {
			assert.Equal(t, user.ID, userID)
			assert.Equal(t, core.MemoryScopeUser, m.Scope)
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.NoError(t, err)
	assert.Equal(t, core.MemoryScopeUser, memory.Scope)
}

func TestCreateUserMemoryFeatureDisabled(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore,
		withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	err := svc.CreateUserMemory(t.Context(), memory, user)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestCreateUserMemoryUserScopedFlagDisabled(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory": true,
			// user-scoped flag not enabled
		}))

	err := svc.CreateUserMemory(t.Context(), memory, user)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestCreateUserMemoryStoreError(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	memoryStore := &MockMemoryStore{
		SaveForUserFunc: func(userID uint64, m *core.Memory) error {
			return errors.New("store error")
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	err := svc.CreateUserMemory(t.Context(), memory, user)
	assert.Error(t, err)
}

func TestGetUserMemories(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	expectedMemory := testMemory(repoNWO, user)

	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			assert.Equal(t, user.ID, userID)
			return []*core.Memory{expectedMemory}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	memories, err := svc.GetUserMemories(codingAgentCtx(t), user, core.UserMemoryQuery{})
	require.NoError(t, err)
	assert.Len(t, memories, 1)
	assert.Equal(t, expectedMemory.ID, memories[0].ID)
}

func TestGetUserMemoriesNoResults(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetUserMemories(codingAgentCtx(t), user, core.UserMemoryQuery{})
	assert.ErrorIs(t, err, core.ErrNoMemoriesNotFound)
}

func TestGetRecentUserMemories(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	expectedMemory := testMemory(repoNWO, user)

	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			assert.Equal(t, user.ID, userID)
			assert.Equal(t, expectedLimit, limit)
			return []*core.Memory{expectedMemory}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	memories, err := svc.GetRecentUserMemories(codingAgentCtx(t), user, expectedLimit, core.UserMemoryQuery{})
	require.NoError(t, err)
	assert.Len(t, memories, 1)
}

func TestGetRecentUserMemoriesNoResults(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{
		FindRecentByUserFunc: func(userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetRecentUserMemories(codingAgentCtx(t), user, expectedLimit, core.UserMemoryQuery{})
	assert.ErrorIs(t, err, core.ErrNoMemoriesNotFound)
}

func TestDeleteUserMemory(t *testing.T) {
	user := testUser()
	memoryID := testMemoryID()

	memoryStore := &MockMemoryStore{
		DeleteForUserFunc: func(userID uint64, id core.MemoryID) error {
			assert.Equal(t, user.ID, userID)
			assert.Equal(t, memoryID, id)
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	err := svc.DeleteUserMemory(t.Context(), user, memoryID)
	require.NoError(t, err)
}

func TestDeleteUserMemories(t *testing.T) {
	user := testUser()
	memoryIDs := []core.MemoryID{"id1", "id2"}

	memoryStore := &MockMemoryStore{
		DeleteBatchForUserFunc: func(userID uint64, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			assert.Equal(t, user.ID, userID)
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	result, err := svc.DeleteUserMemories(t.Context(), user, memoryIDs)
	require.NoError(t, err)
	assert.Len(t, result.Deleted, 2)
}

func TestDeleteAllUserMemories(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{
		DeleteAllForUserFunc: func(userID uint64) error {
			assert.Equal(t, user.ID, userID)
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	err := svc.DeleteAllUserMemories(t.Context(), user)
	require.NoError(t, err)
}

func TestDeleteAllUserMemoriesFeatureDisabled(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore,
		withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	err := svc.DeleteAllUserMemories(t.Context(), user)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestCheckUserMemoryEnabled(t *testing.T) {
	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore)

	enabled, err := svc.CheckUserMemoryEnabled(t.Context(), 1)
	require.NoError(t, err)
	assert.True(t, enabled)
}

func TestCheckUserMemoryEnabledDisabled(t *testing.T) {
	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore,
		withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	enabled, err := svc.CheckUserMemoryEnabled(t.Context(), 1)
	require.NoError(t, err)
	assert.False(t, enabled)
}

func TestCheckUserMemoryEnabledFlagDisabled(t *testing.T) {
	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory": true,
			// user-scoped flag not enabled
		}))

	enabled, err := svc.CheckUserMemoryEnabled(t.Context(), 1)
	require.NoError(t, err)
	assert.False(t, enabled)
}

func TestCheckUserMemoryEnabledNilChecker(t *testing.T) {
	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore, withNilEnablementChecker())

	enabled, err := svc.CheckUserMemoryEnabled(t.Context(), 1)
	require.NoError(t, err)
	assert.False(t, enabled)
}

func TestUserMemoryOperationsGatedByUserScopedFlag(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	// Flags where base memory is enabled but user-scoped is not
	flags := map[string]bool{
		"copilot-feature-agentic-memory": true,
	}

	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(flags))

	t.Run("CreateUserMemory", func(t *testing.T) {
		err := svc.CreateUserMemory(t.Context(), memory, user)
		assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("GetUserMemories", func(t *testing.T) {
		_, err := svc.GetUserMemories(codingAgentCtx(t), user, core.UserMemoryQuery{})
		assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("GetRecentUserMemories", func(t *testing.T) {
		_, err := svc.GetRecentUserMemories(codingAgentCtx(t), user, 10, core.UserMemoryQuery{})
		assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("DeleteUserMemory", func(t *testing.T) {
		err := svc.DeleteUserMemory(t.Context(), user, testMemoryID())
		assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("DeleteUserMemories", func(t *testing.T) {
		_, err := svc.DeleteUserMemories(t.Context(), user, []core.MemoryID{"id1"})
		assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})

	t.Run("DeleteAllUserMemories", func(t *testing.T) {
		err := svc.DeleteAllUserMemories(t.Context(), user)
		assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	})
}

func TestUserScopedMemoryWithDisabledFlag(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	// Both base and user-scoped enabled, but disabled flag set
	flags := map[string]bool{
		"copilot-feature-agentic-memory":             true,
		"copilot_feature_agentic_memory_user_scoped": true,
		"copilot-feature-agentic-memory-disabled":    true,
	}

	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(flags))

	err := svc.CreateUserMemory(t.Context(), memory, user)
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestUserScopedMemoryWithBothFlagsEnabled(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	memory := testMemory(repoNWO, user)

	flags := map[string]bool{
		"copilot-feature-agentic-memory":             true,
		"copilot_feature_agentic_memory_user_scoped": true,
	}

	memoryStore := &MockMemoryStore{
		SaveForUserFunc: func(userID uint64, m *core.Memory) error {
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(flags))

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.NoError(t, err)
}

func TestGetUserMemoriesSortsByScoreWhenVotingEnabled(t *testing.T) {
	user := testUser()
	now := time.Now().UTC()

	low := &core.Memory{ID: "low", CreatedAt: now, Votes: []core.Vote{}}
	high := &core.Memory{
		ID:        "high",
		CreatedAt: now,
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}, {Direction: core.UpVote, Timestamp: now}},
	}

	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{low, high}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	memories, err := svc.GetUserMemories(codingAgentCtx(t), user, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 2)
	assert.Equal(t, core.MemoryID("high"), memories[0].ID, "higher-scored memory should come first")
	assert.Equal(t, core.MemoryID("low"), memories[1].ID)
}

func TestGetTopUserMemories(t *testing.T) {
	user := testUser()
	now := time.Now().UTC()

	low := &core.Memory{ID: "low", CreatedAt: now, Votes: []core.Vote{}}
	mid := &core.Memory{
		ID:        "mid",
		CreatedAt: now,
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}},
	}
	high := &core.Memory{
		ID:        "high",
		CreatedAt: now,
		Votes:     []core.Vote{{Direction: core.UpVote, Timestamp: now}, {Direction: core.UpVote, Timestamp: now}},
	}

	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{low, mid, high}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	memories, err := svc.GetTopUserMemories(t.Context(), user, 2, core.UserMemoryQuery{})
	require.NoError(t, err)
	require.Len(t, memories, 2, "should return only top 2")
	assert.Equal(t, core.MemoryID("high"), memories[0].ID)
	assert.Equal(t, core.MemoryID("mid"), memories[1].ID)
}

func TestGetTopUserMemoriesNoResults(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return []*core.Memory{}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetTopUserMemories(t.Context(), user, 5, core.UserMemoryQuery{})
	assert.ErrorIs(t, err, core.ErrNoMemoriesNotFound)
}

func TestGetTopUserMemoriesFeatureDisabled(t *testing.T) {
	user := testUser()
	memoryStore := &MockMemoryStore{}

	svc := newTestMemoryService(t, memoryStore,
		withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	_, err := svc.GetTopUserMemories(t.Context(), user, 5, core.UserMemoryQuery{})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestGetTopUserMemoriesStoreError(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{
		FindByUserFunc: func(userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
			return nil, errors.New("store error")
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	_, err := svc.GetTopUserMemories(t.Context(), user, 5, core.UserMemoryQuery{})
	assert.Error(t, err)
}
