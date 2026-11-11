package core_test

import (
	"errors"
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
			memoryStore := &MockMemoryStore{
				DeleteForRepositoryFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
					deleteCalled = true
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Equal(t, memoryID, id)
					return nil
				},
			}

			svc := newTestMemoryService(t, memoryStore)
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

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			deleteAllCalled := false
			memoryStore := &MockMemoryStore{
				DeleteAllForRepositoryFunc: func(repoID core.RepositoryID) error {
					deleteAllCalled = true
					assert.Equal(t, core.RepositoryID(1), repoID)
					return nil
				},
			}

			svc := newTestMemoryService(t, memoryStore)
			repository := testRepository(repoNWO, private)

			err := svc.DeleteAllMemories(t.Context(), user, repository)
			require.NoError(t, err)
			assert.True(t, deleteAllCalled, "expected DeleteAll to be called on repository")
		})
	}
}

func TestDeleteMemoryDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryID := testMemoryID()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		DeleteForRepositoryFunc: func(repoID core.RepositoryID, id core.MemoryID) error {
			t.Error("Delete should not be called for disallowed repository")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

	err := svc.DeleteMemory(t.Context(), user, repository, memoryID)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestDeleteAllMemoriesRepositoryError(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()

	errSentinel := errors.New("repository delete failed")
	memoryStore := &MockMemoryStore{
		DeleteAllForRepositoryFunc: func(repoID core.RepositoryID) error {
			return errSentinel
		},
	}

	svc := newTestMemoryService(t, memoryStore)
	repository := testRepository(repoNWO, true)

	err := svc.DeleteAllMemories(t.Context(), user, repository)
	require.Error(t, err)
	assert.ErrorIs(t, err, errSentinel, "expected the repository error to be wrapped and returned")
}

func TestDeleteAllMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		DeleteAllForRepositoryFunc: func(repoID core.RepositoryID) error {
			t.Error("DeleteAll should not be called for disallowed repository")
			return nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

	err := svc.DeleteAllMemories(t.Context(), user, repository)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestDeleteMemoriesSuccess(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1"), core.MemoryID("mem-2"), core.MemoryID("mem-3")}

	for _, private := range []bool{true, false} {
		name := "public"
		if private {
			name = "private"
		}
		t.Run(name, func(t *testing.T) {
			deleteBatchCalled := false
			memoryStore := &MockMemoryStore{
				DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
					deleteBatchCalled = true
					assert.Equal(t, core.RepositoryID(1), repoID)
					assert.Equal(t, memoryIDs, ids)
					return &core.BatchDeleteResult{Deleted: ids}, nil
				},
			}

			svc := newTestMemoryService(t, memoryStore)
			repository := testRepository(repoNWO, private)

			result, err := svc.DeleteMemories(t.Context(), user, repository, memoryIDs)
			require.NoError(t, err)
			assert.True(t, deleteBatchCalled, "expected DeleteBatch to be called on repository")
			assert.Equal(t, memoryIDs, result.Deleted)
			assert.Empty(t, result.Failed)
		})
	}
}

func TestDeleteMemoriesDisallowedRepository(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1"), core.MemoryID("mem-2")}
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			t.Error("DeleteBatch should not be called for disallowed repository")
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore, withDisallowedRepo())

	_, err := svc.DeleteMemories(t.Context(), user, repository, memoryIDs)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error for disallowed repository")
}

func TestDeleteMemoriesNilRepository(t *testing.T) {
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1")}

	memoryStore := &MockMemoryStore{
		DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			t.Error("DeleteBatch should not be called when repository is nil")
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	result, err := svc.DeleteMemories(t.Context(), user, nil, memoryIDs)
	require.ErrorIs(t, err, core.ErrRepositoryNotFound, "expected repository not found error for nil repository")
	assert.Nil(t, result)
}

func TestDeleteMemoriesFeatureNotEnabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1")}
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			t.Error("DeleteBatch should not be called when feature is not enabled")
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withEnablementChecker(&MockMemoryEnablementChecker{Enabled: false}))

	result, err := svc.DeleteMemories(t.Context(), user, repository, memoryIDs)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when enablement check returns false")
	assert.Nil(t, result)
}

func TestDeleteMemoriesFeatureFlagDisabled(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1")}
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			t.Error("DeleteBatch should not be called when feature flag is disabled")
			return &core.BatchDeleteResult{Deleted: ids}, nil
		},
	}

	svc := newTestMemoryService(t, memoryStore,
		withFeatureFlags(nil)) // nil flags = feature disabled

	result, err := svc.DeleteMemories(t.Context(), user, repository, memoryIDs)
	require.ErrorIs(t, err, core.ErrFeatureNotEnabled, "expected feature not enabled error when feature flag is disabled")
	assert.Nil(t, result)
}

func TestDeleteMemoriesRepositoryError(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1"), core.MemoryID("mem-2")}
	repository := testRepository(repoNWO, true)

	errSentinel := errors.New("batch delete failed")
	memoryStore := &MockMemoryStore{
		DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return nil, errSentinel
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	result, err := svc.DeleteMemories(t.Context(), user, repository, memoryIDs)
	require.ErrorIs(t, err, errSentinel, "expected the repository error to be wrapped and returned")
	assert.Nil(t, result)
}

func TestDeleteMemoriesPartialFailure(t *testing.T) {
	repoNWO := testRepoNWO(t)
	user := testUser()
	memoryIDs := []core.MemoryID{core.MemoryID("mem-1"), core.MemoryID("mem-2"), core.MemoryID("mem-3")}
	repository := testRepository(repoNWO, true)

	memoryStore := &MockMemoryStore{
		DeleteBatchForRepoFunc: func(repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
			return &core.BatchDeleteResult{
				Deleted: []core.MemoryID{core.MemoryID("mem-1")},
				Failed:  []core.MemoryID{core.MemoryID("mem-2"), core.MemoryID("mem-3")},
			}, errors.New("partial batch failure")
		},
	}

	svc := newTestMemoryService(t, memoryStore)

	result, err := svc.DeleteMemories(t.Context(), user, repository, memoryIDs)
	require.Error(t, err, "expected error on partial failure")
	require.NotNil(t, result, "expected non-nil result on partial failure")
	assert.Equal(t, []core.MemoryID{core.MemoryID("mem-1")}, result.Deleted)
	assert.Equal(t, []core.MemoryID{core.MemoryID("mem-2"), core.MemoryID("mem-3")}, result.Failed)
}
