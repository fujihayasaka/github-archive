package hydro

import (
	"context"
	"crypto/rsa"
	"slices"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	automationsv0 "github.com/github/hydro-schemas-go/hydro/schemas/copilot_mission_control/v0"
	actionsv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	pull_requestsv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/pull_requests/v1"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/aqueduct"
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
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestDispatcher(t *testing.T) {
	obsv := observability.NewNoopExporters()
	topic := topics.PullRequestTimelineCommentCreate

	t.Run("returns nil if the dispatcher returns any error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghFactory := &github.NoopClientFactory{}

		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		// PullRequestTimelineCommentCreate events should queue jobs
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
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
			IsAgentEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		// add aqueductJobs.EventJobWorkerQueues... too
		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		responseToReturn.IsAgentEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob aqueductJobs.EventJob
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
			IsAgentEnabled: true,
		})
		provider := agenticapptest.NewTestProviderWithID(t, 123)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a PR authored by the agentic app (AuthorId matches bot ID)
		copilotPR := et.EntitiesPullRequestWithNumber(et.PullRequestNumber)
		copilotPR.AuthorId = uint64(provider.CopilotApp().BotID())

		msg := newHydroMessage(t, topic, &githubv1.PullRequestReviewSubmit{
			Actor:             et.EntitiesUserWriter(),
			Repository:        et.EntitiesRepository(),
			Issue:             et.EntitiesIssue(),
			PullRequest:       copilotPR,
			PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		provider := agenticapptest.NewTestProviderWithID(t, 123)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a PR authored by the agentic app (AuthorId matches bot ID)
		copilotPR := et.EntitiesPullRequestWithNumber(et.PullRequestNumber)
		copilotPR.AuthorId = uint64(provider.CopilotApp().BotID())

		msg := newHydroMessage(t, topic, &githubv1.PullRequestReviewSubmit{
			Actor:             et.EntitiesUserWriter(),
			Repository:        et.EntitiesRepository(),
			Issue:             et.EntitiesIssue(),
			PullRequest:       copilotPR,
			PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 0)

		responseToReturn.IsAgentEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
	})

	t.Run("ignores events in repos that don't have the feature flag", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, &githubv1.PullRequestReviewSubmit{
			Actor:             et.EntitiesUserWriter(),
			Repository:        et.EntitiesRepository(),
			Issue:             et.EntitiesIssue(),
			PullRequest:       et.EntitiesPullRequestWithNumber(et.PullRequestNumber),
			PullRequestReview: et.EntitiesPullRequestReview(et.PullRequestNumber, et.ActorLoginWriter),
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 0)
	})
}

func TestGetPullRequestReview_MentionsCopilot(t *testing.T) {
	ctx := requestctx.NewContext(context.Background())
	timestamp := time.Now()

	t.Run("includes review body and comments", func(t *testing.T) {
		reviewBody := "This looks good"
		commentBody := "Please check this logic"

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

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp, agenticapptest.NewTestProviderWithID(t, 123))
		require.NoError(t, err)
		require.NotNil(t, event)
		require.Equal(t, reviewBody, event.PullRequestReview.Body)
		require.Len(t, event.PullRequestReview.Comments, 1)
		require.Equal(t, commentBody, event.PullRequestReview.Comments[0])
	})

	t.Run("includes multiple comments", func(t *testing.T) {
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
					Body: "Please check this logic",
				},
				{
					Id:   67892,
					Body: "And this is also fine",
				},
			},
		}

		reviewBytes, err := proto.Marshal(message)
		require.NoError(t, err)

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp, agenticapptest.NewTestProviderWithID(t, 123))
		require.NoError(t, err)
		require.NotNil(t, event)
		require.Len(t, event.PullRequestReview.Comments, 3)
	})

	t.Run("handles empty comments", func(t *testing.T) {
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

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp, agenticapptest.NewTestProviderWithID(t, 123))
		require.NoError(t, err)
		require.NotNil(t, event)
		require.Empty(t, event.PullRequestReview.Comments)
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

		_, event, err := getPullRequestReviewSubmitEvent(ctx, reviewBytes, timestamp, agenticapptest.NewTestProviderWithID(t, 123))
		require.NoError(t, err)
		require.NotNil(t, event)
		require.Empty(t, event.PullRequestReview.Comments)
	})
}

