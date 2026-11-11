package agentsync

import (
	"context"
	"errors"
	"sort"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/envrouting"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
)

// FeatureFlags defines the feature flag operations needed by the handler.
type FeatureFlags interface {
	IsEnabledForRepo(ctx context.Context, featureFlagName string, repoID int64) bool
	IsEnabledForRepoOrOwner(ctx context.Context, featureFlagName string, repo sweagentd.Repository) bool
}

// EnterpriseResolver resolves whether a repository is the enterprise agent repository.
type EnterpriseResolver interface {
	// IsEnterpriseAgentRepo checks if the given owner ID is associated with an
	// enterprise that has this repository configured as its agent config repo.
	// Returns the configured repository ID if found, or 0 if not.
	//
	// Note: this returns a repository ID (for comparison with event.RepoID),
	// NOT an enterprise/business ID. The business ID for partition key usage
	// comes from the Hydro Repository.business_id field instead.
	IsEnterpriseAgentRepo(ctx context.Context, ownerID int64) (repoID int64, err error)
}

// Handler processes AgentsUpdated Hydro events by syncing agent configs to the store.
type Handler struct {
	reconciler         *Reconciler
	repoStore          AgentStore
	orgStore           AgentStore
	enterpriseStore    AgentStore
	ffClient           FeatureFlags
	enterpriseResolver EnterpriseResolver
	envRouter          *envrouting.Router
	obsv               observability.Exporters
	repoInvalidator    func(repoID int64)
}

// HandlerOption configures optional Handler dependencies.
type HandlerOption func(*Handler)

// WithRepoInvalidator configures a callback invoked after a successful
// repo-scoped AgentsUpdated sync.
func WithRepoInvalidator(fn func(repoID int64)) HandlerOption {
	return func(h *Handler) {
		h.repoInvalidator = fn
	}
}

// NewHandler creates a new Handler.
func NewHandler(
	files FileReader,
	repoStore AgentStore,
	orgStore AgentStore,
	enterpriseStore AgentStore,
	ffClient FeatureFlags,
	enterpriseResolver EnterpriseResolver,
	envRouter *envrouting.Router,
	obsv observability.Exporters,
	opts ...HandlerOption,
) *Handler {
	h := &Handler{
		reconciler:         NewReconciler(files, obsv),
		repoStore:          repoStore,
		orgStore:           orgStore,
		enterpriseStore:    enterpriseStore,
		ffClient:           ffClient,
		enterpriseResolver: enterpriseResolver,
		envRouter:          envRouter,
		obsv:               obsv,
	}
	for _, opt := range opts {
		opt(h)
	}
	return h
}

// Dispatch is the Hydro MessageHandler entry point. It processes raw Hydro
// messages by extracting the envelope and delegating to handleAgentsUpdated.
func (h *Handler) Dispatch(ctx context.Context, m hydro_lib.Message) error {
	// Ensure we have a request ID for tracing
	if requestID := requestid.GetGitHubRequestID(ctx); requestID == "" {
		ctx = requestid.WithNewGitHubRequestID(ctx)
	}

	// Add hydro message metadata to the request context early so that
	// LoggerWithTelemetry includes topic/partition/offset info even when
	// we encounter errors before full envelope parsing.
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		HydroMessage: &requestctx.HydroEvent{
			Topic:     m.Topic,
			Partition: m.Partition,
			Offset:    m.Offset,
		},
	})

	var envelope hydro_pb.Envelope
	err := proto.Unmarshal(m.Value, &envelope)
	if err != nil {
		// Return nil to ack the message. Returning an error causes the hydro
		// consumer to retry the message infinitely with no backoff, blocking
		// all subsequent events across every partition.
		h.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("agentsync: failed to unmarshal envelope")
		h.obsv.Increment(ctx, "hydro.envelope_error", nil)
		return nil
	}

	// Enrich with envelope ID now that it's available.
	requestctx.Data(ctx).HydroMessage.EnvelopeID = envelope.Id

	logger := h.obsv.LoggerWithTelemetry(ctx)

	if m.Topic != topics.AgentsUpdated {
		logger.Error("unexpected topic in agentsync handler",
			kvp.String("topic", m.Topic),
		)
		return nil
	}

	logger.Info("start: agentsync hydro event")
	h.obsv.Increment(ctx, "hydro.event_received", nil)

	start := time.Now()
	err = h.handleAgentsUpdated(ctx, &envelope)
	duration := time.Since(start)

	// Reload logger after handleAgentsUpdated may have added context data
	logger = h.obsv.LoggerWithTelemetry(ctx)

	if err != nil {
		h.obsv.Increment(ctx, "hydro.event_error", nil)
		logger.WithError(err).Error("agentsync dispatch error")
		// Return nil to ack the message. Transient errors will be captured in
		// metrics; we don't want infinite retries for bad payloads.
		return nil
	}

	h.obsv.DistributionMs(ctx, "hydro.dispatch_dist", nil, duration)
	logger.Info("done: agentsync hydro event", kvp.Duration("duration", duration))

	return nil
}

