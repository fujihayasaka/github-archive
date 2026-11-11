package core_test

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCreateMemoryThatContainsSecrets(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	memory.Fact = "Test Fact with secret"
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
	}

	// Create a secret scanner that detects secrets
	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withSecretScanner(secretScanner))

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrMemoryContainsSecrets, "expected error when creating memory that contains secrets")
}

func TestCreateMemoryWithSecretScanningDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	memory.Fact = "Test Fact with secret"
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
	}

	// Scanner that would find a secret (but should not be called)
	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withSecretScanner(secretScanner),
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":           true,
			"copilot_swe_agent_memory_secret_scanning": false, // Disable secret scanning
		}))

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.NoError(t, err, "expected no error when creating memory with secret scanning disabled")
}

func TestCreateUserMemoryThatContainsSecretsWithoutRepoContext(t *testing.T) {
	user := testUser()
	memory := testMemory(core.RepoNWO{}, user)
	memory.Fact = "Test Fact with secret"

	scanCalled := false
	saveCalled := false
	memoryStore := &MockMemoryStore{
		SaveForUserFunc: func(userID uint64, memory *core.Memory) error {
			saveCalled = true
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, gotRepoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			scanCalled = true
			require.Equal(t, core.RepoNWO{}, gotRepoNWO, "expected generic scanning when no repo context is available")

			return []core.MemorySecret{{ID: "secret-id", RepoNWO: gotRepoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withSecretScanner(secretScanner))

	err := svc.CreateUserMemory(t.Context(), memory, user)
	require.ErrorIs(t, err, core.ErrMemoryContainsSecrets, "expected error when creating a user-scoped memory that contains secrets")
	require.True(t, scanCalled, "expected secret scanner to be called for user-scoped memory without repo context")
	require.False(t, saveCalled, "expected user memory save to be skipped when secret scanning blocks creation")
}

func TestVoteOnMemoryThatContainsSecretsScansFactAndReason(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	voteReason := "vote reason with secret"

	findCalled := false
	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			findCalled = true
			return nil, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			saveCalled = true
			assert.Len(t, memories, 1)
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, gotRepoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			require.Equal(t, repoNWO, gotRepoNWO)
			require.Equal(t, testFact, memory.Fact, "fact (user-supplied query) should be scanned")
			require.Equal(t, voteReason, memory.Reason, "vote reason should be scanned")

			return []core.MemorySecret{{ID: "secret-id", RepoNWO: gotRepoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withSecretScanner(secretScanner))

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Agent:         "copilot-swe-agent",
			CommitSHA:     "abc123",
			InteractionID: "interaction-1",
			BaseModel:     "gpt-5",
			Reason:        voteReason,
		},
	})
	require.ErrorIs(t, err, core.ErrMemoryContainsSecrets)
	require.False(t, findCalled, "expected vote lookup to be skipped when secret scanning blocks the vote")
	require.False(t, saveCalled, "expected vote save to be skipped when secret scanning blocks the vote")
}

func TestVoteOnMemoryWithSecretScanningDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	existingMemory := testMemory(repoNWO, user)
	existingMemory.Fact = testFact

	scanCalled := false
	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			require.Equal(t, testFact, fact)
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			saveCalled = true
			assert.Len(t, memories, 1)
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			scanCalled = true
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withSecretScanner(secretScanner),
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":               true,
			"copilot_swe_agent_memory_voting_coding_agent": true,
		}),
	)

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Reason: "vote reason with secret",
		},
	})
	require.NoError(t, err, "expected vote to proceed when secret scanning is disabled")
	require.False(t, scanCalled, "expected secret scanner not to be called when feature flag is disabled")
	require.True(t, saveCalled, "expected vote to be saved when secret scanning is disabled")
}

func TestVoteOnUserMemoryThatContainsSecretsScansFactAndReason(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	voteReason := "vote reason with secret"

	findCalled := false
	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			findCalled = true
			return nil, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			saveCalled = true
			assert.Len(t, memories, 1)
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, gotRepoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			require.Equal(t, repoNWO, gotRepoNWO)
			require.Equal(t, testFact, memory.Fact, "fact (user-supplied query) should be scanned")
			require.Equal(t, voteReason, memory.Reason, "vote reason should be scanned")

			return []core.MemorySecret{{ID: "secret-id", RepoNWO: gotRepoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withSecretScanner(secretScanner))

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Agent:     "copilot-swe-agent",
			CommitSHA: "abc123",
			Reason:    voteReason,
			RepoNWO:   repoNWO,
		},
	})
	require.ErrorIs(t, err, core.ErrMemoryContainsSecrets)
	require.False(t, findCalled, "expected vote lookup to be skipped when secret scanning blocks the vote")
	require.False(t, saveCalled, "expected vote save to be skipped when secret scanning blocks the vote")
}

func TestVoteOnUserMemoryWithSecretScanningDisabled(t *testing.T) {
	user := testUser()
	existingMemory := &core.Memory{
		ID:   "1",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Source:    core.VoteSource{Agent: "initial-agent"},
		}},
	}

	scanCalled := false
	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			require.Equal(t, testFact, fact)
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			saveCalled = true
			assert.Len(t, memories, 1)
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			scanCalled = true
			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withSecretScanner(secretScanner),
		withFeatureFlags(map[string]bool{
			"copilot-feature-agentic-memory":               true,
			"copilot_feature_agentic_memory_user_scoped":   true,
			"copilot_swe_agent_memory_voting_coding_agent": true,
		}),
	)

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Reason: "vote reason with secret",
		},
	})
	require.NoError(t, err, "expected vote to proceed when secret scanning is disabled")
	require.False(t, scanCalled, "expected secret scanner not to be called when feature flag is disabled")
	require.True(t, saveCalled, "expected vote to be saved when secret scanning is disabled")
}

