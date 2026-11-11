// Package triggers evaluates custom agent trigger configurations stored in
// CosmosDB to determine whether incoming events should be processed. It serves
// as the bridge between the agent config store (populated by agentsync) and
// the Hydro event processing pipeline.
package triggers

import (
	"context"
	"slices"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// IssuesTypeOpened represents the "opened" issue event type used in trigger
// configurations following Actions-like syntax.
const IssuesTypeOpened = "opened"

// WorkflowRunTypeFailed represents the "failed" workflow run event type used
// in trigger configurations following Actions-like syntax.
const WorkflowRunTypeFailed = "failed"

// RepoInfo provides repository metadata that isn't stored in agent config
// records but is needed to construct full CustomAgent objects.
type RepoInfo struct {
	OwnerID    int64
	OwnerLogin string
	RepoName   string
}

// agentRecordStore is the subset of store operations needed for trigger evaluation.
type agentRecordStore interface {
	List(ctx context.Context, scopeID int64) ([]*store.AgentRecord, error)
}

// ghTwirpClient is the narrow surface of githubtwirp used by Checker.
type ghTwirpClient interface {
	IsAgentEnabled(ctx context.Context, agentID, userID, repoID int64) (bool, *sweagentdtwirp.ConfigurationForRepositoryResponse, error)
}

// Checker evaluates custom agent trigger configurations from the agent config store.
type Checker struct {
	store   agentRecordStore
	ghTwirp ghTwirpClient
	obsv    observability.Exporters
}

// NewChecker creates a trigger Checker. store may be nil (AgentsWith* then errors);
// ghTwirp may be nil (AutomationsDisabled then reports false).
func NewChecker(store agentRecordStore, ghTwirp ghTwirpClient, obsv observability.Exporters) *Checker {
	return &Checker{store: store, ghTwirp: ghTwirp, obsv: obsv}
}

// HasIssueCreatedTriggers returns true if the repository has any valid agents
// with issue "opened" triggers configured.
func (c *Checker) HasIssueCreatedTriggers(ctx context.Context, repoID int64) (bool, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "triggers.Checker.HasIssueCreatedTriggers")
	defer span.End()

	if c.store == nil {
		return false, goerrors.Errorf("checker: agent record store is not configured")
	}

	records, err := c.store.List(ctx, repoID)
	if err != nil {
		return false, goerrors.Errorf("failed to list agent records for repo %d: %w", repoID, err)
	}

	return slices.ContainsFunc(records, isValidIssueCreatedTrigger), nil
}

// AgentsWithIssueCreatedTriggers returns custom agents that have valid issue
// "opened" triggers configured for the given repository. The returned agents
// are constructed from the stored config records and the provided repo metadata.
func (c *Checker) AgentsWithIssueCreatedTriggers(ctx context.Context, repoID int64, repo RepoInfo) ([]sweagentd.CustomAgent, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "triggers.Checker.AgentsWithIssueCreatedTriggers")
	defer span.End()

	if c.store == nil {
		return nil, goerrors.Errorf("checker: agent record store is not configured")
	}

	records, err := c.store.List(ctx, repoID)
	if err != nil {
		return nil, goerrors.Errorf("failed to list agent records for repo %d: %w", repoID, err)
	}

	records = deduplicateByPath(records)

	var agents []sweagentd.CustomAgent
	for _, record := range records {
		if !isValidIssueCreatedTrigger(record) {
			continue
		}
		agent := AgentFromRecord(record, repoID, repo)
		agents = append(agents, agent)
	}

	return agents, nil
}

// HasWorkflowRunFailedTriggers returns true if the repository has any valid
// agents with workflow_run "failed" triggers configured.
func (c *Checker) HasWorkflowRunFailedTriggers(ctx context.Context, repoID int64) (bool, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "triggers.Checker.HasWorkflowRunFailedTriggers")
	defer span.End()

	if c.store == nil {
		return false, goerrors.Errorf("checker: agent record store is not configured")
	}

	records, err := c.store.List(ctx, repoID)
	if err != nil {
		return false, goerrors.Errorf("failed to list agent records for repo %d: %w", repoID, err)
	}

	return slices.ContainsFunc(records, isValidWorkflowRunFailedTrigger), nil
}

