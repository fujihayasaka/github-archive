package events

import (
	"context"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/store"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/github/sweagentd/internal/triggers"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestOnAutomationRunRequested(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("routes issues.opened to OnIssueCreated", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandler(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "issues", Type: "opened",
			ResourceURL: "/test-org/test-repo/issues/1",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		assert.Len(t, service.QueuedJobs(), 1, "should queue exactly one job")
	})

	t.Run("issues with full URL still works", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandler(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "issues", Type: "opened",
			ResourceURL: "https://github.com/test-org/test-repo/issues/1",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0,
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		assert.Len(t, service.QueuedJobs(), 1, "should queue exactly one job")
	})

	t.Run("routes workflow_run.completed to OnWorkflowRunFailed", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandlerForWorkflowRun(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "workflow_run", Type: "completed",
			ResourceURL: "https://github.com/test-org/test-repo/actions/runs/12345",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		assert.Len(t, service.QueuedJobs(), 1, "should queue exactly one job")
	})

	t.Run("routes pull_request.opened to OnPullRequestOpened", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandlerForPullRequest(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "pull_request", Type: "opened",
			ResourceURL: "https://github.com/test-org/test-repo/pull/7",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		assert.Len(t, service.QueuedJobs(), 1, "should queue exactly one job")
	})

	t.Run("pull_request with path-only URL works", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandlerForPullRequest(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "pull_request", Type: "opened",
			ResourceURL: "/test-org/test-repo/pull/7",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0,
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		assert.Len(t, service.QueuedJobs(), 1, "should queue exactly one job")
	})

	prRoutingCases := []struct {
		name      string
		eventName string
		mockPR    *gg.PullRequest
		wantType  jobs.EventType
	}{
		{"routes pull_request_opened to OnPullRequestOpened", "pull_request_opened", nil, jobs.EventTypePullRequestOpened},
		{"routes pull_request_synchronize to OnPullRequestSynchronize", "pull_request_synchronize", nil, jobs.EventTypePullRequestSynchronize},
		{"routes pull_request_merged to OnPullRequestStateChanged", "pull_request_merged", mergedRunRequestMockPR(7), jobs.EventTypePullRequestMerged},
	}
	for _, tc := range prRoutingCases {
		t.Run(tc.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(nil)
			handler, service, _ := newRunRequestedTestHandlerForPullRequestWithPR(t, obsv, ffClient, tc.mockPR)

			event := AutomationRunRequestedEvent{
				AutomationID: "automation-1",
				Event:        tc.eventName,
				ResourceURL:  "https://github.com/test-org/test-repo/pull/7",
				OwnerLogin:   "test-org",
				RepoName:     "test-repo",
				RepoID:       1,
				OwnerID:      456,
				UserID:       testAutomationOwnerID,
				UserLogin:    "automation-owner",
				AgentID:      0,
				Timestamp:    time.Now(),
			}

			err := handler.OnAutomationRunRequested(context.Background(), event)
			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), 1, "should queue exactly one job")

			// Assert the job carries the event type for the requested PR
			// activity, proving each event name routes to its own handler
			// rather than always running the opened path.
			job, err := service.Store.GetJob(context.Background(), event.OwnerID, event.RepoID, service.QueuedJobs()[0].JobId)
			require.NoError(t, err)
			require.Equal(t, tc.wantType, job.EventType)
		})
	}

	t.Run("fails when pull request URL is invalid", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, _, _ := newRunRequestedTestHandlerForPullRequest(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "pull_request", Type: "opened",
			ResourceURL: "/test-org/test-repo/not-a-pull",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0,
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "parse pull request number")
	})

	t.Run("routes interval to runRequestedInterval", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandlerForInterval(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "interval",
			ResourceURL:  "",
			OwnerLogin:   "test-org",
			RepoName:     "test-repo",
			RepoID:       1,
			OwnerID:      456,
			UserID:       testAutomationOwnerID,
			UserLogin:    "automation-owner",
			AgentID:      0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:    time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		assert.Len(t, service.QueuedJobs(), 1, "should queue exactly one job for interval")
	})

	t.Run("routes manual to runRequestedManual", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, service, _ := newRunRequestedTestHandlerForManual(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "manual",
			ResourceURL:  "",
			OwnerLogin:   "test-org",
			RepoName:     "test-repo",
			RepoID:       1,
			OwnerID:      456,
			UserID:       testAutomationOwnerID,
			UserLogin:    "automation-owner",
			AgentID:      0,
			Timestamp:    time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1, "should queue exactly one job for manual")

		queuedJob := service.QueuedJobs()[0]
		job, err := service.Store.GetJob(context.Background(), event.OwnerID, event.RepoID, queuedJob.JobId)
		require.NoError(t, err)
		assert.Equal(t, jobs.EventTypeManualTriggered, job.EventType)
	})

	t.Run("rejects unsupported event type", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, _, _ := newRunRequestedTestHandler(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "push",
			ResourceURL:  "",
			OwnerLogin:   "test-org",
			RepoName:     "test-repo",
			RepoID:       1,
			OwnerID:      456,
			UserID:       testAutomationOwnerID,
			UserLogin:    "automation-owner",
			AgentID:      0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:    time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "unsupported automation run request event type")
	})

	t.Run("fails when issue URL is invalid", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, _, _ := newRunRequestedTestHandler(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "issues", Type: "opened",
			ResourceURL: "https://github.com/test-org/test-repo/not-an-issue",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "parse issue number")
	})

	t.Run("fails when workflow run URL is invalid", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, _, _ := newRunRequestedTestHandlerForWorkflowRun(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "automation-1",
			Event:        "workflow_run", Type: "completed",
			ResourceURL: "/test-org/test-repo/not-a-run",
			OwnerLogin:  "test-org",
			RepoName:    "test-repo",
			RepoID:      1,
			OwnerID:     456,
			UserID:      testAutomationOwnerID,
			UserLogin:   "automation-owner",
			AgentID:     0, // matches production: Hydro events carry no agent ID; FindByID(0) resolves default Copilot app
			Timestamp:   time.Now(),
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "parse workflow run ID")
	})

	t.Run("rejects empty automation ID", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		handler, _, _ := newRunRequestedTestHandler(t, obsv, ffClient)

		event := AutomationRunRequestedEvent{
			AutomationID: "",
			Event:        "issues", Type: "opened",
			ResourceURL: "https://github.com/test-org/test-repo/issues/42",
		}

		err := handler.OnAutomationRunRequested(context.Background(), event)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "empty automation ID")
	})
}