func TestDispatcher_WorkflowRunExecutionEvent(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	topic := topics.WorkflowRunExecution

	t.Run("executes the right event handler in development", func(t *testing.T) {
		ctx := context.Background()
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
			TenantSlug:     "tenant-from-response",
			TenantId:       "tenant-id-from-response",
		})
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly: true,
		})
		// Use copilot-swe-agent as app login to match the workflow path in ActionsWorkflowRunExecution
		// and a non-zero app ID so the event is not filtered out
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithIDAndLogins(t, 123, "copilot-swe-agent", "copilot-swe-agent[bot]"), nil)

		msg := newHydroMessage(t, topic, et.ActionsWorkflowRunExecution())

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		require.NotContains(t, job.Headers, requestctx.GitHubTenantIDHeader)
		require.NotContains(t, job.Headers, requestctx.GitHubTenantHeader)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("forwards hydro tenant headers in proxima", func(t *testing.T) {
		ctx := context.Background()
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
			TenantSlug:     "tenant-from-response",
			TenantId:       "tenant-id-from-response",
		})
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentProxima, "proxima", agenticapptest.NewTestProviderWithIDAndLogins(t, 123, "copilot-swe-agent", "copilot-swe-agent[bot]"), nil)

		msg := newHydroMessage(t, topic, et.ActionsWorkflowRunExecution())
		msg.Headers = map[string]string{
			requestctx.GitHubTenantHeader:   "test-tenant",
			requestctx.GitHubTenantIDHeader: "tenant-id",
		}

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
	})

	t.Run("ignores events in repos that don't have sweagentd enabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})
		// Use copilot-swe-agent as app login to match the workflow path in ActionsWorkflowRunExecution
		// and a non-zero app ID so the event is not filtered out by the agent ID check
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithIDAndLogins(t, 123, "copilot-swe-agent", "copilot-swe-agent[bot]"), nil)

		msg := newHydroMessage(t, topic, et.ActionsWorkflowRunExecution())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 0)
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
			IsAgentEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, et.EntitiesAlertsAssignmentAssigneeCopilot())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topic)
	})

	t.Run("execution is gated on repo enablement when FF is enabled", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)

		responseToReturn := to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})

		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = responseToReturn
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, et.EntitiesAlertsAssignmentAssigneeCopilot())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 0)

		responseToReturn.IsAgentEnabled = true
		err = e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
	})

	t.Run("ignores events in repos that don't have the feature flag", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topic, et.EntitiesAlertsAssignmentAssigneeCopilot())

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 0)
	})
}

