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
	pullRequestOpenedAgentPath   = ".github/agents/pr-opened-agent.md"
	pullRequestOpenedAgentConfig = `---
name: pr-opened-agent
description: pull_request opened trigger
on:
  pull_request_opened:
    types: [opened]
---
prompt`

	pullRequestWithoutOpenedConfig = `---
name: pr-opened-agent
description: pull_request without opened trigger
on:
  pull_request_merged:
    types: [merged]
---
prompt`

	pullRequestOpenedWithMatchingQueryConfig = `---
name: pr-opened-agent
description: pull_request opened with matching filter
on:
  pull_request_opened:
    types: [opened]
    query: draft:true
---
prompt`

	pullRequestOpenedWithNonMatchingQueryConfig = `---
name: pr-opened-agent
description: pull_request opened with non-matching filter
on:
  pull_request_opened:
    types: [opened]
    query: label:bug
---
prompt`

	pullRequestOpenedWithPathsConfig = `---
name: pr-opened-agent
description: pull_request opened with paths filter
on:
  pull_request_opened:
    types: [opened]
    paths:
      - "src/**"
---
prompt`
)

func TestOnPullRequestOpened(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job when agent has opened trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedAgentConfig)
		event := newPullRequestOpenedEvent(agentID)

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, testAutomationOwnerID, service.QueuedJobs()[0].ActorId)
		require.Equal(t, event.AgentID, service.QueuedJobs()[0].AgentId)

		job, err := service.Store.GetJob(context.Background(), event.Owner.ID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		require.Equal(t, "automation-1", job.AutomationID)
	})

	t.Run("skips when no automation lookup is configured", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedAgentConfig)
		event := newPullRequestOpenedEvent(agentID)
		handler.automationLookup = nil

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when no automations match", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedAgentConfig)
		event := newPullRequestOpenedEvent(agentID)
		handler.automationLookup = &staticAutomationLookup{configs: nil}

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when actor lacks write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedAgentConfig)
		event := newPullRequestOpenedEvent(agentID)
		event.Actor = EventActorReader()

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when actor login is missing", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedAgentConfig)
		event := newPullRequestOpenedEvent(agentID)
		event.Actor = &Actor{ID: event.Actor.ID}

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips job when head branch equals default branch", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedAgentConfig)
		event := newPullRequestOpenedEvent(agentID)
		event.PullRequest.HeadBranch = event.Repo.DefaultBranch

		err := handler.OnPullRequestOpened(context.Background(), event)

		// Default-branch head is a business-logic skip, not an error.
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("queues job when query filter matches pull request", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		// NoopClient default PR is Draft:true, matching `query: draft:true`.
		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedWithMatchingQueryConfig)
		event := newPullRequestOpenedEvent(agentID)

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips job when query filter does not match pull request", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		// NoopClient default PR has no labels, so `query: label:bug` does not match.
		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedWithNonMatchingQueryConfig)
		event := newPullRequestOpenedEvent(agentID)

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("queues job when paths filter matches changed files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFiles = []*gg.CommitFile{{Filename: gg.Ptr("src/foo.go")}}
			},
		)
		event := newPullRequestOpenedEvent(agentID)

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips job when paths filter does not match changed files", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFiles = []*gg.CommitFile{{Filename: gg.Ptr("README.md")}}
			},
		)
		event := newPullRequestOpenedEvent(agentID)

		err := handler.OnPullRequestOpened(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips job when paths filter API errors (fail-closed)", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newPullRequestOpenedTestHandler(t, obsv, ffClient, pullRequestOpenedWithPathsConfig,
			func(f *github.NoopClientFactory) {
				f.MockPullRequestFilesErr = goerrors.New("github API down")
			},
		)
		event := newPullRequestOpenedEvent(agentID)

		err := handler.OnPullRequestOpened(context.Background(), event)

		// Fail-CLOSED: API errors skip rather than fire on every PR.
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})
}

