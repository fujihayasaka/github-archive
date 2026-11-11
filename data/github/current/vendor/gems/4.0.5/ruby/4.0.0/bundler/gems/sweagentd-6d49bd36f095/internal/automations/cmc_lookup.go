package automations

import (
	"context"
	"slices"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/mcp/mcpconfig"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/permissions"
	cmcautomationsv1 "github.com/github/sweagentd/internal/proto/twirp/automations/v1"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

const (
	cmcListPageSize             = 100
	cmcListMaxPages             = 10
	cmcWorkflowRunTypeCompleted = "completed"
)

// CMC catalog event names for pull-request triggers (one entry per activity so github-ui can render distinct picker cards).
const (
	cmcEventPullRequestOpened      = string(EventPullRequestOpened)
	cmcEventPullRequestSynchronize = string(EventPullRequestSynchronize)
	cmcEventPullRequestMerged      = string(EventPullRequestMerged)
)

// CMCLookup resolves automations through CMC's runtime lookup API.
type CMCLookup struct {
	automationsClient cmcautomationsv1.AutomationsAPI
	legacy            Lookup
	obsv              observability.Exporters
	requestTimeout    time.Duration
}

// NewCMCLookup creates a CMC-backed automation lookup.
func NewCMCLookup(automationsClient cmcautomationsv1.AutomationsAPI, legacy Lookup, obsv observability.Exporters, requestTimeout time.Duration) Lookup {
	return &CMCLookup{automationsClient: automationsClient, legacy: legacy, obsv: obsv, requestTimeout: requestTimeout}
}

// HasActiveForEvent reports whether CMC has any runtime-visible automation for
// the coarse repository event. Event-specific fields like workflow name are
// intentionally handled by ListForEvent so this hot-path gate stays cheap.
func (l *CMCLookup) HasActiveForEvent(ctx context.Context, req EventMatchRequest) (bool, error) {
	tags := cmcLookupMetricTags(req, cmcLookupOperationHas)
	cmcReq, disposition := cmcRequestForEvent(req)
	switch disposition {
	case cmcEventIgnored:
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeSkipped}))
		return false, nil
	case cmcEventUnsupported:
		err := unsupportedAutomationEventError(req.EventName, req.ActivityType)
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeUnsupported}))
		return false, err
	}

	// HasActiveForEvent performs a single CMC request, so this bounds the whole lookup.
	ctx, cancel := l.withRequestTimeout(ctx)
	defer cancel()

	resp, err := l.automationsClient.HasRepositoryAutomation(ctx, &cmcautomationsv1.HasRepositoryAutomationRequest{
		OwnerId: uint64(req.OwnerID),
		RepoId:  uint64(req.RepoID),
		Event:   cmcReq.event,
		Types:   cmcReq.types,
	})
	if err != nil {
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeError}))
		return false, goerrors.Errorf("failed to query CMC automation presence: %w", err)
	}
	if resp == nil {
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeNilResponse}))
		l.obsv.LoggerWithTelemetry(ctx).Warn("CMC automation presence response is nil")
		return false, nil
	}
	l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeSuccess}))
	return resp.GetHasAutomation(), nil
}

