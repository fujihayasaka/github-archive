package memory

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/jobs/progress"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/stretchr/testify/require"
)

func TestProgressETag(t *testing.T) {
	ctx := context.Background()

	t.Run("MemoryStore creates progress ETag", func(t *testing.T) {
		store := NewStore()
		p := &progress.Progress{
			ID:           "progress-id",
			AssignmentID: "assignment-id",
			JobID:        "job-id",
			Namespace:    "test",
			Kind:         "log",
			Content:      map[string]any{"message": "test"},
		}

		p, err := store.CreateProgress(ctx, p)
		require.NoError(t, err)
		require.NotEmpty(t, p.ETag, "ETag should be automatically generated")

		// Verify the etag was stored
		retrievedProgress, err := store.GetProgress(ctx, p.AssignmentID, p.JobID, p.ID)
		require.NoError(t, err)
		require.NotEmpty(t, retrievedProgress.ETag, "ETag should be stored")
	})

	t.Run("MemoryStore updates progress ETag on update", func(t *testing.T) {
		store := NewStore()

		p := &progress.Progress{
			ID:           "progress-id-2",
			AssignmentID: "assignment-id",
			JobID:        "job-id",
			Namespace:    "test",
			Kind:         "status",
			Content:      map[string]any{"status": "running"},
		}

		p, err := store.CreateProgress(ctx, p)
		require.NoError(t, err)
		require.NotEmpty(t, p.ETag, "ETag should be automatically generated on creation")

		etag := p.ETag
		require.NotEmpty(t, etag, "ETag should be generated on creation")

		// mutate some fields
		p.Content = map[string]any{"status": "completed"}
		p, err = store.UpdateProgress(ctx, p)
		require.NoError(t, err)

		require.False(t, p.ETag.Equals(*etag), "ETag should change after updating progress")
	})

	t.Run("MemoryStore returns error on update with stale ETag", func(t *testing.T) {
		store := NewStore()

		p := &progress.Progress{
			ID:           "progress-id-3",
			AssignmentID: "assignment-id",
			JobID:        "job-id",
			Namespace:    "test",
			Kind:         "error",
			Content:      map[string]any{"error": "something went wrong"},
		}

		p, err := store.CreateProgress(ctx, p)
		require.NoError(t, err)

		originalETag := p.ETag

		// Simulate another update
		p.Content = map[string]any{"error": "updated error"}
		_, err = store.UpdateProgress(ctx, p)
		require.NoError(t, err)

		// Try to update with stale ETag
		staleProgress := &progress.Progress{
			ID:           p.ID,
			AssignmentID: p.AssignmentID,
			JobID:        p.JobID,
			ETag:         originalETag,
			Content:      map[string]any{"error": "another update"},
		}

		_, err = store.UpdateProgress(ctx, staleProgress)
		require.Error(t, err)
		require.ErrorIs(t, err, db.ErrPreconditionFailedOnUpdate)
	})
}

func TestMemoryStore_BatchCreateProgress(t *testing.T) {
	ctx := context.Background()

	t.Run("successfully creates multiple progress updates", func(t *testing.T) {
		store := NewStore()

		// seed progress updates
		progresses := []*progress.Progress{
			{ID: "p-1", AssignmentID: "a-1", JobID: "j-1", Namespace: "test", Kind: "log"},
			{ID: "p-2", AssignmentID: "a-1", JobID: "j-1", Namespace: "test", Kind: "status"},
			{ID: "p-3", AssignmentID: "a-1", JobID: "j-1", Namespace: "test", Kind: "error"},
		}

		result, err := store.BatchCreateProgress(ctx, progresses)
		require.NoError(t, err)
		require.Len(t, result, 3)

		// Verify all were created with ETags
		for _, p := range result {
			require.NotEmpty(t, p.ETag)
			retrieved, err := store.GetProgress(ctx, p.AssignmentID, p.JobID, p.ID)
			require.NoError(t, err)
			require.Equal(t, p.ID, retrieved.ID)
		}
	})

	t.Run("mismatch assignment/job returns error", func(t *testing.T) {
		store := NewStore()
		progresses := []*progress.Progress{
			{ID: "p-1", AssignmentID: "a-1", JobID: "j-1"},
			{ID: "p-2", AssignmentID: "a-2", JobID: "j-1"}, // different assignment
		}

		_, err := store.BatchCreateProgress(ctx, progresses)
		require.Error(t, err)
		require.ErrorIs(t, err, db.ErrBatchPartitionKeysMismatch)
	})

	t.Run("empty slice is a noop", func(t *testing.T) {
		store := NewStore()

		result, err := store.BatchCreateProgress(ctx, []*progress.Progress{})
		require.NoError(t, err)
		require.Empty(t, result)
	})
}

