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
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/triggers"
	gg "github.com/google/go-github/v75/github"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

const (
	pullRequestSynchronizeAgentPath   = ".github/agents/pr-sync-agent.md"
	pullRequestSynchronizeAgentConfig = `---
name: pr-sync-agent
description: pull_request synchronize trigger
on:
  pull_request_synchronize:
    types: [synchronize]
---
prompt`

	pullRequestSynchronizeWithoutSyncConfig = `---
name: pr-sync-agent
description: pull_request without synchronize trigger
on:
  pull_request_opened:
    types: [opened]
---
prompt`

	pullRequestSynchronizeWithNonMatchingQueryConfig = `---
name: pr-sync-agent
description: pull_request synchronize with non-matching filter
on:
  pull_request_synchronize:
    types: [synchronize]
    query: label:bug
---
prompt`

	pullRequestSynchronizeWithPathsConfig = `---
name: pr-sync-agent
description: pull_request synchronize with paths filter
on:
  pull_request_synchronize:
    types: [synchronize]
    paths:
      - "src/**"
---
prompt`
)

func TestOnPullRequestSynchronize(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job when agent has synchronize trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeAgentConfig)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, testAutomationOwnerID, service.QueuedJobs()[0].ActorId)
		require.Equal(t, event.AgentID, service.QueuedJobs()[0].AgentId)

		job, err := service.Store.GetJob(context.Background(), event.Repo.OwnerID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		require.Equal(t, "automation-1", job.AutomationID)
		require.Equal(t, "feature-branch", job.BranchName)
	})

	t.Run("skips when pull request is from a fork", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeAgentConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequest = &gg.PullRequest{
					ID:     gg.Ptr(int64(200)),
					Number: gg.Ptr(et.PullRequestNumber),
					Base:   &gg.PullRequestBranch{Repo: &gg.Repository{ID: gg.Ptr(int64(1))}},
					Head:   &gg.PullRequestBranch{Repo: &gg.Repository{ID: gg.Ptr(int64(9999))}},
				}
			},
		)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when head repo is unknown (fail closed)", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeAgentConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequest = &gg.PullRequest{
					ID:     gg.Ptr(int64(200)),
					Number: gg.Ptr(et.PullRequestNumber),
					Base:   &gg.PullRequestBranch{Repo: &gg.Repository{ID: gg.Ptr(int64(1))}},
					Head:   &gg.PullRequestBranch{Ref: gg.Ptr("feature-branch")},
				}
			},
		)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when no automation lookup is configured", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeAgentConfig)
		event := newPullRequestSynchronizeEvent(agentID)
		handler.automationLookup = nil

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when no matching automations", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeWithoutSyncConfig)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips job when query filter does not match pull request", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeWithNonMatchingQueryConfig)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("queues job when paths filter matches changed files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFiles = []*gg.CommitFile{{Filename: gg.Ptr("src/foo.go")}}
			},
		)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips job when paths filter does not match changed files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFiles = []*gg.CommitFile{{Filename: gg.Ptr("README.md")}}
			},
		)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips job when paths filter API errors (fail-closed)", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFilesErr = goerrors.New("github API down")
			},
		)
		event := newPullRequestSynchronizeEvent(agentID)

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when head branch equals default branch", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeAgentConfig)
		event := newPullRequestSynchronizeEvent(agentID)
		event.PullRequest.HeadBranch = "main"

		err := handler.OnPullRequestSynchronize(context.Background(), event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("skips when retry cap reached and FF on", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentMaxTriggerRetries): true,
		})
		handler, service, agentID := newPullRequestSynchronizeTestHandler(t, obsv, ffClient, pullRequestSynchronizeAgentConfig)
		event := newPullRequestSynchronizeEvent(agentID)

		ctx := context.Background()
		for i := 0; i < maxSynchronizeJobsPerBranch; i++ {
			_, err := service.Store.CreateJob(ctx, &jobs.Job{
				ID:         uuid.NewString(),
				OwnerID:    event.Repo.OwnerID,
				RepoID:     event.Repo.ID,
				BranchName: event.PullRequest.HeadBranch,
				AgentID:    agentID,
				EventType:  jobs.EventTypePullRequestSynchronize,
				Status:     jobs.JobStatusCompleted,
				CreatedAt:  time.Now().Unix(),
			})
			require.NoError(t, err)
		}

		err := handler.OnPullRequestSynchronize(ctx, event)

		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
	})
}

func newPullRequestSynchronizeTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, opts ...func(*github.NoopClientFactory)) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()

	spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, pullRequestSynchronizeAgentPath, []byte(agentConfig)))
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
	triggerRecord.Path = pullRequestSynchronizeAgentPath
	triggerRecord.Config.Name = "pr-sync-agent"
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := runtimeConfigsForPullRequestSynchronizeAgent(agent)

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func runtimeConfigsForPullRequestSynchronizeAgent(agent sweagentd.CustomAgent) []automations.RuntimeConfig {
	pr := agent.Triggers().PullRequestSynchronize
	if pr == nil {
		return nil
	}
	return []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}
}

func newPullRequestSynchronizeEvent(agentID int64) PullRequestSynchronizeEvent {
	repo := EventRepository()
	repo.ID = 1
	repo.OwnerID = 456
	repo.DefaultBranch = "main"

	pr := &PullRequest{
		ID:         200,
		NodeID:     "PR_pr-sync",
		Number:     et.PullRequestNumber,
		IsOpen:     true,
		State:      PullRequestStateOpen,
		HeadBranch: "feature-branch",
		BaseBranch: "main",
	}

	return PullRequestSynchronizeEvent{
		Actor:       EventActorWriter(),
		Repo:        repo,
		PullRequest: pr,
		BeforeOID:   "abc123",
		AfterOID:    "def456",
		AgentID:     agentID,
		Timestamp:   time.Now(),
	}
}
