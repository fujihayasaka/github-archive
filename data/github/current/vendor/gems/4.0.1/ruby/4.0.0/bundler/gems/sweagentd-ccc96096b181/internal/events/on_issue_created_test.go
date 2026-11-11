package events

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/customagent"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/stretchr/testify/require"
)

const (
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
)

func TestOnIssueCreated(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job when agent has opened trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
		})

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueOpenedConfig)
		event := newIssueCreatedEvent(agentID)

		err := handler.OnIssueCreated(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, event.Actor.ID, service.QueuedJobs()[0].ActorId)
		require.Equal(t, event.AgentID, service.QueuedJobs()[0].AgentId)
	})

	t.Run("skips when agent lacks opened trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
		})

		handler, service, agentID := newIssueCreatedTestHandler(t, obsv, ffClient, issueWithoutOpenedConfig)
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

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents)

	return handler, service, appProvider.CopilotApp().AppID()
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
