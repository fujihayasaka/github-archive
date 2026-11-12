package core_test

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testFact = "ExtensionLoader manages extension lifecycle"

func TestVoteOnMemorySuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			findCalled := false
			saveCalled := false
			metricsStatter := &metricsCapturingStatter{}

			existingMemory := testMemory(repoNWO, user)
			existingMemory.Fact = testFact
			existingMemory.CreatedAt = time.Now().Add(-24 * time.Hour)
			existingMemory.UpdatedAt = existingMemory.CreatedAt
			existingMemory.ExpiresAt = existingMemory.CreatedAt.Add(core.VoteWindow)
			existingMemory.Votes = []core.Vote{{
				Direction: core.UpVote,
				Timestamp: existingMemory.CreatedAt,
				Source:    core.VoteSource{Agent: "initial-agent"},
			}}

			memoryStore := &MockMemoryStore{
				FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
					findCalled = true
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Equal(t, testFact, fact)
					return []*core.Memory{existingMemory}, nil
				},
				SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
					saveCalled = true
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Len(t, memories, 1)
					// Verify a vote was added
					assert.Len(t, memories[0].Votes, 2)
					assert.Equal(t, core.UpVote, memories[0].Votes[1].Direction)
					return nil
				},
			}

			svc := newTestMemoryService(t, memoryStore, withStatter(metricsStatter))
			repository := testRepository(repoNWO, private)

			voteSource := core.VoteSource{
				Agent:     "copilot-swe-agent",
				RepoNWO:   repoNWO,
				CommitSHA: "abc123",
				UserID:    user.ID,
				UserLogin: user.Login,
			}

			err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote, Source: voteSource})
			require.NoError(t, err)
			assert.True(t, findCalled, "expected FindByFactForRepository to be called")
			assert.True(t, saveCalled, "expected SaveForRepository to be called")
			distributionCall, ok := findDistributionCall(metricsStatter.distributionCalls, "memory_service.votes_per_memory")
			require.True(t, ok, "expected votes-per-memory distribution to be emitted")
			assert.InDelta(t, 2.0, distributionCall.value, 0.001)
			counterCall, ok := findCounterCall(metricsStatter.counterCalls, "memory_service.vote_memory.count")
			require.True(t, ok, "expected vote_memory.count counter to be emitted")
			assert.Equal(t, "copilot-developer", counterCall.tags["copilot_integration_id"])
			assert.Equal(t, "upvote", counterCall.tags["direction"])
		})
	}
}

func TestVoteOnMemoryNotFound(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return nil, nil
		},
	}

	metricsStatter := &metricsCapturingStatter{}
	svc := newTestMemoryService(t, memoryStore, withStatter(metricsStatter))
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrMemoryFactNotFound)
	assert.Empty(t, metricsStatter.distributionCalls, "expected no distribution metric when voting target is not found")
}

func TestVoteOnMemoryNilRepository(t *testing.T) {
	user := testUser()

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, nil, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrRepositoryNotFound)
}

func TestVoteOnMemoryInvalidDirection(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.VoteValue(9)})
	assert.ErrorIs(t, err, core.ErrInvalidVoteDirection)
}

func TestVoteOnMemoryFeatureNotEnabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}
	svc := newTestMemoryService(t, memoryStore, withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnMemoryDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			t.Error("FindByFactForRepository should not be called for disallowed repository")
			return nil, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnMemoryVotingFeatureFlagDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}
	// Enable general memory but disable voting specifically
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory": true,
	}))

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnMemoryPerClientFlagCodingAgent(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	findCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			findCalled = true
			return nil, nil
		},
	}
	// Only the coding agent per-client flag is enabled
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
		"copilot_swe_agent_memory_secret_scanning":     true,
	}))

	ctx := featureflags.ContextWithIntegrationID(t.Context(), "copilot-developer")
	err := svc.VoteOnMemory(ctx, user, repository, testFact, &core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrMemoryFactNotFound) // gets past the flag check
	assert.True(t, findCalled, "expected store lookup when coding agent flag allows CCA client")
}

