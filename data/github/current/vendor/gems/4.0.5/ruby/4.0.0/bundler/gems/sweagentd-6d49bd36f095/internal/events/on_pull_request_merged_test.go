package events

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/customagent"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/triggers"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

const (
	pullRequestMergedAgentPath   = ".github/agents/pr-merged-agent.md"
	pullRequestMergedAgentConfig = `---
name: pr-merged-agent
description: pull_request merged trigger
on:
  pull_request_merged:
    types: [merged]
---
prompt`

	pullRequestMergedWithoutMergedConfig = `---
name: pr-merged-agent
description: pull_request without merged trigger
on:
  pull_request_opened:
    types: [opened]
---
prompt`

	pullRequestMergedWithNonMatchingQueryConfig = `---
name: pr-merged-agent
description: pull_request merged with non-matching filter
on:
  pull_request_merged:
    types: [merged]
    query: label:bug
---
prompt`

	pullRequestMergedWithPathsConfig = `---
name: pr-merged-agent
description: pull_request merged with paths filter
on:
  pull_request_merged:
    types: [merged]
    paths:
      - "src/**"
---
prompt`
)

func TestFirePullRequestMergedTriggers(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job when agent has merged trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedAgentConfig)
		event := newPullRequestMergedEvent()

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, testAutomationOwnerID, service.QueuedJobs()[0].ActorId)

		// Verify the cancellation-race defense: the worker-built assignment must
		// not carry the PR ID/number, so the Service cancellation sweep can't match it.
		job, err := service.Store.GetJob(context.Background(), event.Repo.OwnerID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		assignment, err := service.Store.GetAssignment(context.Background(), event.Repo.OwnerID, event.Repo.ID, job.AssignmentID)
		require.NoError(t, err)
		require.Zero(t, assignment.PullRequestID, "merged-trigger assignment must not record PR ID")
		require.Zero(t, assignment.PullRequestNumber, "merged-trigger assignment must not record PR number")
	})

	t.Run("skips when automation lookup returns no matching configs", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedAgentConfig)
		event := newPullRequestMergedEvent()
		handler.automationLookup = &staticAutomationLookup{configs: nil}

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when PR is not merged", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedAgentConfig)
		event := newPullRequestMergedEvent()
		event.PullRequest.State = PullRequestStateClosed

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when no matching automations", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedWithoutMergedConfig)
		event := newPullRequestMergedEvent()

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips job when query filter does not match pull request", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedWithNonMatchingQueryConfig)
		event := newPullRequestMergedEvent()

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("queues job when paths filter matches changed files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFiles = []*gg.CommitFile{{Filename: gg.Ptr("src/foo.go")}}
			},
		)
		event := newPullRequestMergedEvent()

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips job when paths filter does not match changed files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFiles = []*gg.CommitFile{{Filename: gg.Ptr("README.md")}}
			},
		)
		event := newPullRequestMergedEvent()

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips job when paths filter API errors (fail-closed)", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newPullRequestMergedTestHandler(t, obsv, ffClient, pullRequestMergedWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFilesErr = goerrors.New("github API down")
			},
		)
		event := newPullRequestMergedEvent()

		err := handler.firePullRequestMergedTriggers(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})
}

func newPullRequestMergedTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, opts ...func(*github.NoopClientFactory)) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()

	spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, pullRequestMergedAgentPath, []byte(agentConfig)))
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	for _, opt := range opts {
		opt(ghFactory)
	}

	triggerRecord := agentRecordFromConfig(t, agentConfig, 1)
	triggerRecord.Path = pullRequestMergedAgentPath
	triggerRecord.Config.Name = "pr-merged-agent"
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := runtimeConfigsForPullRequestMergedAgent(agent)

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func runtimeConfigsForPullRequestMergedAgent(agent sweagentd.CustomAgent) []automations.RuntimeConfig {
	pr := agent.Triggers().PullRequestMerged
	if pr == nil {
		return nil
	}
	return []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}
}

func newPullRequestMergedEvent() PullRequestStateChangedEvent {
	repo := EventRepository()
	repo.ID = 1
	repo.OwnerID = 456
	repo.DefaultBranch = "main"

	pr := &PullRequest{
		ID:         200,
		NodeID:     "PR_pr-merged",
		Number:     et.PullRequestNumber,
		State:      PullRequestStateMerged,
		HeadBranch: "feature-branch",
		BaseBranch: "main",
	}

	return PullRequestStateChangedEvent{
		Actor:       EventActorWriter(),
		Repo:        repo,
		PullRequest: pr,
		Timestamp:   time.Now(),
	}
}
