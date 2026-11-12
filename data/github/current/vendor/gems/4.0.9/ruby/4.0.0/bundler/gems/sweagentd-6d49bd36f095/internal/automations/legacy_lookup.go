package automations

import (
	"context"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/triggers"
	sweagentdtwirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// NewLegacyLookup adapts the existing custom-agent trigger checker to the
// automation lookup interface. It returns nil when checker is nil so existing
// service/worker split behavior is preserved.
func NewLegacyLookup(checker *triggers.Checker) Lookup {
	if checker == nil {
		return nil
	}
	return &LegacyLookup{checker: checker}
}

// LegacyLookup resolves automations through the existing custom-agent trigger
// checker.
type LegacyLookup struct {
	checker *triggers.Checker
}

// HasActiveForEvent reports whether the legacy custom-agent store has triggers
// for the requested event.
func (l *LegacyLookup) HasActiveForEvent(ctx context.Context, req EventMatchRequest) (bool, error) {
	switch {
	case req.EventName == EventIssues && req.ActivityType == ActivityIssueOpened:
		return l.checker.HasIssueCreatedTriggers(ctx, req.RepoID)
	case req.EventName == EventWorkflowRun && req.ActivityType == ActivityWorkflowRunFailed:
		if !req.workflowConclusionMatches(WorkflowConclusionFailure) {
			return false, nil
		}
		return l.checker.HasWorkflowRunFailedTriggers(ctx, req.RepoID)
	default:
		return false, goerrors.Errorf("unsupported automation event lookup: %s.%s", req.EventName, req.ActivityType)
	}
}

// ListForEvent returns legacy custom-agent-backed runtime configs for the
// requested event.
func (l *LegacyLookup) ListForEvent(ctx context.Context, req ListForEventRequest) ([]RuntimeConfig, error) {
	repo := triggers.RepoInfo{
		OwnerID:    req.Event.OwnerID,
		OwnerLogin: req.Repo.OwnerLogin,
		RepoName:   req.Repo.RepoName,
	}

	switch {
	case req.Event.EventName == EventIssues && req.Event.ActivityType == ActivityIssueOpened:
		agents, err := l.checker.AgentsWithIssueCreatedTriggers(ctx, req.Event.RepoID, repo)
		return runtimeConfigsFromCustomAgents(agents), err
	case req.Event.EventName == EventWorkflowRun && req.Event.ActivityType == ActivityWorkflowRunFailed:
		if !req.Event.workflowConclusionMatches(WorkflowConclusionFailure) {
			return nil, nil
		}
		agents, err := l.checker.AgentsWithWorkflowRunFailedTriggers(ctx, req.Event.RepoID, repo, req.Event.WorkflowName)
		return runtimeConfigsFromCustomAgents(agents), err
	default:
		return nil, goerrors.Errorf("unsupported automation event lookup: %s.%s", req.Event.EventName, req.Event.ActivityType)
	}
}

// AutomationsDisabledFromConfig delegates the existing admin policy gate to the
// legacy checker.
func (l *LegacyLookup) AutomationsDisabledFromConfig(ctx context.Context, cfg *sweagentdtwirp.ConfigurationForRepositoryResponse, repoID int64, triggerType string) bool {
	return l.checker.AutomationsDisabledFromConfig(ctx, cfg, repoID, triggerType)
}

func runtimeConfigsFromCustomAgents(agents []sweagentd.CustomAgent) []RuntimeConfig {
	configs := make([]RuntimeConfig, 0, len(agents))
	for _, agent := range agents {
		configs = append(configs, RuntimeConfig{CustomAgent: agent})
	}
	return configs
}

func (req EventMatchRequest) workflowConclusionMatches(conclusion WorkflowConclusion) bool {
	return req.WorkflowConclusion == "" || req.WorkflowConclusion == conclusion
}