// ListForEvent returns CMC-backed runtime configs that are safe to launch for
// the provided event. CMC performs coarse event/type filtering; sweagentd keeps
// local filtering for trigger fields that depend on the full event payload.
//
// When req.AutomationID is set, only that specific automation is returned
// (used for on-demand automation run requests). Trigger matching is skipped in this case.
func (l *CMCLookup) ListForEvent(ctx context.Context, req ListForEventRequest) ([]RuntimeConfig, error) {
	tags := cmcLookupMetricTags(req.Event, cmcLookupOperationList)

	// When a specific automation ID is requested (run request), fetch it directly
	// without event/trigger filtering.
	if req.AutomationID != "" {
		return l.getAutomationByID(ctx, req, tags)
	}

	cmcReq, disposition := cmcRequestForEvent(req.Event)
	switch disposition {
	case cmcEventIgnored:
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeSkipped}))
		return nil, nil
	case cmcEventUnsupported:
		err := unsupportedAutomationEventError(req.Event.EventName, req.Event.ActivityType)
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeUnsupported}))
		return nil, err
	}

	var configs []RuntimeConfig
	pages := 0
	for pageNumber := range cmcListMaxPages {
		// Apply the configured timeout per CMC page request. The page cap bounds
		// the total list operation without making healthy multi-page lookups fail early.
		requestCtx, cancel := l.withRequestTimeout(ctx)
		resp, err := l.automationsClient.ListRepositoryAutomations(requestCtx, &cmcautomationsv1.ListRepositoryAutomationsRequest{
			OwnerId:  uint64(req.Event.OwnerID),
			RepoId:   uint64(req.Event.RepoID),
			Event:    cmcReq.event,
			Types:    cmcReq.types,
			PageSize: cmcListPageSize,
			// CMC ListOptions treats page numbers as one-based.
			PageNumber: int32(pageNumber + 1),
		})
		cancel()
		if err != nil {
			l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeError}))
			return nil, goerrors.Errorf("failed to list CMC automations: %w", err)
		}
		if resp == nil {
			l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeNilResponse}))
			return nil, goerrors.New("CMC automation list response is nil")
		}
		pages++

		for _, automation := range resp.GetAutomations() {
			if !automationMatchesEvent(automation, req.Event) {
				continue
			}
			agent, err := customAgentFromCMCAutomation(ctx, l.obsv, tags, automation, req.Repo)
			if err != nil {
				l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeInvalidPermissions}))
				l.obsv.LoggerWithTelemetry(ctx).WithError(err).WithFields(
					kvp.String("automation_id", automation.GetId()),
				).Warn("Skipping CMC automation with invalid permissions")
				continue
			}
			configs = append(configs, RuntimeConfig{
				CustomAgent:                 agent,
				AutomationID:                automation.GetId(),
				AutomationOwnerID:           int64(automation.GetUserId()),
				RequireActorWritePermission: automation.GetRequireActorWritePermission(),
			})
		}

		if !resp.GetHasNextPage() {
			l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeSuccess}))
			l.obsv.Distribution(ctx, "automations.lookup_pages", tags, float64(pages))
			return configs, nil
		}
	}

	l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomePaginationCap}))
	l.obsv.Distribution(ctx, "automations.lookup_pages", tags, float64(pages))
	l.obsv.LoggerWithTelemetry(ctx).WithFields(
		kvp.Int("max_pages", cmcListMaxPages),
		kvp.Int64("owner_id", req.Event.OwnerID),
		kvp.Int("page_size", cmcListPageSize),
		kvp.Int64("repo_id", req.Event.RepoID),
	).Warn("CMC automation lookup reached pagination cap")
	return configs, nil
}

// AutomationsDisabledFromConfig delegates the existing monolith admin policy gate
// to the legacy implementation.
func (l *CMCLookup) AutomationsDisabledFromConfig(ctx context.Context, cfg *sweagentdtwirp.ConfigurationForRepositoryResponse, repoID int64, triggerType string) bool {
	if l.legacy == nil {
		return false
	}
	return l.legacy.AutomationsDisabledFromConfig(ctx, cfg, repoID, triggerType)
}

type cmcEventRequest struct {
	event string
	types []string
}

type cmcEventDisposition int

const (
	cmcEventSupported cmcEventDisposition = iota
	cmcEventIgnored
	cmcEventUnsupported
)

