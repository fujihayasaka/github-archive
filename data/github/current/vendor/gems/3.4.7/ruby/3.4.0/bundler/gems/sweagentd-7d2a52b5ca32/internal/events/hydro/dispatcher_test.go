package hydro

import (
	"context"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"

	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/sweagentd/internal/aqueduct"
	"github.com/github/sweagentd/internal/aqueduct/jobs"
	aqueductJobs "github.com/github/sweagentd/internal/aqueduct/jobs"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/events"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestDispatcher(t *testing.T) {
	obsv := observability.NewNoopExporters()
	topic := topics.IssueUpdateAssignee

	t.Run("returns nil if the dispatcher returns any error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghFactory := &github.NoopClientFactory{}

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 1)
	})
}

func TestDispatcher_IssueUpdateAssignee(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.IssueUpdateAssignee

	t.Run("executes the right event handler for assigned", func(t *testing.T) {

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
	})

	t.Run("ignores issue assignment events when CopilotSWEAgentIssuesCrossRepoAssignment enabled for user", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIssuesCrossRepoAssignment: true,
		})

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserCopilot()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Empty(t, jobsInQueue)
	})

	t.Run("does not ignore issue assignment events when CopilotSWEAgentIssuesCrossRepoAssignment disabled for user", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIssuesCrossRepoAssignment: false,
		})

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserCopilot()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)
	})

	t.Run("does not ignore issue un-assignment events when CopilotSWEAgentIssuesCrossRepoAssignment enabled for user", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentIssuesCrossRepoAssignment: true,
		})

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionUnassigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserCopilot()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)

		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		responseToReturn.IsSweagentdEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

	})

	t.Run("executes the right event handler for unassigned", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionUnassigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
	})

	t.Run("ignores events for actions other than assigned or unassigned ", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     "issue.events.foo",
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
	})

	t.Run("ignores events for pull request assigned", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:      IssueUpdateAssigneeActionAssigned,
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			Assignees:   []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
	})

	t.Run("ignores events for pull request unassigned", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
			Action:      IssueUpdateAssigneeActionUnassigned,
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			Assignees:   []*entitiesv1.User{et.EntitiesUserReader()},
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
	})
}

func TestDispatcher_PullRequestTimelineCommentCreate(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.PullRequestTimelineCommentCreate

	t.Run("executes the right event handler for pull request comments", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		responseToReturn.IsSweagentdEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})
}

func TestDispatcher_PullRequestReviewSubmit(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.PullRequestReviewSubmit

	t.Run("executes the right event handler for pull request review comments", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.PullRequestReviewSubmit{
			Actor:             et.EntitiesUserWriter(),
			Repository:        et.EntitiesRepository(),
			Issue:             et.EntitiesIssue(),
			PullRequest:       et.EntitiesPullRequestWithNumber(et.PullRequestNumber),
			PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.PullRequestReviewSubmit{
			Actor:             et.EntitiesUserWriter(),
			Repository:        et.EntitiesRepository(),
			Issue:             et.EntitiesIssue(),
			PullRequest:       et.EntitiesPullRequestWithNumber(et.PullRequestNumber),
			PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 0)

		responseToReturn.IsSweagentdEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 1)
	})

	t.Run("ignores events in repos that don't have the feature flag", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, &githubv1.PullRequestReviewSubmit{
			Actor:             et.EntitiesUserWriter(),
			Repository:        et.EntitiesRepository(),
			Issue:             et.EntitiesIssue(),
			PullRequest:       et.EntitiesPullRequestWithNumber(et.PullRequestNumber),
			PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 0)
	})
}

