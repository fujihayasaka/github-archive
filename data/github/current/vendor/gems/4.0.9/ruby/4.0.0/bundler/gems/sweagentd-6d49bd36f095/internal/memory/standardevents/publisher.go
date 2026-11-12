// Package standardevents provides standard event publishing for memory operations.
package standardevents

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/telemetry/standardevents"
)

// Publisher handles standard event publishing for memory operations.
type Publisher struct {
	obsv      observability.Exporters
	generator *standardevents.MemoryStandardEventGenerator
	ffClient  featureflags.Client
}

// NewPublisher creates a new Publisher.
func NewPublisher(obsv observability.Exporters, ffClient featureflags.Client) *Publisher {
	return &Publisher{
		obsv:      obsv,
		generator: &standardevents.MemoryStandardEventGenerator{},
		ffClient:  ffClient,
	}
}

// RequestContext holds headers extracted from HTTP requests.
type RequestContext struct {
	CopilotIntegrationID string
}

// ExtractRequestContext extracts headers from an HTTP request.
func ExtractRequestContext(r *http.Request) RequestContext {
	return RequestContext{
		CopilotIntegrationID: r.Header.Get(capi.IntegrationIDHeader),
	}
}

// StoreParams contains parameters for a memory store event.
type StoreParams struct {
	UserInfo      *requestctx.UserInfo
	Repository    *core.Repository
	AgentName     string
	InteractionID string
	ReqCtx        RequestContext
	StartTime     time.Time
	// Scope indicates the store scope: "user" or "repository"
	Scope string
}

// PublishStore publishes a standard event for memory store (FF gated).
func (p *Publisher) PublishStore(ctx context.Context, params StoreParams) {
	logger := p.obsv.LoggerWithTelemetry(ctx)

	memCtx := standardevents.NewMemoryEventContext(
		params.UserInfo,
		params.Repository,
		params.AgentName,
		params.ReqCtx.CopilotIntegrationID,
	).WithInteractionID(params.InteractionID)

	if !p.isEnabled(ctx, memCtx.UserID, memCtx.RepoID) {
		return
	}

	logEntry := logger.WithFields(
		kvp.String("agent_name", params.AgentName),
		kvp.Uint64("user_id", params.UserInfo.ID),
		kvp.String("interaction_id", params.InteractionID),
	)
	if params.Repository != nil {
		logEntry = logEntry.WithFields(kvp.Uint64("repo_id", uint64(params.Repository.ID)))
	}
	logEntry.Info("publishing memory store event")

	event := p.generator.GenerateMemoryStoreStandardEvent(ctx, memCtx, standardevents.MemoryStoreParams{
		OccurredAt: params.StartTime,
		Latency:    time.Since(params.StartTime),
		Scope:      params.Scope,
	})
	p.publish(ctx, event, "memory_store")
}

// RetrievalParams contains parameters for a memory retrieval event.
type RetrievalParams struct {
	UserInfo   *requestctx.UserInfo
	Repository *core.Repository
	ReqCtx     RequestContext
	StartTime  time.Time
	// Scope indicates the retrieval scope: "user", "repository", or "combined"
	Scope string
	// UserMemoryCount is the number of user-scoped memories retrieved (optional)
	UserMemoryCount *int64
	// RepoMemoryCount is the number of repository-scoped memories retrieved (optional)
	RepoMemoryCount *int64
}

// PublishRetrieval publishes a standard event for memory retrieval (FF gated).
// No interaction_id available for GET requests.
func (p *Publisher) PublishRetrieval(ctx context.Context, params RetrievalParams) {
	logger := p.obsv.LoggerWithTelemetry(ctx)

	memCtx := standardevents.NewMemoryEventContext(
		params.UserInfo,
		params.Repository,
		"",
		params.ReqCtx.CopilotIntegrationID,
	)

	if !p.isEnabled(ctx, memCtx.UserID, memCtx.RepoID) {
		return
	}

	logEntry := logger.WithFields(
		kvp.Uint64("user_id", params.UserInfo.ID),
		kvp.String("scope", params.Scope),
	)
	if params.Repository != nil {
		logEntry = logEntry.WithFields(kvp.Uint64("repo_id", uint64(params.Repository.ID)))
	}
	logEntry.Info("publishing memory retrieval event")

	event := p.generator.GenerateMemoryRetrievalStandardEvent(ctx, memCtx, standardevents.MemoryRetrievalParams{
		OccurredAt:      params.StartTime,
		Latency:         time.Since(params.StartTime),
		Scope:           params.Scope,
		UserMemoryCount: params.UserMemoryCount,
		RepoMemoryCount: params.RepoMemoryCount,
	})
	p.publish(ctx, event, "memory_retrieval")
}