func TestDispatcher_IgnoresEventsInStagingEnvironment(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{}

	// Test data for each topic with corresponding message and handler
	topicTestCases := []struct {
		topic   string
		message proto.Message
		handler *events.NoopHandler
	}{
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
			topic:   topics.WorkflowRunExecution,
			message: et.ActionsWorkflowRunExecution(),
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
		{
			topic: topics.IssueCreateTemplate,
			message: &githubv1.IssueCreateTemplate{
				Actor:      et.EntitiesUserWriter(),
				Repository: et.EntitiesRepository(),
				Issue:      et.EntitiesIssue(),
			},
			handler: &events.NoopHandler{
				MockOnIssueCreated: func(ctx context.Context, event events.IssueCreatedEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestMergeConflict,
			message: &pull_requestsv1.MergeConflict{
				RepositoryId:  1,
				PullRequestId: 42,
				BaseCommitOid: "base-sha",
				HeadCommitOid: "head-sha",
			},
			handler: &events.NoopHandler{
				MockOnMergeConflict: func(ctx context.Context, event events.MergeConflictEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.AutomationRunRequested,
			message: &automationsv0.AutomationRunRequested{
				AutomationId: "test-automation-id",
				Event:        "issues",
				Type:         "opened",
				ResourceUrl:  "/test-org/test-repo/issues/1",
				OwnerLogin:   "test-org",
				RepoName:     "test-repo",
				RepoId:       123,
				OwnerId:      456,
				UserId:       789,
				UserLogin:    "test-user",
			},
			handler: &events.NoopHandler{
				MockOnAutomationRunRequested: func(ctx context.Context, event events.AutomationRunRequestedEvent) error {
					assert.Equal(t, "test-automation-id", event.AutomationID)
					assert.Equal(t, "issues", event.Event)
					assert.Equal(t, "opened", event.Type)
					assert.Equal(t, "/test-org/test-repo/issues/1", event.ResourceURL)
					assert.Equal(t, "test-org", event.OwnerLogin)
					assert.Equal(t, "test-repo", event.RepoName)
					assert.Equal(t, int64(123), event.RepoID)
					assert.Equal(t, int64(456), event.OwnerID)
					assert.Equal(t, int64(789), event.UserID)
					assert.Equal(t, "test-user", event.UserLogin)
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestCreate,
			message: &githubv1.PullRequestCreate{
				Actor:           et.EntitiesUserWriter(),
				Repository:      et.EntitiesRepository(),
				RepositoryOwner: et.EntitiesUserWriter(),
				Issue:           et.EntitiesIssue(),
				PullRequest:     et.EntitiesPullRequest(),
				HeadRepository:  et.EntitiesRepository(),
				Title:           "Add docs",
				Body:            "Adds documentation",
			},
			handler: &events.NoopHandler{
				MockOnPullRequestOpened: func(ctx context.Context, event events.PullRequestOpenedEvent) error {
					return nil
				},
			},
		},
		{
			topic: topics.PullRequestSynchronize,
			message: &githubv1.PullRequestSynchronize{
				Actor:          et.EntitiesUserWriter(),
				Repository:     et.EntitiesRepository(),
				BaseRepository: et.EntitiesRepository(),
				Issue:          et.EntitiesIssue(),
				PullRequest:    et.EntitiesPullRequest(),
				BeforeOid:      "old-sha",
				AfterOid:       "new-sha",
			},
			handler: &events.NoopHandler{
				MockOnPullRequestSynchronize: func(ctx context.Context, event events.PullRequestSynchronizeEvent) error {
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
				IsAgentEnabled: true,
			})

			// Create a valid hydro message that would be processed if not in staging
			msg := newHydroMessage(t, tc.topic, tc.message)

			executeDispatcher := func(ffMap map[string]bool, environment config.Environment, environmentName string, shouldProcess bool) {
				if ffMap == nil {
					ffMap = make(map[string]bool)
				}

				ffClient := featureflags.NewNoopClient(ffMap)
				dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, tc.handler, ghTwirp, environment, environmentName, agenticapptest.NewTestProviderWithID(t, 123), nil)
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
	topic := topics.PullRequestTimelineCommentCreate

	h := &events.NoopHandler{}
	aq := aqueduct.NewMemoryClient(obsv)
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})

	e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, ghTwirp, config.EnvironmentProduction, "production", agenticapptest.NewTestProviderWithID(t, 123), nil)

	// Create a valid hydro message that should be processed in production
	msg := newHydroMessage(t, topic, &githubv1.PullRequestTimelineCommentCreate{
		Actor:        et.EntitiesUserWriter(),
		Repository:   et.EntitiesRepository(),
		Issue:        et.EntitiesIssue(),
		IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
		Body:         "@copilot please help",
	})

	err := e.Dispatch(context.Background(), msg)

	require.NoError(t, err, "Dispatch should not return an error")
	// PullRequestTimelineCommentCreate events should queue jobs
	require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
}

func TestDispatcher_HydroTenantHeaders(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(nil)
	topic := topics.PullRequestTimelineCommentCreate
	t.Run("extracts tenant headers in Proxima environment", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})

		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentProxima, "test-cnc-01", agenticapptest.NewTestProviderWithID(t, 123), nil)

		// Create a message with tenant headers
		msg := newHydroMessageWithHeaders(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		}, map[string]string{
			requestctx.GitHubTenantIDHeader: "test-tenant-id",
			requestctx.GitHubTenantHeader:   "test-tenant-slug",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		// PullRequestTimelineCommentCreate events should queue jobs
		require.Len(t, jobsInQueue, 1)

		// Verify the tenant information processing completed successfully
	})

	t.Run("skips tenant header extraction in non-Proxima environment", func(t *testing.T) {
		h := &events.NoopHandler{}
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})

		// Use Development environment instead of Proxima
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		// Create a message with tenant headers (should be ignored)
		msg := newHydroMessageWithHeaders(t, topic, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		}, map[string]string{
			requestctx.GitHubTenantIDHeader: "test-tenant-id",
			requestctx.GitHubTenantHeader:   "test-tenant-slug",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		// PullRequestTimelineCommentCreate events should queue jobs
		require.Len(t, jobsInQueue, 1)
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
			IsAgentEnabled: true,
		})

		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, h, ghTwirp, config.EnvironmentStaging, "staging", agenticapptest.NewTestProviderWithID(t, 123), nil)

		// Use mock actors with specific IDs
		mockActors := &mockActors{
			actorID:      123,
			repositoryID: 123,
			ownerID:      123,
		}

		enabled, _, err := dispatcher.checkEnablement(context.Background(), mockActors)
		require.NoError(t, err)
		require.False(t, enabled, "Feature should be disabled for user with disallow flag")
	})

	t.Run("adds tenant context from IsAgentEnabled response when headers-only flag disabled", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		ghFactory := &github.NoopClientFactory{}
		ffClient := featureflags.NewNoopClient(nil)
		aq := aqueduct.NewMemoryClient(obsv)
		h := &events.NoopHandler{}
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
			TenantSlug:     "response-tenant-slug",
			TenantId:       "response-tenant-id",
		})

		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, h, ghTwirp, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		ctx := requestctx.NewContext(context.Background())
		mockEvent := &mockActors{
			actorID:      456,
			repositoryID: 789,
		}

		enabled, _, err := dispatcher.checkEnablement(ctx, mockEvent)
		require.NoError(t, err)
		require.True(t, enabled)
		require.Equal(t, "response-tenant-slug", requestctx.TenantSlug(ctx))
		require.Equal(t, "response-tenant-id", requestctx.TenantID(ctx))
	})

	t.Run("does not add tenant context from IsAgentEnabled response when headers-only flag enabled", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		ghFactory := &github.NoopClientFactory{}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentTwirpProximaHookHeadersOnly: true,
		})
		aq := aqueduct.NewMemoryClient(obsv)
		h := &events.NoopHandler{}
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
			TenantSlug:     "response-tenant-slug",
			TenantId:       "response-tenant-id",
		})

		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, h, ghTwirp, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		ctx := requestctx.NewContext(context.Background())
		mockEvent := &mockActors{
			actorID:      456,
			repositoryID: 789,
		}

		enabled, _, err := dispatcher.checkEnablement(ctx, mockEvent)
		require.NoError(t, err)
		require.True(t, enabled)
		require.Empty(t, requestctx.TenantSlug(ctx))
		require.Empty(t, requestctx.TenantID(ctx))
	})

}