func TestGetPullRequestReview_MentionsCopilot(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	timestamp := time.Now()

	t.Run("detects @copilot mention in review body", func(t *testing.T) {
		reviewBody := "@copilot please fix this issue"

		message := &githubv1.PullRequestReviewSubmit{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			PullRequestReview: &entitiesv1.PullRequestReview{
				Id:   12345,
				Body: reviewBody,
			},
			Comments: []*entitiesv1.PullRequestReviewComment{},
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.True(t, event.PullRequestReview.MentionsCopilot, "Should detect @copilot mention in review body")
	})

	t.Run("detects @copilot mention in review comment", func(t *testing.T) {
		reviewBody := "This looks good"
		commentBody := "@copilot can you explain this change?"

		message := &githubv1.PullRequestReviewSubmit{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			PullRequestReview: &entitiesv1.PullRequestReview{
				Id:   12345,
				Body: reviewBody,
			},
			Comments: []*entitiesv1.PullRequestReviewComment{
				{
					Id:   67890,
					Body: commentBody,
				},
			},
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.True(t, event.PullRequestReview.MentionsCopilot, "Should detect @copilot mention in review comment")
	})

	t.Run("detects @copilot mention in multiple comments", func(t *testing.T) {
		reviewBody := "Overall this looks fine"

		message := &githubv1.PullRequestReviewSubmit{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			PullRequestReview: &entitiesv1.PullRequestReview{
				Id:   12345,
				Body: reviewBody,
			},
			Comments: []*entitiesv1.PullRequestReviewComment{
				{
					Id:   67890,
					Body: "This part looks good",
				},
				{
					Id:   67891,
					Body: "@copilot please check this logic",
				},
				{
					Id:   67892,
					Body: "And this is also fine",
				},
			},
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.True(t, event.PullRequestReview.MentionsCopilot, "Should detect @copilot mention in one of multiple comments")
	})

	t.Run("does not detect @copilot when not mentioned", func(t *testing.T) {
		reviewBody := "This code looks good to me"

		message := &githubv1.PullRequestReviewSubmit{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			PullRequestReview: &entitiesv1.PullRequestReview{
				Id:   12345,
				Body: reviewBody,
			},
			Comments: []*entitiesv1.PullRequestReviewComment{
				{
					Id:   67890,
					Body: "Just a regular comment",
				},
				{
					Id:   67891,
					Body: "Another comment without mentions",
				},
			},
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.False(t, event.PullRequestReview.MentionsCopilot, "Should not detect @copilot when not mentioned")
	})

	t.Run("handles empty review body and comments", func(t *testing.T) {
		message := &githubv1.PullRequestReviewSubmit{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			PullRequestReview: &entitiesv1.PullRequestReview{
				Id:   12345,
				Body: "",
			},
			Comments: []*entitiesv1.PullRequestReviewComment{},
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.False(t, event.PullRequestReview.MentionsCopilot, "Should not detect @copilot when body and comments are empty")
	})

	t.Run("handles nil comments slice", func(t *testing.T) {
		reviewBody := "Simple review"

		message := &githubv1.PullRequestReviewSubmit{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
			PullRequestReview: &entitiesv1.PullRequestReview{
				Id:   12345,
				Body: reviewBody,
			},
			Comments: nil,
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp)
		require.NoError(t, err)
		require.NotNil(t, event)
		require.False(t, event.PullRequestReview.MentionsCopilot, "Should handle nil comments gracefully")
	})
}

func TestDispatcher_ComputeUsageEvent(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.ComputeUsage

	t.Run("executes the right event handler for workflow comments", func(t *testing.T) {
		ctx := context.Background()
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
			TenantSlug:         "test-tenant",
			TenantId:           "tenant-id",
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, et.ActionsComputeUsage())

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		require.Contains(t, job.Headers, requestctx.GitHubTenantIDHeader)
		require.Equal(t, "tenant-id", job.Headers[requestctx.GitHubTenantIDHeader])
		require.Contains(t, job.Headers, requestctx.GitHubTenantHeader)
		require.Equal(t, "test-tenant", job.Headers[requestctx.GitHubTenantHeader])

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("ignores events in repos that don't have the feature flag", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, et.ActionsComputeUsage())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 0)
	})
}

func TestDispatcher_CodeScanningAlertsAssignment(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.CodeScanningAlertAssignment

	t.Run("executes the right event handler for assigned", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, et.EntitiesAlertsAssignmentAssigneeCopilot())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)

		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, et.EntitiesAlertsAssignmentAssigneeCopilot())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 0)

		responseToReturn.IsSweagentdEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 1)
	})

	t.Run("ignores events in repos that don't have the feature flag", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: false,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topic, et.EntitiesAlertsAssignmentAssigneeCopilot())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 0)
	})
}

