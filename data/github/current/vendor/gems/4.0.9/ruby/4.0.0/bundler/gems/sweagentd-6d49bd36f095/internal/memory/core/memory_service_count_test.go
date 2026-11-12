package core_test

import (
	"errors"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCountMemories(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		repoNWO := testRepoNWO(t)
		user := testUser()
		repository := testRepository(repoNWO, true)

		storeCalled := false
		memoryStore := &MockMemoryStore{
			CountByRepositoryFunc: func(repoID core.RepositoryID) (int, error) {
				storeCalled = true
				assert.Equal(t, repository.ID, repoID)
				return 42, nil
			},
		}

		svc := newTestMemoryService(t, memoryStore)

		count, err := svc.CountMemories(t.Context(), user, repository)
		require.NoError(t, err)
		assert.Equal(t, 42, count)
		assert.True(t, storeCalled, "expected CountByRepository to be called")
	})

	t.Run("nil repository", func(t *testing.T) {
		user := testUser()
		memoryStore := &MockMemoryStore{}

		svc := newTestMemoryService(t, memoryStore)

		count, err := svc.CountMemories(t.Context(), user, nil)
		require.ErrorIs(t, err, core.ErrRepositoryNotFound)
		assert.Equal(t, 0, count)
	})

	t.Run("feature not enabled", func(t *testing.T) {
		repoNWO := testRepoNWO(t)
		user := testUser()
		repository := testRepository(repoNWO, true)

		memoryStore := &MockMemoryStore{
			CountByRepositoryFunc: func(repoID core.RepositoryID) (int, error) {
				t.Error("CountByRepository should not be called when feature is not enabled")
				return 0, nil
			},
		}

		svc := newTestMemoryService(t, memoryStore, withNilEnablementChecker())

		count, err := svc.CountMemories(t.Context(), user, repository)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled)
		assert.Equal(t, 0, count)
	})

	t.Run("disallowed repository", func(t *testing.T) {
		repoNWO := testRepoNWO(t)
		user := testUser()
		repository := testRepository(repoNWO, true)

		memoryStore := &MockMemoryStore{
			CountByRepositoryFunc: func(repoID core.RepositoryID) (int, error) {
				t.Error("CountByRepository should not be called for disallowed repository")
				return 0, nil
			},
		}

		svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

		count, err := svc.CountMemories(t.Context(), user, repository)
		require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
		assert.Equal(t, 0, count)
	})

	t.Run("store error", func(t *testing.T) {
		repoNWO := testRepoNWO(t)
		user := testUser()
		repository := testRepository(repoNWO, true)
		storeErr := errors.New("database connection failed")

		memoryStore := &MockMemoryStore{
			CountByRepositoryFunc: func(repoID core.RepositoryID) (int, error) {
				return 0, storeErr
			},
		}

		svc := newTestMemoryService(t, memoryStore)

		count, err := svc.CountMemories(t.Context(), user, repository)
		require.ErrorIs(t, err, storeErr)
		assert.Equal(t, 0, count)
	})
}