func cmcRequestForEvent(req EventMatchRequest) (cmcEventRequest, cmcEventDisposition) {
	switch {
	case req.EventName == EventIssues && req.ActivityType == ActivityIssueOpened:
		return cmcEventRequest{event: string(EventIssues), types: []string{ActivityIssueOpened}}, cmcEventSupported
	case req.EventName == EventWorkflowRun && req.ActivityType == ActivityWorkflowRunFailed:
		if !req.workflowConclusionMatches(WorkflowConclusionFailure) {
			return cmcEventRequest{}, cmcEventIgnored
		}
		return cmcEventRequest{event: string(EventWorkflowRun), types: []string{cmcWorkflowRunTypeCompleted}}, cmcEventSupported
	case req.EventName == EventInterval:
		return cmcEventRequest{event: string(EventInterval)}, cmcEventSupported
	case req.EventName == EventPullRequest && req.ActivityType == ActivityPullRequestOpened:
		return cmcEventRequest{event: cmcEventPullRequestOpened, types: []string{ActivityPullRequestOpened}}, cmcEventSupported
	case req.EventName == EventPullRequest && req.ActivityType == ActivityPullRequestMerged:
		return cmcEventRequest{event: cmcEventPullRequestMerged, types: []string{ActivityPullRequestMerged}}, cmcEventSupported
	case req.EventName == EventPullRequest && req.ActivityType == ActivityPullRequestSynchronize:
		return cmcEventRequest{event: cmcEventPullRequestSynchronize, types: []string{ActivityPullRequestSynchronize}}, cmcEventSupported
	default:
		return cmcEventRequest{}, cmcEventUnsupported
	}
}

func automationMatchesEvent(a *cmcautomationsv1.Automation, req EventMatchRequest) bool {
	if a == nil {
		return false
	}
	for _, trigger := range a.GetTriggers() {
		if triggerMatchesEvent(trigger, req) {
			return true
		}
	}
	return false
}

func triggerMatchesEvent(trigger *cmcautomationsv1.AutomationTrigger, req EventMatchRequest) bool {
	if trigger == nil {
		return false
	}
	cmcReq, disposition := cmcRequestForEvent(req)
	if disposition != cmcEventSupported {
		return false
	}
	if trigger.GetEvent() != cmcReq.event {
		return false
	}
	if req.EventName == EventInterval {
		return true
	}
	if !triggerTypesMatch(trigger.GetTypes(), cmcReq.types) {
		return false
	}

	switch req.EventName {
	case EventIssues, EventInterval, EventPullRequest:
		return true
	case EventWorkflowRun:
		return workflowTriggerMatches(trigger, req)
	default:
		return false
	}
}

func triggerTypesMatch(triggerTypes, eventTypes []string) bool {
	return slices.ContainsFunc(eventTypes, func(eventType string) bool {
		return slices.Contains(triggerTypes, eventType)
	})
}

func workflowTriggerMatches(trigger *cmcautomationsv1.AutomationTrigger, req EventMatchRequest) bool {
	if !workflowNameMatches(trigger.GetWorkflows(), req.WorkflowName) {
		return false
	}
	if req.WorkflowConclusion == "" || len(trigger.GetConclusions()) == 0 {
		return true
	}
	return slices.ContainsFunc(trigger.GetConclusions(), func(conclusion string) bool {
		return strings.EqualFold(conclusion, string(req.WorkflowConclusion))
	})
}

func workflowNameMatches(workflows []string, workflowName string) bool {
	if len(workflows) == 0 {
		return false
	}
	return slices.ContainsFunc(workflows, func(workflow string) bool {
		return strings.EqualFold(workflow, workflowName)
	})
}

const (
	cmcLookupOperationHas  = "has"
	cmcLookupOperationList = "list"

	cmcLookupOutcomeError              = "error"
	cmcLookupOutcomeInvalidPermissions = "invalid_permissions"
	cmcLookupOutcomeNilResponse        = "nil_response"
	cmcLookupOutcomePaginationCap      = "pagination_cap"
	cmcLookupOutcomeSkipped            = "skipped"
	cmcLookupOutcomeSuccess            = "success"
	cmcLookupOutcomeUnsupported        = "unsupported"
	cmcLookupOutcomeUnsupportedMCP     = "unsupported_mcp"
)

func cmcLookupMetricTags(req EventMatchRequest, operation string) stats.Tags {
	return stats.Tags{
		"activity_type": metricTagValue(req.ActivityType),
		"backend":       "cmc",
		"event":         metricTagValue(string(req.EventName)),
		"operation":     operation,
	}
}

func metricTagValue(value string) string {
	if value == "" {
		return "unknown"
	}
	return value
}