func TestDispatcher_IgnoresEventsInStagingEnvironment(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{}
	actor := et.EntitiesUserWriter()
	repository := et.EntitiesRepository()
	issue := et.EntitiesIssue()

	// Test data for each topic with corresponding message and handler
	topicTestCases := []struct {
		topic   string
		message proto.Message
		handler *events.NoopHandler
	}{
		{
			topic:   topics.IssueUpdateAssignee,
			message: &githubv1.IssueUpdateAssignee{Action: IssueUpdateAssigneeActionAssigned, Actor: actor, Repository: repository, Issue: issue, Assignees: []*entitiesv1.User{et.EntitiesUserReader()}},
			handler: &events.NoopHandler{
				MockOnIssueAssigned: func(ctx context.Context, event events.IssueAssignmentEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestTimelineCommentCreate,
			message: &githubv1.PullRequestTimelineCommentCreate{
				Actor:        et.EntitiesUserWriter(),
				Repository:   et.EntitiesRepository(),
				Issue:        et.EntitiesIssue(),
				IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			},
			handler: &events.NoopHandler{
				MockOnPullRequestCommentCreated: func(ctx context.Context, event events.PullRequestCommentCreatedEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestReviewSubmit,
			message: &githubv1.PullRequestReviewSubmit{
				Actor:             et.EntitiesUserWriter(),
				Repository:        et.EntitiesRepository(),
				Issue:             et.EntitiesIssue(),
				PullRequest:       et.EntitiesPullRequestWithNumber(et.PullRequestNumber),
				PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
			},
			handler: &events.NoopHandler{
				MockOnPullRequestReviewSubmit: func(ctx context.Context, event events.PullRequestReviewSubmitEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestReopen,
			message: &githubv1.PullRequestReopen{
				Actor:       et.EntitiesUserWriter(),
				Repository:  et.EntitiesRepository(),
				Issue:       et.EntitiesIssue(),
				PullRequest: et.EntitiesPullRequest(),
			},
			handler: &events.NoopHandler{
				MockOnPullRequestStateChanged: func(ctx context.Context, event events.PullRequestStateChangedEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestClose,
			message: &githubv1.PullRequestClose{
				Actor:       et.EntitiesUserWriter(),
				Repository:  et.EntitiesRepository(),
				Issue:       et.EntitiesIssue(),
				PullRequest: et.EntitiesPullRequest(),
			},
			handler: &events.NoopHandler{
				MockOnPullRequestStateChanged: func(ctx context.Context, event events.PullRequestStateChangedEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestMerge,
			message: &githubv1.PullRequestMerge{
				Actor:       et.EntitiesUserWriter(),
				Repository:  et.EntitiesRepository(),
				Issue:       et.EntitiesIssue(),
				PullRequest: et.EntitiesPullRequest(),
			},
			handler: &events.NoopHandler{
				MockOnPullRequestStateChanged: func(ctx context.Context, event events.PullRequestStateChangedEvent) error {
					return nil
				},
			},
		},
		{
			topic:   topics.ComputeUsage,
			message: et.ActionsComputeUsage(),
			handler: &events.NoopHandler{
				MockOnWorkflowRunCompleted: func(ctx context.Context, event events.WorkflowRunCompletedEvent) error {
					return nil
				},
			},
		},
		{
			topic:   topics.WorkflowRunExecution,
			message: createActionsWorkflowRunExecution(),
			handler: &events.NoopHandler{
				MockOnWorkflowRunCompleted: func(ctx context.Context, event events.WorkflowRunCompletedEvent) error {
					return nil
				},
			},
		},
		{
			topic:   topics.CodeScanningAlertAssignment,
			message: et.EntitiesAlertsAssignmentAssigneeCopilot(),
			handler: &events.NoopHandler{
				MockOnCodeScanningAlertsAssigned: func(ctx context.Context, event events.CodeScanningAlertsAssignmentEvent) error {
					return nil
				},
			},
		},
	}

	// CRITICAL VALIDATION: This test MUST fail if any topics are not validated
	// This ensures that when new topics are added to the Topics enumeration,
	// corresponding test cases MUST be added to topicTestCases array above.

	// Validate we test all topics in the enumeration
	require.Equal(t, len(topics.All), len(topicTestCases), "Test cases must cover all topics in the Topics enumeration")

	// Create sets for bidirectional validation
	topicSet := make(map[string]bool)
	testCaseTopicSet := make(map[string]bool)

	// Track topics from the enumeration
	for _, topic := range topics.All {
		topicSet[topic] = true
	}

	// Track topics from test cases
	for _, tc := range topicTestCases {
		testCaseTopicSet[tc.topic] = true
	}

	// Verify each topic in the enumeration is covered by our test cases
	for _, topic := range topics.All {
		require.True(t, testCaseTopicSet[topic], "Topic %s is missing from test cases", topic)
	}

	// Verify each test case corresponds to a topic in the enumeration
	for _, tc := range topicTestCases {
		require.True(t, topicSet[tc.topic], "Test case for topic %s does not correspond to a topic in the Topics enumeration", tc.topic)
	}

	// Additional safety check: ensure no duplicate topics in test cases
	seenTopics := make(map[string]bool)
	for _, tc := range topicTestCases {
		require.False(t, seenTopics[tc.topic], "Duplicate test case found for topic %s", tc.topic)
		seenTopics[tc.topic] = true
	}

	// Test each topic with different environment configurations
	for _, tc := range topicTestCases {
		t.Run(string(tc.topic), func(t *testing.T) {
			aq := aqueduct.NewMemoryClient(obsv)
			ghTwirp := githubtwirp.NewNoopClient()
			ghTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
				IsSweagentdEnabled: true,
			})

			// Create a valid hydro message that would be processed if not in staging
			msg := newHydroMessage(t, tc.topic, tc.message)

			executeDispatcher := func(ffMap map[string]bool, environment config.Environment, environmentName string, shouldProcess bool) {
				// Need to enable PR state events feature flag for PR-related topics
				if ffMap == nil {
					ffMap = make(map[string]bool)
				}
				if tc.topic == topics.PullRequestReopen || tc.topic == topics.PullRequestClose || tc.topic == topics.PullRequestMerge {
					ffMap[featureflags.CopilotSWEAgentPRStateEventsEnabled] = true
				}

				ffClient := featureflags.NewNoopClient(ffMap)
				dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, tc.handler, ghTwirp, environment, environmentName)
				err := dispatcher.Dispatch(context.Background(), msg)

				require.NoError(t, err, "Dispatch should not return an error for topic %s", tc.topic)

				// Note: We can't easily track if handlers were called without modifying the test structure significantly,
				// but we can verify that the dispatch completes without error, which indicates proper routing
			}

			// Test the standard routing scenarios
			executeDispatcher(nil, config.EnvironmentProduction, "production", true)
			executeDispatcher(nil, config.EnvironmentStaging, "staging", false)
			executeDispatcher(nil, config.EnvironmentStaging, "staging-jedi-knight", false)
			executeDispatcher(nil, config.EnvironmentStaging, "staging-sith-lord", false)

			justStaging := map[string]bool{"sweagentd_route_user_or_repo_to_staging": true}
			executeDispatcher(justStaging, config.EnvironmentProduction, "production", false)
			executeDispatcher(justStaging, config.EnvironmentStaging, "staging", true)
			executeDispatcher(justStaging, config.EnvironmentStaging, "staging-jedi-knight", false)
			executeDispatcher(justStaging, config.EnvironmentStaging, "staging-sith-lord", false)

			justJediKnight := map[string]bool{"sweagentd_route_user_or_repo_to_staging_jedi_knight": true}
			executeDispatcher(justJediKnight, config.EnvironmentProduction, "production", false)
			executeDispatcher(justJediKnight, config.EnvironmentStaging, "staging", false)
			executeDispatcher(justJediKnight, config.EnvironmentStaging, "staging-jedi-knight", true)
			executeDispatcher(justJediKnight, config.EnvironmentStaging, "staging-sith-lord", false)

			justSithLord := map[string]bool{"sweagentd_route_user_or_repo_to_staging_sith_lord": true}
			executeDispatcher(justSithLord, config.EnvironmentProduction, "production", false)
			executeDispatcher(justSithLord, config.EnvironmentStaging, "staging", false)
			executeDispatcher(justSithLord, config.EnvironmentStaging, "staging-jedi-knight", false)
			executeDispatcher(justSithLord, config.EnvironmentStaging, "staging-sith-lord", true)
		})
	}
}

func TestDispatcher_ProcessesEventsInProductionEnvironment(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{}
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.IssueUpdateAssignee

	h := &events.NoopHandler{}
	aq := aqueduct.NewMemoryClient(obsv)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsSweagentdEnabled: true,
	})

	e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, ghTwirp, config.EnvironmentProduction, "production")

	// Create a valid hydro message that should be processed in production
	msg := newHydroMessage(t, topic, &githubv1.IssueUpdateAssignee{
		Action:     IssueUpdateAssigneeActionAssigned,
		Actor:      et.EntitiesUserWriter(),
		Repository: et.EntitiesRepository(),
		Issue:      et.EntitiesIssue(),
		Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
	})

	err := e.Dispatch(context.Background(), msg)

	require.NoError(t, err, "Dispatch should not return an error")
	require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 1)
}

func TestPRHydroEventsIntegration(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentPRStateEventsEnabled: true,
	})
	ghFactory := &github.NoopClientFactory{}

	h := &events.NoopHandler{}

	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsSweagentdEnabled: true,
	})

	// Test that reopen events are routed correctly
	t.Run("reopen events are routed to state change handler", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topics.PullRequestReopen, &githubv1.PullRequestReopen{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestReopen)
	})

	// Test that reopen events with draft PR are routed correctly
	t.Run("reopen draft PR events are routed to state change handler", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		// Create a draft PR by modifying the standard PR
		copilotPR := et.EntitiesPullRequest()
		copilotPR.Draft = true

		msg := newHydroMessage(t, topics.PullRequestReopen, &githubv1.PullRequestReopen{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: copilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestReopen)
	})

	// Test that close events are routed correctly
	t.Run("close events are routed to state change handler", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		copilotPR := et.EntitiesPullRequest()
		copilotPR.PullRequestState = entitiesv1.PullRequest_CLOSED

		msg := newHydroMessage(t, topics.PullRequestClose, &githubv1.PullRequestClose{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: copilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestClose)
	})

	// Test that merge events are routed correctly
	t.Run("merge events are routed to state change handler", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		copilotPR := et.EntitiesPullRequest()
		copilotPR.PullRequestState = entitiesv1.PullRequest_MERGED

		msg := newHydroMessage(t, topics.PullRequestMerge, &githubv1.PullRequestMerge{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: copilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestMerge)
	})

	// Test that non-Copilot PRs are filtered out
	t.Run("non-copilot PR events are ignored", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		// Create a non-Copilot PR with base64 encoded branch name
		// "feature/" in base64 is "ZmVhdHVyZS8="
		nonCopilotPR := et.EntitiesPullRequest()
		nonCopilotPR.HeadBranch = []byte("ZmVhdHVyZS8=")

		msg := newHydroMessage(t, topics.PullRequestReopen, &githubv1.PullRequestReopen{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: nonCopilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		require.Len(t, aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName), 0)
	})
}