func TestVoteOnUserMemoryThatContainsSecretsWithoutRepoContext(t *testing.T) {
	user := testUser()
	existingMemory := &core.Memory{
		ID:   "1",
		Fact: testFact,
		Source: core.MemorySource{
			User: user,
		},
		Votes: []core.Vote{{
			Direction: core.UpVote,
			Source:    core.VoteSource{Agent: "initial-agent"},
		}},
	}

	scanCalled := false
	saveCalled := false
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return []*core.Memory{existingMemory}, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			saveCalled = true
			assert.Len(t, memories, 1)
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			scanCalled = true
			require.Equal(t, core.RepoNWO{}, repoNWO, "expected generic scanning when no repo context is available")
			require.Equal(t, testFact, memory.Fact, "fact (user-supplied query) should be scanned")
			require.Equal(t, "vote reason with secret", memory.Reason, "vote reason should be scanned")

			return []core.MemorySecret{{ID: "secret-id", RepoNWO: repoNWO, SecretKey: "secret-key", Secret: "secret-value"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withSecretScanner(secretScanner))

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Agent:  "copilot-swe-agent",
			Reason: "vote reason with secret",
		},
	})
	require.ErrorIs(t, err, core.ErrMemoryContainsSecrets, "expected vote to be blocked when generic secret scanning detects secrets")
	require.True(t, scanCalled, "expected secret scanner to be called when NWO is empty")
	require.False(t, saveCalled, "expected vote save to be skipped when secret scanning blocks the vote")
}

// --- Async path secret scanning tests ---

func TestVoteOnMemoryAsyncScansFactAndReason(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)
	voteReason := "vote reason with secret"

	scanCalled := make(chan struct{}, 1)
	saveCalled := make(chan struct{}, 1)
	memoryStore := &MockMemoryStore{
		FindByFactForRepositoryFunc: func(repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
			return nil, nil
		},
		SaveBatchForRepositoryFunc: func(repoID core.RepositoryID, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			saveCalled <- struct{}{}
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, gotRepoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			assert.Equal(t, repoNWO, gotRepoNWO)
			assert.Equal(t, testFact, memory.Fact, "fact should be scanned asynchronously")
			assert.Equal(t, voteReason, memory.Reason, "vote reason should be scanned asynchronously")
			scanCalled <- struct{}{}
			return []core.MemorySecret{{ID: "secret-id"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withAsyncVoting(), withSecretScanner(secretScanner))

	err := svc.VoteOnMemory(codingAgentCtx(t), user, repository, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Agent:  "copilot-swe-agent",
			Reason: voteReason,
		},
	})
	require.NoError(t, err, "async path should return immediately")

	select {
	case <-scanCalled:
	case <-time.After(2 * time.Second):
		t.Fatal("async vote goroutine did not invoke secret scanner within timeout")
	}

	select {
	case <-saveCalled:
		t.Error("store save should be skipped when secret scanning detects secrets")
	case <-time.After(200 * time.Millisecond):
		// Expected: save was not called.
	}
}

func TestVoteOnUserMemoryAsyncScansFactAndReason(t *testing.T) {
	user := testUser()
	repoNWO := testRepoNWO(t)
	voteReason := "vote reason with secret"

	scanCalled := make(chan struct{}, 1)
	saveCalled := make(chan struct{}, 1)
	memoryStore := &MockMemoryStore{
		FindByFactForUserFunc: func(userID uint64, fact string) ([]*core.Memory, error) {
			return nil, nil
		},
		SaveBatchForUserFunc: func(userID uint64, memories []*core.Memory) error {
			assert.Len(t, memories, 1)
			saveCalled <- struct{}{}
			return nil
		},
	}

	secretScanner := &MockSecretScanner{
		ScanFunc: func(ctx context.Context, gotRepoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
			assert.Equal(t, repoNWO, gotRepoNWO)
			assert.Equal(t, testFact, memory.Fact, "fact should be scanned asynchronously")
			assert.Equal(t, voteReason, memory.Reason, "vote reason should be scanned asynchronously")
			scanCalled <- struct{}{}
			return []core.MemorySecret{{ID: "secret-id"}}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withAsyncVoting(), withSecretScanner(secretScanner))

	err := svc.VoteOnUserMemory(codingAgentCtx(t), user, testFact, &core.Vote{
		Direction: core.UpVote,
		Source: core.VoteSource{
			Agent:   "copilot-swe-agent",
			Reason:  voteReason,
			RepoNWO: repoNWO,
		},
	})
	require.NoError(t, err, "async path should return immediately")

	select {
	case <-scanCalled:
	case <-time.After(2 * time.Second):
		t.Fatal("async user vote goroutine did not invoke secret scanner within timeout")
	}

	select {
	case <-saveCalled:
		t.Error("store save should be skipped when secret scanning detects secrets")
	case <-time.After(200 * time.Millisecond):
		// Expected: save was not called.
	}
}