func customAgentFromCMCAutomation(ctx context.Context, obsv observability.Exporters, tags stats.Tags, a *cmcautomationsv1.Automation, repo RepoInfo) (sweagentd.CustomAgent, error) {
	if a == nil {
		return nil, goerrors.New("CMC automation is nil")
	}

	perms := permissions.New(a.GetPermissions())
	err := perms.Validate()
	if err != nil {
		return nil, goerrors.Errorf("invalid permissions for CMC automation %q: %w", a.GetId(), err)
	}

	name := a.GetName()
	if name == "" {
		name = a.GetId()
	}

	metadata := customagent.Metadata{
		Name:        name,
		RepoID:      int64(a.GetRepoId()),
		RepoOwnerID: int64(a.GetOwnerId()),
		RepoOwner:   repo.OwnerLogin,
		RepoName:    repo.RepoName,
		// Job-scoped agents still need a Version value; use the CMC automation
		// ID until execution stores automation identity separately.
		Version: a.GetId(),
		Scope:   agentconfig.ScopeJob,
	}

	attrs := customagent.ConfigAttributes{
		DisplayName:       a.GetName(),
		Description:       a.GetDescription(),
		Prompt:            a.GetPrompt(),
		Tools:             append([]string(nil), a.GetTools()...),
		Permissions:       perms,
		MCPConfig:         mcpConfigFromCMCAutomation(ctx, obsv, tags, a.GetId(), a.GetMcpServers()),
		GitHubMCPToolsets: append([]string(nil), a.GetGithubMcpToolsets()...),
		Model:             a.GetModel(),
		Triggers:          customAgentTriggersFromCMCAutomation(a.GetTriggers()),
	}

	return customagent.NewJobScopedAgent(metadata, customagent.NewConfigWithAttributes(attrs)), nil
}

func customAgentTriggersFromCMCAutomation(triggers []*cmcautomationsv1.AutomationTrigger) sweagentd.CustomAgentTriggers {
	var out sweagentd.CustomAgentTriggers
	for _, trigger := range triggers {
		if trigger == nil {
			continue
		}
		switch trigger.GetEvent() {
		case string(EventIssues):
			if out.Issues == nil {
				out.Issues = &sweagentd.CustomAgentTrigger{}
			}
			out.Issues.Types = append(out.Issues.Types, trigger.GetTypes()...)
			if out.Issues.Query == "" {
				out.Issues.Query = trigger.GetQuery()
			}
		case string(EventInterval):
			if out.Interval == nil {
				out.Interval = &sweagentd.CustomAgentIntervalTrigger{}
			}
			out.Interval.Types = append(out.Interval.Types, trigger.GetTypes()...)
		case string(EventWorkflowRun):
			if out.WorkflowRun == nil {
				out.WorkflowRun = &sweagentd.CustomAgentWorkflowRunTrigger{}
			}
			out.WorkflowRun.Types = append(out.WorkflowRun.Types, trigger.GetTypes()...)
			out.WorkflowRun.Workflows = append(out.WorkflowRun.Workflows, trigger.GetWorkflows()...)
		case cmcEventPullRequestOpened:
			if out.PullRequestOpened == nil {
				out.PullRequestOpened = &sweagentd.CustomAgentPullRequestTrigger{}
			}
			out.PullRequestOpened.Types = append(out.PullRequestOpened.Types, trigger.GetTypes()...)
			if out.PullRequestOpened.Query == "" {
				out.PullRequestOpened.Query = trigger.GetQuery()
			}
			if len(out.PullRequestOpened.Paths) == 0 {
				out.PullRequestOpened.Paths = append(out.PullRequestOpened.Paths, trigger.GetPaths()...)
			}
		case cmcEventPullRequestSynchronize:
			if out.PullRequestSynchronize == nil {
				out.PullRequestSynchronize = &sweagentd.CustomAgentPullRequestTrigger{}
			}
			out.PullRequestSynchronize.Types = append(out.PullRequestSynchronize.Types, trigger.GetTypes()...)
			if out.PullRequestSynchronize.Query == "" {
				out.PullRequestSynchronize.Query = trigger.GetQuery()
			}
			if len(out.PullRequestSynchronize.Paths) == 0 {
				out.PullRequestSynchronize.Paths = append(out.PullRequestSynchronize.Paths, trigger.GetPaths()...)
			}
		case cmcEventPullRequestMerged:
			if out.PullRequestMerged == nil {
				out.PullRequestMerged = &sweagentd.CustomAgentPullRequestTrigger{}
			}
			out.PullRequestMerged.Types = append(out.PullRequestMerged.Types, trigger.GetTypes()...)
			if out.PullRequestMerged.Query == "" {
				out.PullRequestMerged.Query = trigger.GetQuery()
			}
			if len(out.PullRequestMerged.Paths) == 0 {
				out.PullRequestMerged.Paths = append(out.PullRequestMerged.Paths, trigger.GetPaths()...)
			}
		default:
			continue
		}
	}
	return out
}

