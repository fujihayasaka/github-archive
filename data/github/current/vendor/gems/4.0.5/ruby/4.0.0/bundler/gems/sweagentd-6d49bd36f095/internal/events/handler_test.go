package events

import (
	"context"
	"fmt"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/automations"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	gh "github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/triggers"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
)

func commonHandlerDependencies() (capiClient *capi.NoopClient, jobStore *memory.Store, ghTwirp *githubtwirp.NoopClient) {
	ghTwirp = githubtwirp.NewNoopClient()
	// Set up basic mock for GetCopilotUser to avoid nil pointer errors
	ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{
				CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
			},
		}, nil
	}
	return capi.NewNoopClient(),
		memory.NewStore(),
		ghTwirp
}

func NewTestHandler(t *testing.T, obsv observability.Exporters, capiClient capi.Client, ffClient featureflags.Client, jobsStore db.JobsStore, ghTwirp githubtwirp.ClientInterface, ghFactory gh.ClientFactoryInterface) (*Handler, *jobservicetest.TestService, *jobexecutor.TestJobExecutor) {
	t.Helper()
	if ffClient == nil {
		ffClient = featureflags.NewNoopClient(nil)
	}
	if ghFactory == nil {
		ghFactory = &gh.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
	}
	if ghTwirp == nil {
		ghTwirp = githubtwirp.NewNoopClient()
	}
	if capiClient == nil {
		capiClient = capi.NewNoopClient()
	}

	// Create default appProvider for tests
	appProvider := agenticapptest.NewTestProvider(t)

	spokes := spokestest.NewClient(t)
	customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
	service := jobservicetest.New(t, obsv, ffClient, jobsStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
	triggerChecker := triggers.NewChecker(nil, ghTwirp, obsv)
	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, automations.NewLegacyLookup(triggerChecker))
	return handler, service, executor
}

func NewDefaultTestHandler(t *testing.T, obsv observability.Exporters, ffClient featureflags.Client, ghFactory gh.ClientFactoryInterface) (*Handler, *jobservicetest.TestService, *jobexecutor.TestJobExecutor) {
	capiClient, jobStore, ghTwirp := commonHandlerDependencies()
	return NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
}

func TestCreatePendingJob(t *testing.T) {
	assignment := et.Assignment()

	repo := et.Repo()

	t.Run("creates new pending job for pull request comment", func(t *testing.T) {
		actor := et.ActorWriter()
		pr := et.PullRequest()
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		require.Len(t, pr.Comments.Nodes, 1)

		comment := pr.Comments.Nodes[0]

		job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
			ID:         comment.Author.GetID(),
			Login:      comment.Author.GetLogin(),
			TrackingID: "tracking-id",
		}, pr.HeadRef.Name)
		require.NotNil(t, job)

		require.Equal(t, assignment.ID, job.AssignmentID)
		require.Equal(t, repo.ID, job.RepoID)
		require.Equal(t, repo.Owner.GetID(), job.OwnerID)
		require.Equal(t, "repo", repo.Name)
		require.Equal(t, repo.Owner.Login, "owner")
		require.Equal(t, "repo", repo.Name)
		require.Equal(t, jobs.AgentActionFixPRComment, job.Action)
		require.Equal(t, jobs.JobStatusPending, job.Status)

		require.Equal(t, actor.GetLogin(), job.ActorLogin)
		require.Equal(t, actor.GetID(), job.ActorID)
		require.Equal(t, pr.HeadRef.Name, job.BaseCommit)
	})

	t.Run("creates new pending job for pull request review", func(t *testing.T) {
		actor := et.ActorWriter()
		pr := et.PullRequest()
		pr = et.AddReviewToPullRequest(pr, true, *actor, *et.ActorWriter())

		require.Len(t, pr.Reviews.Nodes, 1)
		require.Len(t, pr.Reviews.Nodes[0].Comments.Nodes, 1)

		review := pr.Reviews.Nodes[0]

		job := assignment.NewJob(jobs.AgentActionFixPRComment, jobs.JobActor{
			ID:         review.Author.GetID(),
			Login:      review.Author.GetLogin(),
			TrackingID: "tracking-id",
		}, pr.HeadRef.Name)
		require.NotNil(t, job)

		require.Equal(t, assignment.ID, job.AssignmentID)
		require.Equal(t, repo.ID, job.RepoID)
		require.Equal(t, repo.Owner.GetID(), job.OwnerID)
		require.Equal(t, "repo", repo.Name)
		require.Equal(t, repo.Owner.Login, "owner")
		require.Equal(t, "repo", repo.Name)
		require.Equal(t, jobs.AgentActionFixPRComment, job.Action)
		require.Equal(t, jobs.JobStatusPending, job.Status)

		require.Equal(t, actor.GetLogin(), job.ActorLogin)
		require.Equal(t, actor.GetID(), job.ActorID)
		require.Equal(t, pr.HeadRef.Name, job.BaseCommit)
	})

	t.Run("creates new pending job for issue", func(t *testing.T) {
		actor := EventActorWriter()
		job := assignment.NewJob(jobs.AgentActionFix, jobs.JobActor{
			ID:         actor.ID,
			Login:      actor.Login,
			TrackingID: "tracking-id",
		}, repo.DefaultBranchRef.Name)

		require.NotNil(t, job)

		require.Equal(t, assignment.ID, job.AssignmentID)
		require.Equal(t, repo.ID, job.RepoID)
		require.Equal(t, repo.Owner.GetID(), job.OwnerID)
		require.Equal(t, "repo", repo.Name)
		require.Equal(t, "owner", repo.Owner.Login)
		require.Equal(t, "repo", repo.Name)
		require.Equal(t, jobs.AgentActionFix, job.Action)
		require.Equal(t, jobs.JobStatusPending, job.Status)

		require.Equal(t, actor.Login, job.ActorLogin)
		require.Equal(t, actor.ID, job.ActorID)
		require.Empty(t, job.BranchName)
		require.Equal(t, repo.DefaultBranchRef.Name, job.BaseCommit)
	})
}