func (h *Handler) handleAgentsUpdated(ctx context.Context, envelope *hydro_pb.Envelope) error {
	msg, err := ParseAgentsUpdated(envelope.GetMessage())
	if err != nil {
		return goerrors.Errorf("parsing AgentsUpdated: %w", err)
	}

	event, err := NewSyncEvent(msg)
	if err != nil {
		return goerrors.Errorf("creating sync event: %w", err)
	}

	// Enrich the request context with repo and actor data so that TelemetryTags
	// and LoggerWithTelemetry include them automatically.
	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      event.RepoID,
		OwnerID: event.OwnerID,
	})
	if event.ActorID != 0 {
		_ = requestctx.AddUser(ctx, &requestctx.UserInfo{
			ID:    uint64(event.ActorID),
			Login: event.ActorLogin,
		})
	}

	scopeTags := stats.Tags{"scope": event.Scope}
	logger := h.obsv.LoggerWithTelemetry(ctx)

	// Feature flag gate: check per-repository or per-owner
	if !h.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentConfigSync, event) {
		h.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "feature_flag", "scope": event.Scope}, 1)
		return nil
	}

	// Gate by environment to prevent duplicate CosmosDB records across environments.
	if h.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentConfigSyncEnvRouting, event.RepoID) &&
		!h.envRouter.ShouldProcess(ctx, event.ActorID, event.RepoID, event.OwnerID) {
		logger.Info("agentsync: skipping event based on environment routing")
		h.obsv.Statter.Counter("hydro.event_skipped", stats.Tags{"reason": "environment_routing", "scope": event.Scope}, 1)
		return nil
	}

	logger.Info("agentsync: processing event",
		kvp.String("scope", event.Scope),
		kvp.Int64("scope_id", event.ScopeID),
		kvp.Int64("repo_id", event.RepoID),
		kvp.String("commit_sha", event.CommitSHA),
		kvp.Int("changed_files", len(event.ChangedFiles)),
	)

	h.obsv.Increment(ctx, "agentsync.event_received", scopeTags)

	// Select the appropriate store based on scope
	agentStore := h.storeForScope(event.Scope)
	if agentStore == nil {
		return goerrors.Errorf("no store for scope %q", event.Scope)
	}

	// Reconcile agent configs
	result, err := h.reconciler.Reconcile(ctx, agentStore, event, h.parseAgentConfig)
	if err != nil {
		h.obsv.Increment(ctx, "agentsync.reconcile_error", scopeTags)
		return goerrors.Errorf("reconciling agents: %w", err)
	}

	// Variable-count metrics require direct Statter.Counter with merged tags.
	allTags := h.obsv.TelemetryTags(ctx).Merge(scopeTags)
	h.obsv.Statter.Counter("agentsync.agents_added", allTags, int64(result.Added))
	h.obsv.Statter.Counter("agentsync.agents_updated", allTags, int64(result.Updated))
	h.obsv.Statter.Counter("agentsync.agents_deleted", allTags, int64(result.Deleted))
	if result.Errors > 0 {
		h.obsv.Statter.Counter("agentsync.reconcile_item_errors", allTags, int64(result.Errors))
	}

	logger.Info("agentsync: reconciliation complete",
		kvp.Int("added", result.Added),
		kvp.Int("updated", result.Updated),
		kvp.Int("deleted", result.Deleted),
		kvp.Int("errors", result.Errors),
	)

	// Invalidate any downstream caches keyed by repoID so subsequent
	// HasActiveForEvent calls see fresh data.
	if h.repoInvalidator != nil && event.Scope == agentconfig.ScopeRepository && event.RepoID != 0 {
		h.repoInvalidator(event.RepoID)
	}

	// For org-scoped repos, also check if this is the enterprise agent repo.
	// Short-circuit: only make the twirp call if the repo belongs to an enterprise
	// (BusinessID > 0). This avoids a twirp roundtrip for every non-enterprise
	// org push, which is the vast majority of events.
	if event.Scope == agentconfig.ScopeOrganization && h.enterpriseResolver != nil && event.BusinessID != 0 {
		h.handleEnterpriseSyncIfNeeded(ctx, event)
	}

	return nil
}