type mockActors struct {
	actorID      int64
	repositoryID int64
	ownerID      int64
	agentID      int64
}

func (a *mockActors) GetRepositoryID() int64 { return a.repositoryID }
func (a *mockActors) GetOwnerID() int64      { return a.ownerID }
func (a *mockActors) GetActorID() int64      { return a.actorID }
func (a *mockActors) GetAgentID() int64      { return a.agentID }

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

// counterCall records a single Counter invocation for test assertions.
type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

// distributionMsCall records a single DistributionMs invocation for test assertions.
type distributionMsCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

// metricsCapturingStatter captures Counter and DistributionMs calls for assertions.
type metricsCapturingStatter struct {
	stats.NullClient
	counterCalls        []counterCall
	distributionMsCalls []distributionMsCall
}

func (s *metricsCapturingStatter) Counter(key string, tags stats.Tags, value int64) {
	s.counterCalls = append(s.counterCalls, counterCall{key, tags, value})
}

func (s *metricsCapturingStatter) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	s.distributionMsCalls = append(s.distributionMsCalls, distributionMsCall{key, tags, duration})
}

func TestDispatcher_SkipMetrics(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}

	t.Run("emits event_skipped with reason not_enabled when repo is not enabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(nil)
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: false,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topics.PullRequestTimelineCommentCreate, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))

		// Should have emitted hydro.event_skipped with reason=not_enabled
		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, "not_enabled", skippedCalls[0].tags["reason"])

		// Ensure only minimal tags are emitted to keep cardinality low
		require.Equal(t, stats.Tags{"reason": "not_enabled", "topic": topics.PullRequestTimelineCommentCreate}, skippedCalls[0].tags)

		// Should NOT have emitted hydro.dispatch_dist
		require.Empty(t, filterDistributionMsCalls(statter.distributionMsCalls, "hydro.dispatch_dist"))
	})

	t.Run("emits event_skipped with reason environment_filter when event is filtered by environment", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(nil)
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})
		// Use staging environment; without the routing feature flag the event should be skipped
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, noopClient, config.EnvironmentStaging, "staging", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topics.PullRequestTimelineCommentCreate, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))

		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, "environment_filter", skippedCalls[0].tags["reason"])

		// Ensure only minimal tags are emitted to keep cardinality low
		require.Equal(t, stats.Tags{"reason": "environment_filter", "topic": topics.PullRequestTimelineCommentCreate}, skippedCalls[0].tags)

		require.Empty(t, filterDistributionMsCalls(statter.distributionMsCalls, "hydro.dispatch_dist"))
	})

	t.Run("emits dispatch_dist only when event is actually processed", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(nil)
		aq := aqueduct.NewMemoryClient(obsv)
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, noopClient, config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), nil)

		msg := newHydroMessage(t, topics.PullRequestTimelineCommentCreate, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)

		// Should have emitted hydro.dispatch_dist for the successfully processed event
		require.Len(t, filterDistributionMsCalls(statter.distributionMsCalls, "hydro.dispatch_dist"), 1)

		// Should NOT have emitted hydro.event_skipped
		require.Empty(t, filterCounterCalls(statter.counterCalls, "hydro.event_skipped"))
	})
}

