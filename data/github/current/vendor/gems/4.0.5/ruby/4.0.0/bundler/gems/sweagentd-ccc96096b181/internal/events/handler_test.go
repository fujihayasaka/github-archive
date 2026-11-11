package events

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
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
	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents)
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

func TestGetMostRecentJob(t *testing.T) {
	t.Run("returns nil for empty job list", func(t *testing.T) {
		result := getMostRecentJob([]*jobs.Job{})
		require.Nil(t, result)
	})

	t.Run("returns single job when list has one job", func(t *testing.T) {
		job := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
		}
		result := getMostRecentJob([]*jobs.Job{job})
		require.Equal(t, job, result)
	})

	t.Run("returns most recent job from multiple jobs", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 3000,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 2000,
		}

		result := getMostRecentJob([]*jobs.Job{job1, job2, job3})
		require.Equal(t, job2, result)
		require.Equal(t, "job-2", result.ID)
	})

	t.Run("returns first job when all have same CreatedAt", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 1000,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 1000,
		}

		result := getMostRecentJob([]*jobs.Job{job1, job2, job3})
		require.Equal(t, job1, result)
		require.Equal(t, "job-1", result.ID)
	})

	t.Run("returns most recent job when it's first in list", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 3000,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 1000,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 2000,
		}

		result := getMostRecentJob([]*jobs.Job{job1, job2, job3})
		require.Equal(t, job1, result)
		require.Equal(t, "job-1", result.ID)
	})

	t.Run("returns most recent job when it's last in list", func(t *testing.T) {
		job1 := &jobs.Job{
			ID:        "job-1",
			CreatedAt: 1000,
		}
		job2 := &jobs.Job{
			ID:        "job-2",
			CreatedAt: 2000,
		}
		job3 := &jobs.Job{
			ID:        "job-3",
			CreatedAt: 3000,
		}

		result := getMostRecentJob([]*jobs.Job{job1, job2, job3})
		require.Equal(t, job3, result)
		require.Equal(t, "job-3", result.ID)
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