// AgentsWithWorkflowRunFailedTriggers returns custom agents that have valid
// workflow_run "failed" triggers configured for the given repository that match
// the provided workflow name. The trigger must specify an explicit workflows
// list and the workflow name must match one of the entries. Triggers without
// a workflows list are skipped because the workflow_run trigger is opt-in only.
func (c *Checker) AgentsWithWorkflowRunFailedTriggers(ctx context.Context, repoID int64, repo RepoInfo, workflowName string) ([]sweagentd.CustomAgent, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "triggers.Checker.AgentsWithWorkflowRunFailedTriggers")
	defer span.End()

	if c.store == nil {
		return nil, goerrors.Errorf("checker: agent record store is not configured")
	}

	records, err := c.store.List(ctx, repoID)
	if err != nil {
		return nil, goerrors.Errorf("failed to list agent records for repo %d: %w", repoID, err)
	}

	records = deduplicateByPath(records)

	var agents []sweagentd.CustomAgent
	for _, record := range records {
		if !isValidWorkflowRunFailedTrigger(record) {
			continue
		}
		if !workflowNameMatches(record.Config.Triggers.WorkflowRun, workflowName) {
			continue
		}
		agent := AgentFromRecord(record, repoID, repo)
		agents = append(agents, agent)
	}

	return agents, nil
}

// AutomationsDisabledFromConfig is the admin automations policy gate for callers
// that already hold a cfg. Returns true when the dotcom admin has set the
// policy and the trigger should be skipped.
func (c *Checker) AutomationsDisabledFromConfig(ctx context.Context, cfg *sweagentdtwirp.ConfigurationForRepositoryResponse, repoID int64, triggerType string) bool {
	ctx, span := c.obsv.Tracer.Start(ctx, "triggers.Checker.AutomationsDisabledFromConfig")
	defer span.End()

	if !cfg.GetAutomationsDisabled() {
		return false
	}
	c.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.String("trigger_type", triggerType),
		kvp.Int64("repo_id", repoID),
	).Info("triggered automations disabled for repository, skipping")
	c.obsv.Increment(ctx, "triggers.skipped", stats.Tags{
		"trigger_type": triggerType,
		"reason":       "automations_disabled",
	})
	return true
}

// AutomationsDisabled is the admin policy gate for callers without a cfg in hand
// (the scheduler today). Fetches via Twirp and delegates to AutomationsDisabledFromConfig.
func (c *Checker) AutomationsDisabled(ctx context.Context, agentID, actorID, repoID int64, triggerType string) (bool, error) {
	ctx, span := c.obsv.Tracer.Start(ctx, "triggers.Checker.AutomationsDisabled")
	defer span.End()

	if c.ghTwirp == nil {
		return false, nil
	}
	_, cfg, err := c.ghTwirp.IsAgentEnabled(ctx, agentID, actorID, repoID)
	if err != nil {
		return false, goerrors.Errorf("failed to check IsAgentEnabled for repo %d: %w", repoID, err)
	}
	return c.AutomationsDisabledFromConfig(ctx, cfg, repoID, triggerType), nil
}

// isValidIssueCreatedTrigger checks whether an agent record represents a valid
// agent with an issue "opened" trigger. Records with sync errors or targeting
// only VS Code are excluded.
func isValidIssueCreatedTrigger(record *store.AgentRecord) bool {
	if record.SyncError != "" {
		return false
	}

	target := record.Config.Target
	if target != "" && target != customagent.TargetGitHubCopilot {
		return false
	}

	triggers := record.Config.Triggers
	if triggers.Issues == nil {
		return false
	}

	return slices.Contains(triggers.Issues.Types, IssuesTypeOpened)
}

// isValidWorkflowRunFailedTrigger checks whether an agent record represents a
// valid agent with a workflow_run "failed" trigger. Records with sync errors or
// targeting only VS Code are excluded. The trigger must specify an explicit
// workflows list — triggers without workflows are not valid because the
// workflow_run trigger is opt-in only.
func isValidWorkflowRunFailedTrigger(record *store.AgentRecord) bool {
	if record.SyncError != "" {
		return false
	}

	target := record.Config.Target
	if target != "" && target != customagent.TargetGitHubCopilot {
		return false
	}

	triggers := record.Config.Triggers
	if triggers.WorkflowRun == nil {
		return false
	}

	if len(triggers.WorkflowRun.Workflows) == 0 {
		return false
	}

	return slices.Contains(triggers.WorkflowRun.Types, WorkflowRunTypeFailed)
}

// workflowNameMatches returns true if the provided workflow name matches the
// agent's trigger configuration. The trigger must specify an explicit workflows
// list — triggers without workflows do not match any workflow because the
// workflow_run trigger is opt-in only. The workflow name is the display name
// from the GitHub API (the `name:` field in the workflow YAML), consistent with
// GitHub Actions workflow_run trigger semantics. Matching is case-insensitive.
func workflowNameMatches(trigger *sweagentd.CustomAgentWorkflowRunTrigger, workflowName string) bool {
	if trigger == nil || len(trigger.Workflows) == 0 {
		return false
	}

	return slices.ContainsFunc(trigger.Workflows, func(w string) bool {
		return strings.EqualFold(w, workflowName)
	})
}

