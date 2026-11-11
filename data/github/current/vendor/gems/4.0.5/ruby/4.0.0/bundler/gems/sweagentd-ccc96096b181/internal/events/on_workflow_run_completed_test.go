package events

import (
	"context"
	"errors"
	"testing"
	"time"

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

		// Create a simple repository for the test
		ggRepo := gg.Repository{
			Name: gg.Ptr("repo"),
			Owner: &gg.User{
				Login: gg.Ptr("owner"),
			},
		}

		session, err := h.updateSessionFromWorkflow(ctx, gh, job, &ggRepo, workflowDetails)

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

	// Test basic job status updates using ListWorkflowJobs
	statusUpdateTestCases := []struct {
		name             string
		conclusion       string
		expectedStatus   jobs.JobStatus
		needsGitHubMocks bool // whether this test needs GitHub API mocks
	}{
		{
			name:             "updates job status to completed",
			conclusion:       "success",
			expectedStatus:   jobs.JobStatusCompleted,
			needsGitHubMocks: true,
		},
		{
			name:             "updates job status to cancelled",
			conclusion:       "cancelled",
			expectedStatus:   jobs.JobStatusCancelled,
			needsGitHubMocks: true,
		},
	}

	for _, tc := range statusUpdateTestCases {
		t.Run(tc.name, func(t *testing.T) {
			var ghFactory *github.NoopClientFactory

			if tc.needsGitHubMocks {
				// Mock ListWorkflowJobs to return job details for GetWorkflowDetails
				gh := &github.NoopClient{
					MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
						return []*gg.WorkflowJob{
							{
								ID:         gg.Ptr(int64(789)),
								Conclusion: gg.Ptr(tc.conclusion),
							},
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

			workflowRun := EventWorkflowRunWithConclusion(tc.conclusion)
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
		require.Equal(t, requestReviewersCall.Args[0], "test-owner")
		require.Equal(t, requestReviewersCall.Args[1], "test-repo")
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
		require.Equal(t, requestReviewersCall.Args[0], "test-owner")
		require.Equal(t, requestReviewersCall.Args[1], "test-repo")
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

			// Mock ListWorkflowJobs to get job details for GetWorkflowDetails
			gh := &github.NoopClient{
				MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
					return []*gg.WorkflowJob{
						{
							ID:         gg.Ptr(int64(789)),
							Conclusion: &tc.workflowJobConclusion,
						},
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
			ghFactory := &github.NoopClientFactory{
				MockNewClient: func(token string) github.ClientInterface {
					return gh
				},
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
				WorkflowRun: EventWorkflowRunWithConclusion(tc.workflowRunConclusion),
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
				MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
					return []*gg.WorkflowJob{
						{
							ID:         gg.Ptr(int64(789)),
							Conclusion: &cancelled,
						},
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
				MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
					return gh, nil
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
				WorkflowRun: EventWorkflowRunWithConclusion(cancelled),
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

		// Set up GitHub client to fail when trying to list workflow jobs
		// This simulates the scenario where ListWorkflowJobs fails
		gh := &github.NoopClient{
			MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
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

		// Workflow run with success conclusion but ListWorkflowJobs will fail
		workflowRun := &WorkflowRun{
			ID:          123456,
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
			MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
				// Return a workflow job but with nil conclusion (rate-limiting scenario)
				return []*gg.WorkflowJob{
					{
						ID:         gg.Ptr(int64(789)),
						Conclusion: nil, // This is the key part - conclusion is nil due to rate limiting
					},
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

		// Workflow run with failure conclusion
		workflowRun := &WorkflowRun{
			ID:          123456,
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

	t.Run("falls back to conclusion mapping when workflow jobs list is empty", func(t *testing.T) {
		testSessionID := "session-no-jobs"

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

		// Set up GitHub client to return empty workflow jobs list
		// This simulates another case where the API call succeeds but returns no jobs
		gh := &github.NoopClient{
			MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
				return []*gg.WorkflowJob{}, nil // Return empty list
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

		// Workflow run with success conclusion
		workflowRun := &WorkflowRun{
			ID:          123456,
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
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status, "should use conclusion mapping when workflow jobs list is empty")
		require.NotNil(t, updatedJob.CompletedAt)

		// Verify the session was updated with the correct state based on conclusion mapping
		require.True(t, updateSessionCalled, "session update should have been called")
		require.Equal(t, capi.SessionStateCompleted, capturedSessionState, "session should be marked as completed based on conclusion mapping")
	})

	t.Run("handles workflow run by listing workflow jobs", func(t *testing.T) {
		testSessionID := "test-session-id"

		capiClientLocal, _, ghTwirp := commonHandlerDependencies()
		capiClientLocal.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		capiClientLocal.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			require.Equal(t, testSessionID, sessionID)
			require.Equal(t, capi.SessionStateCompleted, update.State)
			updateSessionCalled = true
			return nil
		}

		// Mock ListWorkflowJobs to return a single completed job
		mockListWorkflowJobs := func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
			return []*gg.WorkflowJob{
				{
					ID:          gg.Ptr(int64(789)),
					Name:        gg.Ptr("test-job"),
					Status:      gg.Ptr("completed"),
					Conclusion:  gg.Ptr("success"),
					StartedAt:   &gg.Timestamp{},
					CompletedAt: &gg.Timestamp{},
				},
			}, nil
		}

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return &github.NoopClient{
					GithubAppLogin:         et.GitHubAppLogin,
					GithubBotLogin:         et.GitHubBotLogin,
					MockPullRequestContext: &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *et.PullRequest(*et.UserCopilot())},
					MockListWorkflowJobs:   mockListWorkflowJobs,
				}, nil
			},
		}

		h, _, _ := NewTestHandler(t, obsv, capiClientLocal, ffClient, memory.NewStore(), ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.JobWithSessionID(jobs.JobStatusRunning, testSessionID)
		job.ComputeID = "123456" // This matches the workflow run ID below
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Workflow run that will use ListWorkflowJobs to get job details
		workflowRun := &WorkflowRun{
			ID:          123456,
			Path:        "dynamic/copilot-swe-agent/test",
			Conclusion:  "success",
			CompletedAt: 1234567890,
		}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: workflowRun,
		})

		require.NoError(t, err)

		// Verify the job was finalized correctly
		updatedJob, err := h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.NotNil(t, updatedJob.CompletedAt)

		// Verify the session was updated
		require.True(t, updateSessionCalled, "expected session update to be called")
	})

	t.Run("emits step duration metrics for well-known steps", func(t *testing.T) {
		testSessionID := "session-step-metrics"
		updateSessionCalled := false

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			updateSessionCalled = true
			return nil
		}

		// Track DistributionMs calls
		var distributionCalls []stepMetricsDistributionCall

		obsv := observability.NewNoopExporters()
		obsv.Statter = &stepMetricsTestStatter{
			NullClient: stats.NullClient{},
			calls:      &distributionCalls,
		}

		startTime := time.Date(2024, 1, 1, 10, 0, 0, 0, time.UTC)
		endTime := time.Date(2024, 1, 1, 10, 5, 0, 0, time.UTC) // 5 minutes later

		gh := &github.NoopClient{
			MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
				success := "success"
				return []*gg.WorkflowJob{
					{
						ID:         gg.Ptr(int64(789)),
						Conclusion: &success,
						Steps: []*gg.TaskStep{
							{
								Name:        gg.Ptr("Processing Request (Linux)"),
								Conclusion:  &success,
								StartedAt:   &gg.Timestamp{Time: startTime},
								CompletedAt: &gg.Timestamp{Time: endTime},
							},
							{
								Name:        gg.Ptr("Custom User Step"),
								Conclusion:  &success,
								StartedAt:   &gg.Timestamp{Time: startTime},
								CompletedAt: &gg.Timestamp{Time: endTime},
							},
							{
								Name:        gg.Ptr("Clean Up (Linux)"),
								Conclusion:  &success,
								StartedAt:   &gg.Timestamp{Time: endTime},
								CompletedAt: &gg.Timestamp{Time: endTime.Add(30 * time.Second)},
							},
						},
					},
				}, nil
			},
		}

		ghFactory := &github.NoopClientFactory{
			MockNewClient: func(token string) github.ClientInterface {
				return gh
			},
			MockNewClientFromRepo: func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.Job(jobs.JobStatusRunning)
		job.SessionID = testSessionID
		job.ComputeID = "123456" // This matches the workflow run ID below
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		workflowRun := &WorkflowRun{
			ID:          123456,
			Path:        "dynamic/copilot-swe-agent/test",
			Conclusion:  "success",
			CompletedAt: 1234567890,
		}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: workflowRun,
		})

		require.NoError(t, err)

		// Verify the job was finalized correctly
		updatedJob, err := h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)

		// Verify that step metrics were emitted for well-known steps only
		stepMetricCalls := []stepMetricsDistributionCall{}
		for _, call := range distributionCalls {
			if call.key == "dynamic_workflow_step_duration" {
				stepMetricCalls = append(stepMetricCalls, call)
			}
		}

		// Should have 2 step metric calls: "Processing Request (Linux)" and "Clean Up (Linux)"
		// "Custom User Step" should not have a metric since it's not a well-known step
		require.Len(t, stepMetricCalls, 2, "expected 2 step metrics for well-known steps")

		// Verify the step names in the tags
		stepNames := make([]string, 0, len(stepMetricCalls))
		for _, call := range stepMetricCalls {
			if name, ok := call.tags["step_name"]; ok {
				stepNames = append(stepNames, name)
			}
		}
		require.Contains(t, stepNames, "Processing Request (Linux)")
		require.Contains(t, stepNames, "Clean Up (Linux)")

		// Verify step conclusions are included
		for _, call := range stepMetricCalls {
			conclusion, ok := call.tags["step_conclusion"]
			require.True(t, ok, "expected step_conclusion tag to be present")
			require.Equal(t, "success", conclusion)
		}

		// Verify durations are correct
		for _, call := range stepMetricCalls {
			if call.tags["step_name"] == "Processing Request (Linux)" {
				require.Equal(t, 5*time.Minute, call.duration)
			}
			if call.tags["step_name"] == "Clean Up (Linux)" {
				require.Equal(t, 30*time.Second, call.duration)
			}
		}

		require.True(t, updateSessionCalled, "expected session update to be called")
	})
}

// stepMetricsDistributionCall captures the arguments to a DistributionMs call
type stepMetricsDistributionCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

// stepMetricsTestStatter is a test helper that captures DistributionMs calls
type stepMetricsTestStatter struct {
	stats.NullClient

	calls *[]stepMetricsDistributionCall
}

func (s *stepMetricsTestStatter) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	*s.calls = append(*s.calls, stepMetricsDistributionCall{key: key, tags: tags, duration: duration})
}