func TestVoteOnMemoryPerClientFlagBlocksWrongClient(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}
	// Only the coding agent flag is enabled; VSCode flag is off
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
	}))

	// VSCode client should be blocked — VSCode flag is not enabled and base is off
	ctx := featureflags.ContextWithIntegrationID(t.Context(), "vscode-chat")
	err := svc.VoteOnMemory(ctx, user, repository, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnMemoryUnknownIntegrationDisablesVoting(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{}
	// All per-client flags enabled, but unknown integration has no mapping → voting disabled
	svc := newTestMemoryService(t, memoryStore, withFeatureFlags(map[string]bool{
		"copilot-feature-agentic-memory":               true,
		"copilot_swe_agent_memory_voting_coding_agent": true,
		"copilot_swe_agent_memory_secret_scanning":     true,
	}))

	ctx := featureflags.ContextWithIntegrationID(t.Context(), "some-unknown-client")
	err := svc.VoteOnMemory(ctx, user, repository, testFact, &core.Vote{Direction: core.UpVote})
	assert.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestVoteOnMemoryDownvoteDoesNotResetExpiry(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	existingMemory := testMemory(repoNWO, user)
	existingMemory.Fact = testFact
	existingMemory.CreatedAt = time.Now().Add(-24 * time.Hour)
	existingMemory.UpdatedAt = existingMemory.CreatedAt
	originalExpiry := existingMemory.CreatedAt.Add(core.VoteWindow)
	existingMemory.ExpiresAt = originalExpiry
	existingMemory.Votes = []core.Vote{{
		Direction: core.UpVote,
		Timestamp: existingMemory.CreatedAt,
		Source:    core.VoteSource{Agent: "initial-agent"},
	}}

	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			// After a downvote, ExpiresAt should NOT have been reset to a new 28-day window
			assert.Len(t, memories, 1)
			assert.Equal(t, originalExpiry, memories[0].ExpiresAt)
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.DownVote, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err)
}

func TestVoteOnMemoryDownvoteMultipleMemories(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	now := time.Now()
	memory1 := &core.Memory{
		ID:   "mem-1",
		Fact: testFact,
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           repoNWO,
			User:          user,
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
			InteractionID: "interaction2",
			NWO:           repoNWO,
			User:          user,
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
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return []*core.Memory{memory1, memory2}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
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

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.DownVote, Source: core.VoteSource{Agent: "downvoter"}})
	require.NoError(t, err)
}

func TestVoteOnMemoryUpvotePicksHighestScored(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	now := time.Now()

	// memory1 has the newest UpdatedAt but only one upvote (lower decayed score).
	memory1 := &core.Memory{
		ID:   "mem-1",
		Fact: testFact,
		Source: core.MemorySource{
			InteractionID: "interaction1",
			NWO:           repoNWO,
			User:          user,
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
	// memory2 has an OLDER UpdatedAt but two upvotes (higher decayed score),
	// so it is the memory the user sees in GetTopMemories and should receive the upvote.
	memory2 := &core.Memory{
		ID:   "mem-2",
		Fact: testFact,
		Source: core.MemorySource{
			InteractionID: "interaction2",
			NWO:           repoNWO,
			User:          user,
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
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			// Stores return matches sorted by UpdatedAt DESC, so memory1 comes first.
			return []*core.Memory{memory1, memory2}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			savedMemories = memories
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "upvoter"}})
	require.NoError(t, err)

	require.Len(t, savedMemories, 1, "upvote should target exactly one memory")
	assert.Equal(t, core.MemoryID("mem-2"), savedMemories[0].ID,
		"upvote should land on the highest-scored memory, not the most-recently-updated one")
	assert.Len(t, memory1.Votes, 1, "memory1 should not have received a new vote")
}

func TestVoteOnMemoryUpvoteAllNegativeScoresReturnsNotFound(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	now := time.Now()
	mkNegative := func(id string, updatedAt time.Time) *core.Memory {
		return &core.Memory{
			ID:   core.MemoryID(id),
			Fact: testFact,
			Source: core.MemorySource{
				InteractionID: id,
				NWO:           repoNWO,
				User:          user,
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
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return []*core.Memory{memory1, memory2}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "upvoter"}})
	require.ErrorIs(t, err, core.ErrMemoryFactNotFound)
	assert.False(t, saveCalled, "save should not be called when no positively-scored memory exists")
}

func TestVoteOnMemorySaveFailure(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	existingMemory := testMemory(repoNWO, user)
	existingMemory.Fact = testFact
	existingMemory.Votes = []core.Vote{}

	saveErr := assert.AnError

	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			return saveErr
		},
	}

	metricsStatter := &metricsCapturingStatter{}
	svc := newTestMemoryService(t, memoryStore, withStatter(metricsStatter))
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote})
	require.Error(t, err)
	assert.Empty(t, metricsStatter.distributionCalls, "expected no distribution metric when vote persistence fails")
}

func TestVoteOnMemoryConcurrencyRetrySuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	attempt := 0

	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			m := testMemory(repoNWO, user)
			m.Fact = testFact
			m.Votes = []core.Vote{{Direction: core.UpVote, Timestamp: time.Now()}}
			return []*core.Memory{m}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			attempt++
			assert.Len(t, memories, 1)
			if attempt < 3 {
				return core.ErrConcurrencyConflict
			}
			return nil // Succeed on third attempt
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err)
	assert.Equal(t, 3, attempt, "expected 3 attempts (2 retries + 1 success)")
}

func TestVoteOnMemoryConcurrencyRetriesExhausted(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	attempts := 0

	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			m := testMemory(repoNWO, user)
			m.Fact = testFact
			m.Votes = []core.Vote{}
			return []*core.Memory{m}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			attempts++
			assert.Len(t, memories, 1)
			return core.ErrConcurrencyConflict // Always conflict
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrConcurrencyConflict)
	assert.Equal(t, 3, attempts, "expected exactly 3 attempts before giving up")
}

