package memory

import (
	"context"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/stretchr/testify/require"
)

func TestJobETag(t *testing.T) {
	ctx := context.Background()

	t.Run("MemoryStore creates job ETag", func(t *testing.T) {
		store := NewStore()
		job := &jobs.Job{
			ID:        "job-id",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		require.NotEmpty(t, job.ETag, "ETag should be automatically generated")

		// Verify the hash was stored
		retrievedJob, err := store.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.NotEmpty(t, retrievedJob.ETag, "ETag should be stored")
	})

	t.Run("MemoryStore creates assignment ETag", func(t *testing.T) {
		store := NewStore()

		assignment := &jobs.Assignment{
			ID:        "assignment-id-3",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)
		require.NotEmpty(t, assignment.ETag, "ETag should be automatically generated")
	})

	t.Run("MemoryStore creates job ETag", func(t *testing.T) {
		store := NewStore()

		job := &jobs.Job{
			ID:        "job-id-2",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		require.NotEmpty(t, job.ETag, "ETag should be automatically generated")
	})

	t.Run("MemoryStore updates assignment ETag on patch", func(t *testing.T) {
		store := NewStore()

		assignment := &jobs.Assignment{
			ID:        "assignment-id-3",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)
		require.NotEmpty(t, assignment.ETag, "ETag should be automatically generated on creation")

		etag := assignment.ETag
		require.NotEmpty(t, etag, "ETag should be generated on creation")

		prNumber := 8
		err = store.PatchAssignment(ctx, assignment, db.AssignmentPatch{PullRequestNumber: &prNumber})
		require.NoError(t, err)

		require.False(t, assignment.ETag.Equals(*etag), "ETag should change after patching assignment")
	})

	t.Run("MemoryStore updates job ETag on patch", func(t *testing.T) {
		store := NewStore()

		job := &jobs.Job{
			ID:        "job-id-3",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		require.NotEmpty(t, job.ETag, "ETag should be automatically generated on creation")

		etag := job.ETag
		require.NotEmpty(t, etag, "ETag should be generated on creation")

		newStatus := jobs.JobStatusCompleted
		err = store.PatchJob(ctx, job, db.JobPatch{Status: &newStatus})
		require.NoError(t, err)

		require.False(t, job.ETag.Equals(*etag), "ETag should change after patching job")
	})

	t.Run("MemoryStore updates assignment ETag on update", func(t *testing.T) {
		store := NewStore()

		assignment := &jobs.Assignment{
			ID:        "assignment-id-4",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		assignment, err := store.CreateAssignment(ctx, assignment)
		require.NoError(t, err)
		require.NotEmpty(t, assignment.ETag, "ETag should be automatically generated on creation")

		etag := assignment.ETag
		require.NotEmpty(t, etag, "ETag should be generated on creation")

		assignment.PullRequestNumber = 8
		assignment, err = store.UpdateAssignment(ctx, assignment)
		require.NoError(t, err)

		require.False(t, assignment.ETag.Equals(*etag), "ETag should change after patching assignment")
	})

	t.Run("MemoryStore updates job ETag on update", func(t *testing.T) {
		store := NewStore()

		job := &jobs.Job{
			ID:        "job-id-4",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
		}

		job, err := store.CreateJob(ctx, job)
		require.NoError(t, err)
		require.NotEmpty(t, job.ETag, "ETag should be automatically generated on creation")

		etag := job.ETag
		require.NotEmpty(t, etag, "ETag should be generated on creation")

		job.Status = jobs.JobStatusCompleted
		job, err = store.UpdateJob(ctx, job)
		require.NoError(t, err)

		require.False(t, job.ETag.Equals(*etag), "ETag should change after patching job")
	})
}

func TestCommandETag(t *testing.T) {
	ctx := context.Background()

	t.Run("MemoryStore creates command ETag", func(t *testing.T) {
		store := NewStore()

		cmd := &command.Command{
			ID:           "command-id-1",
			AssignmentID: "assignment-id-1",
			JobID:        "job-id-1",
			OwnerID:      1,
			RepoID:       2,
			SessionID:    "session-1",
			ExternalID:   "ext-cmd-1",
			ActorID:      100,
			Content:      "do something",
			Status:       command.StatusPending,
		}

		cmd, err := store.CreateCommand(ctx, cmd)
		require.NoError(t, err)
		require.NotEmpty(t, cmd.ETag, "ETag should be automatically generated")
	})

	t.Run("MemoryStore updates command ETag on patch", func(t *testing.T) {
		store := NewStore()
		cmd := &command.Command{
			ID:           "command-id-2",
			AssignmentID: "assignment-id-2",
			JobID:        "job-id-2",
			OwnerID:      1,
			RepoID:       2,
			SessionID:    "session-2",
			ExternalID:   "ext-cmd-2",
			ActorID:      101,
			Content:      "do something else",
			Status:       command.StatusPending,
		}
		cmd, err := store.CreateCommand(ctx, cmd)
		require.NoError(t, err)
		require.NotEmpty(t, cmd.ETag)
		oldETag := cmd.ETag

		newStatus := command.StatusDelivered
		deliveredAt := time.Now().Unix()
		err = store.PatchCommand(ctx, cmd, db.CommandPatch{Status: &newStatus, DeliveredAt: &deliveredAt})
		require.NoError(t, err)
		require.False(t, cmd.ETag.Equals(*oldETag), "ETag should change after patching command")
		require.Equal(t, newStatus, cmd.Status)
		require.Equal(t, deliveredAt, cmd.DeliveredAt)
	})

	t.Run("MemoryStore updates command ETag on update", func(t *testing.T) {
		store := NewStore()
		cmd := &command.Command{
			ID:           "command-id-3",
			AssignmentID: "assignment-id-3",
			JobID:        "job-id-3",
			OwnerID:      1,
			RepoID:       2,
			SessionID:    "session-3",
			ExternalID:   "ext-cmd-3",
			ActorID:      102,
			Content:      "original content",
			Status:       command.StatusPending,
		}
		cmd, err := store.CreateCommand(ctx, cmd)
		require.NoError(t, err)
		require.NotEmpty(t, cmd.ETag)
		oldETag := cmd.ETag

		// mutate some fields
		cmd.Content = "updated content"
		cmd.Status = command.StatusDelivered
		cmd.DeliveredAt = time.Now().Unix()

		cmd, err = store.UpdateCommand(ctx, cmd)
		require.NoError(t, err)
		require.False(t, cmd.ETag.Equals(*oldETag), "ETag should change after updating command")
		require.Equal(t, command.StatusDelivered, cmd.Status)
		require.Equal(t, "updated content", cmd.Content)
	})
}

func TestMemoryStore_ListJobsForPullRequestNumber(t *testing.T) {
	ctx := context.Background()
	store := NewStore()

	// Create some test jobs
	job1 := &jobs.Job{
		ID:                "job-1",
		OwnerID:           1,
		RepoID:            2,
		RepoOwner:         "owner",
		RepoName:          "repo",
		PullRequestNumber: 123,
	}

	job2 := &jobs.Job{
		ID:                "job-2",
		OwnerID:           1,
		RepoID:            2,
		RepoOwner:         "owner",
		RepoName:          "repo",
		PullRequestNumber: 456,
	}

	job3 := &jobs.Job{
		ID:                "job-3",
		OwnerID:           1,
		RepoID:            2,
		RepoOwner:         "owner",
		RepoName:          "repo",
		PullRequestNumber: 123, // Same as job1
	}

	// Different repo
	job4 := &jobs.Job{
		ID:                "job-4",
		OwnerID:           1,
		RepoID:            3,
		RepoOwner:         "owner",
		RepoName:          "other-repo",
		PullRequestNumber: 123,
	}

	// Create all jobs
	_, err := store.CreateJob(ctx, job1)
	require.NoError(t, err)
	_, err = store.CreateJob(ctx, job2)
	require.NoError(t, err)
	_, err = store.CreateJob(ctx, job3)
	require.NoError(t, err)
	_, err = store.CreateJob(ctx, job4)
	require.NoError(t, err)

	// Test getting jobs for PR 123 in repo 2
	jobs, err := store.ListJobsForPullRequestNumber(ctx, 1, 2, 123)
	require.NoError(t, err)
	require.Len(t, jobs, 2, "Should find 2 jobs for PR 123 in repo 2")

	// Verify the correct jobs are returned
	jobIDs := make([]string, len(jobs))
	for i, job := range jobs {
		jobIDs[i] = job.ID
	}
	require.Contains(t, jobIDs, "job-1")
	require.Contains(t, jobIDs, "job-3")

	// Test getting jobs for PR 456
	jobs, err = store.ListJobsForPullRequestNumber(ctx, 1, 2, 456)
	require.NoError(t, err)
	require.Len(t, jobs, 1, "Should find 1 job for PR 456")
	require.Equal(t, "job-2", jobs[0].ID)

	// Test getting jobs for non-existent PR
	jobs, err = store.ListJobsForPullRequestNumber(ctx, 1, 2, 999)
	require.NoError(t, err)
	require.Len(t, jobs, 0, "Should find no jobs for non-existent PR")

	// Test getting jobs for PR 123 in different repo
	jobs, err = store.ListJobsForPullRequestNumber(ctx, 1, 3, 123)
	require.NoError(t, err)
	require.Len(t, jobs, 1, "Should find 1 job for PR 123 in repo 3")
	require.Equal(t, "job-4", jobs[0].ID)
}

func TestMemoryStore_BatchPatchCommands(t *testing.T) {
	ctx := context.Background()

	t.Run("successfully patches multiple commands", func(t *testing.T) {
		store := NewStore()

		// seed commands
		c1, err := store.CreateCommand(ctx, &command.Command{ID: "cmd-1", AssignmentID: "a-1", JobID: "j-1", OwnerID: 1, RepoID: 2})
		require.NoError(t, err)
		c2, err := store.CreateCommand(ctx, &command.Command{ID: "cmd-2", AssignmentID: "a-1", JobID: "j-1", OwnerID: 1, RepoID: 2})
		require.NoError(t, err)

		oldETag1 := c1.ETag
		oldETag2 := c2.ETag

		newStatus := command.StatusDelivered
		now := time.Now().Unix()
		patch := db.CommandPatch{Status: &newStatus, DeliveredAt: &now}
		err = store.BatchPatchCommands(ctx, []*command.Command{c1, c2}, patch)
		require.NoError(t, err)

		require.Equal(t, newStatus, c1.Status)
		require.Equal(t, newStatus, c2.Status)
		require.NotNil(t, c1.ETag)
		require.NotNil(t, c2.ETag)
		require.False(t, c1.ETag.Equals(*oldETag1), "ETag for c1 should change")
		require.False(t, c2.ETag.Equals(*oldETag2), "ETag for c2 should change")
	})

	t.Run("mismatch assignment/job returns error", func(t *testing.T) {
		store := NewStore()
		c1, err := store.CreateCommand(ctx, &command.Command{ID: "cmd-1", AssignmentID: "a-1", JobID: "j-1", OwnerID: 1, RepoID: 2})
		require.NoError(t, err)
		c2, err := store.CreateCommand(ctx, &command.Command{ID: "cmd-2", AssignmentID: "a-2", JobID: "j-1", OwnerID: 1, RepoID: 2})
		require.NoError(t, err)

		err = store.BatchPatchCommands(ctx, []*command.Command{c1, c2}, db.CommandPatch{})
		require.Error(t, err)
		require.ErrorIs(t, err, db.ErrBatchPartitionKeysMismatch)
	})

	t.Run("partial failure returns aggregated error and leaves conflicting command ETag unchanged", func(t *testing.T) {
		store := NewStore()
		c1, err := store.CreateCommand(ctx, &command.Command{ID: "cmd-1", AssignmentID: "a-1", JobID: "j-1", OwnerID: 1, RepoID: 2})
		require.NoError(t, err)
		c2, err := store.CreateCommand(ctx, &command.Command{ID: "cmd-2", AssignmentID: "a-1", JobID: "j-1", OwnerID: 1, RepoID: 2})
		require.NoError(t, err)

		// Simulate stale ETag on c2 by mutating underlying stored command directly via another patch
		newStatus := command.StatusDelivered
		err = store.PatchCommand(ctx, c2, db.CommandPatch{Status: &newStatus})
		require.NoError(t, err)

		// Create a stale copy of c2 with an outdated ETag to simulate client sending stale data
		staleC2 := *c2 // shallow copy of struct
		outdated := azcore.ETag("\"outdated-etag\"")
		staleC2.ETag = &outdated

		patchStatus := command.StatusIgnored
		patch := db.CommandPatch{Status: &patchStatus}
		err = store.BatchPatchCommands(ctx, []*command.Command{c1, &staleC2}, patch)
		require.Error(t, err)
		require.ErrorIs(t, err, db.ErrBatchOperationFailed)
		require.Contains(t, err.Error(), "failed to patch command")

		// c1 should have been updated
		require.Equal(t, patchStatus, c1.Status)
		// c2 should not have new status because conflict prevented update
		require.NotEqual(t, patchStatus, c2.Status, "conflicting command should not be updated")
	})
}

func TestMemoryStore_GetJobForSessionID(t *testing.T) {
	store := NewStore()
	ctx := context.Background()

	// Create a job
	job := &jobs.Job{
		ID:        "test-job",
		SessionID: "test-session",
		OwnerID:   1,
		RepoID:    2,
	}

	_, err := store.CreateJob(ctx, job)
	require.NoError(t, err)

	t.Run("returns job when session exists", func(t *testing.T) {
		foundJob, err := store.GetJobForSessionID(ctx, 1, 2, "test-session")
		require.NoError(t, err)
		require.NotNil(t, foundJob)
		require.Equal(t, "test-job", foundJob.ID)
		require.Equal(t, "test-session", foundJob.SessionID)
	})

	t.Run("returns nil when session ID doesn't exist", func(t *testing.T) {
		foundJob, err := store.GetJobForSessionID(ctx, 1, 2, "non-existent")
		require.NoError(t, err)
		require.Nil(t, foundJob)
	})

	t.Run("returns nil when owner doesn't exist", func(t *testing.T) {
		foundJob, err := store.GetJobForSessionID(ctx, 999, 2, "test-session")
		require.NoError(t, err)
		require.Nil(t, foundJob)
	})

	t.Run("returns nil when repo doesn't exist", func(t *testing.T) {
		foundJob, err := store.GetJobForSessionID(ctx, 1, 999, "test-session")
		require.NoError(t, err)
		require.Nil(t, foundJob)
	})
}
