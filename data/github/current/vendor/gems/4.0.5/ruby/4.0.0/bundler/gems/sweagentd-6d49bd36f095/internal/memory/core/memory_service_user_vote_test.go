package core_test

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestVoteOnUserMemorySuccess(t *testing.T) {
	user := testUser()

	findCalled := false
	saveCalled := false
	metricsStatter := &metricsCapturingStatter{}

	existingMemory := &core.Memory{
		ID:      "1",
		Subject: "Test Subject",
		Fact:    testFact,
		Reason:  "Test Reason",
		Source: core.MemorySource{
			User: user,
		},
		CreatedAt: time.Now().Add(-24 * time.Hour),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: time.Now().Add(-24 * time.Hour),
			Source:    core.VoteSource{Agent: "initial-agent"},
		}},
	}
	existingMemory.UpdatedAt = existingMemory.CreatedAt
	existingMemory.ExpiresAt = existingMemory.CreatedAt.Add(core.VoteWindow)

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			findCalled = true
			assert.Equal(t, user.ID, userID)
			assert.Equal(t, testFact, fact)
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			saveCalled = true
			assert.Equal(t, user.ID, userID)
			assert.Len(t, memories, 1)
			assert.Len(t, memories[0].Votes, 2)
			assert.Equal(t, core.UpVote, memories[0].Votes[1].Direction)
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting(), withStatter(metricsStatter))

	voteSource := core.VoteSource{
		Agent:     "copilot-swe-agent",
		CommitSHA: "abc123",
		UserID:    user.ID,
		UserLogin: user.Login,
	}

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote, Source: voteSource})
	require.NoError(t, err)
	assert.True(t, findCalled, "expected FindByFactForUser to be called")
	assert.True(t, saveCalled, "expected SaveForUser to be called")
	counterCall, ok := findCounterCall(metricsStatter.counterCalls, "memory_service.vote_user_memory.count")
	require.True(t, ok, "expected vote_user_memory.count counter to be emitted")
	assert.Equal(t, "copilot-developer", counterCall.tags["copilot_integration_id"])
	assert.Equal(t, "upvote", counterCall.tags["direction"])
}

func TestVoteOnUserMemoryNotFound(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrMemoryFactNotFound)
}

func TestVoteOnUserMemoryInvalidDirection(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.VoteValue(9)})
	assert.ErrorIs(t, err, core.ErrInvalidVoteDirection)
}

func TestVoteOnUserMemoryFeatureNotEnabled(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore, withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnUserMemoryVotingFlagDisabled(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":             true,
		"copilot_feature_agentic_memory_user_scoped": true,
	}))

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnUserMemoryPerClientFlagCodingAgent(t *testing.T) {
	user := testUser()

	findCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			findCalled = true
			return nil, nil
		},
	}
	// Only coding agent per-client flag enabled
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_feature_agentic_memory_user_scoped":   true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
		"copilot_swe_agent_memory_secret_scanning":     true,
	}))

	ctx := featureflags.ContextWithIntegrationID(t.Context(), "copilot-developer")
	err := svc.VoteOnUserMemory(ctx, user, testFact, &core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrMemoryFactNotFound) // gets past the flag check
	assert.True(t, findCalled, "expected store lookup when coding agent flag allows CCA client")
}

func TestVoteOnUserMemoryPerClientFlagBlocksWrongClient(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{}
	// Only coding agent flag enabled; VSCode flag is off
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_feature_agentic_memory_user_scoped":   true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
	}))

	// VSCode client should be blocked — VSCode flag is not enabled and base is off
	ctx := featureflags.ContextWithIntegrationID(t.Context(), "vscode-chat")
	err := svc.VoteOnUserMemory(ctx, user, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnUserMemoryDownvoteDoesNotResetExpiry(t *testing.T) {
	user := testUser()

	existingMemory := &core.Memory{
		ID:   "1",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		CreatedAt: time.Now().Add(-24 * time.Hour),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: time.Now().Add(-24 * time.Hour),
			Source:    core.VoteSource{Agent: "initial-agent"},
		}},
	}
	existingMemory.UpdatedAt = existingMemory.CreatedAt
	originalExpiry := existingMemory.CreatedAt.Add(core.VoteWindow)
	existingMemory.ExpiresAt = originalExpiry

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			assert.Equal(t, originalExpiry, memories[0].ExpiresAt)
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.DownVote, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err)
}

func TestVoteOnUserMemoryDownvoteMultipleMemories(t *testing.T) {
	user := testUser()
	metricsStatter := &metricsCapturingStatter{}

	now := time.Now()
	memory1 := &core.Memory{
		ID:   "mem-1",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		CreatedAt: now.Add(-1 * time.Hour),
		UpdatedAt: now.Add(-1 * time.Hour),
		ExpiresAt: now.Add(core.VoteWindow),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: now.Add(-1 * time.Hour),
			Source:    core.VoteSource{Agent: "agent-1"},
		}},
	}
	memory2 := &core.Memory{
		ID:   "mem-2",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		CreatedAt: now.Add(-2 * time.Hour),
		UpdatedAt: now.Add(-2 * time.Hour),
		ExpiresAt: now.Add(core.VoteWindow),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: now.Add(-2 * time.Hour),
			Source:    core.VoteSource{Agent: "agent-2"},
		}},
	}

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return []*core.Memory{memory1, memory2}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			assert.Len(t, memories, 2)

			for _, m := range memories {
				require.Len(t, m.Votes, 2, "memory %s should have 2 votes", m.ID)
				assert.Equal(t, core.DownVote, m.Votes[1].Direction)
			}

			// Oldest memory should have earliest or equal UpdatedAt
			assert.True(t, memory2.UpdatedAt.Before(memory1.UpdatedAt) || memory2.UpdatedAt.Equal(memory1.UpdatedAt),
				"oldest memory should have UpdatedAt <= newest memory")

			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withStatter(metricsStatter), withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.DownVote, Source: core.VoteSource{Agent: "downvoter"}})
	require.NoError(t, err)
}

