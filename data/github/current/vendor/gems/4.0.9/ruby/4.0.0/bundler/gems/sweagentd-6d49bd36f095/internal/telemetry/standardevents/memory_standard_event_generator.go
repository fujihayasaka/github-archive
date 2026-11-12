package standardevents

import (
	"context"
	"fmt"
	"strconv"
	"time"

	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// MemoryEventContext contains the contextual information needed to generate memory StandardEvents.
// This replaces *requestctx.CtxJob, which is unavailable in the HTTP handler context
// since memory requests arrive as separate HTTP calls from the runtime, not within Aqueduct jobs.
type MemoryEventContext struct {
	UserID               uint64
	RepoID               uint64
	OwnerID              int64
	AgentName            string
	CopilotIntegrationID string
	InteractionID        string
}

// NewMemoryEventContext creates a MemoryEventContext.
// repository can be nil for user-scoped only operations.
func NewMemoryEventContext(userInfo *requestctx.UserInfo, repository *core.Repository, agentName, copilotIntegrationID string) *MemoryEventContext {
	ctx := &MemoryEventContext{
		UserID:               userInfo.ID,
		AgentName:            agentName,
		CopilotIntegrationID: copilotIntegrationID,
	}
	if repository != nil {
		ctx.RepoID = uint64(repository.ID)
		ctx.OwnerID = repository.OwnerID
	}
	return ctx
}

// WithInteractionID sets the interaction ID and returns the receiver for chaining.
func (m *MemoryEventContext) WithInteractionID(interactionID string) *MemoryEventContext {
	m.InteractionID = interactionID
	return m
}

// MemoryRetrievalParams contains the telemetry data needed to generate a memory retrieval StandardEvent.
type MemoryRetrievalParams struct {
	OccurredAt time.Time
	Latency    time.Duration
	// Scope indicates the retrieval scope: "user", "repository", or "combined"
	Scope string
	// UserMemoryCount is the number of user-scoped memories retrieved (optional)
	UserMemoryCount *int64
	// RepoMemoryCount is the number of repository-scoped memories retrieved (optional)
	RepoMemoryCount *int64
}

// MemoryStoreParams contains the telemetry data needed to generate a memory store StandardEvent.
type MemoryStoreParams struct {
	OccurredAt time.Time
	Latency    time.Duration
	// Scope indicates the store scope: "user" or "repository"
	Scope string
}

// MemoryVoteParams contains the telemetry data needed to generate a memory vote StandardEvent.
type MemoryVoteParams struct {
	OccurredAt time.Time
	Latency    time.Duration
	Direction  string // "upvote" or "downvote"
	// Scope indicates the vote scope: "user" or "repository"
	Scope string
}

// MemoryDeleteParams contains the telemetry data needed to generate a memory delete StandardEvent.
type MemoryDeleteParams struct {
	OccurredAt time.Time
	Latency    time.Duration
	Operation  string // "delete_single" or "delete_all"
	MemoryID   string // optional, only for single delete
}

const (
	// Event type prefix for all memory-related events
	eventTypePrefixMemory = "copilot_coding_agent"

	// Event type for memory events
	eventTypeMemoryRetrieval = "memory_retrieval"
	eventTypeMemoryStore     = "memory_store"
	eventTypeMemoryVote      = "memory_vote"
	eventTypeMemoryDelete    = "memory_delete"
)

var (
	// EventTypeMemoryRetrieval is the full event type for memory retrieval events.
	EventTypeMemoryRetrieval = fmt.Sprintf("%s.%s", eventTypePrefixMemory, eventTypeMemoryRetrieval)
	// EventTypeMemoryStore is the full event type for memory store events.
	EventTypeMemoryStore = fmt.Sprintf("%s.%s", eventTypePrefixMemory, eventTypeMemoryStore)
	// EventTypeMemoryVote is the full event type for memory vote events.
	EventTypeMemoryVote = fmt.Sprintf("%s.%s", eventTypePrefixMemory, eventTypeMemoryVote)
	// EventTypeMemoryDelete is the full event type for memory delete events.
	EventTypeMemoryDelete = fmt.Sprintf("%s.%s", eventTypePrefixMemory, eventTypeMemoryDelete)
)

// MemoryStandardEventGenerator generates StandardEvent messages for memory-related events.
type MemoryStandardEventGenerator struct{}

// GenerateMemoryRetrievalStandardEvent creates a StandardEvent for a memory retrieval event.
func (g *MemoryStandardEventGenerator) GenerateMemoryRetrievalStandardEvent(ctx context.Context, memCtx *MemoryEventContext, params MemoryRetrievalParams) *standardpb.StandardEvent {
	sdkContext := exp.AssignmentFromContext(ctx).GetAssignmentContext()

	event := newBaseEvent(
		EventTypeMemoryRetrieval,
		params.OccurredAt,
		strconv.FormatUint(memCtx.RepoID, 10),
		EntityTypeRepositoryID,
		sdkContext,
	)

	g.populateEventMetadata(event, memCtx)

	event.Measurements["latency_ms"] = float64(params.Latency.Milliseconds())

	// Add scope metadata
	if params.Scope != "" {
		event.Metadata["memory_scope"] = params.Scope
	}

	// Add per-scope counts for combined retrievals
	if params.UserMemoryCount != nil {
		event.Measurements["user_memory_count"] = float64(*params.UserMemoryCount)
	}
	if params.RepoMemoryCount != nil {
		event.Measurements["repo_memory_count"] = float64(*params.RepoMemoryCount)
	}

	return event
}

// GenerateMemoryStoreStandardEvent creates a StandardEvent for a memory store event.
func (g *MemoryStandardEventGenerator) GenerateMemoryStoreStandardEvent(ctx context.Context, memCtx *MemoryEventContext, params MemoryStoreParams) *standardpb.StandardEvent {
	sdkContext := exp.AssignmentFromContext(ctx).GetAssignmentContext()

	event := newBaseEvent(
		EventTypeMemoryStore,
		params.OccurredAt,
		strconv.FormatUint(memCtx.RepoID, 10),
		EntityTypeRepositoryID,
		sdkContext,
	)

	g.populateEventMetadata(event, memCtx)

	event.Measurements["latency_ms"] = float64(params.Latency.Milliseconds())

	if params.Scope != "" {
		event.Metadata["memory_scope"] = params.Scope
	}

	return event
}

// GenerateMemoryVoteStandardEvent creates a StandardEvent for a memory vote event.
func (g *MemoryStandardEventGenerator) GenerateMemoryVoteStandardEvent(ctx context.Context, memCtx *MemoryEventContext, params MemoryVoteParams) *standardpb.StandardEvent {
	sdkContext := exp.AssignmentFromContext(ctx).GetAssignmentContext()

	event := newBaseEvent(
		EventTypeMemoryVote,
		params.OccurredAt,
		strconv.FormatUint(memCtx.RepoID, 10),
		EntityTypeRepositoryID,
		sdkContext,
	)

	g.populateEventMetadata(event, memCtx)

	event.Measurements["latency_ms"] = float64(params.Latency.Milliseconds())
	event.Metadata["vote_direction"] = params.Direction

	if params.Scope != "" {
		event.Metadata["memory_scope"] = params.Scope
	}

	return event
}

// GenerateMemoryDeleteStandardEvent creates a StandardEvent for a memory delete event.
func (g *MemoryStandardEventGenerator) GenerateMemoryDeleteStandardEvent(ctx context.Context, memCtx *MemoryEventContext, params MemoryDeleteParams) *standardpb.StandardEvent {
	sdkContext := exp.AssignmentFromContext(ctx).GetAssignmentContext()

	event := newBaseEvent(
		EventTypeMemoryDelete,
		params.OccurredAt,
		strconv.FormatUint(memCtx.RepoID, 10),
		EntityTypeRepositoryID,
		sdkContext,
	)

	g.populateEventMetadata(event, memCtx)

	event.Measurements["latency_ms"] = float64(params.Latency.Milliseconds())
	event.Metadata["operation"] = params.Operation
	if params.MemoryID != "" {
		event.Metadata["memory_id"] = params.MemoryID
	}

	return event
}

// populateEventMetadata populates the standard metadata fields on a StandardEvent.
func (g *MemoryStandardEventGenerator) populateEventMetadata(event *standardpb.StandardEvent, memCtx *MemoryEventContext) {
	// Only include repo fields when a repository context is available
	if memCtx.RepoID != 0 {
		event.Metadata["repository_id"] = strconv.FormatUint(memCtx.RepoID, 10)
	}
	if memCtx.OwnerID != 0 {
		event.Metadata["owner_id"] = strconv.FormatInt(memCtx.OwnerID, 10)
	}
	event.Metadata["actor_id"] = strconv.FormatUint(memCtx.UserID, 10)
	event.Metadata["agent_name"] = memCtx.AgentName
	event.Metadata["copilot_integration_id"] = memCtx.CopilotIntegrationID
	if memCtx.InteractionID != "" {
		event.Metadata["interaction_id"] = memCtx.InteractionID
	}
}