func TestMemoryStore_ListProgress(t *testing.T) {
	store := NewStore()
	ctx := context.Background()

	// Create some test progress updates
	p1 := &progress.Progress{
		ID:           "p-1",
		AssignmentID: "a-1",
		JobID:        "j-1",
		Namespace:    "test",
		Kind:         "log",
		Content:      map[string]any{"message": "log 1"},
	}

	p2 := &progress.Progress{
		ID:           "p-2",
		AssignmentID: "a-1",
		JobID:        "j-1",
		Namespace:    "test",
		Kind:         "status",
		Content:      map[string]any{"status": "running"},
	}

	p3 := &progress.Progress{
		ID:           "p-3",
		AssignmentID: "a-1",
		JobID:        "j-2", // Different job
		Namespace:    "test",
		Kind:         "log",
		Content:      map[string]any{"message": "log 3"},
	}

	// Create all progress updates
	_, err := store.CreateProgress(ctx, p1)
	require.NoError(t, err)
	_, err = store.CreateProgress(ctx, p2)
	require.NoError(t, err)
	_, err = store.CreateProgress(ctx, p3)
	require.NoError(t, err)

	t.Run("lists all progress for assignment and job", func(t *testing.T) {
		progresses, err := store.ListProgress(ctx, "a-1", "j-1")
		require.NoError(t, err)
		require.Len(t, progresses, 2, "Should find 2 progress updates for job j-1")

		// Verify the correct progress updates are returned
		progressIDs := make([]string, len(progresses))
		for i, p := range progresses {
			progressIDs[i] = p.ID
		}
		require.Contains(t, progressIDs, "p-1")
		require.Contains(t, progressIDs, "p-2")
	})

	t.Run("lists progress for different job", func(t *testing.T) {
		progresses, err := store.ListProgress(ctx, "a-1", "j-2")
		require.NoError(t, err)
		require.Len(t, progresses, 1, "Should find 1 progress update for job j-2")
		require.Equal(t, "p-3", progresses[0].ID)
	})

	t.Run("returns empty for non-existent job", func(t *testing.T) {
		progresses, err := store.ListProgress(ctx, "a-1", "j-999")
		require.NoError(t, err)
		require.Len(t, progresses, 0, "Should find no progress updates for non-existent job")
	})
}

func TestMemoryStore_ListProgressByNamespace(t *testing.T) {
	store := NewStore()
	ctx := context.Background()

	// Create test progress updates with different namespaces
	progresses := []*progress.Progress{
		{ID: "p-1", AssignmentID: "a-1", JobID: "j-1", Namespace: "logs", Kind: "info"},
		{ID: "p-2", AssignmentID: "a-1", JobID: "j-1", Namespace: "logs", Kind: "error"},
		{ID: "p-3", AssignmentID: "a-1", JobID: "j-1", Namespace: "status", Kind: "update"},
		{ID: "p-4", AssignmentID: "a-1", JobID: "j-1", Namespace: "logs", Kind: "debug"},
	}

	for _, p := range progresses {
		_, err := store.CreateProgress(ctx, p)
		require.NoError(t, err)
	}

	t.Run("lists progress by namespace", func(t *testing.T) {
		result, err := store.ListProgressByNamespace(ctx, "a-1", "j-1", []string{"logs"})
		require.NoError(t, err)
		require.Len(t, result, 3, "Should find 3 progress updates in 'logs' namespace")

		for _, p := range result {
			require.Equal(t, "logs", p.Namespace)
		}
	})

	t.Run("lists progress for different namespace", func(t *testing.T) {
		result, err := store.ListProgressByNamespace(ctx, "a-1", "j-1", []string{"status"})
		require.NoError(t, err)
		require.Len(t, result, 1, "Should find 1 progress update in 'status' namespace")
		require.Equal(t, "p-3", result[0].ID)
	})

	t.Run("returns empty for non-existent namespace", func(t *testing.T) {
		result, err := store.ListProgressByNamespace(ctx, "a-1", "j-1", []string{"nonexistent"})
		require.NoError(t, err)
		require.Len(t, result, 0, "Should find no progress updates for non-existent namespace")
	})
}