func TestParseIssueNumberFromURL(t *testing.T) {
	tests := []struct {
		name    string
		url     string
		want    int
		wantErr bool
	}{
		{name: "standard URL", url: "https://github.com/owner/repo/issues/42", want: 42},
		{name: "with trailing slash", url: "https://github.com/owner/repo/issues/7/", want: 7},
		{name: "no scheme", url: "/owner/repo/issues/99", want: 99},
		{name: "with query string", url: "https://github.com/owner/repo/issues/42?foo=bar", want: 42},
		{name: "with fragment", url: "https://github.com/owner/repo/issues/42#issuecomment-123", want: 42},
		{name: "with query and fragment", url: "https://github.com/owner/repo/issues/42?q=1#top", want: 42},
		{name: "missing number", url: "https://github.com/owner/repo/issues/", wantErr: true},
		{name: "not a number", url: "https://github.com/owner/repo/issues/abc", wantErr: true},
		{name: "no issues segment", url: "https://github.com/owner/repo/pulls/1", wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseIssueNumberFromURL(tc.url)
			if tc.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tc.want, got)
			}
		})
	}
}

func TestParseWorkflowRunIDFromURL(t *testing.T) {
	tests := []struct {
		name    string
		url     string
		want    int64
		wantErr bool
	}{
		{name: "standard URL", url: "https://github.com/owner/repo/actions/runs/12345", want: 12345},
		{name: "with trailing slash", url: "https://github.com/owner/repo/actions/runs/999/", want: 999},
		{name: "with query string", url: "https://github.com/owner/repo/actions/runs/12345?check_suite_focus=true", want: 12345},
		{name: "with fragment", url: "https://github.com/owner/repo/actions/runs/12345#step:3:1", want: 12345},
		{name: "no runs segment", url: "https://github.com/owner/repo/actions/workflows/ci.yml", wantErr: true},
		{name: "not a number", url: "https://github.com/owner/repo/actions/runs/abc", wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parseWorkflowRunIDFromURL(tc.url)
			if tc.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tc.want, got)
			}
		})
	}
}

func TestParsePullRequestNumberFromURL(t *testing.T) {
	tests := []struct {
		name    string
		url     string
		want    int
		wantErr bool
	}{
		{name: "standard URL", url: "https://github.com/owner/repo/pull/42", want: 42},
		{name: "with trailing slash", url: "https://github.com/owner/repo/pull/7/", want: 7},
		{name: "no scheme", url: "/owner/repo/pull/99", want: 99},
		{name: "with query string", url: "https://github.com/owner/repo/pull/42?diff=unified", want: 42},
		{name: "with fragment", url: "https://github.com/owner/repo/pull/42#discussion_r123", want: 42},
		{name: "with query and fragment", url: "https://github.com/owner/repo/pull/42?q=1#top", want: 42},
		{name: "missing number", url: "https://github.com/owner/repo/pull/", wantErr: true},
		{name: "not a number", url: "https://github.com/owner/repo/pull/abc", wantErr: true},
		{name: "no pull segment", url: "https://github.com/owner/repo/issues/1", wantErr: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := parsePullRequestNumberFromURL(tc.url)
			if tc.wantErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tc.want, got)
			}
		})
	}
}

// --- Test helpers ---

func newRunRequestedTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	return newRunRequestedTestHandlerWithConfig(t, obsv, ffClient, issueOpenedConfig)
}