func mcpConfigFromCMCAutomation(ctx context.Context, obsv observability.Exporters, tags stats.Tags, automationID string, servers []*cmcautomationsv1.MCPServer) mcpconfig.JSON {
	out := mcpconfig.JSON{Servers: make(map[string]mcpconfig.Server, len(servers))}
	for _, s := range servers {
		if s == nil || s.GetName() == "" {
			continue
		}
		if !mcpconfig.IsRemote(s.GetType()) {
			obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeUnsupportedMCP}))
			obsv.LoggerWithTelemetry(ctx).WithFields(
				kvp.String("automation_id", automationID),
				kvp.String("mcp_server_name", s.GetName()),
				kvp.String("mcp_server_type", metricTagValue(s.GetType())),
			).Warn("Skipping non-remote CMC MCP server")
			continue
		}
		server := mcpconfig.Server{
			Type:  s.GetType(),
			Tools: append([]string(nil), s.GetTools()...),
			Remote: &mcpconfig.Remote{
				URL: s.GetUrl(),
			},
		}
		// CMC automations/v1 exposes name/type/url/tools. It does not yet expose
		// remote headers or auth/OIDC config.
		out.Servers[s.GetName()] = server
	}
	return out
}

func unsupportedAutomationEventError(eventName EventName, activityType string) error {
	return goerrors.Errorf("unsupported automation event lookup: %s.%s", eventName, activityType)
}

// getAutomationByID fetches a single automation by ID from CMC for run requests.
// It skips event/trigger matching since run requests target a specific automation.
func (l *CMCLookup) getAutomationByID(ctx context.Context, req ListForEventRequest, tags stats.Tags) ([]RuntimeConfig, error) {
	ctx, cancel := l.withRequestTimeout(ctx)
	defer cancel()

	resp, err := l.automationsClient.GetAutomationByID(ctx, &cmcautomationsv1.GetAutomationByIDRequest{
		AutomationId: req.AutomationID,
		OwnerId:      uint64(req.Event.OwnerID),
		RepoId:       uint64(req.Event.RepoID),
	})
	if err != nil {
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeError}))
		return nil, goerrors.Errorf("failed to get automation by ID from CMC: %w", err)
	}
	if resp == nil || resp.GetAutomation() == nil {
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeNilResponse}))
		return nil, goerrors.Errorf("automation %s not found in CMC", req.AutomationID)
	}

	automation := resp.GetAutomation()
	agent, err := customAgentFromCMCAutomation(ctx, l.obsv, tags, automation, req.Repo)
	if err != nil {
		l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeInvalidPermissions}))
		return nil, goerrors.Errorf("automation %s has invalid config: %w", req.AutomationID, err)
	}

	l.obsv.Increment(ctx, "automations.lookup", tags.Merge(stats.Tags{"outcome": cmcLookupOutcomeSuccess}))
	return []RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      automation.GetId(),
		AutomationOwnerID: int64(automation.GetUserId()),
	}}, nil
}

func (l *CMCLookup) withRequestTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	if l.requestTimeout <= 0 {
		return ctx, func() {}
	}
	return context.WithTimeout(ctx, l.requestTimeout)
}