func TestVoteOnUserMemoryUpvotePicksHighestScored(t *testing.T) {
	user := testUser()

	now := time.Now()

	memory1 := &core.Memory{
		ID:   "mem-1",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		CreatedAt: now.Add(-1 * 24 * time.Hour),
		UpdatedAt: now.Add(-1 * time.Hour),
		ExpiresAt: now.Add(core.VoteWindow),
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Timestamp: now.Add(-1 * 24 * time.Hour),
			Source:    core.VoteSource{Agent: "agent-1"},
		}},
	}
	memory2 := &core.Memory{
		ID:   "mem-2",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		CreatedAt: now.Add(-7 * 24 * time.Hour),
		UpdatedAt: now.Add(-5 * 24 * time.Hour),
		ExpiresAt: now.Add(core.VoteWindow),
		Votes: []core.Vote{
			{
				Direction: core.UpVote,
				Timestamp: now.Add(-5 * 24 * time.Hour),
				Source:    core.VoteSource{Agent: "agent-2a"},
			},
			{
				Direction: core.UpVote,
				Timestamp: now.Add(-5 * 24 * time.Hour),
				Source:    core.VoteSource{Agent: "agent-2b"},
			},
		},
	}

	require.Greater(t, memory2.Score(now), memory1.Score(now),
		"test setup: memory2 must be higher-scored than memory1")
	require.True(t, memory2.UpdatedAt.Before(memory1.UpdatedAt),
		"test setup: memory2 must have an older UpdatedAt than memory1")

	var savedMemories []*core.Memory
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return []*core.Memory{memory1, memory2}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			savedMemories = memories
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "upvoter"}})
	require.NoError(t, err)

	require.Len(t, savedMemories, 1, "upvote should target exactly one memory")
	assert.Equal(t, core.MemoryID("mem-2"), savedMemories[0].ID,
		"upvote should land on the highest-scored memory, not the most-recently-updated one")
	assert.Len(t, memory1.Votes, 1, "memory1 should not have received a new vote")
}

func TestVoteOnUserMemoryUpvoteAllNegativeScoresReturnsNotFound(t *testing.T) {
	user := testUser()

	now := time.Now()
	mkNegative := func(id string, updatedAt time.Time) *core.Memory {
		return &core.Memory{
			ID:   core.MemoryID(id),
			Fact: testFact,
			Source: core.MemorySource{
				User: user,
			},
			CreatedAt: updatedAt,
			UpdatedAt: updatedAt,
			ExpiresAt: now.Add(core.VoteWindow),
			Votes: []core.Vote{{
				Direction: core.DownVote,
				Timestamp: updatedAt,
				Source:    core.VoteSource{Agent: id + "-downvoter"},
			}},
		}
	}
	memory1 := mkNegative("mem-1", now.Add(-1*time.Hour))
	memory2 := mkNegative("mem-2", now.Add(-2*time.Hour))

	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return []*core.Memory{memory1, memory2}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "upvoter"}})
	require.ErrorIs(t, err, core.ErrMemoryFactNotFound)
	assert.False(t, saveCalled, "save should not be called when no positively-scored memory exists")
}

func TestVoteOnUserMemorySaveFailure(t *testing.T) {
	user := testUser()

	existingMemory := &core.Memory{
		ID:   "1",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		Votes: []core.Vote{},
	}

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			return assert.AnError
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote})
	assert.Error(t, err)
}

func TestVoteOnUserMemoryConcurrencyRetrySuccess(t *testing.T) {
	user := testUser()
	attempt := 0

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			m := &core.Memory{
				ID:   "1",
				Fact: testFact,
				Source: core.MemorySource{
					User: user,
				},
				Votes: []core.Vote{{Direction: core.UpVote, Timestamp: time.Now()}},
			}
			return []*core.Memory{m}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			attempt++
			assert.Len(t, memories, 1)
			if attempt < 3 {
				return core.ErrConcurrencyConflict
			}
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err)
	assert.Equal(t, 3, attempt, "expected 3 attempts (2 retries + 1 success)")
}

func TestVoteOnUserMemoryConcurrencyRetriesExhausted(t *testing.T) {
	user := testUser()
	attempts := 0

	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			m := &core.Memory{
				ID:   "1",
				Fact: testFact,
				Source: core.MemorySource{
					User: user,
				},
				Votes: []core.Vote{},
			}
			return []*core.Memory{m}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			attempts++
			assert.Len(t, memories, 1)
			return core.ErrConcurrencyConflict
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrConcurrencyConflict)
	assert.Equal(t, 3, attempts, "expected exactly 3 attempts before giving up")
}