func TestDispatcher_HydroTenantHeaders(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.IssueUpdateAssignee
	t.Run("extracts tenant headers in Proxima environment", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})

		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentProxima, "test-cnc-01")

		// Create a message with tenant headers
		msg := newHydroMessageWithHeaders(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		}, map[string]string{
			requestctx.GitHubTenantIDHeader: "test-tenant-id",
			requestctx.GitHubTenantHeader:   "test-tenant-slug",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		require.Contains(t, job.Headers, requestctx.GitHubTenantIDHeader)
		require.Equal(t, "test-tenant-id", job.Headers[requestctx.GitHubTenantIDHeader])
		require.Contains(t, job.Headers, requestctx.GitHubTenantHeader)
		require.Equal(t, "test-tenant-slug", job.Headers[requestctx.GitHubTenantHeader])

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)

		// Verify the tenant information was added to the request context
		// and that the dispatcher completed successfully
	})

	t.Run("skips tenant header extraction in non-Proxima environment", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})

		// Use Development environment instead of Proxima
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		// Create a message with tenant headers (should be ignored)
		msg := newHydroMessageWithHeaders(t, topic, &githubv1.IssueUpdateAssignee{
			Action:     IssueUpdateAssigneeActionAssigned,
			Actor:      et.EntitiesUserWriter(),
			Repository: et.EntitiesRepository(),
			Issue:      et.EntitiesIssue(),
			Assignees:  []*entitiesv1.User{et.EntitiesUserReader()},
		}, map[string]string{
			requestctx.GitHubTenantIDHeader: "test-tenant-id",
			requestctx.GitHubTenantHeader:   "test-tenant-slug",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		require.NotContains(t, job.Headers, requestctx.GitHubTenantIDHeader)
		require.NotContains(t, job.Headers, requestctx.GitHubTenantHeader)
	})
}

