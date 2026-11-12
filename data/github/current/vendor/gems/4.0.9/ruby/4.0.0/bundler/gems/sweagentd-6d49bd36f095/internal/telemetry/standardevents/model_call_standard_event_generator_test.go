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

func TestModelCallPipelineGenerator_GenerateModelCallStandardEvent(t *testing.T) {
	gen := &ModelCallStandardEventGenerator{}

	t.Run("basic model call event", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id-123",
			SessionID:                "session-abc",
			IsAutoMode:               true,
			EventType:                jobs.EventTypeIssueAssignment,
			Action:                   jobs.AgentActionFix,
			Experiments: &experiments.AssignmentExperiments{
				AssignmentContext: "exp-ctx-abc",
			},
		}

		params := ModelCallParams{
			Model:            "gpt-4",
			CompletionTokens: 150,
			PromptTokens:     500,
			TotalTokens:      650,
			DurationMs:       1200,
			ToolCallsCount:   3,
			OccurredAt:       time.Unix(1710000000, 0),
			ProgressKind:     "model_call_success",
			RequestID:        "req-abc-123",
		}

		event := gen.GenerateModelCallStandardEvent(context.Background(), job, params)

		require.NotNil(t, event)
		assert.Equal(t, "copilot_coding_agent_model_call", event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "tracking-id-123", event.PrimaryEntityId)
		assert.Equal(t, "copilot_tracking_id", event.PrimaryEntityIdType)
		assert.Nil(t, event.ActivityCorrelationId)
		assert.Equal(t, "owner-repo-uuid", event.SessionId.GetValue())
		assert.Equal(t, "", event.PrimaryAssignmentContext)
		assert.Equal(t, time.Unix(1710000000, 0).UTC(), event.OccurredAt.AsTime())

		assert.InDelta(t, float64(150), event.Measurements["completion_tokens_count"], 0)
		assert.InDelta(t, float64(500), event.Measurements["prompt_tokens_count"], 0)
		assert.InDelta(t, float64(650), event.Measurements["total_tokens_count"], 0)
		assert.InDelta(t, float64(1200), event.Measurements["duration_ms"], 0)
		assert.InDelta(t, float64(3), event.Measurements["tool_calls_count"], 0)

		assert.Equal(t, "model_call_success", event.Metadata["progress_kind"])
		assert.True(t, event.Conditions["is_auto_mode"])
		assert.False(t, event.Conditions["is_custom_agent"])

		assert.Equal(t, "req-abc-123", event.Metadata["request_id"])
		assert.Equal(t, "gpt-4", event.Metadata["model"])
		assert.Equal(t, "issue_assignment", event.Metadata["event_type"])
		assert.Equal(t, "fix", event.Metadata["action"])
		_, hasError := event.Metadata["error"]
		assert.False(t, hasError)
		_, hasStatusCode := event.Metadata["status_code"]
		assert.False(t, hasStatusCode)
	})

	t.Run("failed model call event", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
		}

		params := ModelCallParams{
			Model:        "gpt-4",
			OccurredAt:   time.Unix(1710000000, 0),
			ProgressKind: "model_call_failure",
			Error:        "rate limit exceeded",
			StatusCode:   429,
		}

		event := gen.GenerateModelCallStandardEvent(context.Background(), job, params)

		require.NotNil(t, event)
		assert.Equal(t, "model_call_failure", event.Metadata["progress_kind"])
		assert.Equal(t, "rate limit exceeded", event.Metadata["error"])
		assert.Equal(t, "429", event.Metadata["status_code"])
	})

	t.Run("model call with zero tokens", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
		}

		params := ModelCallParams{
			Model:      "gpt-4",
			OccurredAt: time.Unix(1710000000, 0),
		}

		event := gen.GenerateModelCallStandardEvent(context.Background(), job, params)

		require.NotNil(t, event)
		assert.InDelta(t, float64(0), event.Measurements["completion_tokens_count"], 0)
		assert.InDelta(t, float64(0), event.Measurements["prompt_tokens_count"], 0)
		assert.InDelta(t, float64(0), event.Measurements["total_tokens_count"], 0)
		assert.InDelta(t, float64(0), event.Measurements["duration_ms"], 0)
		assert.InDelta(t, float64(0), event.Measurements["tool_calls_count"], 0)
	})

	t.Run("job without experiments", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
		}

		params := ModelCallParams{
			Model:      "gpt-4",
			OccurredAt: time.Unix(1710000000, 0),
		}

		event := gen.GenerateModelCallStandardEvent(context.Background(), job, params)

		require.NotNil(t, event)
		assert.Equal(t, "", event.PrimaryAssignmentContext)
	})

	t.Run("no secondary entity for model calls", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			PullRequestID:            42,
			ActorAnalyticsTrackingID: "tracking-id",
		}

		params := ModelCallParams{
			Model:      "gpt-4",
			OccurredAt: time.Unix(1710000000, 0),
		}

		event := gen.GenerateModelCallStandardEvent(context.Background(), job, params)

		require.NotNil(t, event)
		// Model call events don't set secondary entity
		assert.Nil(t, event.SecondaryEntityId)
	})

	t.Run("deduplication IDs are unique", func(t *testing.T) {
		job := &jobs.Job{
			ID:                       "owner-repo-uuid",
			ActorAnalyticsTrackingID: "tracking-id",
		}

		params := ModelCallParams{
			Model:      "gpt-4",
			OccurredAt: time.Unix(1710000000, 0),
		}

		event1 := gen.GenerateModelCallStandardEvent(context.Background(), job, params)
		event2 := gen.GenerateModelCallStandardEvent(context.Background(), job, params)

		assert.NotEqual(t, event1.DeduplicationId, event2.DeduplicationId)
	})
}