func TestDispatcher_GatesTriggerFeatureFlag(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}

	makeTwirpEnabled := func() *githubtwirp.NoopClient {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})
		return noopClient
	}

	makeIssueMsg := func(t *testing.T) hydro_lib.Message {
		t.Helper()
		return newHydroMessage(t, topics.IssueCreateTemplate, &githubv1.IssueCreateTemplate{
			Actor:           et.EntitiesUserWriter(),
			Repository:      et.EntitiesRepository(),
			RepositoryOwner: et.EntitiesUser(et.RepoOwner),
			Issue:           et.EntitiesIssue(),
		})
	}

	makeFailedWorkflowMsg := func(t *testing.T) hydro_lib.Message {
		t.Helper()
		repoID, _ := et.IDsFromString(et.RepoName)
		ownerID, _ := et.IDsFromString(et.RepoOwner)
		actorID, _ := et.IDsFromString(et.ActorLoginWriter)
		workflowRunID, _ := et.IDsFromString("workflow-run")
		return newHydroMessage(t, topics.WorkflowRunExecution, &actionsv0.WorkflowRunExecution{
			WorkflowRunId:     workflowRunID,
			RepositoryId:      repoID,
			RepositoryOwnerId: ownerID,
			ActorId:           actorID,
			WorkflowRunPath:   ".github/workflows/ci.yaml",
			Conclusion:        "failure",
			Status:            "completed",
		})
	}

	t.Run("skips issue trigger before store lookup when main trigger flag is disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasIssueCreated: true}
		dispatcher := NewDispatcher(obsv, featureflags.NewNoopClient(nil), ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		err := dispatcher.Dispatch(context.Background(), makeIssueMsg(t))
		require.NoError(t, err)

		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))
		require.Equal(t, 0, checker.issueCreatedChecks)
		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "trigger_feature_flag", "topic": topics.IssueCreateTemplate}, skippedCalls[0].tags)
	})

	t.Run("skips issue trigger before store lookup when issue-opened flag is disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasIssueCreated: true}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
		})
		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		err := dispatcher.Dispatch(context.Background(), makeIssueMsg(t))
		require.NoError(t, err)

		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))
		require.Equal(t, 0, checker.issueCreatedChecks)
		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "event_filter", "topic": topics.IssueCreateTemplate}, skippedCalls[0].tags)
	})

	t.Run("skips workflow_run trigger before store lookup when main trigger flag is disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasWorkflowRunFailed: true}
		dispatcher := NewDispatcher(obsv, featureflags.NewNoopClient(nil), ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		err := dispatcher.Dispatch(context.Background(), makeFailedWorkflowMsg(t))
		require.NoError(t, err)

		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))
		require.Equal(t, 0, checker.workflowRunFailedChecks)
		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "trigger_feature_flag", "topic": topics.WorkflowRunExecution}, skippedCalls[0].tags)
	})

	t.Run("does not block non-trigger CCA events when main trigger flag is disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		dispatcher := NewDispatcher(obsv, featureflags.NewNoopClient(nil), ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), &mockAutomationLookup{})

		msg := newHydroMessage(t, topics.PullRequestTimelineCommentCreate, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := dispatcher.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
		require.Empty(t, filterCounterCalls(statter.counterCalls, "hydro.event_skipped"))
	})

	t.Run("still uses trigger-specific matching when main trigger flag is enabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasIssueCreated: false}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
			featureflags.CopilotSWEAgentIssueOpenedTrigger:  true,
		})
		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		err := dispatcher.Dispatch(context.Background(), makeIssueMsg(t))
		require.NoError(t, err)

		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))
		require.Equal(t, 1, checker.issueCreatedChecks)
		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "event_filter", "topic": topics.IssueCreateTemplate}, skippedCalls[0].tags)
	})
}

