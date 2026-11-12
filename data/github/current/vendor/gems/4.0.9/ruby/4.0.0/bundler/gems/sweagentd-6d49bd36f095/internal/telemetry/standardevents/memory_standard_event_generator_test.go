package standardevents

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMemoryStandardEventGenerator_GenerateMemoryRetrievalStandardEvent(t *testing.T) {
	gen := &MemoryStandardEventGenerator{}

	t.Run("basic memory retrieval event", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			UserID:               111,
			RepoID:               12345,
			OwnerID:              67890,
			AgentName:            "copilot-developer",
			CopilotIntegrationID: "copilot-developer",
		}

		params := MemoryRetrievalParams{
			OccurredAt: time.Unix(1710000000, 0),
			Latency:    150 * time.Millisecond,
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, EventTypeMemoryRetrieval, event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "12345", event.PrimaryEntityId)
		assert.Equal(t, EntityTypeRepositoryID, event.PrimaryEntityIdType)
		assert.Equal(t, time.Unix(1710000000, 0).UTC(), event.OccurredAt.AsTime())

		// Measurements
		assert.InDelta(t, float64(150), event.Measurements["latency_ms"], 0)

		// Metadata
		assert.Equal(t, "12345", event.Metadata["repository_id"])
		assert.Equal(t, "67890", event.Metadata["owner_id"])
		assert.Equal(t, "111", event.Metadata["actor_id"])
		assert.Equal(t, "copilot-developer", event.Metadata["agent_name"])
		assert.Equal(t, "copilot-developer", event.Metadata["copilot_integration_id"])
	})

	t.Run("zero memories retrieved", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID: 12345,
		}

		params := MemoryRetrievalParams{
			OccurredAt: time.Unix(1710000000, 0),
			Latency:    0,
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.InDelta(t, float64(0), event.Measurements["latency_ms"], 0)
	})

	t.Run("event type constant matches", func(t *testing.T) {
		assert.Equal(t, "memory_retrieval", eventTypeMemoryRetrieval)
	})
}

func TestMemoryStandardEventGenerator_GenerateMemoryStoreStandardEvent(t *testing.T) {
	gen := &MemoryStandardEventGenerator{}

	t.Run("basic memory store event", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			UserID:               111,
			RepoID:               12345,
			OwnerID:              67890,
			AgentName:            "copilot-developer",
			CopilotIntegrationID: "copilot-developer",
		}

		params := MemoryStoreParams{
			OccurredAt: time.Unix(1710000000, 0),
			Latency:    200 * time.Millisecond,
		}

		event := gen.GenerateMemoryStoreStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, EventTypeMemoryStore, event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "12345", event.PrimaryEntityId)
		assert.Equal(t, EntityTypeRepositoryID, event.PrimaryEntityIdType)
		assert.Equal(t, time.Unix(1710000000, 0).UTC(), event.OccurredAt.AsTime())

		// Measurements
		assert.InDelta(t, float64(200), event.Measurements["latency_ms"], 0)
		_, hasMemoryCount := event.Measurements["memory_retrieval_count"]
		assert.False(t, hasMemoryCount, "memory store event should not have memory_retrieval_count")

		// Metadata
		assert.Equal(t, "12345", event.Metadata["repository_id"])
		assert.Equal(t, "67890", event.Metadata["owner_id"])
		assert.Equal(t, "111", event.Metadata["actor_id"])
		assert.Equal(t, "copilot-developer", event.Metadata["agent_name"])
		assert.Equal(t, "copilot-developer", event.Metadata["copilot_integration_id"])
	})

	t.Run("event type constant matches", func(t *testing.T) {
		assert.Equal(t, "memory_store", eventTypeMemoryStore)
	})
}