// handleEnterpriseSyncIfNeeded checks if an org-scoped repo is also the enterprise
// agent config repo, and if so, syncs to the enterprise store as well.
//
// Enterprise-level custom agents live in a .github-private repo within an org
// selected by the enterprise owner (see docs: "Enabling and protecting custom
// agents in your enterprise"). The same repo therefore serves both org and
// enterprise scopes, but with different CosmosDB partition keys:
//   - Org scope:        ScopeID = owner (org) ID
//   - Enterprise scope: ScopeID = business ID (from Repository.business_id)
//
// The business ID comes from the Hydro Repository entity, NOT the
// EnterpriseAgentsResponse twirp proto (which only returns repository_id).
// If business_id is absent (zero), enterprise sync is skipped to avoid
// writing records under an incorrect partition key.
func (h *Handler) handleEnterpriseSyncIfNeeded(ctx context.Context, event *SyncEvent) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	enterpriseRepoID, err := h.enterpriseResolver.IsEnterpriseAgentRepo(ctx, event.OwnerID)
	if err != nil {
		logger.Warn("agentsync: failed to check enterprise agent repo",
			kvp.String("error", err.Error()),
		)
		return
	}
	if enterpriseRepoID == 0 || enterpriseRepoID != event.RepoID {
		return
	}

	// This is also the enterprise agent repo — sync to enterprise store.
	// Use the business ID from the repository entity as the enterprise ScopeID
	// (partition key). Skip if not available, since we need a correct partition key.
	if event.BusinessID == 0 {
		logger.Warn("agentsync: enterprise agent repo detected but business_id not set, skipping enterprise sync",
			kvp.Int64("repo_id", event.RepoID),
		)
		return
	}

	enterpriseEvent := *event
	enterpriseEvent.Scope = agentconfig.ScopeEnterprise
	enterpriseEvent.ScopeID = event.BusinessID

	entScopeTags := stats.Tags{"scope": agentconfig.ScopeEnterprise}

	h.obsv.Increment(ctx, "agentsync.enterprise_sync", entScopeTags)

	result, err := h.reconciler.Reconcile(ctx, h.enterpriseStore, &enterpriseEvent, h.parseAgentConfig)
	if err != nil {
		h.obsv.Increment(ctx, "agentsync.reconcile_error", entScopeTags)
		logger.Error("agentsync: enterprise reconciliation failed",
			kvp.String("error", err.Error()),
		)
		return
	}

	logger.Info("agentsync: enterprise reconciliation complete",
		kvp.Int("added", result.Added),
		kvp.Int("updated", result.Updated),
		kvp.Int("deleted", result.Deleted),
		kvp.Int("errors", result.Errors),
	)
}

func (h *Handler) storeForScope(scope string) AgentStore {
	switch scope {
	case agentconfig.ScopeRepository:
		return h.repoStore
	case agentconfig.ScopeOrganization:
		return h.orgStore
	case agentconfig.ScopeEnterprise:
		return h.enterpriseStore
	default:
		return nil
	}
}

// parseAgentConfig wraps the existing customagent config parsing to produce a store.AgentConfig.
// On validation errors (*ErrConfigValidationError), it returns the partially parsed config
// alongside the error so the reconciler can persist it with SyncError set.
func (h *Handler) parseAgentConfig(_ string, contents []byte, name string) (*store.AgentConfig, error) {
	attrs, err := customagent.ParseConfigForSync(string(contents), name)
	if err != nil {
		// For validation errors, extract the partial config so the reconciler can
		// upsert it with SyncError set, following the pattern from
		// customagent/repository.go where partial configs are preserved.
		var configError *customagent.ErrConfigValidationError
		if errors.As(err, &configError) {
			return attrsToStoreConfig(name, configError.Attributes()), err
		}
		return nil, err
	}

	return attrsToStoreConfig(name, attrs), nil
}

