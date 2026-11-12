package standardevents

import (
	"context"
	"testing"
	"time"

	"github.com/github/feature-management-client-go/githubexp"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/customagent"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestJobLifecyclePipelineGenerator_GenerateJobStartedStandardEvent(t *testing.T) {
	gen := &JobLifecycleStandardEventGenerator{}

	t.Run("basic job started event", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			PullRequestID:            42,
			ActorAnalyticsTrackingID: "tracking-id-123",
			SessionID:                "session-abc",
			Model:                    "gpt-4",
			IsAutoMode:               true,
			CreatedAt:                1710000000,
			EventType:                jobs.EventTypeIssueAssignment,
			Action:                   jobs.AgentActionFix,
			Experiments: &experiments.AssignmentExperiments{
				AssignmentContext: "exp-ctx-abc",
			},
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "copilot_coding_agent_job_started", event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "tracking-id-123", event.PrimaryEntityId)
		assert.Equal(t, "copilot_tracking_id", event.PrimaryEntityIdType)
		assert.Nil(t, event.ActivityCorrelationId)
		assert.Equal(t, "owner-repo-uuid", event.SessionId.GetValue())
		assert.Equal(t, "", event.PrimaryAssignmentContext)
		assert.Equal(t, "42", event.SecondaryEntityId.GetValue())
		assert.Equal(t, "github_pull_request_id", event.SecondaryEntityIdType.GetValue())
		assert.Equal(t, "exp-ctx-abc", event.SecondaryAssignmentContext.GetValue())
		assert.Equal(t, time.Unix(1710000000, 0).UTC(), event.OccurredAt.AsTime())
		assert.True(t, event.Conditions["is_auto_mode"])
		assert.False(t, event.Conditions["is_automation"])
		assert.False(t, event.Conditions["is_custom_agent"])
		assert.False(t, event.Conditions["custom_setup_steps_used"])
		assert.Equal(t, "gpt-4", event.Metadata["model"])
		assert.Equal(t, "issue_assignment", event.Metadata["event_type"])
		assert.Equal(t, "fix", event.Metadata["action"])
		assert.Equal(t, "session-abc", event.Metadata["session_id"])
		_, hasCustomAgent := event.Metadata["custom_agent_name"]
		assert.False(t, hasCustomAgent)
	})

	t.Run("job without experiments", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "", event.PrimaryAssignmentContext)
		assert.Nil(t, event.SecondaryAssignmentContext)
		assert.Equal(t, "owner-repo-uuid", event.SessionId.GetValue())
	})

	t.Run("job without pull request", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			PullRequestID:            0,
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Nil(t, event.SecondaryEntityId)
		assert.Nil(t, event.SecondaryEntityIdType)
	})

	t.Run("is_auto_mode false", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			IsAutoMode:               false,
			CreatedAt:                1710000000,
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.False(t, event.Conditions["is_auto_mode"])
	})

	t.Run("custom agent job", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
			CustomSetupStepsUsed:     true,
			CustomAgent: customagent.DBRecord{
				Name: "my-agent",
			},
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.False(t, event.Conditions["is_automation"])
		assert.True(t, event.Conditions["is_custom_agent"])
		assert.True(t, event.Conditions["custom_setup_steps_used"])
		assert.Equal(t, "my-agent", event.Metadata["custom_agent_name"])
	})

	t.Run("compute metadata for Actions job", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
			ComputeID:                "12345",
			Launcher:                 "actions",
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "12345", event.Metadata["compute_id"])
		assert.Equal(t, "actions", event.Metadata["compute_type"])
		assert.Equal(t, "12345", event.Metadata["workflow_run_id"])
	})

	t.Run("compute metadata for sandbox job", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
			ComputeID:                "sb-abc-123",
			Launcher:                 "sandbox",
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "sb-abc-123", event.Metadata["compute_id"])
		assert.Equal(t, "sandbox", event.Metadata["compute_type"])
		_, hasWorkflowRunID := event.Metadata["workflow_run_id"]
		assert.False(t, hasWorkflowRunID)
	})

	t.Run("triggered custom agent job is marked as automation", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
			IsTriggered:              true,
			CustomAgent: customagent.DBRecord{
				Name: "automation-agent",
			},
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.True(t, event.Conditions["is_automation"])
		assert.True(t, event.Conditions["is_custom_agent"])
		assert.Equal(t, "automation-agent", event.Metadata["custom_agent_name"])
	})

	t.Run("with SDK assignment context from context", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			StartedAt:                1710000000,
		}

		// Create context with SDK assignment
		sdkAssignment := githubexp.NewAssignmentResult(nil, "sdk-assignment-ctx", 0)
		ctx := exp.WithAssignment(context.Background(), sdkAssignment)

		event := gen.GenerateJobStartedStandardEvent(ctx, job)

		require.NotNil(t, event)
		assert.Equal(t, "sdk-assignment-ctx", event.PrimaryAssignmentContext)
	})

	t.Run("job-cached SDKAssignmentContext takes precedence over context", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			StartedAt:                1710000000,
			SDKAssignmentContext:     "job-cached-ctx",
		}

		// Also set a different value in context — the job-cached value should win
		sdkAssignment := githubexp.NewAssignmentResult(nil, "context-based-ctx", 0)
		ctx := exp.WithAssignment(context.Background(), sdkAssignment)

		event := gen.GenerateJobStartedStandardEvent(ctx, job)

		require.NotNil(t, event)
		assert.Equal(t, "job-cached-ctx", event.PrimaryAssignmentContext)
	})

	t.Run("SDKAssignmentContext without context fallback", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			StartedAt:                1710000000,
			SDKAssignmentContext:     "job-only-ctx",
		}

		event := gen.GenerateJobStartedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "job-only-ctx", event.PrimaryAssignmentContext)
	})
}