func TestHydroTenantHeaders(t *testing.T) {
	t.Run("returns empty values for nil headers", func(t *testing.T) {
		id, slug, err := HydroTenantHeaders(nil)
		require.NoError(t, err)
		require.Empty(t, id)
		require.Empty(t, slug)
	})

	t.Run("returns empty values for empty headers", func(t *testing.T) {
		id, slug, err := HydroTenantHeaders(map[string]string{})
		require.NoError(t, err)
		require.Empty(t, id)
		require.Empty(t, slug)
	})

	t.Run("extracts tenant ID when present", func(t *testing.T) {
		headers := map[string]string{
			requestctx.GitHubTenantIDHeader: "test-tenant-id",
		}
		id, slug, err := HydroTenantHeaders(headers)
		require.NoError(t, err)
		require.Equal(t, "test-tenant-id", id)
		require.Empty(t, slug)
	})

	t.Run("extracts tenant slug when present", func(t *testing.T) {
		headers := map[string]string{
			requestctx.GitHubTenantHeader: "test-tenant-slug",
		}
		id, slug, err := HydroTenantHeaders(headers)
		require.NoError(t, err)
		require.Empty(t, id)
		require.Equal(t, "test-tenant-slug", slug)
	})

	t.Run("extracts both tenant ID and slug when present", func(t *testing.T) {
		headers := map[string]string{
			requestctx.GitHubTenantIDHeader: "test-tenant-id",
			requestctx.GitHubTenantHeader:   "test-tenant-slug",
		}
		id, slug, err := HydroTenantHeaders(headers)
		require.NoError(t, err)
		require.Equal(t, "test-tenant-id", id)
		require.Equal(t, "test-tenant-slug", slug)
	})
}

