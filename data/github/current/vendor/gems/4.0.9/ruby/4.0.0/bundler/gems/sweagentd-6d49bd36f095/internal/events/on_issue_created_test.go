package events

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/store"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/triggers"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

const (
	testAutomationOwnerID = int64(9001)

	customAgentPath   = ".github/agents/issue-agent.md"
	issueOpenedConfig = `---
name: issue-agent
description: issue opened trigger
on:
  issues:
    types: [opened]
---
prompt`

	issueWithoutOpenedConfig = `---
name: issue-agent
description: issue without create trigger
on:
  issues:
    types: [reopened]
---
prompt`

	issueOpenedWithMatchingQueryConfig = `---
name: issue-agent
description: issue with opened trigger and matching query
on:
  issues:
    types: [opened]
    query: "no:label"
---
prompt`

	issueOpenedWithNonMatchingQueryConfig = `---
name: issue-agent
description: issue with opened trigger and non-matching query
on:
  issues:
    types: [opened]
    query: "label:bug"
---
prompt`
)

func TestOnIssueCreated(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job when agent has opened trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, testAutomationOwnerID, service.QueuedJobs()[0].ActorId)
		require.Equal(t, event.AgentID, service.QueuedJobs()[0].AgentId)

		job, err := service.Store.GetJob(context.Background(), event.Owner.ID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		expectedURL := fmt.Sprintf("https://github.com/%s/%s/issues/%d", event.Owner.Login, event.Repo.Name, event.Issue.Number)
		require.Equal(t, expectedURL, job.EventURL, "event URL should be set to the issue HTML URL")
	})

	t.Run("uses automation owner as job actor when provided by runtime config", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		automationOwnerID := testAutomationOwnerID
		handler.automationLookup = &staticAutomationLookup{configs: []automations.RuntimeConfig{{
			CustomAgent:       triggers.AgentFromRecord(agentRecordFromConfig(t, issueOpenedConfig, event.Repo.ID), event.Repo.ID, triggers.RepoInfo{OwnerID: event.Owner.ID, OwnerLogin: event.Owner.Login, RepoName: event.Repo.Name}),
			AutomationID:      "automation-1",
			AutomationOwnerID: automationOwnerID,
		}}}

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, automationOwnerID, service.QueuedJobs()[0].ActorId)

		job, err := service.Store.GetJob(context.Background(), event.Owner.ID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		require.Equal(t, automationOwnerID, job.ActorID)
		require.Equal(t, "test-user", job.ActorLogin)
		require.Equal(t, "automation-1", job.AutomationID)
	})

	t.Run("skips event when runtime config is missing automation owner", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		handler.automationLookup = &staticAutomationLookup{configs: []automations.RuntimeConfig{{
			CustomAgent:  triggers.AgentFromRecord(agentRecordFromConfig(t, issueOpenedConfig, event.Repo.ID), event.Repo.ID, triggers.RepoInfo{OwnerID: event.Owner.ID, OwnerLogin: event.Owner.Login, RepoName: event.Repo.Name}),
			AutomationID: "automation-1",
		}}}

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips event when automation owner lookup fails", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		ghFactory := handler.ghFactory.(*github.NoopClientFactory)
		ghFactory.MockGetUserByID = func(context.Context, uint64) (*gg.User, error) {
			return nil, errors.New("owner lookup failed")
		}

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips event when automation owner lookup returns empty login", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		ghFactory := handler.ghFactory.(*github.NoopClientFactory)
		ghFactory.MockGetUserByID = func(_ context.Context, id uint64) (*gg.User, error) {
			return &gg.User{ID: gg.Ptr(int64(id)), Login: gg.Ptr("")}, nil
		}

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips event when automation owner lacks write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		ghFactory := handler.ghFactory.(*github.NoopClientFactory)
		ghFactory.MockGetUserByID = func(_ context.Context, id uint64) (*gg.User, error) {
			return &gg.User{ID: gg.Ptr(int64(id)), Login: gg.Ptr("automation-owner-read")}, nil
		}

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when issue actor lacks write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		event.Actor = EventActorReader()

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips with require-write reason when issue actor lacks write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		var skippedCounterCalls []stats.Tags
		obsvWithMetrics := observability.NewNoopExporters()
		obsvWithMetrics.Statter = &observability.MockStatter{
			MockCounter: func(key string, tags stats.Tags, _ int64) {
				if key == "triggers.skipped" {
					skippedCounterCalls = append(skippedCounterCalls, tags)
				}
			},
		}

		handler, service, agentID := newIssueCreatedTestHandler(t, obsvWithMetrics, ffClient, issueOpenedConfig)
		handler.automationLookup.(*staticAutomationLookup).configs[0].RequireActorWritePermission = true
		handler.ghTwirp.(*githubtwirp.NoopClient).NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(context.Context, *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{AllowReadAccessTriggers: true}, nil
		}
		event := newIssueCreatedEvent(agentID)
		event.Actor = EventActorReader()

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
		require.Contains(t, skippedCounterCalls, stats.Tags{"trigger_type": "issue_created", "reason": triggerSkipReasonAutomationRequiresActorWrite})
	})

	t.Run("queues job when automation requires write and issue actor has write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		handler.automationLookup.(*staticAutomationLookup).configs[0].RequireActorWritePermission = true
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips when issue actor login is missing", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)
		event.Actor = &Actor{ID: event.Actor.ID}

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when agent lacks opened trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueWithoutOpenedConfig)
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when trigger checker is nil", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, customAgentPath, []byte(issueOpenedConfig)))
		customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		appProvider := agenticapptest.NewTestProvider(t)
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)

		event := newIssueCreatedEvent(appProvider.CopilotApp().AppID())
		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("creates branch without pull request", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		job, err := service.Store.GetJob(context.Background(), event.Owner.ID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		require.NotNil(t, job.Features.Branch, "branch feature should be set")
		require.Equal(t, event.Repo.DefaultBranch, job.Features.Branch.BaseRef)
		require.Empty(t, job.Features.Branch.Name, "branch name should be generated by the job builder")
		require.NotEmpty(t, job.BranchName, "job builder should create a branch name")
		require.NotEqual(t, event.Repo.DefaultBranch, job.BranchName)
		require.Nil(t, job.Features.PullRequest, "pull request feature should never be set")
	})

	t.Run("queues job when query filter matches issue", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		// The mock issue has no labels, so "no:label" should match.
		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedWithMatchingQueryConfig)
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips job when query filter does not match issue", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		// The mock issue has no labels, so "label:bug" should not match.
		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedWithNonMatchingQueryConfig)
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})
}

func newIssueCreatedTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()

	spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, customAgentPath, []byte(agentConfig)))
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	triggerRecord := agentRecordFromConfig(t, agentConfig, 1)
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := runtimeConfigsForIssueAgent(agent)

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func runtimeConfigsForIssueAgent(agent sweagentd.CustomAgent) []automations.RuntimeConfig {
	issueTrigger := agent.Triggers().Issues
	if issueTrigger == nil || !stringSliceContains(issueTrigger.Types, automations.ActivityIssueOpened) {
		return nil
	}
	return []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}
}

type staticAutomationLookup struct {
	configs []automations.RuntimeConfig
}

func (s *staticAutomationLookup) HasActiveForEvent(context.Context, automations.EventMatchRequest) (bool, error) {
	return len(s.configs) > 0, nil
}

func (s *staticAutomationLookup) ListForEvent(context.Context, automations.ListForEventRequest) ([]automations.RuntimeConfig, error) {
	return s.configs, nil
}

func (s *staticAutomationLookup) AutomationsDisabledFromConfig(context.Context, *sweagentdTwirp.ConfigurationForRepositoryResponse, int64, string) bool {
	return false
}

func stringSliceContains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

// agentRecordFromConfig creates a store.AgentRecord from a raw agent config string.
func agentRecordFromConfig(t *testing.T, agentConfig string, repoID int64) *store.AgentRecord {
	t.Helper()

	attrs, err := customagent.ParseConfigForSync(agentConfig, "issue-agent")
	require.NoError(t, err)

	return &store.AgentRecord{
		ID:      uuid.NewString(),
		ScopeID: repoID,
		Path:    customAgentPath,
		Config: store.AgentConfig{
			Name:        "issue-agent",
			DisplayName: attrs.DisplayName,
			Description: attrs.Description,
			Tools:       attrs.Tools,
			Target:      attrs.Target,
			Triggers:    attrs.Triggers,
		},
		TreeOID: "abc123",
	}
}

func newIssueCreatedEvent(agentID int64) IssueCreatedEvent {
	owner := eventActor(et.RepoOwner)
	owner.ID = 456

	repo := EventRepository()
	repo.ID = 1
	repo.OwnerID = owner.ID
	repo.DefaultBranch = "main"

	issue := EventIssue()
	issue.Number = et.IssueNumber

	return IssueCreatedEvent{
		Actor:     EventActorWriter(),
		Repo:      repo,
		Owner:     owner,
		Issue:     issue,
		AgentID:   agentID,
		Timestamp: time.Now(),
	}
}