// attrsToStoreConfig converts parsed ConfigAttributes to a store.AgentConfig.
//
//nolint:gocritic // hugeParam: attrs is a large struct but passed by value intentionally for config conversion
func attrsToStoreConfig(name string, attrs customagent.ConfigAttributes) *store.AgentConfig {
	cfg := &store.AgentConfig{
		Name:                   name,
		DisplayName:            attrs.DisplayName,
		Description:            attrs.Description,
		Tools:                  attrs.Tools,
		Target:                 attrs.Target,
		Metadata:               attrs.Metadata,
		ArgumentHint:           attrs.ArgumentHint,
		InferenceEnabled:       attrs.InferenceEnabled,
		DisableModelInvocation: attrs.DisableModelInvocation,
		UserInvocable:          attrs.UserInvocable,
		Model:                  attrs.Model,
		Handoffs:               attrs.Handoffs,
		Permissions:            attrs.Permissions,
		Triggers:               attrs.Triggers,
		GitHubMCPToolsets:      attrs.GitHubMCPToolsets,
		Skills:                 attrs.Skills,
	}

	// Map MCP servers from the parsed mcpconfig format to store format.
	// Sort server names for deterministic ordering to avoid unnecessary upserts.
	serverNames := make([]string, 0, len(attrs.MCPConfig.Servers))
	for name := range attrs.MCPConfig.Servers {
		serverNames = append(serverNames, name)
	}
	sort.Strings(serverNames)

	for _, serverName := range serverNames {
		srv := attrs.MCPConfig.Servers[serverName]
		ms := store.MCPServer{
			Name:  serverName,
			Tools: srv.Tools,
			Type:  srv.Type,
		}
		if srv.Local != nil {
			ms.Command = srv.Command
			ms.Args = srv.Args
			ms.Env = srv.Env
		}
		if srv.Remote != nil {
			ms.URL = srv.URL
			ms.Headers = srv.Headers
			if ms.Type == "" {
				ms.Type = srv.Remote.Type
			}
		}
		cfg.MCPServers = append(cfg.MCPServers, ms)
	}

	return cfg
}

// NoopEnterpriseResolver is an EnterpriseResolver that always returns 0 (no enterprise repo).
type NoopEnterpriseResolver struct{}

// IsEnterpriseAgentRepo always returns 0 and nil.
func (n *NoopEnterpriseResolver) IsEnterpriseAgentRepo(_ context.Context, _ int64) (int64, error) {
	return 0, nil
}

// TwirpEnterpriseResolver uses the SweagentdAPI twirp service to check enterprise agent repos.
type TwirpEnterpriseResolver struct {
	sweagentdAPI sweagentdv1.SweagentdAPI
}

// NewTwirpEnterpriseResolver creates a new TwirpEnterpriseResolver.
func NewTwirpEnterpriseResolver(sweagentdAPI sweagentdv1.SweagentdAPI) *TwirpEnterpriseResolver {
	return &TwirpEnterpriseResolver{sweagentdAPI: sweagentdAPI}
}

// IsEnterpriseAgentRepo checks if the owner has an enterprise with a configured
// agent repo, and returns the configured repository ID if so.
func (r *TwirpEnterpriseResolver) IsEnterpriseAgentRepo(ctx context.Context, ownerID int64) (int64, error) {
	req := &sweagentdv1.EnterpriseAgentsRequest{
		FindAgentsBy: &sweagentdv1.EnterpriseAgentsRequest_OwnerId{
			OwnerId: uint64(ownerID),
		},
	}

	resp, err := r.sweagentdAPI.EnterpriseAgents(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) && twirpErr.Code() == twirp.NotFound {
			return 0, nil
		}
		return 0, goerrors.Errorf("failed to query enterprise agents: %w", err)
	}

	return int64(resp.GetRepositoryId()), nil
}