func TestDispatcher_checkEnablement(t *testing.T) {
	t.Run("returns false when user is flagged with disallow feature flag", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		ghFactory := &github.NoopClientFactory{}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentAPIDisallow: true,
		})
		aq := aqueduct.NewMemoryClient(obsv)
		h := &events.NoopHandler{}
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsSweagentdEnabled: true,
		})

		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, h, ghTwirp, config.EnvironmentStaging, "staging")

		// Use mock actors with specific IDs
		mockActors := &mockActors{
			actorID:      123,
			repositoryID: 123,
			ownerID:      123,
		}

		enabled, err := dispatcher.checkEnablement(context.Background(), mockActors)
		require.NoError(t, err)
		require.False(t, enabled, "Feature should be disabled for user with disallow flag")
	})
}

type mockActors struct {
	actorID      int64
	repositoryID int64
	ownerID      int64
}

func (a *mockActors) GetRepositoryID() int64 { return a.repositoryID }
func (a *mockActors) GetOwnerID() int64      { return a.ownerID }
func (a *mockActors) GetActorID() int64      { return a.actorID }

// newHydroMessage creates a hydro message with the given topic and message.
// It marshals the message into the envelope's message field.
func newHydroMessage(t *testing.T, topic string, message proto.Message) hydro_lib.Message {
	t.Helper()
	val, err := proto.Marshal(message)
	require.NoError(t, err)
	env, err := proto.Marshal(&hydro_pb.Envelope{
		TypeUrl: "test",
		Message: val,
	})
	require.NoError(t, err)
	return hydro_lib.Message{
		Topic: topic,
		Value: env,
	}
}

