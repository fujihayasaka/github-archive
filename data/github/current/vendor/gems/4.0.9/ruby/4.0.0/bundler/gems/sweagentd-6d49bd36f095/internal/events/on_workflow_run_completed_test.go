package events

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobutils"
	"github.com/github/sweagentd/internal/launcher"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/sweagentd"
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

	t.Run("skips workflow analysis but still does PR work when job is already terminal", func(t *testing.T) {
		listWorkflowJobsCalled := false

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		noopClient := &github.NoopClient{
			GithubAppLogin:         et.GitHubAppLogin,
			GithubBotLogin:         et.GitHubBotLogin,
			MockPullRequestContext: &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr},
			MockListWorkflowJobs: func(ctx context.Context, owner, repo string, runID int64) ([]*gg.WorkflowJob, error) {
				listWorkflowJobsCalled = true
				return nil, errors.New("should not be called")
			},
		}

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
			MockNewClientFromRepo: func(ctx context.Context, repoID, repoOwnerID int64) (github.ClientInterface, error) {
				return noopClient, nil
			},
		}

		h, _, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRun(),
		})

		require.NoError(t, err)
		require.False(t, listWorkflowJobsCalled, "ListWorkflowJobs should not be called for terminal jobs")

		// Verify PR work still ran by checking that GetPullRequestContext was called
		var prContextCalled bool
		for _, call := range noopClient.MethodCalls {
			if call.Method == "GetPullRequestContext" {
				prContextCalled = true
				break
			}
		}
		require.True(t, prContextCalled, "GetPullRequestContext should still be called for terminal jobs with a PR")
	})

	t.Run("skips PR operations when job has no pull request number", func(t *testing.T) {
		testSessionID := "session-no-pr"
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		capiClient.MockGetSession = func(ctx context.Context, sessionID string) (*capi.Session, error) {
			return &capi.Session{
				ID:    sessionID,
				State: capi.SessionStateInProgress,
			}, nil
		}
		updateSessionCalled := false
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
			require.Equal(t, testSessionID, sessionID)
			updateSessionCalled = true
			return nil
		}

		gh := &github.NoopClient{
			MockRepositoryContext: &github.RepositoryContext{
				Repository: *et.Repo(),
			},
			GithubAppLogin: et.GitHubAppLogin,
			GithubBotLogin: et.GitHubBotLogin,
		}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
				return gh, nil
			},
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create an assignment and job without a PR (PullRequestNumber = 0)
		assignment := et.AssignmentWithPR(0)
		h.jobsStore.CreateAssignment(context.Background(), assignment)

		job := et.JobWithPR(0, jobs.JobStatusRunning)
		job.SessionID = testSessionID
		h.jobsStore.CreateJob(context.Background(), job)

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithNumberAndConclusion(0, "success"),
		})

		require.NoError(t, err)

		// Verify job status was updated to completed
		updatedJob, err := h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, updatedJob.Status)
		require.NotNil(t, updatedJob.CompletedAt)

		// Verify session was updated
		require.True(t, updateSessionCalled, "expected session update to be called")

		// Verify no PR-related operations were performed (no method calls since GetPullRequestContext is skipped)
		require.False(t, gh.HasMethodCall("GetPullRequestContext"), "expected GetPullRequestContext to not be called for jobs without PR")
		require.Len(t, service.QueuedJobs(), 0, "expected no pending jobs to be queued since PR operations were skipped")
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

		require.True(t, gh.HasMethodCall("RequestReviewers"), "expected RequestReviewers to be called")
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

		require.False(t, gh.HasMethodCall("RequestReviewers"), "expected RequestReviewers not to be called")
	})

	t.Run("skips review request when actor is PR author", func(t *testing.T) {
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

		// Create a PR authored by the actor (work-on-current-branch scenario)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		gh.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}
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

		require.False(t, gh.HasMethodCall("RequestReviewers"), "expected RequestReviewers not to be called when actor is PR author")
	})

	t.Run("skips review request for code review agent jobs", func(t *testing.T) {
		const ccrAppID = int64(946600)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		capiClient.MockUpdateSession = func(ctx context.Context, sessionID string, update capi.SessionUpdate) error {
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

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Register a CCR app in the provider. CopilotCodeReview implements
		// sweagentd.AgenticAppReviewerAssignment with AssignActorAsReviewer()=false.
		ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-code-review", 0, "copilot-code-review-bot", "commit-login", "commit@email.com")
		h.appProvider = agenticapptest.NewTestProviderWithThirdPartyApps(t, 0, ccrApp)

		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		job := et.Job(jobs.JobStatusRunning)
		job.UseAsyncSessions = true
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		gh.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("success"),
			AgentID:     ccrAppID,
		})

		require.NoError(t, err)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, job.Status)

		require.False(t, gh.HasMethodCall("RequestReviewers"), "expected RequestReviewers not to be called for code review agent")
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

		require.True(t, gh.HasMethodCall("RequestReviewers"), "expected RequestReviewers to be called")
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

	t.Run("requests review even when UseAsyncSessions is true", func(t *testing.T) {
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

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
		job.UseAsyncSessions = true
		job.SessionID = "async-session-id"
		h.jobsStore.CreateJob(context.Background(), job)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{})
		err := h.OnWorkflowRunCompleted(ctx, WorkflowRunCompletedEvent{
			Repo:        EventWorkflowRepository(),
			WorkflowRun: EventWorkflowRunWithConclusion("success"),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusCompleted, job.Status)

		require.True(t, gh.HasMethodCall("RequestReviewers"), "expected RequestReviewers to be called even with async sessions")
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

	t.Run("launches pending job on PRs not authored by Copilot", func(t *testing.T) {
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
		require.Len(t, service.QueuedJobs(), 1)

		job, err = h.jobsStore.GetJob(context.Background(), job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.Equal(t, jobs.JobStatusFailed, job.Status)
		require.NotNil(t, job.CompletedAt)
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
			annotation:            "Some unknown cancellation reason",
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

		// Verify dynamic_workflow_completed metric has agent_id and agent_slug tags
		var workflowMetricCalls []stepMetricsDistributionCall
		for _, call := range distributionCalls {
			if call.key == "dynamic_workflow_completed" {
				workflowMetricCalls = append(workflowMetricCalls, call)
			}
		}
		require.Len(t, workflowMetricCalls, 1, "expected 1 dynamic_workflow_completed metric")
		require.Equal(t, "0", workflowMetricCalls[0].tags["agent_id"])
		require.Equal(t, "copilot", workflowMetricCalls[0].tags["agent_slug"])
		require.Equal(t, "success", workflowMetricCalls[0].tags["workflow_run_conclusion"])
		require.Equal(t, "success", workflowMetricCalls[0].tags["processing_request_conclusion"])

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

func TestProcessingRequestConclusion(t *testing.T) {
	t.Run("nil workflow job returns not_reached", func(t *testing.T) {
		require.Equal(t, "not_reached", processingRequestConclusion(nil))
	})

	t.Run("workflow job with no steps returns not_reached", func(t *testing.T) {
		require.Equal(t, "not_reached", processingRequestConclusion(&gg.WorkflowJob{}))
	})

	t.Run("workflow job without Processing Request step returns not_reached", func(t *testing.T) {
		conclusion := "success"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Setup Agent (Linux)"), Conclusion: &conclusion},
			{Name: gg.Ptr("Some user step"), Conclusion: &conclusion},
		}}
		require.Equal(t, "not_reached", processingRequestConclusion(job))
	})

	t.Run("Processing Request (Linux) success returns success", func(t *testing.T) {
		success := "success"
		skipped := "skipped"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &success},
			{Name: gg.Ptr("Processing Request (Windows)"), Conclusion: &skipped},
		}}
		require.Equal(t, "success", processingRequestConclusion(job))
	})

	t.Run("Processing Request (Linux) failure returns failure", func(t *testing.T) {
		failure := "failure"
		skipped := "skipped"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &failure},
			{Name: gg.Ptr("Processing Request (Windows)"), Conclusion: &skipped},
		}}
		require.Equal(t, "failure", processingRequestConclusion(job))
	})

	t.Run("Processing Request (Windows) success returns success when Linux is skipped", func(t *testing.T) {
		success := "success"
		skipped := "skipped"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &skipped},
			{Name: gg.Ptr("Processing Request (Windows)"), Conclusion: &success},
		}}
		require.Equal(t, "success", processingRequestConclusion(job))
	})

	t.Run("Processing Request cancelled returns cancelled", func(t *testing.T) {
		cancelled := "cancelled"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &cancelled},
		}}
		require.Equal(t, "cancelled", processingRequestConclusion(job))
	})

	t.Run("both variants skipped returns not_reached", func(t *testing.T) {
		skipped := "skipped"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &skipped},
			{Name: gg.Ptr("Processing Request (Windows)"), Conclusion: &skipped},
		}}
		require.Equal(t, "not_reached", processingRequestConclusion(job))
	})

	t.Run("nil step is ignored", func(t *testing.T) {
		success := "success"
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			nil,
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &success},
		}}
		require.Equal(t, "success", processingRequestConclusion(job))
	})

	t.Run("Processing Request with empty conclusion returns not_reached", func(t *testing.T) {
		empty := ""
		job := &gg.WorkflowJob{Steps: []*gg.TaskStep{
			{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &empty},
		}}
		require.Equal(t, "not_reached", processingRequestConclusion(job))
	})
}