// TestMatchesAnyChangedPath verifies the inline gitignore-style path matcher.
func TestMatchesAnyChangedPath(t *testing.T) {
	files := func(names ...string) []*gg.CommitFile {
		out := make([]*gg.CommitFile, len(names))
		for i, n := range names {
			n := n
			out[i] = &gg.CommitFile{Filename: &n}
		}
		return out
	}

	t.Run("matches when at least one file hits an include pattern", func(t *testing.T) {
		matched, err := matchesAnyChangedPath([]string{"src/**"}, files("src/foo.go", "README.md"))
		require.NoError(t, err)
		require.True(t, matched)
	})

	t.Run("does not match when no file hits an include pattern", func(t *testing.T) {
		matched, err := matchesAnyChangedPath([]string{"src/**"}, files("README.md", "docs/notes.md"))
		require.NoError(t, err)
		require.False(t, matched)
	})

	t.Run("excludes filter out matches but at least one remaining still matches", func(t *testing.T) {
		matched, err := matchesAnyChangedPath([]string{"src/**", "!**/*.md"}, files("src/foo.go", "src/foo.md"))
		require.NoError(t, err)
		require.True(t, matched)
	})

	t.Run("does not match when every included file is excluded", func(t *testing.T) {
		matched, err := matchesAnyChangedPath([]string{"**/*", "!**/*.md"}, files("docs/a.md", "docs/b.md"))
		require.NoError(t, err)
		require.False(t, matched)
	})

	t.Run("fail-closed on invalid pattern", func(t *testing.T) {
		matched, err := matchesAnyChangedPath([]string{"["}, files("src/foo.go"))
		require.Error(t, err)
		require.False(t, matched)
	})
}

// TestPullRequestOpenedEvent_IsFromFork verifies the fork-detection helper.
func TestPullRequestOpenedEvent_IsFromFork(t *testing.T) {
	t.Run("returns false when head repo matches base", func(t *testing.T) {
		event := &PullRequestOpenedEvent{
			Repo:       &Repository{ID: 42},
			HeadRepoID: 42,
		}
		require.False(t, event.IsFromFork())
	})

	t.Run("returns false when head repo id is zero", func(t *testing.T) {
		event := &PullRequestOpenedEvent{
			Repo:       &Repository{ID: 42},
			HeadRepoID: 0,
		}
		require.False(t, event.IsFromFork())
	})

	t.Run("returns true when head repo differs from base", func(t *testing.T) {
		event := &PullRequestOpenedEvent{
			Repo:       &Repository{ID: 42},
			HeadRepoID: 100,
		}
		require.True(t, event.IsFromFork())
	})

	t.Run("returns false when receiver is nil", func(t *testing.T) {
		var event *PullRequestOpenedEvent
		require.False(t, event.IsFromFork())
	})
}

func newPullRequestOpenedTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, opts ...func(*github.NoopClientFactory)) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()

	spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, pullRequestOpenedAgentPath, []byte(agentConfig)))
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
	triggerRecord.Path = pullRequestOpenedAgentPath
	triggerRecord.Config.Name = "pr-opened-agent"
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := runtimeConfigsForPullRequestAgent(agent)

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func runtimeConfigsForPullRequestAgent(agent sweagentd.CustomAgent) []automations.RuntimeConfig {
	pr := agent.Triggers().PullRequestOpened
	if pr == nil {
		return nil
	}
	return []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}
}

func newPullRequestOpenedEvent(agentID int64) PullRequestOpenedEvent {
	owner := eventActor(et.RepoOwner)
	owner.ID = 456

	repo := EventRepository()
	repo.ID = 1
	repo.OwnerID = owner.ID
	repo.DefaultBranch = "main"

	pr := &PullRequest{
		ID:         200,
		NodeID:     "PR_pr-opened",
		Number:     et.PullRequestNumber,
		IsOpen:     true,
		State:      PullRequestStateOpen,
		HeadBranch: "feature-branch",
		BaseBranch: "main",
	}

	return PullRequestOpenedEvent{
		Actor:       EventActorWriter(),
		Repo:        repo,
		Owner:       owner,
		PullRequest: pr,
		HeadRepoID:  repo.ID,
		Title:       "Add feature",
		Body:        "Adds a useful feature.",
		AgentID:     agentID,
		Timestamp:   time.Now(),
	}
}