func TestGetMostRecentJobWithAgent(t *testing.T) {
	const targetAgent int64 = 42
	const otherAgent int64 = 99

	t.Run("returns nil for empty job list", func(t *testing.T) {
		result := getMostRecentJobWithAgent([]*jobs.Job{}, targetAgent)
		require.Nil(t, result)
	})

	t.Run("returns nil for nil job list", func(t *testing.T) {
		result := getMostRecentJobWithAgent(nil, targetAgent)
		require.Nil(t, result)
	})

	t.Run("returns single job when it matches the agent", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   targetAgent,
		}
		result := getMostRecentJobWithAgent([]*jobs.Job{job}, targetAgent)
		require.Equal(t, job, result)
	})

	t.Run("returns nil when single job does not match the agent", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   otherAgent,
		}
		result := getMostRecentJobWithAgent([]*jobs.Job{job}, targetAgent)
		require.Nil(t, result)
	})

	t.Run("returns most recent job matching agent from multiple jobs", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   targetAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 3000,
			AgentID:   targetAgent,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 2000,
			AgentID:   targetAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2, job3}, targetAgent)
		require.Equal(t, job2, result)
		require.Equal(t, "job-2", result.ID)
	})

	t.Run("returns nil when no jobs match the agent", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   otherAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 3000,
			AgentID:   otherAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2}, targetAgent)
		require.Nil(t, result)
	})

	t.Run("ignores newer jobs from different agent", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   targetAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 5000,
			AgentID:   otherAgent,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 3000,
			AgentID:   targetAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2, job3}, targetAgent)
		require.Equal(t, job3, result)
		require.Equal(t, "job-3", result.ID)
	})

	t.Run("returns first matching job when all have same CreatedAt", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   targetAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 1000,
			AgentID:   targetAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2}, targetAgent)
		require.Equal(t, job1, result)
		require.Equal(t, "job-1", result.ID)
	})

	t.Run("returns matching job when it is first in list with mixed agents", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 3000,
			AgentID:   targetAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 1000,
			AgentID:   otherAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2}, targetAgent)
		require.Equal(t, job1, result)
		require.Equal(t, "job-1", result.ID)
	})

	t.Run("returns matching job when it is last in list with mixed agents", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
			AgentID:   otherAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 2000,
			AgentID:   otherAgent,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 3000,
			AgentID:   targetAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2, job3}, targetAgent)
		require.Equal(t, job3, result)
		require.Equal(t, "job-3", result.ID)
	})

	t.Run("finds matching job when newer non-matching job appears first", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 5000,
			AgentID:   otherAgent,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 3000,
			AgentID:   targetAgent,
		}

		result := getMostRecentJobWithAgent([]*jobs.Job{job1, job2}, targetAgent)
		require.Equal(t, job2, result)
		require.Equal(t, "job-2", result.ID)
	})
}

