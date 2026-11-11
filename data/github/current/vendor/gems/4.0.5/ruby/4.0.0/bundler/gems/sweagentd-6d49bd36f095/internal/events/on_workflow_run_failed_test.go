package events

import (
	"context"
	"errors"
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
	"github.com/github/sweagentd/internal/jobs"
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

type workflowRunFailedPublicRepoClient struct {
	*github.NoopClient
}

func (c *workflowRunFailedPublicRepoClient) GetRepositoryByID(ctx context.Context, id int64) (*gg.Repository, error) {
	repo, err := c.NoopClient.GetRepositoryByID(ctx, id)
	if err != nil {
		return nil, err
	}
	repo.Visibility = gg.Ptr("public")
	return repo, nil
}

const (
	workflowRunFailedAgentConfig = `---
name: ci-fix-agent
description: fixes failed CI runs
on:
  workflow_run:
    types: [failed]
    workflows: [CI]
---
prompt`

	workflowRunFailedWithWorkflowsConfig = `---
name: ci-fix-agent
description: fixes failed CI runs
on:
  workflow_run:
    types: [failed]
    workflows: [CI, tests]
---
prompt`

	workflowRunWithoutFailedConfig = `---
name: ci-fix-agent
description: no failed trigger
on:
  workflow_run:
    types: [completed]
    workflows: [CI]
---
prompt`

	workflowRunFailedWithoutWorkflowsConfig = `---
name: ci-fix-agent
description: fixes failed CI runs
on:
  workflow_run:
    types: [failed]
---
prompt`
)

func TestOnWorkflowRunFailed(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job when agent has workflow_run failed trigger", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Verify the job uses the workflow run's head branch (not the repo default branch)
		queuedJob := service.QueuedJobs()[0]
		job, err := service.Store.GetJob(context.Background(), event.Repo.OwnerID, event.Repo.ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, "fix/my-feature", job.BranchName)
		require.Equal(t, "fix/my-feature", job.BaseCommit)
	})

	t.Run("uses automation owner as job actor when provided by runtime config", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")
		automationOwnerID := testAutomationOwnerID
		handler.automationLookup = &staticAutomationLookup{configs: []automations.RuntimeConfig{{
			CustomAgent:       triggers.AgentFromRecord(workflowAgentRecordFromConfig(t, workflowRunFailedAgentConfig, event.Repo.ID), event.Repo.ID, triggers.RepoInfo{OwnerID: event.Repo.OwnerID, OwnerLogin: "test-org", RepoName: "test-repo"}),
			AutomationID:      "automation-1",
			AutomationOwnerID: automationOwnerID,
		}}}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, automationOwnerID, service.QueuedJobs()[0].ActorId)

		job, err := service.Store.GetJob(context.Background(), event.Repo.OwnerID, event.Repo.ID, service.QueuedJobs()[0].JobId)
		require.NoError(t, err)
		require.Equal(t, automationOwnerID, job.ActorID)
		require.Equal(t, "test-user", job.ActorLogin)
		require.Equal(t, "automation-1", job.AutomationID)
	})

	t.Run("skips when runtime config is missing automation owner", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")
		handler.automationLookup = &staticAutomationLookup{configs: []automations.RuntimeConfig{{
			CustomAgent:  triggers.AgentFromRecord(workflowAgentRecordFromConfig(t, workflowRunFailedAgentConfig, event.Repo.ID), event.Repo.ID, triggers.RepoInfo{OwnerID: event.Repo.OwnerID, OwnerLogin: "test-org", RepoName: "test-repo"}),
			AutomationID: "automation-1",
		}}}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when automation owner lookup fails", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")
		ghFactory := handler.ghFactory.(*github.NoopClientFactory)
		ghFactory.MockGetUserByID = func(context.Context, uint64) (*gg.User, error) {
			return nil, errors.New("owner lookup failed")
		}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when triggering actor lacks write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandlerWithTriggeringActor(t, obsv, ffClient, workflowRunFailedAgentConfig, et.ActorLoginReader)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips with require-write reason when triggering actor lacks write permissions", func(t *testing.T) {
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

		handler, service, agentID := newWorkflowRunFailedTestHandlerWithTriggeringActor(t, obsvWithMetrics, ffClient, workflowRunFailedAgentConfig, et.ActorLoginReader)
		handler.automationLookup.(*staticAutomationLookup).configs[0].RequireActorWritePermission = true
		handler.ghTwirp.(*githubtwirp.NoopClient).NoopSweagentdAPI.MockGetEffectiveTriggerActorPolicy = func(context.Context, *sweagentdTwirp.GetEffectiveTriggerActorPolicyRequest) (*sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse, error) {
			return &sweagentdTwirp.GetEffectiveTriggerActorPolicyResponse{AllowReadAccessTriggers: true}, nil
		}
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
		require.Contains(t, skippedCounterCalls, stats.Tags{"trigger_type": "workflow_run_failed", "reason": triggerSkipReasonAutomationRequiresActorWrite})
	})

	t.Run("queues job when automation requires write and triggering actor has write permissions", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		handler.automationLookup.(*staticAutomationLookup).configs[0].RequireActorWritePermission = true
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips event for public repositories", func(t *testing.T) {
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
		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsvWithMetrics, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")
		ghFactory := handler.ghFactory.(*github.NoopClientFactory)
		ghFactory.MockNewClientFromRepo = func(context.Context, int64, int64) (github.ClientInterface, error) {
			return &workflowRunFailedPublicRepoClient{NoopClient: &github.NoopClient{}}, nil
		}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
		require.Contains(t, skippedCounterCalls, stats.Tags{"trigger_type": "workflow_run_failed", "reason": "public_repository"})
	})

	t.Run("skips when triggering actor login is missing", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandlerWithTriggeringActor(t, obsv, ffClient, workflowRunFailedAgentConfig, "")
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("queues job when workflow name matches filter", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedWithWorkflowsConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips when workflow name does not match filter", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandlerWithName(t, obsv, ffClient, workflowRunFailedWithWorkflowsConfig, "deploy")
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/deploy.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when agent lacks failed trigger type", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunWithoutFailedConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when agent has no workflows list", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedWithoutWorkflowsConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when trigger checker is nil", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		spokes := spokestest.NewClient(t)
		customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		appProvider := agenticapptest.NewTestProvider(t)
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)

		event := newWorkflowRunFailedEvent(appProvider.CopilotApp().AppID(), ".github/workflows/ci.yaml")
		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips when max retries reached", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMaxTriggerRetries: true,
		})

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		// Seed 3 existing triggered jobs for the same branch
		for i := 0; i < maxTriggeredJobsPerBranch; i++ {
			_, err := service.Store.CreateJob(context.Background(), &jobs.Job{
				ID:         uuid.NewString(),
				OwnerID:    event.Repo.OwnerID,
				RepoID:     event.Repo.ID,
				BranchName: "fix/my-feature",
				EventType:  jobs.EventTypeWorkflowRunFailed,
				Status:     jobs.JobStatusCompleted,
				CreatedAt:  time.Now().Unix(),
			})
			require.NoError(t, err)
		}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0, "should not queue a job when max retries reached")
	})

	t.Run("queues job when under max retries", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentMaxTriggerRetries: true,
		})

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		// Seed 2 existing jobs (under the cap of 3)
		for i := 0; i < maxTriggeredJobsPerBranch-1; i++ {
			_, err := service.Store.CreateJob(context.Background(), &jobs.Job{
				ID:         uuid.NewString(),
				OwnerID:    event.Repo.OwnerID,
				RepoID:     event.Repo.ID,
				BranchName: "fix/my-feature",
				EventType:  jobs.EventTypeWorkflowRunFailed,
				Status:     jobs.JobStatusCompleted,
				CreatedAt:  time.Now().Unix(),
			})
			require.NoError(t, err)
		}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1, "should queue a job when under max retries")
	})

	t.Run("ignores retry cap when FF is off", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		// Seed jobs over the cap — should still queue because FF is off
		for i := 0; i < maxTriggeredJobsPerBranch+5; i++ {
			_, err := service.Store.CreateJob(context.Background(), &jobs.Job{
				ID:         uuid.NewString(),
				OwnerID:    event.Repo.OwnerID,
				RepoID:     event.Repo.ID,
				BranchName: "fix/my-feature",
				EventType:  jobs.EventTypeWorkflowRunFailed,
				Status:     jobs.JobStatusCompleted,
				CreatedAt:  time.Now().Unix(),
			})
			require.NoError(t, err)
		}

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1, "should queue when FF is off regardless of retry count")
	})

	t.Run("links assignment to existing PR when workflow run has PRs", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandlerWithPRs(t, obsv, ffClient, workflowRunFailedAgentConfig)
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		queuedJob := service.QueuedJobs()[0]
		job, err := service.Store.GetJob(context.Background(), event.Repo.OwnerID, event.Repo.ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, "fix/my-feature", job.BranchName)
		require.Equal(t, int64(42), job.PullRequestID)
		require.Equal(t, 7, job.PullRequestNumber)

		assignment, err := service.Store.GetAssignment(context.Background(), event.Repo.OwnerID, event.Repo.ID, job.AssignmentID)
		require.NoError(t, err)
		require.Equal(t, int64(42), assignment.PullRequestID)
		require.Equal(t, 7, assignment.PullRequestNumber)
	})

	t.Run("rejects workflow run whose head branch is the default branch", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newWorkflowRunFailedTestHandlerWithHeadBranch(t, obsv, ffClient, workflowRunFailedAgentConfig, "main")
		event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")

		err := handler.OnWorkflowRunFailed(context.Background(), event)

		// The error is returned for this specific agent's build, but OnWorkflowRunFailed
		// logs it and continues to the next agent, so we check that no jobs were queued.
		// Since there's only one agent, the event handler still returns nil.
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0, "should not queue job when head branch is the default branch")
	})
}