func TestNotifyCustomSetupStepFailure(t *testing.T) {
	const (
		ccrAppID         = int64(946600)
		ccaAppID         = int64(12345)
		repoID           = int64(987)
		prNumber         = 42
		runID            = int64(7777)
		customStepName   = "Install pnpm"
		customStepName2  = "Run database migrations"
		outsideStepName  = "Processing Request (Linux)"
		outsideStepName2 = "Set up runner"
	)

	failure := "failure"
	ccrApp := agenticapp.NewCopilotCodeReview(ccrAppID, "copilot-pull-request-reviewer", 1, "copilot-pull-request-reviewer[bot]", "commit-login", "commit@email.com")
	// CCA does not implement AgenticAppSetupStepFailureNotifier and stays silent.
	ccaApp := agenticapp.NewCopilot(ccaAppID, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	repo := &gg.Repository{
		ID:      gg.Ptr(repoID),
		Name:    gg.Ptr("test-repo"),
		HTMLURL: gg.Ptr("https://github.com/test-owner/test-repo"),
		Owner:   &gg.User{Login: gg.Ptr("test-owner")},
	}
	run := &WorkflowRun{ID: runID}

	customStep := &gg.TaskStep{Name: gg.Ptr(customStepName), Conclusion: &failure}
	customStep2 := &gg.TaskStep{Name: gg.Ptr(customStepName2), Conclusion: &failure}
	outsideStep := &gg.TaskStep{Name: gg.Ptr(outsideStepName), Conclusion: &failure}
	outsideStep2 := &gg.TaskStep{Name: gg.Ptr(outsideStepName2), Conclusion: &failure}

	stepWithFence := &gg.TaskStep{
		Name:       gg.Ptr("foo```\n## Spoofed heading"),
		Conclusion: &failure,
	}

	// wrap returns a Linux+Windows Starting/Finishing wrapper pair around the
	// supplied steps, mirroring what launcher.sessionLogStep{Linux,Windows} emit
	// in the rendered workflow.
	wrap := func(steps ...*gg.TaskStep) []*gg.TaskStep {
		wrapped := make([]*gg.TaskStep, 0, len(steps)+4)
		wrapped = append(wrapped,
			&gg.TaskStep{Name: gg.Ptr(launcher.UserSetupStepStartLinuxName)},
			&gg.TaskStep{Name: gg.Ptr(launcher.UserSetupStepStartWindowsName)},
		)
		wrapped = append(wrapped, steps...)
		wrapped = append(wrapped,
			&gg.TaskStep{Name: gg.Ptr(launcher.UserSetupStepFinishLinuxName)},
			&gg.TaskStep{Name: gg.Ptr(launcher.UserSetupStepFinishWindowsName)},
		)
		return wrapped
	}

	// makeDetails builds WorkflowJobDetails whose WorkflowJob.Steps is the
	// concatenation of timelineSteps and whose FailedSteps list mirrors the
	// failures the caller wants to assert on. Callers are responsible for
	// ensuring the FailedSteps pointers also appear inside timelineSteps when
	// they are expected to be reported.
	makeDetails := func(timelineSteps []*gg.TaskStep, failedSteps []*gg.TaskStep) *jobutils.WorkflowJobDetails {
		return &jobutils.WorkflowJobDetails{
			WorkflowJob: &gg.WorkflowJob{Steps: timelineSteps},
			FailedSteps: failedSteps,
		}
	}

	type testCase struct {
		name               string
		app                sweagentd.AgenticApp
		prNumber           int
		details            *jobutils.WorkflowJobDetails
		wantCommentCalls   int
		wantBodyContains   []string
		wantBodyNotContain []string
	}

	cases := []testCase{
		{
			name:     "CCR with single failed custom step posts one comment",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				wrap(customStep),
				[]*gg.TaskStep{customStep},
			),
			wantCommentCalls: 1,
			wantBodyContains: []string{
				customStepName,
				"https://github.com/test-owner/test-repo/actions/runs/7777",
				"<!-- copilot-coding-agent-error: ccr-setup-step-failure -->",
				"failing step above",
			},
		},
		{
			name:     "CCR with multiple failed custom steps consolidates into a single comment",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				append(wrap(customStep), wrap(customStep2)...),
				[]*gg.TaskStep{customStep, customStep2},
			),
			wantCommentCalls: 1,
			wantBodyContains: []string{
				customStepName,
				customStepName2,
				"failing steps above",
			},
		},
		{
			name:     "CCR with only a failed step outside the wrapper pair does not post",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				// wrapper pair exists (so a copilot-setup-steps.yml was rendered),
				// but the failure lands outside it.
				append(wrap(&gg.TaskStep{Name: gg.Ptr(customStepName)}), outsideStep),
				[]*gg.TaskStep{outsideStep},
			),
			wantCommentCalls: 0,
		},
		{
			name:     "CCR with no wrapper pair (no custom setup steps configured) does not post",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				[]*gg.TaskStep{outsideStep, outsideStep2},
				[]*gg.TaskStep{outsideStep, outsideStep2},
			),
			wantCommentCalls: 0,
		},
		{
			name:     "CCR with a mix of outside-wrapper and inside-wrapper failures only reports inside-wrapper",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				append(wrap(customStep), outsideStep),
				[]*gg.TaskStep{outsideStep, customStep},
			),
			wantCommentCalls:   1,
			wantBodyContains:   []string{customStepName},
			wantBodyNotContain: []string{outsideStepName},
		},
		{
			name:     "CCA (no opt-in interface) does not post even when custom steps fail",
			app:      ccaApp,
			prNumber: prNumber,
			details: makeDetails(
				wrap(customStep),
				[]*gg.TaskStep{customStep},
			),
			wantCommentCalls: 0,
		},
		{
			name:     "CCR with no PR number does not post",
			app:      ccrApp,
			prNumber: 0,
			details: makeDetails(
				wrap(customStep),
				[]*gg.TaskStep{customStep},
			),
			wantCommentCalls: 0,
		},
		{
			name:             "CCR with nil details does not post",
			app:              ccrApp,
			prNumber:         prNumber,
			details:          nil,
			wantCommentCalls: 0,
		},
		{
			// With Option B (timeline-walk), the function looks at
			// WorkflowJob.Steps directly, not FailedSteps. A timeline
			// containing only healthy user steps inside wrappers produces no
			// failed names and no comment.
			name:     "CCR with no failed step inside the wrapper pair does not post",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				wrap(&gg.TaskStep{Name: gg.Ptr(customStepName), Conclusion: gg.Ptr("success")}),
				nil,
			),
			wantCommentCalls: 0,
		},
		{
			name:     "CCR strips triple backticks from step names so the code fence cannot be terminated",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				wrap(stepWithFence),
				[]*gg.TaskStep{stepWithFence},
			),
			wantCommentCalls: 1,
			wantBodyNotContain: []string{
				"foo```",
			},
		},
		{
			// Defensive: details is non-nil with FailedSteps populated but
			// WorkflowJob is nil. collectUserSetupStepNames returns an empty
			// set, so we bail before attempting to dereference Steps.
			name:     "CCR with nil WorkflowJob does not post and does not panic",
			app:      ccrApp,
			prNumber: prNumber,
			details: &jobutils.WorkflowJobDetails{
				WorkflowJob: nil,
				FailedSteps: []*gg.TaskStep{customStep},
			},
			wantCommentCalls: 0,
		},
		{
			// Defensive: WorkflowJob.Steps contains a nil entry. The handler
			// skips it without dereferencing.
			name:     "CCR with nil entry in WorkflowJob.Steps skips the nil and reports the rest",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				[]*gg.TaskStep{
					{Name: gg.Ptr(launcher.UserSetupStepStartLinuxName)},
					{Name: gg.Ptr(launcher.UserSetupStepStartWindowsName)},
					nil,
					customStep,
					nil,
					{Name: gg.Ptr(launcher.UserSetupStepFinishLinuxName)},
					{Name: gg.Ptr(launcher.UserSetupStepFinishWindowsName)},
				},
				nil,
			),
			wantCommentCalls: 1,
			wantBodyContains: []string{customStepName},
		},
		{
			// Multi-pair scenario: a healthy first user step bracketed by a
			// Start/Finish pair, then a failing second user step bracketed by
			// its own pair. Only the failure should be reported, and the
			// `inside` toggle must correctly reset between pairs.
			name:     "CCR with multiple wrapper pairs reports only the failed inside-wrapper step",
			app:      ccrApp,
			prNumber: prNumber,
			details: makeDetails(
				append(
					wrap(&gg.TaskStep{Name: gg.Ptr("Healthy first step")}),
					wrap(customStep)...,
				),
				[]*gg.TaskStep{customStep},
			),
			wantCommentCalls:   1,
			wantBodyContains:   []string{customStepName},
			wantBodyNotContain: []string{"Healthy first step"},
		},
		{
			// Realistic timeline shape: runner-injected steps surround the
			// dynamic-workflow framework steps and the user-wrapped block.
			// Only the user step inside the wrapper pair should be reported.
			// Failed steps share pointer identity with their entry in
			// WorkflowJob.Steps, mirroring what jobutils.getFailedSteps
			// produces.
			name:     "CCR with realistic timeline reports only steps inside the wrapper pair",
			app:      ccrApp,
			prNumber: prNumber,
			details: func() *jobutils.WorkflowJobDetails {
				setUpRunner := &gg.TaskStep{Name: gg.Ptr("Set up runner"), Conclusion: &failure}
				processing := &gg.TaskStep{Name: gg.Ptr("Processing Request (Linux)"), Conclusion: &failure}
				timeline := append(
					[]*gg.TaskStep{
						{Name: gg.Ptr("Set up job")},
						setUpRunner,
						{Name: gg.Ptr("Initialize")},
						{Name: gg.Ptr("Prepare Copilot (Linux)")},
					},
					append(
						wrap(customStep),
						processing,
						&gg.TaskStep{Name: gg.Ptr("Complete runner")},
						&gg.TaskStep{Name: gg.Ptr("Complete job")},
					)...,
				)
				return makeDetails(timeline, []*gg.TaskStep{setUpRunner, customStep, processing})
			}(),
			wantCommentCalls: 1,
			wantBodyContains: []string{customStepName},
			wantBodyNotContain: []string{
				"Set up runner",
				"Processing Request (Linux)",
			},
		},
		{
			// Regression for the name-collision bug: an outside-wrapper step
			// fails AND happens to share a display name with an inside-wrapper
			// user step. Pointer-identity scoping must report only the
			// inside-wrapper failure, not the outside one.
			name:     "CCR with outside-wrapper failure that shares a display name with an inside-wrapper step reports only the inside failure",
			app:      ccrApp,
			prNumber: prNumber,
			details: func() *jobutils.WorkflowJobDetails {
				insideSetup := &gg.TaskStep{Name: gg.Ptr("Setup"), Conclusion: &failure}
				outsideLookalike := &gg.TaskStep{Name: gg.Ptr("Setup"), Conclusion: &failure}
				timeline := append(
					[]*gg.TaskStep{outsideLookalike},
					wrap(insideSetup)...,
				)
				// Both failures appear in FailedSteps with distinct pointers,
				// as jobutils.getFailedSteps would emit them.
				return makeDetails(timeline, []*gg.TaskStep{outsideLookalike, insideSetup})
			}(),
			wantCommentCalls: 1,
			wantBodyContains: []string{"Setup", "failing step above"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			obsv := observability.NewNoopExporters()
			h := &Handler{obsv: obsv, ffClient: featureflags.NewNoopClient(nil)}
			gh := &github.NoopClient{}
			job := &jobs.Job{RepoID: repoID, PullRequestNumber: tc.prNumber}

			h.notifyCustomSetupStepFailure(context.Background(), gh, tc.app, job, repo, run, tc.details)

			var createCommentCalls []github.MethodCall
			for _, call := range gh.MethodCalls {
				if call.Method == "CreateComment" {
					createCommentCalls = append(createCommentCalls, call)
				}
			}
			require.Len(t, createCommentCalls, tc.wantCommentCalls, "unexpected CreateComment call count")
			if tc.wantCommentCalls == 0 {
				return
			}

			// Args: []any{repoID, issueOrPRNumber, body}
			require.Equal(t, repoID, createCommentCalls[0].Args[0])
			require.Equal(t, prNumber, createCommentCalls[0].Args[1])
			body, ok := createCommentCalls[0].Args[2].(string)
			require.True(t, ok, "body should be a string")
			for _, want := range tc.wantBodyContains {
				require.Contains(t, body, want)
			}
			for _, unwanted := range tc.wantBodyNotContain {
				require.NotContains(t, body, unwanted)
			}
		})
	}
}