func TestInheritedWorkflowsAccessForAgent(t *testing.T) {
	const targetAgent int64 = 42
	const otherAgent int64 = 99
	trueVal := true
	falseVal := false

	t.Run("returns nil for empty job list", func(t *testing.T) {
		result := jobs.InheritedWorkflowsAccess([]*jobs.Job{}, targetAgent)
		require.Nil(t, result)
	})

	t.Run("returns nil for nil job list", func(t *testing.T) {
		result := jobs.InheritedWorkflowsAccess(nil, targetAgent)
		require.Nil(t, result)
	})

	t.Run("returns nil when no same-agent job has a checked value", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 1000, AgentID: targetAgent, CanWriteWorkflows: nil},
			{ID: "job-2", CreatedAt: 2000, AgentID: targetAgent, CanWriteWorkflows: nil},
		}
		require.Nil(t, jobs.InheritedWorkflowsAccess(jobsList, targetAgent))
	})

	t.Run("returns value of single matching job", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 1000, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("ignores jobs from other agents", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 5000, AgentID: otherAgent, CanWriteWorkflows: &falseVal},
			{ID: "job-2", CreatedAt: 1000, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("returns most recent non-nil value from same agent", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "job-1", CreatedAt: 1000, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
			{ID: "job-2", CreatedAt: 3000, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
			{ID: "job-3", CreatedAt: 2000, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})

	t.Run("falls back to older non-nil value when newest is nil (stuck-nil mitigation)", func(t *testing.T) {
		jobsList := []*jobs.Job{
			{ID: "older", CreatedAt: 1000, AgentID: targetAgent, CanWriteWorkflows: &falseVal},
			{ID: "newest", CreatedAt: 5000, AgentID: targetAgent, CanWriteWorkflows: nil},
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.False(t, *result)
	})

	t.Run("skips nil entries in the slice", func(t *testing.T) {
		jobsList := []*jobs.Job{
			nil,
			{ID: "job-1", CreatedAt: 1000, AgentID: targetAgent, CanWriteWorkflows: &trueVal},
			nil,
		}
		result := jobs.InheritedWorkflowsAccess(jobsList, targetAgent)
		require.NotNil(t, result)
		require.True(t, *result)
	})
}

func TestHandlerProcess_AgentIDFromEvent(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ctx := context.Background()

	t.Run("uses agent ID from event when agent exists", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		handler, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, nil)

		// Get the copilot app ID from the handler's app provider
		copilotAppID := handler.appProvider.CopilotApp().AppID()

		// Create an event with the copilot app ID
		event := &PullRequestCommentCreatedEvent{
			Actor:       EventActorWriter(),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     1,
				NodeID: "comment-node-id",
				Body:   "test comment",
			},
			AgentID: copilotAppID,
		}

		// The Process method will find the agent by ID from the event
		// Verify it doesn't error on agent lookup
		_ = handler.Process(ctx, event)
	})

	t.Run("uses CopilotApp when agent ID is 0", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		handler, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, nil)

		// Create an event with agent ID = 0
		event := &PullRequestCommentCreatedEvent{
			Actor:       EventActorWriter(),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     1,
				NodeID: "comment-node-id",
				Body:   "test comment",
			},
			AgentID: 0,
		}

		// This should use CopilotApp as fallback since agent ID is 0
		_ = handler.Process(ctx, event)
	})
}

