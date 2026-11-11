package events

import (
	"context"
	"errors"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/capi"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestOnWorkflowRunCompleted(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		capi.CopilotAPIAgentSessions: true,
	})
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	capiClient, _, ghTwirp := commonHandlerDependencies()
	capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
		return &capi.Session{
			ID: sessionID,
		}, nil
	}
	capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
		return nil
	}

	// Helper function to create workflow run with or without JobID
	createWorkflowRun := func(conclusion string, withJobID bool) *WorkflowRun {
		run := EventWorkflowRunWithConclusion(conclusion)
		if !withJobID {
			run.JobID = nil // Remove JobID to trigger conclusion path
		}
		return run
	}

	t.Run("queues the pending job", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			capi.CopilotAPIAgentSessions: true,
		})
		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.JobWithSessionID(jobs.JobStatusRunning, "session")
		jobB := et.Job(jobs.JobStatusPending)
		jobB.ComputeID = ""
		h.jobsStore.CreateJob(context.Background(), job)
		h.jobsStore.CreateJob(context.Background(), jobB)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("failure"),
		})

		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)

		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("ignores workflows not from integration", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		run := EventWorkflowRun()
		run.Path = "dynamic/some-other-app/copilot"

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: run,
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("should handle if there is no session update", func(t *testing.T) {
		capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateCompleted,
			}, nil
		}
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		gh := ghFactory.NewClient("test-token")

		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job, err := h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))
		require.NoError(t, err)

		job.SessionID = "session-id"
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})

		workflowDetails := &jobutils.WorkflowJobDetails{
			JobStatus: jobs.JobStatusCompleted,
		}

		session, err := h.updateSessionFromWorkflow(ctx, gh, job, workflowDetails)

		require.NoError(t, err)
		require.Equal(t, capi.Session{
			ID:    "session-id",
			State: capi.SessionStateCompleted,
		}, *session)
	})

	t.Run("fails if not job matches workflow", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRun(),
		})

		require.ErrorContains(t, err, "failed to find job for workflow run")
		require.Len(t, service.QueuedJobs(), 0)
	})

	// Test basic job status updates for both job details (with GitHub API) and conclusion (without GitHub API)
	statusUpdateTestCases := []struct {
		name             string
		conclusion       string
		expectedStatus   jobs.JobStatus
		withJobID        bool // true = use job details, false = use run conclusion
		needsGitHubMocks bool // whether this test needs GitHub API mocks
	}{
		// Job details tests
		{
			name:             "job details: updates job status to completed",
			conclusion:       "success",
			expectedStatus:   jobs.JobStatusCompleted,
			withJobID:        true,
			needsGitHubMocks: true,
		},
		{
			name:             "job details: updates job status to cancelled",
			conclusion:       "cancelled",
			expectedStatus:   jobs.JobStatusCancelled,
			withJobID:        true,
			needsGitHubMocks: true,
		},
		// Run conclusion tests
		{
			name:             "conclusion: updates job status to completed",
			conclusion:       "success",
			expectedStatus:   jobs.JobStatusCompleted,
			withJobID:        false,
			needsGitHubMocks: false,
		},
		{
			name:             "conclusion: updates job status to cancelled",
			conclusion:       "cancelled",
			expectedStatus:   jobs.JobStatusCancelled,
			withJobID:        false,
			needsGitHubMocks: false,
		},
	}

	for _, tc := range statusUpdateTestCases {
		t.Run(tc.name, func(t *testing.T) {
			var ghFactory *github.NoopClientFactory

			if tc.needsGitHubMocks {
				// need GitHub API mocks to get job details for GetWorkflowDetails
				gh := &github.NoopClient{
					MockGetWorkflowJobByID: func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
						return &gg.WorkflowJob{
							ID:         &jobID,
							Conclusion: gg.Ptr(tc.conclusion),
						}, nil
					},
				}
				ghFactory = &github.NoopClientFactory{
					MockNewClient: func(token string) github.ClientInterface {
						return gh
					},
					MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
						return gh, nil
					},
				}
			} else {
				// use basic NoopClientFactory without GitHub API mocks for conclusion-based job finalization
				ghFactory = &github.NoopClientFactory{
					GitHubAppLogin: et.GitHubAppLogin,
					GitHubBotLogin: et.GitHubBotLogin,
				}
			}

			h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, memory.NewStore(), ghTwirp, ghFactory)
			h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
			job := et.JobWithSessionID(jobs.JobStatusRunning, "session")
			h.jobsStore.CreateJob(context.Background(), job)

			actor := et.ActorWriter()
			pr := et.PullRequest(*et.UserCopilot())
			pr = et.AddCommentToPullRequest(pr, true, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			workflowRun := createWorkflowRun(tc.conclusion, tc.withJobID)
			ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
			err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
				Repo:        EventWorkflowRepository(),
				WorkflowRun: workflowRun,
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), 0)

			job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
			require.NoError(t, err)
			require.Equal(t, tc.expectedStatus, job.Status)
			require.NotNil(t, job.CompletedAt)
			require.Equal(t, workflowRun.CompletedAt, job.CompletedAt)
		})
	}

	t.Run("updates job status to cancelled, updates session and requests review", func(t *testing.T) {
		testSessionID := "session-2"
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			require.Equal(t, capi.SessionStateCancelled, update.State)
			require.Equal(t, testSessionID, sessionID)
			updateSessionCalled = true
			return nil
		}

		gh := &github.NoopClient{
			MockRepositoryContext: &github.RepositoryContext{
				Repository: *et.Repo(),
			},
			MockIssueContext: &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue(*et.UserCopilot())},
			GithubAppLogin:   et.GitHubAppLogin,
			GithubBotLogin:   et.GitHubBotLogin,
		}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin:   et.GitHubAppLogin,
			GitHubBotLogin:   et.GitHubBotLogin,
			MockIssueContext: &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue(*et.UserCopilot())},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.Job(jobs.JobStatusRunning)
		job.SessionID = testSessionID
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("cancelled"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, job.Status)
		require.NotNil(t, job.CompletedAt)

		require.True(t, updateSessionCalled, "expected update session to be called")

		require.Len(t, gh.MethodCalls, 1)
		var requestReviewersCall github.MethodCall
		for _, call := range gh.MethodCalls {
			if call.Method == "RequestReviewers" {
				requestReviewersCall = call
				break
			}
		}
		require.NotEmpty(t, requestReviewersCall)
		require.Len(t, requestReviewersCall.Args, 4)
		require.Equal(t, requestReviewersCall.Args[0], job.RepoOwner)
		require.Equal(t, requestReviewersCall.Args[1], job.RepoName)
		require.Equal(t, requestReviewersCall.Args[2], job.PullRequestNumber)
		require.Equal(t, requestReviewersCall.Args[3], []string{job.ActorLogin})
	})

	t.Run("updates job status to cancelled and updates session, but skips review request with flag enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			capi.CopilotAPIAgentSessions:              true,
			"sweagentd_skip_review_request_on_cancel": true,
		})

		testSessionID := "session-2"
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			require.Equal(t, capi.SessionStateCancelled, update.State)
			require.Equal(t, testSessionID, sessionID)
			updateSessionCalled = true
			return nil
		}

		gh := &github.NoopClient{
			MockRepositoryContext: &github.RepositoryContext{
				Repository: *et.Repo(),
			},
			MockIssueContext: &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue(*et.UserCopilot())},
			GithubAppLogin:   et.GitHubAppLogin,
			GithubBotLogin:   et.GitHubBotLogin,
		}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin:   et.GitHubAppLogin,
			GitHubBotLogin:   et.GitHubBotLogin,
			MockIssueContext: &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue(*et.UserCopilot())},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.Job(jobs.JobStatusRunning)
		job.SessionID = testSessionID
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("cancelled"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCancelled, job.Status)
		require.NotNil(t, job.CompletedAt)

		require.True(t, updateSessionCalled, "expected update session to be called")

		require.Len(t, gh.MethodCalls, 0)
	})

	t.Run("updates job status to failed, marks session as failed and requests review", func(t *testing.T) {
		testSessionID := "session-1"
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			require.Equal(t, capi.SessionStateFailed, update.State)
			require.Equal(t, testSessionID, sessionID)
			updateSessionCalled = true
			return nil
		}

		gh := &github.NoopClient{
			MockRepositoryContext: &github.RepositoryContext{
				Repository: *et.Repo(),
			},
			MockIssueContext: &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue(*et.UserCopilot())},
			GithubAppLogin:   et.GitHubAppLogin,
			GithubBotLogin:   et.GitHubBotLogin,
		}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin:   et.GitHubAppLogin,
			GitHubBotLogin:   et.GitHubBotLogin,
			MockIssueContext: &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue(*et.UserCopilot())},
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.Job(jobs.JobStatusRunning)
		job.SessionID = testSessionID
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("failure"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, job.Status)
		require.NotNil(t, job.CompletedAt)

		require.True(t, updateSessionCalled, "expected update session to be called")

		require.Len(t, gh.MethodCalls, 1)
		var requestReviewersCall github.MethodCall
		for _, call := range gh.MethodCalls {
			if call.Method == "RequestReviewers" {
				requestReviewersCall = call
				break
			}
		}
		require.NotEmpty(t, requestReviewersCall)
		require.Len(t, requestReviewersCall.Args, 4)
		require.Equal(t, requestReviewersCall.Args[0], job.RepoOwner)
		require.Equal(t, requestReviewersCall.Args[1], job.RepoName)
		require.Equal(t, requestReviewersCall.Args[2], job.PullRequestNumber)
		require.Equal(t, requestReviewersCall.Args[3], []string{job.ActorLogin})
	})

	t.Run("launches pending job", func(t *testing.T) {
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.JobWithSessionID(jobs.JobStatusRunning, "session")
		jobB := et.Job(jobs.JobStatusPending)
		jobB.ComputeID = ""
		h.jobsStore.CreateJob(context.Background(), job)
		h.jobsStore.CreateJob(context.Background(), jobB)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("failure"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, job.Status)
		require.NotNil(t, job.CompletedAt)
	})

	t.Run("launches pending job for a PRs assigned to other users but not Copilot", func(t *testing.T) {
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.JobWithSessionID(jobs.JobStatusRunning, "session")
		jobB := et.Job(jobs.JobStatusPending)
		jobB.ComputeID = ""
		h.jobsStore.CreateJob(context.Background(), job)
		h.jobsStore.CreateJob(context.Background(), jobB)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("failure"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, job.Status)
		require.NotNil(t, job.CompletedAt)
	})

	t.Run("skips launching pending job on PRs that are closed", func(t *testing.T) {
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.JobWithSessionID(jobs.JobStatusRunning, "session")
		jobB := et.Job(jobs.JobStatusPending)
		jobB.ComputeID = ""
		h.jobsStore.CreateJob(context.Background(), job)
		h.jobsStore.CreateJob(context.Background(), jobB)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)
		pr.Closed = true

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("failure"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips launching pending job on PRs not authored by Copilot", func(t *testing.T) {
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.JobWithSessionID(jobs.JobStatusRunning, "session")
		jobB := et.Job(jobs.JobStatusPending)
		jobB.ComputeID = ""
		h.jobsStore.CreateJob(context.Background(), job)
		h.jobsStore.CreateJob(context.Background(), jobB)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(et.ActorAdmin(), *et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("failure"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	inferFromAnnotationTestCases := []struct {
		name                  string
		annotationMessage     string
		expectedSessionState  capi.SessionState
		expectedErrorContains string
		expectedJobStatus     jobs.JobStatus
		ffClient              featureflags.Client
		workflowRunConclusion string
		workflowJobConclusion string
		withJobID             bool // true = use job details, false = use run conclusion
	}{
		// use GitHub API calls for intelligent timeout detection with GetWorkflowDetails
		{
			name:                  "check annotation for out-of-disk error using GetWorkflowDetails",
			annotationMessage:     "System.IO.IOException: No space left on device : at GitHub.Runner.Worker.Program.Main(String[] args)",
			expectedSessionState:  capi.SessionStateFailed,
			expectedErrorContains: "Copilot had to stop work due to insufficient disk space.",
			expectedJobStatus:     jobs.JobStatusFailed,
			ffClient:              ffClient,
			workflowRunConclusion: "failure",
			workflowJobConclusion: "failure",
			withJobID:             true,
		},
		{
			name:                  "check annotation for timed out error using GetWorkflowDetails",
			annotationMessage:     "The job has exceeded the maximum execution time of 1m0s",
			expectedSessionState:  capi.SessionStateTimedOut,
			expectedErrorContains: "Copilot had to stop work due to a timeout.",
			expectedJobStatus:     jobs.JobStatusTimedOut,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				"agent_session_update_allow_timedout": true,
				capi.CopilotAPIAgentSessions:          true,
			}),
			workflowRunConclusion: "cancelled",
			workflowJobConclusion: "cancelled",
			withJobID:             true,
		},
		// use only workflow conclusion for basic status mapping with GetWorkflowDetails
		{
			name:                  "failure conclusion maps to failed status using GetWorkflowDetails",
			annotationMessage:     "",
			expectedSessionState:  capi.SessionStateFailed,
			expectedErrorContains: "",
			expectedJobStatus:     jobs.JobStatusFailed,
			ffClient:              ffClient,
			workflowRunConclusion: "failure",
			workflowJobConclusion: "failure",
			withJobID:             true,
		},
		{
			name:                  "cancelled conclusion maps to cancelled status using GetWorkflowDetails",
			annotationMessage:     "",
			expectedSessionState:  capi.SessionStateCancelled,
			expectedErrorContains: "",
			expectedJobStatus:     jobs.JobStatusCancelled,
			ffClient:              ffClient,
			workflowRunConclusion: "cancelled",
			workflowJobConclusion: "cancelled",
			withJobID:             true,
		},
	}

	for _, tc := range inferFromAnnotationTestCases {
		t.Run(tc.name, func(t *testing.T) {
			testSessionID := "session-1"

			capiClientLocal, jobStore, ghTwirp := commonHandlerDependencies()
			capiClientLocal.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
				return &capi.Session{
					ID:    sessionID,
					State: capi.SessionStateInProgress,
				}, nil
			}
			updateSessionCalled := false
			capiClientLocal.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
				require.Equal(t, tc.expectedSessionState, update.State)
				require.Equal(t, testSessionID, sessionID)
				if tc.expectedErrorContains != "" {
					require.NotNil(t, update.Error)
					require.Contains(t, update.Error.Message, tc.expectedErrorContains)
				}
				updateSessionCalled = true
				return nil
			}

			var ghFactory *github.NoopClientFactory
			if tc.withJobID {
				// need GitHub API mocks to get job details for GetWorkflowDetails
				gh := &github.NoopClient{
					MockGetWorkflowJobByID: func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
						return &gg.WorkflowJob{
							ID:         &jobID,
							Conclusion: &tc.workflowJobConclusion,
						}, nil
					},
					MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
						if tc.annotationMessage != "" {
							return []*gg.CheckRunAnnotation{
								{
									AnnotationLevel: gg.Ptr("failure"),
									Message:         &tc.annotationMessage,
								},
							}, nil
						}
						return []*gg.CheckRunAnnotation{}, nil
					},
				}
				ghFactory = &github.NoopClientFactory{
					MockNewClient: func(token string) github.ClientInterface {
						return gh
					},
				}
			} else {
				// use basic NoopClientFactory without GitHub API mocks for conclusion-based job finalization
				ghFactory = &github.NoopClientFactory{
					GitHubAppLogin: et.GitHubAppLogin,
					GitHubBotLogin: et.GitHubBotLogin,
				}
			}

			h, service, _ := NewTestHandler(t, obsv, capiClientLocal, tc.ffClient, jobStore, ghTwirp, ghFactory)
			h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
			job := et.Job(jobs.JobStatusRunning)
			job.SessionID = testSessionID
			h.jobsStore.CreateJob(context.Background(), job)

			actor := et.ActorWriter()
			pr := et.PullRequest(*et.UserCopilot())
			pr = et.AddCommentToPullRequest(pr, true, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
			err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
				Repo:        EventWorkflowRepository(),
				WorkflowRun: createWorkflowRun(tc.workflowRunConclusion, tc.withJobID),
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), 0)

			job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
			require.NoError(t, err)
			require.Equal(t, tc.expectedJobStatus, job.Status)
			require.NotNil(t, job.CompletedAt)

			require.True(t, updateSessionCalled, "expected update session to be called")
		})
	}

	cancellationTestCases := []struct {
		name                  string
		annotation            string
		expectedMetricEmitted bool
		ffClient              featureflags.Client
		expectedJobStatus     jobs.JobStatus
	}{
		{
			name:                  "user cancellation should be ignored",
			annotation:            "The run was canceled by @monalisa.",
			expectedMetricEmitted: false,
			ffClient:              ffClient,
			expectedJobStatus:     jobs.JobStatusCancelled,
		},
		{
			name:                  "timeout cancellation should be ignored",
			annotation:            "The job has exceeded the maximum execution time of",
			expectedMetricEmitted: false,
			ffClient: featureflags.NewNoopClient(map[string]bool{
				"agent_session_update_allow_timedout": true,
				capi.CopilotAPIAgentSessions:          true,
			}),
			expectedJobStatus: jobs.JobStatusTimedOut,
		},
		{
			name:                  "non-user cancellation should be tracked",
			annotation:            "The job was not acquired by Runner of type hosted even after multiple attempts",
			expectedMetricEmitted: true,
			ffClient:              ffClient,
			expectedJobStatus:     jobs.JobStatusCancelled,
		},
	}
	for _, tc := range cancellationTestCases {
		t.Run(tc.name, func(t *testing.T) {
			testSessionID := "session-1"
			cancelled := "cancelled"
			failure := "failure"
			annotationMessage := tc.annotation

			counterCalled := false
			obsv.Statter = &observability.MockStatter{
				MockCounter: func(key string, tags stats.Tags, value int64) {
					if key == "dynamic_workflow_unknown_cancellation" {
						require.Equal(t, int64(1), value)
						counterCalled = true
					}
				},
			}
			capiClient, jobStore, ghTwirp := commonHandlerDependencies()
			capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
				return &capi.Session{
					ID:    sessionID,
					State: capi.SessionStateInProgress,
				}, nil
			}
			gh := &github.NoopClient{
				MockGetWorkflowJobByID: func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
					return &gg.WorkflowJob{
						ID:         &jobID,
						Conclusion: &cancelled,
					}, nil
				},
				MockListCheckRunAnnotations: func(ctx context.Context, owner, repo string, jobID int64) ([]*gg.CheckRunAnnotation, error) {
					return []*gg.CheckRunAnnotation{
						{
							AnnotationLevel: &failure,
							Message:         &annotationMessage,
						},
					}, nil
				},
			}
			ghFactory := &github.NoopClientFactory{
				MockNewClient: func(token string) github.ClientInterface {
					return gh
				},
			}
			h, service, _ := NewTestHandler(t, obsv, capiClient, tc.ffClient, jobStore, ghTwirp, ghFactory)
			h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
			job := et.Job(jobs.JobStatusRunning)
			job.SessionID = testSessionID
			h.jobsStore.CreateJob(context.Background(), job)

			actor := et.ActorWriter()
			pr := et.PullRequest(*et.UserCopilot())
			pr = et.AddCommentToPullRequest(pr, true, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
			err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
				Repo:        EventWorkflowRepository(),
				WorkflowRun: EventWorkflowRunWithConclusion(failure),
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), 0)

			job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
			require.NoError(t, err)
			require.Equal(t, tc.expectedJobStatus, job.Status)
			require.NotNil(t, job.CompletedAt)

			require.Equal(t, tc.expectedMetricEmitted, counterCalled)
		})
	}

	t.Run("handles nil workflow details gracefully when GitHub API fails", func(t *testing.T) {
		// This test reproduces the bug where a job completes successfully but the session
		// is marked as failed due to nil workflow details being passed to GetSessionUpdateForWorkflowRun
		testSessionID := "session-bug-test"

		capiClientLocal, _, ghTwirp := commonHandlerDependencies()
		capiClientLocal.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		var capturedSessionState capi.SessionState
		capiClientLocal.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			updateSessionCalled = true
			capturedSessionState = update.State
			require.Equal(t, testSessionID, sessionID)
			return nil
		}

		// Set up GitHub client to fail when trying to get workflow job details
		// This simulates the scenario where GetWorkflowJobByID or GetWorkflowDetails fails
		gh := &github.NoopClient{
			MockGetWorkflowJobByID: func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
				return nil, errors.New("GitHub API failure")
			},
		}
		ghFactory := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClientLocal, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		// Create a job with ComputeID that matches the workflow run ID
		job := et.JobWithSessionID(jobs.JobStatusRunning, testSessionID)
		job.ComputeID = "123456" // This matches the workflow run ID below
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Workflow run with success conclusion but with JobID that will cause API failure
		jobID := int64(789) // This will cause GetWorkflowJobByID to fail
		workflowRun := &WorkflowRun{
			ID:          123456,
			JobID:       &jobID, // This will cause GetWorkflowJobByID to fail
			Path:        "dynamic/copilot-swe-agent/test",
			Conclusion:  "success",
			CompletedAt: 1234567890,
		}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: workflowRun,
		})

		// The handler should succeed despite the GitHub API failure
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		// Verify the job was finalized with correct status (from conclusion mapping)
		updatedJob, err := h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.NotNil(t, updatedJob.CompletedAt)

		// Verify the session was updated correctly despite nil workflow details
		require.True(t, updateSessionCalled, "session update should have been called")
		require.Equal(t, capi.SessionStateCompleted, capturedSessionState, "session should be marked as completed when job succeeds")
	})

	t.Run("falls back to conclusion mapping when workflow job conclusion is nil", func(t *testing.T) {
		testSessionID := "session-nil-conclusion"

		capiClientLocal, _, ghTwirp := commonHandlerDependencies()
		capiClientLocal.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		var capturedSessionState capi.SessionState
		capiClientLocal.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			updateSessionCalled = true
			capturedSessionState = update.State
			require.Equal(t, testSessionID, sessionID)
			return nil
		}

		// Set up GitHub client to return a workflow job with nil conclusion
		// This simulates rate-limiting where the API returns the job but conclusion is null
		gh := &github.NoopClient{
			MockGetWorkflowJobByID: func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
				// Return a workflow job but with nil conclusion (rate-limiting scenario)
				return &gg.WorkflowJob{
					ID:         &jobID,
					Conclusion: nil, // This is the key part - conclusion is nil due to rate limiting
				}, nil
			},
		}
		ghFactory := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClientLocal, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		// Create a job with ComputeID that matches the workflow run ID
		job := et.JobWithSessionID(jobs.JobStatusRunning, testSessionID)
		job.ComputeID = "123456" // This matches the workflow run ID below
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Workflow run with failure conclusion and JobID
		jobID := int64(789)
		workflowRun := &WorkflowRun{
			ID:          123456,
			JobID:       &jobID, // Job ID is present, so GetWorkflowJobByID will be called
			Path:        "dynamic/copilot-swe-agent/test",
			Conclusion:  "failure", // This is the conclusion from Hydro event that should be used
			CompletedAt: 1234567890,
		}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: workflowRun,
		})

		// The handler should succeed and fall back to conclusion mapping
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		// Verify the job was finalized with correct status (from conclusion mapping, not job details)
		updatedJob, err := h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, updatedJob.Status, "should use conclusion mapping when workflow job conclusion is nil")
		require.NotNil(t, updatedJob.CompletedAt)

		// Verify the session was updated with the correct state based on conclusion mapping
		require.True(t, updateSessionCalled, "session update should have been called")
		require.Equal(t, capi.SessionStateFailed, capturedSessionState, "session should be marked as failed based on conclusion mapping")
	})

	t.Run("falls back to conclusion mapping when workflow job is nil", func(t *testing.T) {
		testSessionID := "session-nil-job"

		capiClientLocal, _, ghTwirp := commonHandlerDependencies()
		capiClientLocal.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		var capturedSessionState capi.SessionState
		capiClientLocal.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			updateSessionCalled = true
			capturedSessionState = update.State
			require.Equal(t, testSessionID, sessionID)
			return nil
		}

		// Set up GitHub client to return nil workflow job
		// This simulates another case where the API call succeeds but returns nil
		gh := &github.NoopClient{
			MockGetWorkflowJobByID: func(ctx context.Context, owner, repo string, jobID int64) (*gg.WorkflowJob, error) {
				return nil, nil // Return nil workflow job (no error, but job is nil)
			},
		}
		ghFactory := &github.NoopClientFactory{
			MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClientLocal, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		// Create a job with ComputeID that matches the workflow run ID
		job := et.JobWithSessionID(jobs.JobStatusRunning, testSessionID)
		job.ComputeID = "123456" // This matches the workflow run ID below
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Workflow run with success conclusion and JobID
		jobID := int64(789)
		workflowRun := &WorkflowRun{
			ID:          123456,
			JobID:       &jobID, // Job ID is present, so GetWorkflowJobByID will be called
			Path:        "dynamic/copilot-swe-agent/test",
			Conclusion:  "success", // This is the conclusion from Hydro event that should be used
			CompletedAt: 1234567890,
		}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: workflowRun,
		})

		// The handler should succeed and fall back to conclusion mapping
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		// Verify the job was finalized with correct status (from conclusion mapping, not job details)
		updatedJob, err := h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status, "should use conclusion mapping when workflow job is nil")
		require.NotNil(t, updatedJob.CompletedAt)

		// Verify the session was updated with the correct state based on conclusion mapping
		require.True(t, updateSessionCalled, "session update should have been called")
		require.Equal(t, capi.SessionStateCompleted, capturedSessionState, "session should be marked as completed based on conclusion mapping")
	})
}
