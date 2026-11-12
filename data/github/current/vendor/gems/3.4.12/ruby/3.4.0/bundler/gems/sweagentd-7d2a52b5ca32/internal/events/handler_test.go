package events

import (
	"context"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
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

	spokes := spokestest.NewClient(t)
	service := jobservicetest.New(t, obsv, ffClient, jobsStore, capiClient, ghFactory, ghTwirp, nil, nil, customagent.NewService(obsv, spokes, ghTwirp, ffClient))
	executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
	handler := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, nil)
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
		require.Equal(t, repo.Name, job.RepoName)
		require.Equal(t, repo.Owner.Login, job.RepoOwner)
		require.Equal(t, repo.Name, job.RepoName)
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
		require.Equal(t, repo.Name, job.RepoName)
		require.Equal(t, repo.Owner.Login, job.RepoOwner)
		require.Equal(t, repo.Name, job.RepoName)
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
		require.Equal(t, repo.Name, job.RepoName)
		require.Equal(t, repo.Owner.Login, job.RepoOwner)
		require.Equal(t, repo.Name, job.RepoName)
		require.Equal(t, jobs.AgentActionFix, job.Action)
		require.Equal(t, jobs.JobStatusPending, job.Status)

		require.Equal(t, actor.Login, job.ActorLogin)
		require.Equal(t, actor.ID, job.ActorID)
		require.Empty(t, job.BranchName)
		require.Equal(t, repo.DefaultBranchRef.Name, job.BaseCommit)
	})
}