func TestMemoryStore_ListProgressByNamespaceAndKind(t *testing.T) {
	store := NewStore()
	ctx := context.Background()

	// Create test progress updates with different namespaces and kinds
	progresses := []*progress.Progress{
		{ID: "p-1", AssignmentID: "a-1", JobID: "j-1", Namespace: "logs", Kind: "info"},
		{ID: "p-2", AssignmentID: "a-1", JobID: "j-1", Namespace: "logs", Kind: "error"},
		{ID: "p-3", AssignmentID: "a-1", JobID: "j-1", Namespace: "logs", Kind: "info"},
		{ID: "p-4", AssignmentID: "a-1", JobID: "j-1", Namespace: "status", Kind: "info"},
	}

	for _, p := range progresses {
		_, err := store.CreateProgress(ctx, p)
		require.NoError(t, err)
	}

	t.Run("lists progress by namespace and kind", func(t *testing.T) {
		result, err := store.ListProgressByNamespaceAndKind(ctx, "a-1", "j-1", "logs", "info")
		require.NoError(t, err)
		require.Len(t, result, 2, "Should find 2 progress updates with namespace 'logs' and kind 'info'")

		for _, p := range result {
			require.Equal(t, "logs", p.Namespace)
			require.Equal(t, "info", p.Kind)
		}
	})

	t.Run("lists progress for different kind", func(t *testing.T) {
		result, err := store.ListProgressByNamespaceAndKind(ctx, "a-1", "j-1", "logs", "error")
		require.NoError(t, err)
		require.Len(t, result, 1, "Should find 1 progress update with namespace 'logs' and kind 'error'")
		require.Equal(t, "p-2", result[0].ID)
	})

	t.Run("returns empty for non-matching namespace and kind combination", func(t *testing.T) {
		result, err := store.ListProgressByNamespaceAndKind(ctx, "a-1", "j-1", "logs", "debug")
		require.NoError(t, err)
		require.Len(t, result, 0, "Should find no progress updates for non-matching combination")
	})
}

func TestMemoryStore_GetProgress(t *testing.T) {
	store := NewStore()
	ctx := context.Background()

	// Create a progress update
	p := &progress.Progress{
		ID:           "test-progress",
		AssignmentID: "test-assignment",
		JobID:        "test-job",
		Namespace:    "test",
		Kind:         "log",
		Content:      map[string]any{"message": "test message"},
	}

	_, err := store.CreateProgress(ctx, p)
	require.NoError(t, err)

	t.Run("returns progress when it exists", func(t *testing.T) {
		retrieved, err := store.GetProgress(ctx, "test-assignment", "test-job", "test-progress")
		require.NoError(t, err)
		require.NotNil(t, retrieved)
		require.Equal(t, "test-progress", retrieved.ID)
		require.Equal(t, "test-assignment", retrieved.AssignmentID)
		require.Equal(t, "test-job", retrieved.JobID)
	})

	t.Run("returns error when progress doesn't exist", func(t *testing.T) {
		_, err := store.GetProgress(ctx, "test-assignment", "test-job", "nonexistent")
		require.Error(t, err)
	})

	t.Run("returns error when assignment doesn't exist", func(t *testing.T) {
		_, err := store.GetProgress(ctx, "nonexistent", "test-job", "test-progress")
		require.Error(t, err)
	})

	t.Run("returns error when job doesn't exist", func(t *testing.T) {
		_, err := store.GetProgress(ctx, "test-assignment", "nonexistent", "test-progress")
		require.Error(t, err)
	})
}