func TestOnWorkflowRunFailedPublicRepositoryFlagDisabledProceeds(t *testing.T) {
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotAutomationsBlockPublicRepos: false,
	})
	var skippedCounterCalls []stats.Tags
	obsvWithMetrics := observability.NewNoopExporters()
	obsvWithMetrics.Statter = &observability.MockStatter{
		MockCounter: func(key string, tags stats.Tags, _ int64) {
			if key == "triggers.skipped" {
				skippedCounterCalls = append(skippedCounterCalls, tags)
			}
		},
	}
	handler, service, agentID := newWorkflowRunFailedTestHandler(t, obsvWithMetrics, ffClient, workflowRunFailedAgentConfig)
	event := newWorkflowRunFailedEvent(agentID, ".github/workflows/ci.yaml")
	ghFactory := handler.ghFactory.(*github.NoopClientFactory)
	ghFactory.MockNewClientFromRepo = func(context.Context, int64, int64) (github.ClientInterface, error) {
		return &workflowRunFailedPublicRepoClient{NoopClient: &github.NoopClient{MockWorkflowRun: ghFactory.MockWorkflowRun}}, nil
	}

	err := handler.OnWorkflowRunFailed(context.Background(), event)

	require.NoError(t, err)
	require.Len(t, service.QueuedJobs(), 1)
	require.NotContains(t, skippedCounterCalls, stats.Tags{"trigger_type": "workflow_run_failed", "reason": "public_repository"})
}

func newWorkflowRunFailedTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	return newWorkflowRunFailedTestHandlerWithName(t, obsv, ffClient, agentConfig, "CI")
}

func newWorkflowRunFailedTestHandlerWithName(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, workflowName string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	return newWorkflowRunFailedTestHandlerFull(t, obsv, ffClient, agentConfig, workflowName, nil, "fix/my-feature", et.ActorLoginWriter)
}

func newWorkflowRunFailedTestHandlerWithTriggeringActor(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, triggeringActorLogin string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	return newWorkflowRunFailedTestHandlerFull(t, obsv, ffClient, agentConfig, "CI", nil, "fix/my-feature", triggeringActorLogin)
}

func newWorkflowRunFailedTestHandlerWithPRs(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	prs := []*gg.PullRequest{
		{
			ID:     gg.Ptr(int64(42)),
			Number: gg.Ptr(7),
			Head: &gg.PullRequestBranch{
				Ref: gg.Ptr("fix/my-feature"),
			},
		},
	}
	return newWorkflowRunFailedTestHandlerFull(t, obsv, ffClient, agentConfig, "CI", prs, "fix/my-feature", et.ActorLoginWriter)
}

func newWorkflowRunFailedTestHandlerWithHeadBranch(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, headBranch string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	return newWorkflowRunFailedTestHandlerFull(t, obsv, ffClient, agentConfig, "CI", nil, headBranch, et.ActorLoginWriter)
}

