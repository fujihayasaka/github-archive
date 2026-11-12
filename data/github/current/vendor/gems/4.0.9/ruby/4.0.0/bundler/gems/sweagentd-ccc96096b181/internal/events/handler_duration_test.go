package events

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/go-stats"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

type distributionCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

// testStatter captures DistributionMs calls for verification
type testStatter struct {
	stats.NullClient
	calls []distributionCall
}

func (s *testStatter) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	s.calls = append(s.calls, distributionCall{key: key, tags: tags, duration: duration})
}

func TestProcess_DurationMetric(t *testing.T) {
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("emits success outcome for pull_request_comment_created", func(t *testing.T) {
		statter := &testStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		event := &PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		}
		err := h.Process(context.Background(), event)
		require.NoError(t, err)

		// Find the duration metric call
		var durationCall *distributionCall
		for i := range statter.calls {
			if statter.calls[i].key == "events.handler_duration_ms" {
				durationCall = &statter.calls[i]
				break
			}
		}

		require.NotNil(t, durationCall, "expected events.handler_duration_ms metric to be emitted")
		require.Equal(t, "pull_request_comment_created", durationCall.tags["event_type"])
		require.Equal(t, "success", durationCall.tags["outcome"])
		require.Greater(t, durationCall.duration, time.Duration(0))
	})

	t.Run("emits error outcome for pull_request_comment_created when handler fails", func(t *testing.T) {
		statter := &testStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		// Configure the GitHub factory to return an error
		errorGhFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
			MockNewClientFromRepo: func(ctx context.Context, repoID, repoOwnerID int64) (github.ClientInterface, error) {
				return nil, errors.New("mock error: failed to create client")
			},
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, errorGhFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		event := &PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		}
		err := h.Process(context.Background(), event)
		require.Error(t, err)

		// Find the duration metric call
		var durationCall *distributionCall
		for i := range statter.calls {
			if statter.calls[i].key == "events.handler_duration_ms" {
				durationCall = &statter.calls[i]
				break
			}
		}

		require.NotNil(t, durationCall, "expected events.handler_duration_ms metric to be emitted")
		require.Equal(t, "pull_request_comment_created", durationCall.tags["event_type"])
		require.Equal(t, "error", durationCall.tags["outcome"])
		require.Greater(t, durationCall.duration, time.Duration(0))
	})

	t.Run("emits success outcome for pull_request_review_submit", func(t *testing.T) {
		statter := &testStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		event := &PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		}
		err := h.Process(context.Background(), event)
		require.NoError(t, err)

		// Find the duration metric call
		var durationCall *distributionCall
		for i := range statter.calls {
			if statter.calls[i].key == "events.handler_duration_ms" {
				durationCall = &statter.calls[i]
				break
			}
		}

		require.NotNil(t, durationCall, "expected events.handler_duration_ms metric to be emitted")
		require.Equal(t, "pull_request_review_submit", durationCall.tags["event_type"])
		require.Equal(t, "success", durationCall.tags["outcome"])
		require.Greater(t, durationCall.duration, time.Duration(0))
	})

	t.Run("emits error outcome for pull_request_review_submit when handler fails", func(t *testing.T) {
		statter := &testStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		// Configure the GitHub factory to return an error
		errorGhFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
			MockNewClientFromRepo: func(ctx context.Context, repoID, repoOwnerID int64) (github.ClientInterface, error) {
				return nil, errors.New("mock error: failed to create client")
			},
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, errorGhFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		event := &PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		}
		err := h.Process(context.Background(), event)
		require.Error(t, err)

		// Find the duration metric call
		var durationCall *distributionCall
		for i := range statter.calls {
			if statter.calls[i].key == "events.handler_duration_ms" {
				durationCall = &statter.calls[i]
				break
			}
		}

		require.NotNil(t, durationCall, "expected events.handler_duration_ms metric to be emitted")
		require.Equal(t, "pull_request_review_submit", durationCall.tags["event_type"])
		require.Equal(t, "error", durationCall.tags["outcome"])
		require.Greater(t, durationCall.duration, time.Duration(0))
	})
}

func TestEventTypeName(t *testing.T) {
	tests := []struct {
		name     string
		event    any
		expected string
	}{
		{"PullRequestCommentCreatedEvent", &PullRequestCommentCreatedEvent{}, "pull_request_comment_created"},
		{"PullRequestReviewSubmitEvent", &PullRequestReviewSubmitEvent{}, "pull_request_review_submit"},
		{"PullRequestStateChangedEvent", &PullRequestStateChangedEvent{}, "pull_request_state_changed"},
		{"WorkflowRunCompletedEvent", &WorkflowRunCompletedEvent{}, "workflow_run_completed"},
		{"CodeScanningAlertsAssignmentEvent", &CodeScanningAlertsAssignmentEvent{}, "code_scanning_alerts_assignment"},
		{"IssueCreatedEvent", &IssueCreatedEvent{}, "issue_created"},
		{"unknown type", "unknown", "unknown"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := eventTypeName(tc.event)
			require.Equal(t, tc.expected, result)
		})
	}
}