func newRunRequestedTestHandlerForWorkflowRun(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()
	spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, customAgentPath, []byte(workflowRunFailedAgentConfig)))
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
		MockWorkflowRun: &gg.WorkflowRun{
			ID:         gg.Ptr(int64(12345)),
			Name:       gg.Ptr("CI"),
			HeadBranch: gg.Ptr("fix/issue-123"),
			HTMLURL:    gg.Ptr("https://github.com/test-org/test-repo/actions/runs/12345"),
			Conclusion: gg.Ptr("failure"),
			TriggeringActor: &gg.User{
				ID:    gg.Ptr(testAutomationOwnerID),
				Login: gg.Ptr("automation-owner"),
			},
			Repository: &gg.Repository{
				FullName: gg.Ptr("test-org/test-repo"),
				Owner:    &gg.User{Login: gg.Ptr("test-org")},
				Name:     gg.Ptr("test-repo"),
			},
		},
	}

	triggerRecord := workflowAgentRecordFromConfig(t, workflowRunFailedAgentConfig, 1)
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func newRunRequestedTestHandlerForInterval(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()
	spokes := spokestest.NewClient(t)
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	// Build a runtime config for an interval automation.
	agent := newIntervalCustomAgent()
	runtimeConfigs := []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

// mergedRunRequestMockPR returns a merged same-repo PR so a pull_request_merged
// run request passes the merged-state guard in firePullRequestMergedTriggers.
func mergedRunRequestMockPR(number int) *gg.PullRequest {
	return &gg.PullRequest{
		ID:      gg.Ptr(int64(1)),
		Number:  gg.Ptr(number),
		Merged:  gg.Ptr(true),
		State:   gg.Ptr("closed"),
		Title:   gg.Ptr("merged-pull-request"),
		Body:    gg.Ptr("merged-pull-request-body"),
		HTMLURL: gg.Ptr("https://github.com/test-org/test-repo/pull/7"),
		Base: &gg.PullRequestBranch{
			Ref:  gg.Ptr("main"),
			Repo: &gg.Repository{ID: gg.Ptr(int64(1)), Owner: &gg.User{Login: gg.Ptr("test-org")}},
		},
		Head: &gg.PullRequestBranch{
			Ref:  gg.Ptr("feature-branch"),
			Repo: &gg.Repository{ID: gg.Ptr(int64(1))},
		},
	}
}

func newRunRequestedTestHandlerForManual(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()
	spokes := spokestest.NewClient(t)
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	// Build a runtime config for a manual automation (reuse interval agent shape).
	agent := newIntervalCustomAgent()
	runtimeConfigs := []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func newRunRequestedTestHandlerForPullRequest(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()
	return newRunRequestedTestHandlerForPullRequestWithPR(t, obsv, ffClient, nil)
}

func newRunRequestedTestHandlerForPullRequestWithPR(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, mockPR *gg.PullRequest) (*Handler, *jobservicetest.TestService, int64) {
	t.Helper()

	capiClient, jobStore, ghTwirp := commonHandlerDependencies()
	spokes := spokestest.NewClient(t, spokestest.WithRepoBlob(1, pullRequestOpenedAgentPath, []byte(pullRequestOpenedAgentConfig)))
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	appProvider := agenticapptest.NewTestProvider(t)
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin:  et.GitHubAppLogin,
		GitHubBotLogin:  et.GitHubBotLogin,
		MockPullRequest: mockPR,
	}

	triggerRecord := agentRecordFromConfig(t, pullRequestOpenedAgentConfig, 1)
	triggerRecord.Path = pullRequestOpenedAgentPath
	triggerRecord.Config.Name = "pr-opened-agent"
	agent := triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
	runtimeConfigs := runtimeConfigsForPullRequestAgent(agent)

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

func newRunRequestedTestHandlerWithConfig(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, agentConfig string) (*Handler, *jobservicetest.TestService, int64) {
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
	runtimeConfigs := []automations.RuntimeConfig{{
		CustomAgent:       agent,
		AutomationID:      "automation-1",
		AutomationOwnerID: testAutomationOwnerID,
	}}

	service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)

	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, &staticAutomationLookup{configs: runtimeConfigs})

	return handler, service, appProvider.CopilotApp().AppID()
}

// newIntervalCustomAgent creates a minimal custom agent with interval triggers for testing.
func newIntervalCustomAgent() sweagentd.CustomAgent {
	triggerRecord := &store.AgentRecord{
		ID:      "interval-agent-id",
		ScopeID: 1,
		Path:    ".github/agents/interval-agent.md",
		Config: store.AgentConfig{
			Name:        "interval-agent",
			Description: "scheduled automation",
			Triggers: sweagentd.CustomAgentTriggers{
				Interval: &sweagentd.CustomAgentIntervalTrigger{
					Types: []string{"daily"},
				},
			},
		},
		TreeOID: "abc123",
	}
	return triggers.AgentFromRecord(triggerRecord, 1, triggers.RepoInfo{OwnerID: 456, OwnerLogin: "test-org", RepoName: "test-repo"})
}