// NormalizeWorkflowName strips .yml and .yaml extensions from a workflow name
// for consistent matching between trigger configs and actual workflow paths.
func NormalizeWorkflowName(name string) string {
	if n, found := strings.CutSuffix(name, ".yaml"); found {
		return n
	}
	if n, found := strings.CutSuffix(name, ".yml"); found {
		return n
	}
	return name
}

// isMoreRecentRecord returns true if a should be preferred over b when
// deduplicating records for the same path. It uses SyncedAt, then UpdatedAt,
// then ID as a deterministic tie-breaker so the result doesn't depend on
// input slice order.
func isMoreRecentRecord(a, b *store.AgentRecord) bool {
	if a.SyncedAt != b.SyncedAt {
		return a.SyncedAt > b.SyncedAt
	}
	if a.UpdatedAt != b.UpdatedAt {
		return a.UpdatedAt > b.UpdatedAt
	}
	return a.ID > b.ID
}

// deduplicateByPath returns at most one record per file path, keeping the most
// recently synced entry. Concurrent agent reconciliations can create duplicate
// CosmosDB documents for the same agent file; this prevents duplicate job
// creation until the reconciler's full-sync cleanup runs.
func deduplicateByPath(records []*store.AgentRecord) []*store.AgentRecord {
	seen := make(map[string]*store.AgentRecord, len(records))
	for _, r := range records {
		if existing, ok := seen[r.Path]; !ok || isMoreRecentRecord(r, existing) {
			seen[r.Path] = r
		}
	}
	deduped := make([]*store.AgentRecord, 0, len(seen))
	for _, r := range records {
		if seen[r.Path] == r {
			deduped = append(deduped, r)
		}
	}
	return deduped
}

// AgentFromRecord converts a store.AgentRecord to a sweagentd.CustomAgent using
// repo metadata from the event context. When MCP servers are configured, it
// returns a PrivilegedAgent so the MCP config is available downstream.
func AgentFromRecord(record *store.AgentRecord, repoID int64, repo RepoInfo) sweagentd.CustomAgent {
	metadata := customagent.Metadata{
		Name:        record.Config.Name,
		RepoID:      repoID,
		RepoOwnerID: repo.OwnerID,
		RepoOwner:   repo.OwnerLogin,
		RepoName:    repo.RepoName,
		Version:     record.TreeOID,
		Scope:       agentconfig.ScopeRepository,
	}

	attrs := customagent.ConfigAttributes{
		DisplayName:            record.Config.DisplayName,
		Description:            record.Config.Description,
		Tools:                  record.Config.Tools,
		Target:                 record.Config.Target,
		Metadata:               record.Config.Metadata,
		ArgumentHint:           record.Config.ArgumentHint,
		InferenceEnabled:       record.Config.InferenceEnabled,
		DisableModelInvocation: record.Config.DisableModelInvocation,
		UserInvocable:          record.Config.UserInvocable,
		Model:                  record.Config.Model,
		Handoffs:               record.Config.Handoffs,
		Triggers:               record.Config.Triggers,
		Permissions:            record.Config.Permissions,
		MCPConfig:              mcpConfigFromStoreServers(record.Config.MCPServers),
		GitHubMCPToolsets:      record.Config.GitHubMCPToolsets,
		Skills:                 record.Config.Skills,
	}

	agent := customagent.NewWithConfig(metadata, customagent.NewConfigWithAttributes(attrs))

	if len(record.Config.MCPServers) > 0 {
		return customagent.NewPrivilegedAgent(agent)
	}

	return agent
}

// mcpConfigFromStoreServers converts store MCP server records to mcpconfig.JSON.
func mcpConfigFromStoreServers(servers []store.MCPServer) mcpconfig.JSON {
	out := mcpconfig.JSON{
		Servers: make(map[string]mcpconfig.Server, len(servers)),
	}
	for _, s := range servers {
		server := mcpconfig.Server{
			Type:  s.Type,
			Tools: s.Tools,
		}
		if mcpconfig.IsLocal(s.Type) {
			server.Local = &mcpconfig.Local{
				Command: s.Command,
				Args:    s.Args,
				Env:     s.Env,
			}
		}
		if mcpconfig.IsRemote(s.Type) {
			server.Remote = &mcpconfig.Remote{
				URL:     s.URL,
				Headers: s.Headers,
			}
		}
		out.Servers[s.Name] = server
	}
	return out
}