// VoteParams contains parameters for a memory vote event.
type VoteParams struct {
	UserInfo      *requestctx.UserInfo
	Repository    *core.Repository
	AgentName     string
	InteractionID string // from request body when present
	Direction     string
	ReqCtx        RequestContext
	StartTime     time.Time
	// Scope indicates the vote scope: "user" or "repository"
	Scope string
}

// PublishVote publishes a standard event for memory vote (FF gated).
func (p *Publisher) PublishVote(ctx context.Context, params VoteParams) {
	logger := p.obsv.LoggerWithTelemetry(ctx)

	direction := strings.ToLower(params.Direction)

	memCtx := standardevents.NewMemoryEventContext(
		params.UserInfo,
		params.Repository,
		params.AgentName,
		params.ReqCtx.CopilotIntegrationID,
	).WithInteractionID(params.InteractionID)

	if !p.isEnabled(ctx, memCtx.UserID, memCtx.RepoID) {
		return
	}

	logEntry := logger.WithFields(
		kvp.String("agent_name", params.AgentName),
		kvp.Uint64("user_id", params.UserInfo.ID),
		kvp.String("interaction_id", params.InteractionID),
		kvp.String("vote_direction", direction),
	)
	if params.Repository != nil {
		logEntry = logEntry.WithFields(kvp.Uint64("repo_id", uint64(params.Repository.ID)))
	}
	logEntry.Info("publishing memory vote event")

	event := p.generator.GenerateMemoryVoteStandardEvent(ctx, memCtx, standardevents.MemoryVoteParams{
		OccurredAt: params.StartTime,
		Latency:    time.Since(params.StartTime),
		Direction:  direction,
		Scope:      params.Scope,
	})
	p.publish(ctx, event, "memory_vote")
}

// DeleteParams contains parameters for a memory delete event.
type DeleteParams struct {
	UserInfo   *requestctx.UserInfo
	Repository *core.Repository
	ReqCtx     RequestContext
	StartTime  time.Time
	Operation  string // "delete_single" or "delete_all"
	MemoryID   string // optional, only for single delete
}

// PublishDelete publishes a standard event for memory deletion (FF gated).
func (p *Publisher) PublishDelete(ctx context.Context, params DeleteParams) {
	logger := p.obsv.LoggerWithTelemetry(ctx)

	memCtx := standardevents.NewMemoryEventContext(
		params.UserInfo,
		params.Repository,
		"",
		params.ReqCtx.CopilotIntegrationID,
	)

	if !p.isEnabled(ctx, memCtx.UserID, memCtx.RepoID) {
		return
	}

	logEntry := logger.WithFields(
		kvp.String("operation", params.Operation),
		kvp.Uint64("user_id", params.UserInfo.ID),
		kvp.String("memory_id", params.MemoryID),
	)
	if params.Repository != nil {
		logEntry = logEntry.WithFields(kvp.Uint64("repo_id", uint64(params.Repository.ID)))
	}
	logEntry.Info("publishing memory delete event")

	event := p.generator.GenerateMemoryDeleteStandardEvent(ctx, memCtx, standardevents.MemoryDeleteParams{
		OccurredAt: params.StartTime,
		Latency:    time.Since(params.StartTime),
		Operation:  params.Operation,
		MemoryID:   params.MemoryID,
	})
	p.publish(ctx, event, "memory_delete")
}

func (p *Publisher) isEnabled(ctx context.Context, userID, repoID uint64) bool {
	if p.ffClient == nil {
		return false
	}
	return p.ffClient.IsEnabledForUserOrRepo(ctx, featureflags.CodingAgentMemoryStandardEvents, int64(userID), int64(repoID))
}

func (p *Publisher) publish(ctx context.Context, event *standardpb.StandardEvent, eventName string) {
	logger := p.obsv.LoggerWithTelemetry(ctx)
	err := p.obsv.HydroPbl.Publish(event)
	if err != nil {
		logger.WithError(err).Error("failed to publish " + eventName + " event")
	}
}