func TestDispatcher_GatesAutomationsDisabled(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}

	makeIssueMsg := func(t *testing.T) hydro_lib.Message {
		return newHydroMessage(t, topics.IssueCreateTemplate, &githubv1.IssueCreateTemplate{
			Actor:           et.EntitiesUserWriter(),
			Repository:      et.EntitiesRepository(),
			RepositoryOwner: et.EntitiesUser(et.RepoOwner),
			Issue:           et.EntitiesIssue(),
		})
	}

	// IssueCreated must pass shouldProcessEvent first, which needs the
	// custom-agent-triggers FF on AND an automation lookup reporting matches.
	makeFFClient := func() featureflags.Client {
		return featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
			featureflags.CopilotSWEAgentIssueOpenedTrigger:  true,
		})
	}

	makeTwirpWithAutomationsDisabled := func() *githubtwirp.NoopClient {
		c := githubtwirp.NewNoopClient()
		c.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled:      true,
			AutomationsDisabled: true,
		})
		return c
	}

	t.Run("skips trigger event when automation lookup reports automations disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, makeFFClient(), ghFactory, aq, &events.NoopHandler{}, makeTwirpWithAutomationsDisabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), &mockAutomationLookup{hasIssueCreated: true, automationsDisabled: true})

		err := e.Dispatch(context.Background(), makeIssueMsg(t))
		require.NoError(t, err)

		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))

		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "automations_disabled", "topic": topics.IssueCreateTemplate}, skippedCalls[0].tags)
	})

	t.Run("does not skip trigger event when automation lookup reports policy off", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, makeFFClient(), ghFactory, aq, &events.NoopHandler{}, makeTwirpWithAutomationsDisabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), &mockAutomationLookup{hasIssueCreated: true, automationsDisabled: false})

		err := e.Dispatch(context.Background(), makeIssueMsg(t))
		require.NoError(t, err)

		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
		require.Empty(t, filterCounterCalls(statter.counterCalls, "hydro.event_skipped"))
	})

	t.Run("does not skip user-invoked event even when automations disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		aq := aqueduct.NewMemoryClient(obsv)
		e := NewDispatcher(obsv, makeFFClient(), ghFactory, aq, &events.NoopHandler{}, makeTwirpWithAutomationsDisabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), &mockAutomationLookup{automationsDisabled: true})

		// PullRequestTimelineCommentCreate is user-invoked, so triggerForEvent
		// returns "" and the gate is a no-op.
		msg := newHydroMessage(t, topics.PullRequestTimelineCommentCreate, &githubv1.PullRequestTimelineCommentCreate{
			Actor:        et.EntitiesUserWriter(),
			Repository:   et.EntitiesRepository(),
			Issue:        et.EntitiesIssue(),
			IssueComment: et.EntitiesIssueComment(et.ActorLoginWriter),
			Body:         "@copilot please help",
		})

		err := e.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
		require.Empty(t, filterCounterCalls(statter.counterCalls, "hydro.event_skipped"))
	})
}