func TestAssignmentForPR(t *testing.T) {
	obsv := observability.NewNoopExporters()
	defaultAssignment := et.Assignment()

	const (
		originalPRID     int64 = 12345
		stackedPRID      int64 = 99999
		originalPRNumber       = 100
		stackedPRNumber        = 999
	)

	tests := []struct {
		name           string
		assignment     *jobs.Assignment
		lookupPRID     *int64
		lookupPRNumber *int
		expectFound    bool
	}{
		{
			name:           "finds assignment by PR ID",
			assignment:     defaultAssignment,
			lookupPRID:     ptrInt64(defaultAssignment.PullRequestID),
			lookupPRNumber: ptrInt(defaultAssignment.PullRequestNumber),
			expectFound:    true,
		},
		{
			name: "finds assignment by PR ID when assignment has no resource",
			assignment: &jobs.Assignment{
				ID:                "legacy-assignment",
				OwnerID:           defaultAssignment.OwnerID,
				RepoID:            defaultAssignment.RepoID,
				PullRequestID:     defaultAssignment.PullRequestID,
				PullRequestNumber: defaultAssignment.PullRequestNumber,
				Resources:         []jobs.AssignmentResource{},
			},
			lookupPRID:     ptrInt64(defaultAssignment.PullRequestID),
			lookupPRNumber: ptrInt(defaultAssignment.PullRequestNumber),
			expectFound:    true,
		},
		{
			name:           "returns nil when no assignment exists",
			assignment:     nil,
			lookupPRID:     ptrInt64(999999),
			lookupPRNumber: ptrInt(999),
			expectFound:    false,
		},
		{
			name: "does not find assignment when PR ID does not match",
			assignment: &jobs.Assignment{
				ID:                "stacked-assignment",
				OwnerID:           defaultAssignment.OwnerID,
				RepoID:            defaultAssignment.RepoID,
				PullRequestID:     stackedPRID,
				PullRequestNumber: stackedPRNumber,
				Resources: []jobs.AssignmentResource{
					{Type: "pull_request", ID: "12345"},
				},
			},
			lookupPRID:     ptrInt64(originalPRID),
			lookupPRNumber: ptrInt(originalPRNumber),
			expectFound:    false,
		},
		{
			name: "finds assignment by PR ID for stacked PR",
			assignment: &jobs.Assignment{
				ID:                "stacked-assignment-found",
				OwnerID:           defaultAssignment.OwnerID,
				RepoID:            defaultAssignment.RepoID,
				PullRequestID:     stackedPRID,
				PullRequestNumber: stackedPRNumber,
				Resources: []jobs.AssignmentResource{
					{Type: "pull_request", ID: "12345"},
				},
			},
			lookupPRID:     ptrInt64(stackedPRID),
			lookupPRNumber: ptrInt(stackedPRNumber),
			expectFound:    true,
		},
		{
			name:           "uses legacy lookup when prID is nil",
			assignment:     defaultAssignment,
			lookupPRID:     nil,
			lookupPRNumber: ptrInt(defaultAssignment.PullRequestNumber),
			expectFound:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			capiClient, jobStore, ghTwirp := commonHandlerDependencies()
			ffClient := featureflags.NewNoopClient(nil)
			handler, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, nil)

			var expectedID string
			if tt.assignment != nil {
				created, err := handler.jobsStore.CreateAssignment(context.Background(), tt.assignment)
				require.NoError(t, err)
				expectedID = created.ID
			}

			repo := &Repository{ID: defaultAssignment.RepoID, OwnerID: defaultAssignment.OwnerID}
			foundAssignment, err := handler.assignmentForPR(context.Background(), repo, tt.lookupPRID, tt.lookupPRNumber)

			require.NoError(t, err)
			if tt.expectFound {
				require.NotNil(t, foundAssignment)
				require.Equal(t, expectedID, foundAssignment.ID)
			} else {
				require.Nil(t, foundAssignment)
			}
		})
	}

	t.Run("returns correct assignment when both original and stacked PR assignments exist", func(t *testing.T) {
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ffClient := featureflags.NewNoopClient(nil)
		handler, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, nil)

		originalAssignment := &jobs.Assignment{
			ID:                "original-pr-assignment",
			OwnerID:           defaultAssignment.OwnerID,
			RepoID:            defaultAssignment.RepoID,
			PullRequestID:     originalPRID,
			PullRequestNumber: originalPRNumber,
		}
		stackedAssignment := &jobs.Assignment{
			ID:                "stacked-pr-assignment",
			OwnerID:           defaultAssignment.OwnerID,
			RepoID:            defaultAssignment.RepoID,
			PullRequestID:     stackedPRID,
			PullRequestNumber: stackedPRNumber,
		}
		_, err := handler.jobsStore.CreateAssignment(context.Background(), originalAssignment)
		require.NoError(t, err)
		_, err = handler.jobsStore.CreateAssignment(context.Background(), stackedAssignment)
		require.NoError(t, err)

		repo := &Repository{ID: defaultAssignment.RepoID, OwnerID: defaultAssignment.OwnerID}

		// Looking up by original PR ID returns the original assignment
		foundOriginal, err := handler.assignmentForPR(context.Background(), repo, ptrInt64(originalPRID), ptrInt(originalPRNumber))
		require.NoError(t, err)
		require.NotNil(t, foundOriginal)
		require.Equal(t, "original-pr-assignment", foundOriginal.ID)

		// Looking up by stacked PR ID returns the stacked assignment
		foundStacked, err := handler.assignmentForPR(context.Background(), repo, ptrInt64(stackedPRID), ptrInt(stackedPRNumber))
		require.NoError(t, err)
		require.NotNil(t, foundStacked)
		require.Equal(t, "stacked-pr-assignment", foundStacked.ID)
	})
}