func TestMemoryStandardEventGenerator_GenerateMemoryVoteStandardEvent(t *testing.T) {
	gen := &MemoryStandardEventGenerator{}

	t.Run("basic memory vote event with upvote", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			UserID:               111,
			RepoID:               12345,
			OwnerID:              67890,
			AgentName:            "copilot-developer",
			CopilotIntegrationID: "copilot-developer",
			InteractionID:        "session-abc-123",
		}

		params := MemoryVoteParams{
			OccurredAt: time.Unix(1710000000, 0),
			Latency:    100 * time.Millisecond,
			Direction:  "upvote",
		}

		event := gen.GenerateMemoryVoteStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, EventTypeMemoryVote, event.EventType)
		assert.Equal(t, OwningService, event.OwningService)
		assert.Equal(t, EventVersion, event.EventVersion)
		assert.NotEmpty(t, event.DeduplicationId)
		assert.Equal(t, "12345", event.PrimaryEntityId)
		assert.Equal(t, EntityTypeRepositoryID, event.PrimaryEntityIdType)
		assert.Equal(t, time.Unix(1710000000, 0).UTC(), event.OccurredAt.AsTime())

		// Measurements
		assert.InDelta(t, float64(100), event.Measurements["latency_ms"], 0)

		// Metadata
		assert.Equal(t, "12345", event.Metadata["repository_id"])
		assert.Equal(t, "67890", event.Metadata["owner_id"])
		assert.Equal(t, "111", event.Metadata["actor_id"])
		assert.Equal(t, "copilot-developer", event.Metadata["agent_name"])
		assert.Equal(t, "copilot-developer", event.Metadata["copilot_integration_id"])
		assert.Equal(t, "upvote", event.Metadata["vote_direction"])
		assert.Equal(t, "session-abc-123", event.Metadata["interaction_id"])
	})

	t.Run("memory vote event with downvote", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID:        12345,
			InteractionID: "session-xyz-456",
		}

		params := MemoryVoteParams{
			OccurredAt: time.Unix(1710000000, 0),
			Latency:    50 * time.Millisecond,
			Direction:  "downvote",
		}

		event := gen.GenerateMemoryVoteStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, "downvote", event.Metadata["vote_direction"])
		assert.Equal(t, "session-xyz-456", event.Metadata["interaction_id"])
	})

	t.Run("memory vote event without interaction_id omits field", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID: 12345,
			// No InteractionID set
		}

		params := MemoryVoteParams{
			OccurredAt: time.Unix(1710000000, 0),
			Direction:  "upvote",
		}

		event := gen.GenerateMemoryVoteStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		_, hasInteractionID := event.Metadata["interaction_id"]
		assert.False(t, hasInteractionID, "interaction_id should not be present when empty")
	})

	t.Run("event type constant matches", func(t *testing.T) {
		assert.Equal(t, "memory_vote", eventTypeMemoryVote)
	})
}

func TestMemoryStandardEventGenerator_PopulateEventMetaData(t *testing.T) {
	gen := &MemoryStandardEventGenerator{}

	t.Run("all metadata fields populated", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			UserID:               77777,
			RepoID:               99999,
			OwnerID:              88888,
			AgentName:            "copilot-developer",
			CopilotIntegrationID: "copilot-developer",
		}

		params := MemoryRetrievalParams{
			OccurredAt: time.Unix(1710000000, 0),
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, "99999", event.Metadata["repository_id"])
		assert.Equal(t, "88888", event.Metadata["owner_id"])
		assert.Equal(t, "77777", event.Metadata["actor_id"])
		assert.Equal(t, "copilot-developer", event.Metadata["agent_name"])
		assert.Equal(t, "copilot-developer", event.Metadata["copilot_integration_id"])
	})

	t.Run("empty context omits repo fields", func(t *testing.T) {
		memCtx := &MemoryEventContext{}

		params := MemoryRetrievalParams{
			OccurredAt: time.Unix(1710000000, 0),
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		// repository_id and owner_id are omitted when zero (user-only context)
		_, hasRepoID := event.Metadata["repository_id"]
		_, hasOwnerID := event.Metadata["owner_id"]
		assert.False(t, hasRepoID, "repository_id should be omitted when zero")
		assert.False(t, hasOwnerID, "owner_id should be omitted when zero")
		// actor_id is always included
		assert.Equal(t, "0", event.Metadata["actor_id"])
		assert.Equal(t, "", event.Metadata["agent_name"])
		assert.Equal(t, "", event.Metadata["copilot_integration_id"])
	})

	t.Run("scope field included when set", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID: 12345,
		}

		params := MemoryRetrievalParams{
			OccurredAt: time.Unix(1710000000, 0),
			Scope:      "combined",
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, "combined", event.Metadata["memory_scope"])
	})

	t.Run("scope field not included when empty", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID: 12345,
		}

		params := MemoryRetrievalParams{
			OccurredAt: time.Unix(1710000000, 0),
			Scope:      "",
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		_, hasScope := event.Metadata["memory_scope"]
		assert.False(t, hasScope, "memory_scope should not be present when Scope is empty")
	})

	t.Run("per-scope counts included for combined retrieval", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID: 12345,
		}

		userCount := int64(3)
		repoCount := int64(7)
		params := MemoryRetrievalParams{
			OccurredAt:      time.Unix(1710000000, 0),
			Scope:           "combined",
			UserMemoryCount: &userCount,
			RepoMemoryCount: &repoCount,
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, "combined", event.Metadata["memory_scope"])
		assert.InDelta(t, float64(3), event.Measurements["user_memory_count"], 0)
		assert.InDelta(t, float64(7), event.Measurements["repo_memory_count"], 0)
	})

	t.Run("per-scope counts not included when nil", func(t *testing.T) {
		memCtx := &MemoryEventContext{
			RepoID: 12345,
		}

		params := MemoryRetrievalParams{
			OccurredAt:      time.Unix(1710000000, 0),
			Scope:           "repository",
			UserMemoryCount: nil,
			RepoMemoryCount: nil,
		}

		event := gen.GenerateMemoryRetrievalStandardEvent(context.Background(), memCtx, params)

		require.NotNil(t, event)
		assert.Equal(t, "repository", event.Metadata["memory_scope"])
		_, hasUserCount := event.Measurements["user_memory_count"]
		_, hasRepoCount := event.Measurements["repo_memory_count"]
		assert.False(t, hasUserCount, "user_memory_count should not be present when nil")
		assert.False(t, hasRepoCount, "repo_memory_count should not be present when nil")
	})
}