func newWorkflowRunFailedTestHandlerFull(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string, workflowName string, pullRequests []*gg.PullRequest, headBranch string, triggeringActorLogin string) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()

	spokes := spokestest.NewClient(t)
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
		MockWorkflowRun: &gg.WorkflowRun{
			ID:           gg.Ptr(int64(12345)),
			Name:         gg.Ptr(workflowName),
			RunNumber:    gg.Ptr(42),
			HeadBranch:   gg.Ptr(headBranch),
			HTMLURL:      gg.Ptr("https://github.com/test-org/test-repo/actions/runs/12345"),
			Conclusion:   gg.Ptr("failure"),
			PullRequests: pullRequests,
			TriggeringActor: &gg.User{
				ID:    gg.Ptr(int64(789)),
				Login: gg.Ptr(triggeringActorLogin),
			},
			Repository: &gg.Repository{
				FullName: gg.Ptr("test-org/test-repo"),
				Owner:    &gg.User{Login: gg.Ptr("test-org")},
				Name:     gg.Ptr("test-repo"),
			},
		},
	}

	triggerRecord := workflowAgentRecordFromConfig(t, agentConfig, 1)
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := runtimeConfigsForWorkflowAgent(agent, workflowName)

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func runtimeConfigsForWorkflowAgent(agent sweagentd.CustomAgent, workflowName string) []automations.RuntimeConfig {
	workflowTrigger := agent.Triggers().WorkflowRun
	if workflowTrigger == nil ||
		!stringSliceContains(workflowTrigger.Types, automations.ActivityWorkflowRunFailed) ||
		!stringSliceContains(workflowTrigger.Workflows, workflowName) {
		return nil
	}
	return []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}
}

func workflowAgentRecordFromConfig(t *testing.T, agentConfig string, repoID int64) *store.AgentRecord {
	t.Helper()

	attrs, err := customagent.ParseConfigForSync(agentConfig, "ci-fix-agent")
	require.NoError(t, err)

	return &store.AgentRecord{
		ID:      uuid.NewString(),
		ScopeID: repoID,
		Path:    ".github/agents/ci-fix-agent.md",
		Config: store.AgentConfig{
			Name:        "ci-fix-agent",
			DisplayName: attrs.DisplayName,
			Description: attrs.Description,
			Tools:       attrs.Tools,
			Target:      attrs.Target,
			Triggers:    attrs.Triggers,
		},
		TreeOID: "abc123",
	}
}

func newWorkflowRunFailedEvent(agentID int64, workflowPath string) WorkflowRunCompletedEvent {
	return WorkflowRunCompletedEvent{
		Repo: &WorkflowRepository{
			ID:      1,
			OwnerID: 456,
		},
		WorkflowRun: &WorkflowRun{
			ID:         12345,
			UserID:     789,
			Path:       workflowPath,
			Status:     WorkflowCompletedEventStatusCompleted,
			Conclusion: WorkflowCompletedEventConclusionFailure,
		},
		AgentID:   agentID,
		Timestamp: time.Now(),
		Kind:      WorkflowRunKindFailedTrigger,
	}
}
