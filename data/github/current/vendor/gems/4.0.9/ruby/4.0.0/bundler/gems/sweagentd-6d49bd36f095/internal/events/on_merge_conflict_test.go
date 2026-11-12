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

func TestOnMergeConflict(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("queues job for merge conflict event", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newMergeConflictTestHandler(t, obsv, ffClient)
		event := newMergeConflictEvent(agentID)

		err := handler.OnMergeConflict(context.Background(), event)

		require.NoError(t, err)
		queuedJobs := service.QueuedJobs()
		require.Len(t, queuedJobs, 1)

		job, err := service.Store.GetJob(context.Background(), queuedJobs[0].OwnerId, queuedJobs[0].RepositoryId, queuedJobs[0].JobId)
		require.NoError(t, err)
		require.True(t, job.IsTriggered)
		require.Equal(t, mergeConflictAgentName, job.CustomAgent.Name)
	})

	t.Run("queues when trigger checker is nil", func(t *testing.T) {
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

		event := newMergeConflictEvent(appProvider.CopilotApp().AppID())
		err := handler.OnMergeConflict(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("does not queue job when pull request not found", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newMergeConflictTestHandler(t, obsv, ffClient)
		event := newMergeConflictEvent(agentID)
		// Use a PR ID that doesn't match any PR returned by the noop client (ID=1)
		event.PullRequestID = 999

		err := handler.OnMergeConflict(context.Background(), event)

		// The handler logs the error and continues (doesn't propagate non-limiter errors),
		// so no error is returned but no job should be queued.
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("resolves owner ID from repository API response", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		handler, service, agentID := newMergeConflictTestHandler(t, obsv, ffClient)
		event := newMergeConflictEvent(agentID)
		// OwnerID=0 simulates the proto not providing the owner ID.
		// The handler should resolve it from the GitHub API response.
		event.Repo.OwnerID = 0

		err := handler.OnMergeConflict(context.Background(), event)

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})
}

func newMergeConflictTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

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

	return handler, service, appProvider.CopilotApp().AppID()
}

func newMergeConflictEvent(agentID int64) MergeConflictEvent {
	return MergeConflictEvent{
		Repo: &MergeConflictRepository{
			ID:      1,
			OwnerID: 0, // OwnerID is not available from the proto; resolved in handler
		},
		PullRequestID: 1, // Matches NoopClient.ListPullRequestsWithCommit return value
		BaseCommitOID: "base-sha",
		HeadCommitOID: "head-sha",
		ConflictPaths: []string{"file1.go", "file2.go"},
		AgentID:       agentID,
		Timestamp:     time.Now(),
	}
}