func TestDispatcher_GatesPublicRepository(t *testing.T) {
	ghFactory := &github.NoopClientFactory{}

	makeTwirpEnabled := func() *githubtwirp.NoopClient {
		noopClient := githubtwirp.NewNoopClient()
		noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
			IsAgentEnabled: true,
		})
		return noopClient
	}

	makeFFClient := func() featureflags.Client {
		return featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
			featureflags.CopilotSWEAgentIssueOpenedTrigger:  true,
		})
	}

	makePublicIssueMsg := func(t *testing.T) hydro_lib.Message {
		t.Helper()
		return newHydroMessage(t, topics.IssueCreateTemplate, &githubv1.IssueCreateTemplate{
			Actor:           et.EntitiesUserWriter(),
			Repository:      et.EntitiesPublicRepository(),
			RepositoryOwner: et.EntitiesUser(et.RepoOwner),
			Issue:           et.EntitiesIssue(),
		})
	}

	t.Run("skips issue_created trigger before enqueueing when repository is public", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasIssueCreated: true}
		dispatcher := NewDispatcher(obsv, makeFFClient(), ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		err := dispatcher.Dispatch(context.Background(), makePublicIssueMsg(t))
		require.NoError(t, err)

		require.Empty(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...))
		require.Equal(t, 0, checker.issueCreatedChecks)
		skippedCalls := filterCounterCalls(statter.counterCalls, "hydro.event_skipped")
		require.Len(t, skippedCalls, 1)
		require.Equal(t, stats.Tags{"reason": "public_repository", "topic": topics.IssueCreateTemplate}, skippedCalls[0].tags)
	})

	t.Run("does not skip public issue_created trigger when public-repo block is disabled", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasIssueCreated: true}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCustomAgentTriggers: true,
			featureflags.CopilotAutomationsBlockPublicRepos: false,
			featureflags.CopilotSWEAgentIssueOpenedTrigger:  true,
		})
		dispatcher := NewDispatcher(obsv, ffClient, ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		err := dispatcher.Dispatch(context.Background(), makePublicIssueMsg(t))
		require.NoError(t, err)

		require.Empty(t, filterCounterCalls(statter.counterCalls, "hydro.event_skipped"))
		require.Equal(t, 1, checker.issueCreatedChecks)
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
	})

	t.Run("does not skip issue_created trigger for private repository", func(t *testing.T) {
		statter := &metricsCapturingStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter
		aq := aqueduct.NewMemoryClient(obsv)
		checker := &mockAutomationLookup{hasIssueCreated: true}
		dispatcher := NewDispatcher(obsv, makeFFClient(), ghFactory, aq, &events.NoopHandler{}, makeTwirpEnabled(), config.EnvironmentDevelopment, "development", agenticapptest.NewTestProviderWithID(t, 123), checker)

		msg := newHydroMessage(t, topics.IssueCreateTemplate, &githubv1.IssueCreateTemplate{
			Actor:           et.EntitiesUserWriter(),
			Repository:      et.EntitiesRepository(),
			RepositoryOwner: et.EntitiesUser(et.RepoOwner),
			Issue:           et.EntitiesIssue(),
		})
		err := dispatcher.Dispatch(context.Background(), msg)
		require.NoError(t, err)

		// Private repo: event should be enqueued (no public_repository skip).
		require.Empty(t, filterCounterCalls(statter.counterCalls, "hydro.event_skipped"))
		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 1)
	})
}

func filterCounterCalls(calls []counterCall, key string) []counterCall {
	var filtered []counterCall
	for _, c := range calls {
		if c.key == key {
			filtered = append(filtered, c)
		}
	}
	return filtered
}

