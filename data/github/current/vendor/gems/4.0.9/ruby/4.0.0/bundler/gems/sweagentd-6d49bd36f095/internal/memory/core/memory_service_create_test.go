package core_test

import (
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCreateMemory(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			memory := core.NewMemory(
				testMemoryID(),
				"Test Subject",
				"Test Fact",
				"Test Reason",
				[]string{"source1"},
				core.MemorySource{
					InteractionID: "interaction1",
					NWO:           repoNWO,
					User:          user,
				},
			)
			repository := testRepository(repoNWO, private)
			metricsStatter := &metricsCapturingStatter{}

			memoryStore := &MockMemoryStore{
				SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
					assert.Equal(t, repository.ID, repoID)
					assert.Equal(t, core.MemoryScopeRepository, memory.Scope)
					return nil
				},
			}

			svc := newTestMemoryService(t, memoryStore, withStatter(metricsStatter))

			err := svc.CreateMemory(t.Context(), memory, repository)
			require.NoError(t, err, "expected no error when creating memory for %s repo", name)
			assert.Equal(t, core.MemoryScopeRepository, memory.Scope)
			distributionCall, ok := findDistributionCall(metricsStatter.distributionCalls, "memory_service.votes_per_memory")
			require.True(t, ok, "expected votes-per-memory distribution to be emitted")
			assert.InDelta(t, 1.0, distributionCall.value, 0.001)
		})
	}
}

// Tests for public repository behavior (Private: false)

// End-to-end process test for creation, retrieval and deletion of memory in a public repository.
// We need less granular tests here since most logic is already covered in earlier tests.
func TestCreateAndGetMemoryPublicRepositorySuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, false) // public repo

	memoryStore := &MockMemoryStore{
		FindByRepositoryFunc: func(repoID core.RepositoryID) ([]*core.Memory, error) {
			return []*core.Memory{memory}, nil
		},
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			return nil
		},
		DeleteForRepositoryFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore) // public repo

	// Let's first store our memory...
	err := svc.CreateMemory(t.Context(), memory, repository)
	require.NoError(t, err, "expected no error for public repository")

	// ... and then retrieve it.
	result, err := svc.GetMemories(t.Context(), user, repository)
	require.NoError(t, err, "expected no error when retrieving memories for public repository")
	assert.Len(t, result, 1, "expected exactly one memory retrieved")
	assert.Equal(t, memory, result[0], "expected retrieved memory to match stored memory")

	// Now let's try to delete the memory
	err = svc.DeleteMemory(t.Context(), user, repository, memory.ID)
	require.NoError(t, err, "expected no error when deleting memory from public repository")
}

// Tests for disallowed repositories

func TestCreateMemoryDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			t.Error("Save should not be called for disallowed repository")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestCreateMemory_WhenEnablementCheckerNil_DisablesFeature(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			t.Error("Save should not be called when enablement is unavailable")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withNilEnablementChecker())

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}

func TestCreateMemory_WhenEnablementDisabledForUser(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			t.Error("Save should not be called when enablement is false")
			return nil
		},
	}

	enablementChecker := &MockMemoryEnablementChecker{Enabled: false}
	svc := newTestMemoryService(t, memoryStore, withEnablementChecker(enablementChecker))

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
	assert.True(t, enablementChecker.Called)
	assert.Equal(t, int64(user.ID), enablementChecker.LastUserID)
}

func TestCreateMemory_WhenEnablementCheckErrors_PropagatesError(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memory := testMemory(repoNWO, user)
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		SaveForRepositoryFunc: func(repoID core.RepositoryID, memory *core.Memory) error {
			t.Error("Save should not be called when enablement check fails")
			return nil
		},
	}

	enablementChecker := &MockMemoryEnablementChecker{
		Enabled: false,
		Err:     core.ErrFeatureNotEnabled,
	}
	svc := newTestMemoryService(t, memoryStore, withEnablementChecker(enablementChecker))

	err := svc.CreateMemory(t.Context(), memory, repository)
	require.Error(t, err)
	require.ErrorContains(t, err, "memories are not enabled for this actor")
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
}