func TestCollectFailedUserSetupStepNames(t *testing.T) {
	failure := "failure"
	success := "success"
	skipped := "skipped"
	step := func(name string) *gg.TaskStep {
		return &gg.TaskStep{Name: gg.Ptr(name)}
	}
	failingStep := func(name string) *gg.TaskStep {
		return &gg.TaskStep{Name: gg.Ptr(name), Conclusion: &failure}
	}
	startL := step(launcher.UserSetupStepStartLinuxName)
	startW := step(launcher.UserSetupStepStartWindowsName)
	finishL := step(launcher.UserSetupStepFinishLinuxName)
	finishW := step(launcher.UserSetupStepFinishWindowsName)

	cases := []struct {
		name string
		job  *gg.WorkflowJob
		want []string
	}{
		{
			name: "nil workflow job returns empty",
			job:  nil,
		},
		{
			name: "empty steps returns empty",
			job:  &gg.WorkflowJob{},
		},
		{
			name: "no wrapper markers returns empty even with outside failures",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				failingStep("Set up job"),
				failingStep("Set up runner"),
			}},
		},
		{
			name: "single failing inside-wrapper step is collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				step("Set up job"),
				startL, startW,
				failingStep("Install pnpm"),
				finishL, finishW,
			}},
			want: []string{"Install pnpm"},
		},
		{
			name: "healthy inside-wrapper step is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				{Name: gg.Ptr("Install pnpm"), Conclusion: &success},
				finishL, finishW,
			}},
		},
		{
			name: "skipped inside-wrapper step is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				{Name: gg.Ptr("Install pnpm"), Conclusion: &skipped},
				finishL, finishW,
			}},
		},
		{
			name: "step with nil Conclusion inside wrappers is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				{Name: gg.Ptr("Install pnpm")}, // no conclusion
				finishL, finishW,
			}},
		},
		{
			name: "outside-wrapper failure is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				failingStep("Set up runner"),
				startL, startW,
				{Name: gg.Ptr("Install pnpm"), Conclusion: &success},
				finishL, finishW,
			}},
		},
		{
			name: "mix of healthy and failing across multiple wrapper pairs returns only failures in order",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				{Name: gg.Ptr("Healthy first step"), Conclusion: &success},
				finishL, finishW,
				startL, startW,
				failingStep("Run database migrations"),
				finishL, finishW,
				startL, startW,
				failingStep("Install pnpm"),
				finishL, finishW,
			}},
			want: []string{"Run database migrations", "Install pnpm"},
		},
		{
			name: "duplicate inside-wrapper failure names are preserved (timeline order, not deduped)",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				failingStep("Setup"),
				finishL, finishW,
				startL, startW,
				failingStep("Setup"),
				finishL, finishW,
			}},
			want: []string{"Setup", "Setup"},
		},
		{
			name: "nil entries in Steps are skipped without affecting the toggle",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				nil,
				failingStep("Install pnpm"),
				nil,
				finishL, finishW,
			}},
			want: []string{"Install pnpm"},
		},
		{
			name: "failing step with empty name inside wrappers is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				{Name: gg.Ptr(""), Conclusion: &failure},
				failingStep("Real step"),
				{Name: nil, Conclusion: &failure},
				finishL, finishW,
			}},
			want: []string{"Real step"},
		},
		{
			name: "leading and trailing whitespace in step names is trimmed",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				{Name: gg.Ptr("  Install pnpm  "), Conclusion: &failure},
				finishL, finishW,
			}},
			want: []string{"Install pnpm"},
		},
		{
			name: "orphan Finish before any Start is a no-op",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				failingStep("Should not be collected"),
				finishL,
				failingStep("Also should not be collected"),
				startL, startW,
				failingStep("Should be collected"),
				finishL, finishW,
			}},
			want: []string{"Should be collected"},
		},
		{
			// An orphan Start (no matching Finish) latches the toggle for the
			// remainder of the timeline. Documented limitation; launcher
			// always emits matched pairs.
			name: "orphan Start latches the toggle until end of list",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				failingStep("Inside pair one"),
				finishL, finishW,
				startL,
				failingStep("After orphan start"),
				{Name: gg.Ptr("Successful after orphan start"), Conclusion: &success},
				failingStep("Also after orphan start"),
			}},
			want: []string{"Inside pair one", "After orphan start", "Also after orphan start"},
		},
		{
			// Regression for the name-collision bug raised in PR review: a
			// failing step outside the wrapper region whose display name
			// coincides with an inside-wrapper step's name must NOT be
			// collected, even if both have Conclusion=failure.
			name: "outside-wrapper failure with same display name as inside-wrapper failure is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				failingStep("Setup"), // outside, must NOT be reported
				startL, startW,
				failingStep("Setup"), // inside, MUST be reported
				finishL, finishW,
			}},
			want: []string{"Setup"},
		},
		{
			// Defensive: a user step named exactly like a wrapper marker is
			// treated as a marker. Documented limitation; collision is
			// unlikely given the verbose wrapper names.
			name: "user step colliding with marker name is not collected",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				startL, startW,
				failingStep(launcher.UserSetupStepStartLinuxName), // collides; not collected
				failingStep("Real step"),
				finishL, finishW,
			}},
			want: []string{"Real step"},
		},
		{
			// Wrappers run on (success() || !cancelled()) and toggle based on
			// name regardless of step conclusion. Skipped wrapper steps (e.g.,
			// the Windows pair on a Linux runner) still appear in the timeline
			// and must be honored.
			name: "skipped or cancelled wrapper steps still toggle correctly",
			job: &gg.WorkflowJob{Steps: []*gg.TaskStep{
				{Name: gg.Ptr(launcher.UserSetupStepStartLinuxName), Conclusion: &success},
				{Name: gg.Ptr(launcher.UserSetupStepStartWindowsName), Conclusion: &skipped},
				failingStep("Install pnpm"),
				{Name: gg.Ptr(launcher.UserSetupStepFinishLinuxName), Conclusion: &success},
				{Name: gg.Ptr(launcher.UserSetupStepFinishWindowsName), Conclusion: &skipped},
			}},
			want: []string{"Install pnpm"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := collectFailedUserSetupStepNames(tc.job)
			require.Equal(t, tc.want, got)
		})
	}
}