// --- Async voting path tests ---

func TestVoteOnMemoryAsyncReturnsImmediately(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	existingMemory := testMemory(repoNWO, user)
	existingMemory.Fact = testFact
	existingMemory.Votes = []core.Vote{}

	saveCalled := make(chan struct{}, 1)
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			saveCalled <- struct{}{}
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withAsyncVoting())
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err, "expected VoteOnMemory to return immediately with no error")

	// Wait for the goroutine to complete and verify store was called.
	select {
	case <-saveCalled:
	case <-time.After(2 * time.Second):
		t.Fatal("async vote goroutine did not complete within timeout")
	}
}

func TestVoteOnMemoryAsyncStoreNotCalledWhenSecretsDetected(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	scanCalled := make(chan struct{}, 1)
	saveCalled := make(chan struct{}, 1)
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return []*core.Memory{testMemory(repoNWO, user)}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			saveCalled <- struct{}{}
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, gotRepoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			scanCalled <- struct{}{}
			return []core.MemorySecret{{ID: "secret-id"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withAsyncVoting(), withSecretScanner(secretScanner))
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{Direction: core.UpVote, Source: core.VoteSource{Agent: "test"}})
	require.NoError(t, err, "expected async vote to return immediately even when secrets will be detected")

	// Wait for secret scanning to run in the goroutine.
	select {
	case <-scanCalled:
	case <-time.After(2 * time.Second):
		t.Fatal("async vote goroutine did not invoke secret scanner within timeout")
	}

	// Verify the store was NOT called because secret scanning blocked the vote.
	select {
	case <-saveCalled:
		t.Error("expected store save to be skipped when secret scanning detects secrets")
	case <-time.After(200 * time.Millisecond):
		// Expected: save was not called.
	}
}

// TestVoteOnMemory_ScopeMismatchTreatedAsNotFound pins the invariant that
// executeVote rejects a memory whose Scope does not match the call site's
// expected scope. Repository voting must never mutate a user-scoped memory
// (and vice versa) even if the store accidentally returns one. The mismatch
// is surfaced as ErrMemoryNotFound to avoid leaking the existence of the
// wrong-scope memory.
func TestVoteOnMemory_ScopeMismatchTreatedAsNotFound(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			m := testMemory(repoNWO, user)
			m.Fact = testFact
			// Simulate a store layer bug: returns a user-scoped memory from a
			// repository lookup.
			m.Scope = core.MemoryScopeUser
			return []*core.Memory{m}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact,
		&core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrMemoryNotFound)
	assert.False(t, saveCalled, "save must not be invoked on scope mismatch")
}

// TestVoteOnUserMemory_ScopeMismatchTreatedAsNotFound is the user-scoped
// counterpart to TestVoteOnMemory_ScopeMismatchTreatedAsNotFound.
func TestVoteOnUserMemory_ScopeMismatchTreatedAsNotFound(t *testing.T) {
	user := testUser()

	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			m := testMemory(testRepoNWO(t), user)
			m.Fact = testFact
			m.Scope = core.MemoryScopeRepository
			return []*core.Memory{m}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withVoting())
	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact,
		&core.Vote{Direction: core.UpVote})
	require.ErrorIs(t, err, core.ErrMemoryNotFound)
	assert.False(t, saveCalled, "save must not be invoked on scope mismatch")
}

// TestVoteOnMemory_RetryAppendsExactlyOneVote pins the invariant that the
// optimistic-concurrency retry loop in executeVote credits exactly one vote on
// eventual success, even when earlier attempts mutated the in-memory copy
// returned by findByFact. Each retry must refetch the memory so the
// previously-appended vote is discarded.
func TestVoteOnMemory_RetryAppendsExactlyOneVote(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	attempts := 0
	saveAttempts := 0
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			attempts++
			// Always return a fresh copy with one pre-existing upvote so we can
			// detect any "carry-over" vote from a previous attempt.
			m := testMemory(repoNWO, user)
			m.Fact = testFact
			m.Scope = core.MemoryScopeRepository
			m.Votes = []core.Vote{{Direction: core.UpVote, Timestamp: time.Now().Add(-time.Hour)}}
			return []*core.Memory{m}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			saveAttempts++
			require.Len(t, memories, 1)
			// Conflict on the first save, succeed on the second.
			if saveAttempts == 1 {
				return core.ErrConcurrencyConflict
			}
			// Invariant: exactly one vote is appended (1 existing + 1 new = 2).
			assert.Len(t, memories[0].Votes, 2,
				"retry must refetch and not carry over the previous attempt's appended vote")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact,
		&core.Vote{Direction: core.UpVote})
	require.NoError(t, err)
	assert.Equal(t, 2, attempts, "expected exactly 2 findByFact attempts")
	assert.Equal(t, 2, saveAttempts, "expected exactly 2 save attempts (conflict + success)")
}