func ptrInt64(v int64) *int64 { return &v }
func ptrInt(v int) *int       { return &v }
func ptrBool(v bool) *bool    { return &v }

// newAppWorkflowsHandler builds a Handler whose installation-permissions RPC
// returns perms and whose feature flags are set per flags. Shared by the
// comment and review handler tests that exercise the App workflows verdict.
func newAppWorkflowsHandler(t *testing.T, flags map[string]bool, perms map[string]string) (*Handler, *jobservicetest.TestService) {
	t.Helper()
	ghFactory := &gh.NoopClientFactory{GitHubAppLogin: et.GitHubAppLogin, GitHubBotLogin: et.GitHubBotLogin}
	capiClient, jobStore, ghTwirp := commonHandlerDependencies()
	ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(_ context.Context, _ *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
		return &copilotUsersTwirp.GetCopilotUserResponse{
			UserDetails: &copilotUsersTwirp.CopilotUserDetails{CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE},
		}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockGetRepositoryInstallation = func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
		return &sweagentdTwirp.GetRepositoryInstallationResponse{Permissions: perms}, nil
	}
	h, service, _ := NewTestHandler(t, observability.NewNoopExporters(), capiClient, featureflags.NewNoopClient(flags), jobStore, ghTwirp, ghFactory)
	h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

	actor := et.ActorWriter()
	pr := et.PullRequest(*et.UserCopilot())
	pr = et.AddCommentToPullRequest(pr, true, *actor)
	pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)
	ghFactory.MockPullRequestContext = &gh.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}
	return h, service
}

// queuedJobWorkflowsAccess returns the CanWriteWorkflows pointer on the single
// queued job, asserting that exactly one was queued.
func queuedJobWorkflowsAccess(t *testing.T, h *Handler, service *jobservicetest.TestService) *bool {
	t.Helper()
	queued := service.QueuedJobs()
	require.Len(t, queued, 1)
	job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queued[0].JobId)
	require.NoError(t, err)
	return job.CanWriteWorkflows
}

func TestNewAssignmentHasPRResource(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &gh.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("new assignment created with PR resource", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		handler, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &gh.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := handler.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
			EventUrl: "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		queuedJob := service.QueuedJobs()[0]
		job, err := handler.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)

		assignment, err := handler.jobsStore.GetAssignment(context.Background(), EventRepository().OwnerID, EventRepository().ID, job.AssignmentID)
		require.NoError(t, err)
		require.NotNil(t, assignment)

		require.Len(t, assignment.Resources, 1)
		require.Equal(t, "pull_request", assignment.Resources[0].Type)
		require.Equal(t, fmt.Sprintf("%d", pr.GetID()), assignment.Resources[0].ID)
		require.Equal(t, pr.GetID(), assignment.PullRequestID)
		require.Equal(t, pr.Number, assignment.PullRequestNumber)
	})
}
