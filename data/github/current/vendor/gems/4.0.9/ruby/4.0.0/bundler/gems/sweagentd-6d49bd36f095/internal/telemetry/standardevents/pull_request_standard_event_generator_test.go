package standardevents

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/experiments"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPullRequestStandardEventGenerator_GeneratePullRequestStateChangedStandardEvent(t *testing.T) {
	gen := &PullRequestStandardEventGenerator{}

	t.Run("PR merged event", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			PullRequestID:            42,
			ActorAnalyticsTrackingID: "tracking-id-123",
			SessionID:                "session-abc",
			Model:                    "gpt-4",
			IsAutoMode:               true,
			RepoID:                   100,
			OwnerID:                  200,
			ActorID:                  300,
			AgentID:                  400,
			AssignmentID:             "assignment-xyz",
			ComputeID:                "compute-123",
			EventType:                jobs.EventTypeIssueAssignment,
			Action:                   jobs.AgentActionFix,
			Experiments: &experiments.AssignmentExperiments{
				AssignmentContext: "exp-ctx-abc",
			},
		}
		occurredAt := time.Unix(1710000000, 0)

		event := gen.GeneratePullRequestStateChangedStandardEvent(context.Background(), job, "merged", occurredAt)

		require.NotNil(t, event)
		assert.Equal(t, "copilot_coding_agent_pull_request_state_changed", event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "tracking-id-123", event.PrimaryEntityId)
		assert.Equal(t, "copilot_tracking_id", event.PrimaryEntityIdType)
		assert.Equal(t, "", event.PrimaryAssignmentContext)
		assert.Equal(t, "owner-repo-uuid", event.SessionId.GetValue())
		assert.Equal(t, "42", event.SecondaryEntityId.GetValue())
		assert.Equal(t, "github_pull_request_id", event.SecondaryEntityIdType.GetValue())
		assert.Equal(t, "exp-ctx-abc", event.SecondaryAssignmentContext.GetValue())
		assert.Equal(t, occurredAt.UTC(), event.OccurredAt.AsTime())
		assert.Equal(t, "merged", event.Metadata["pr_state"])
		assert.Equal(t, "gpt-4", event.Metadata["model"])
		assert.True(t, event.Conditions["is_auto_mode"])
		assert.False(t, event.Conditions["is_custom_agent"])
		assert.Equal(t, "issue_assignment", event.Metadata["event_type"])
		assert.Equal(t, "fix", event.Metadata["action"])
		assert.Equal(t, "session-abc", event.Metadata["session_id"])
		assert.Empty(t, event.Measurements)
	})

	t.Run("PR closed event", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			PullRequestID:            99,
			ActorAnalyticsTrackingID: "tracking-id-456",
			Model:                    "gpt-4o",
		}
		occurredAt := time.Unix(1710000500, 0)

		event := gen.GeneratePullRequestStateChangedStandardEvent(context.Background(), job, "closed", occurredAt)

		require.NotNil(t, event)
		assert.Equal(t, "copilot_coding_agent_pull_request_state_changed", event.EventType)
		assert.Equal(t, "closed", event.Metadata["pr_state"])
		assert.Equal(t, "99", event.SecondaryEntityId.GetValue())
	})
}