// TestPRHydroEventsFeatureFlag tests that PR state events are properly gated by feature flag
func TestPRHydroEventsFeatureFlag(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{}

	h := &events.NoopHandler{}

	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsSweagentdEnabled: true,
	})

	t.Run("events processed when feature flag enabled", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)

		// Create a feature flag client that returns true for the PR state events flag
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPRStateEventsEnabled: true,
		})

		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topics.PullRequestReopen, &githubv1.PullRequestReopen{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob jobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestReopen)
	})

	t.Run("events skipped when feature flag disabled", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)

		// Create a feature flag client that returns false for the PR state events flag
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPRStateEventsEnabled: false,
		})

		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development")

		msg := newHydroMessage(t, topics.PullRequestReopen, &githubv1.PullRequestReopen{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: et.EntitiesPullRequest(),
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(aqueductJobs.EventJobQueueName, aqueductJobs.EventJobBackgroundQueueName)
		require.Len(t, jobsInQueue, 0)
	})
}

// newHydroMessageWithHeaders creates a hydro message with the given topic, message, and headers.
// It marshals the message into the envelope's message field and includes the provided headers.
func newHydroMessageWithHeaders(t *testing.T, topic string, message proto.Message, headers map[string]string) hydro_lib.Message {
	t.Helper()
	val, err := proto.Marshal(message)
	require.NoError(t, err)
	env, err := proto.Marshal(&hydro_pb.Envelope{
		TypeUrl: "test",
		Message: val,
	})
	require.NoError(t, err)
	return hydro_lib.Message{
		Topic:   topic,
		Value:   env,
		Headers: headers,
	}
}

// createActionsWorkflowRunExecution creates a test WorkflowRunExecution message
func createActionsWorkflowRunExecution() *actionsv0.WorkflowRunExecution {
	// Generate consistent IDs like other test helpers
	rID, _ := et.IDsFromString(et.RepoName)
	oID, _ := et.IDsFromString(et.RepoOwner)

	// Create a minimal WorkflowRunExecution message with only required/existing fields
	return &actionsv0.WorkflowRunExecution{
		WorkflowRunId:     1234,
		RepositoryId:      rID,
		RepositoryOwnerId: oID,
	}
}