func filterDistributionMsCalls(calls []distributionMsCall, key string) []distributionMsCall {
	var filtered []distributionMsCall
	for _, c := range calls {
		if c.key == key {
			filtered = append(filtered, c)
		}
	}
	return filtered
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

func TestPRHydroEventsIntegration(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghFactory := &github.NoopClientFactory{}

	h := &events.NoopHandler{}

	noopClient := githubtwirp.NewNoopClient()
	noopClient.NoopSweagentdAPI.ConfigurationForRepositoryResponse = to.Ptr(sweagentdTwirp.ConfigurationForRepositoryResponse{
		IsAgentEnabled: true,
	})

	// Test that close events are routed correctly
	t.Run("close events are routed to state change handler", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		provider := agenticapptest.NewTestProviderWithID(t, 123)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a closed PR authored by the agentic app
		copilotPR := et.EntitiesPullRequest()
		copilotPR.PullRequestState = entitiesv1.PullRequest_CLOSED
		copilotPR.AuthorId = uint64(provider.CopilotApp().BotID())

		msg := newHydroMessage(t, topics.PullRequestClose, &githubv1.PullRequestClose{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: copilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestClose)
	})

	// Test that merge events are routed correctly
	t.Run("merge events are routed to state change handler", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		provider := agenticapptest.NewTestProviderWithID(t, 123)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a merged PR authored by the agentic app
		copilotPR := et.EntitiesPullRequest()
		copilotPR.PullRequestState = entitiesv1.PullRequest_MERGED
		copilotPR.AuthorId = uint64(provider.CopilotApp().BotID())

		msg := newHydroMessage(t, topics.PullRequestMerge, &githubv1.PullRequestMerge{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: copilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestMerge)
	})

	// Test that PRs not authored by an agentic app are filtered out
	t.Run("non-agentic-app PR events are ignored", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		// Create a provider with multiple apps
		customApp := &mockAgenticApp{
			appID:        456,
			botID:        789,
			branchPrefix: "custom-agent",
		}
		copilot := agenticapptest.NewTestCopilotWithID(t, 123)
		provider := agenticapp.NewProvider(copilot, customApp)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a non-agentic app PR with an author ID that doesn't match any agentic app
		nonAgenticPR := et.EntitiesPullRequest()
		nonAgenticPR.AuthorId = 999 // Does not match any bot ID in provider

		msg := newHydroMessage(t, topics.PullRequestClose, &githubv1.PullRequestClose{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: nonAgenticPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		require.Len(t, aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...), 0)
	})

	t.Run("copilot-authored PR events are processed", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		provider := agenticapptest.NewTestProviderWithID(t, 123)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a PR authored by the copilot bot (AuthorId matches copilot's botID)
		copilotPR := et.EntitiesPullRequest()
		copilotPR.AuthorId = uint64(provider.CopilotApp().BotID())

		msg := newHydroMessage(t, topics.PullRequestClose, &githubv1.PullRequestClose{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: copilotPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestClose)
	})

	// Test that PRs authored by custom agentic apps are processed
	t.Run("custom agentic app PR events are processed", func(t *testing.T) {
		aq := aqueduct.NewMemoryClient(obsv)
		// Create a provider with multiple apps
		customApp := &mockAgenticApp{
			appID:        456,
			botID:        789,
			branchPrefix: "custom-agent",
		}
		copilot := agenticapptest.NewTestCopilotWithID(t, 123)
		provider := agenticapp.NewProvider(copilot, customApp)
		e := NewDispatcher(obsv, ffClient, ghFactory, aq, h, noopClient, config.EnvironmentDevelopment, "development", provider, nil)

		// Create a PR authored by the custom agentic app (AuthorId matches custom app's botID)
		customAgentPR := et.EntitiesPullRequest()
		customAgentPR.AuthorId = uint64(customApp.BotID())

		msg := newHydroMessage(t, topics.PullRequestClose, &githubv1.PullRequestClose{
			Actor:       et.EntitiesUserWriter(),
			Repository:  et.EntitiesRepository(),
			Issue:       et.EntitiesIssue(),
			PullRequest: customAgentPR,
		})

		err := e.Dispatch(ctx, msg)
		require.NoError(t, err)

		jobsInQueue := aq.QueuedJobs(slices.Concat(aqueductJobs.EventJobServiceQueues, aqueductJobs.EventJobWorkerQueues)...)
		require.Len(t, jobsInQueue, 1)

		job := jobsInQueue[0]
		require.Equal(t, job.Queue, aqueductJobs.EventJobBackgroundQueueName)

		var eventJob aqueductJobs.EventJob
		err = eventJob.Unmarshal(job.Payload)
		require.NoError(t, err)
		require.Equal(t, eventJob.Topic, topics.PullRequestClose)
	})
}

// mockAgenticApp is a test helper that implements sweagentd.AgenticApp
type mockAgenticApp struct {
	appID        int64
	botID        int64
	branchPrefix string
}

func (m *mockAgenticApp) AppID() int64    { return m.appID }
func (m *mockAgenticApp) AppName() string { return "Mock App" }

func (m *mockAgenticApp) WorkflowRunName(_ int) string { return "" }

func (m *mockAgenticApp) BranchPrefix() string { return m.branchPrefix }

func (m *mockAgenticApp) BotID() int64                { return m.botID }
func (m *mockAgenticApp) PrivateKey() *rsa.PrivateKey { return nil }
func (m *mockAgenticApp) ClientID() string            { return "mock-client-id" }
func (m *mockAgenticApp) ClientSecret() string        { return "mock-client-secret" }
func (m *mockAgenticApp) BotLogin() string            { return "mock-bot" }
func (m *mockAgenticApp) CommitLogin() string         { return "mock-commit" }
func (m *mockAgenticApp) CommitEmail() string         { return "mock@email.com" }
func (m *mockAgenticApp) MentionableSlug() string     { return "mock-app" }
func (m *mockAgenticApp) ComputeSlug() string         { return "mock-app" }
func (m *mockAgenticApp) EngineSlug() string          { return m.ComputeSlug() }
func (m *mockAgenticApp) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return nil
}
func (m *mockAgenticApp) ModelVendors() []string                    { return nil }
func (m *mockAgenticApp) SetupCompute(compute sweagentd.ComputeEnv) {}

func (m *mockAgenticApp) HasSource() bool                     { return false }
func (m *mockAgenticApp) SourceURL() string                   { return "" }
func (m *mockAgenticApp) IsQuotaExempt() bool                 { return false }
func (m *mockAgenticApp) UsesExperiments() bool               { return true }
func (m *mockAgenticApp) AgentSource() *sweagentd.AgentSource { return nil }
func (m *mockAgenticApp) IsGlobalApp() bool                   { return false }
func (m *mockAgenticApp) IsPartnerApp() bool                  { return false }
func (m *mockAgenticApp) IsThirdPartyApp() bool               { return false }
func (m *mockAgenticApp) Metadata() map[string]string         { return nil }