func TestJobLifecyclePipelineGenerator_GenerateJobCompletedStandardEvent(t *testing.T) {
	gen := &JobLifecycleStandardEventGenerator{}

	t.Run("basic job completed event", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			PullRequestID:            42,
			ActorAnalyticsTrackingID: "tracking-id-123",
			SessionID:                "session-abc",
			Model:                    "gpt-4",
			IsAutoMode:               true,
			CreatedAt:                1710000000,
			CompletedAt:              1710000300,
			Status:                   jobs.JobStatusCompleted,
			EventType:                jobs.EventTypeIssueAssignment,
			Action:                   jobs.AgentActionFix,
			Experiments: &experiments.AssignmentExperiments{
				AssignmentContext: "exp-ctx-abc",
			},
		}

		event := gen.GenerateJobCompletedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "copilot_coding_agent_job_completed", event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "tracking-id-123", event.PrimaryEntityId)
		assert.Equal(t, "copilot_tracking_id", event.PrimaryEntityIdType)
		assert.Nil(t, event.ActivityCorrelationId)
		assert.Equal(t, "owner-repo-uuid", event.SessionId.GetValue())
		assert.Equal(t, "", event.PrimaryAssignmentContext)
		assert.Equal(t, "42", event.SecondaryEntityId.GetValue())
		assert.Equal(t, "github_pull_request_id", event.SecondaryEntityIdType.GetValue())
		assert.Equal(t, "exp-ctx-abc", event.SecondaryAssignmentContext.GetValue())
		assert.Equal(t, time.Unix(1710000300, 0).UTC(), event.OccurredAt.AsTime())
		assert.InDelta(t, float64(300), event.Measurements["duration_sec"], 0)
		assert.True(t, event.Conditions["is_auto_mode"])
		assert.False(t, event.Conditions["is_automation"])
		assert.False(t, event.Conditions["is_custom_agent"])
		assert.False(t, event.Conditions["custom_setup_steps_used"])
		assert.Equal(t, "gpt-4", event.Metadata["model"])
		assert.Equal(t, "issue_assignment", event.Metadata["event_type"])
		assert.Equal(t, "fix", event.Metadata["action"])
		assert.Equal(t, "completed", event.Metadata["terminal_state"])
		_, hasTerminalReason := event.Metadata["terminal_reason"]
		assert.False(t, hasTerminalReason)
	})

	t.Run("job completed with error", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
			CompletedAt:              1710000100,
			Status:                   jobs.JobStatusFailed,
			Error: &jobs.JobError{
				Message:            "something went wrong",
				Service:            "capi",
				ResponseStatusCode: "429",
			},
		}

		event := gen.GenerateJobCompletedStandardEvent(context.Background(), job)

		require.NotNil(t, event)
		assert.Equal(t, "failed", event.Metadata["terminal_state"])
		assert.NotEmpty(t, event.Metadata["terminal_reason"])
	})

	t.Run("deduplication IDs are unique", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
			CreatedAt:                1710000000,
			CompletedAt:              1710000300,
		}

		event1 := gen.GenerateJobCompletedStandardEvent(context.Background(), job)
		event2 := gen.GenerateJobCompletedStandardEvent(context.Background(), job)

		assert.NotEqual(t, event1.DeduplicationId, event2.DeduplicationId)
	})
}
