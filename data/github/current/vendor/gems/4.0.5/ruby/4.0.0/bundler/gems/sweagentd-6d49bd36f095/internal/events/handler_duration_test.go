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
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

type distributionCall struct {
	key      string
	tags     stats.Tags
	duration time.Duration
}

type counterCall struct {
	key  string
	tags stats.Tags
}

// testStatter captures DistributionMs and Counter calls for verification
type testStatter struct {
	stats.NullClient
	calls        []distributionCall
	counterCalls []counterCall
}

func (s *testStatter) DistributionMs(key string, tags stats.Tags, duration time.Duration) {
	s.calls = append(s.calls, distributionCall{key: key, tags: tags, duration: duration})
}

func (s *testStatter) Counter(key string, tags stats.Tags, _ int64) {
	s.counterCalls = append(s.counterCalls, counterCall{key: key, tags: tags})
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

	t.Run("emits expected outcome for pull_request_comment_created when error is expected", func(t *testing.T) {
		statter := &testStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPRCommentRulesCheck: true,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		prCtx := &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		rulesGhFactory := &github.NoopClientFactory{
			GitHubAppLogin:         et.GitHubAppLogin,
			GitHubBotLogin:         et.GitHubBotLogin,
			MockPullRequestContext: prCtx,
			MockNewClientFromRepo: func(ctx context.Context, repoID, repoOwnerID int64) (github.ClientInterface, error) {
				return &github.NoopClient{
					GithubAppLogin:         et.GitHubAppLogin,
					GithubBotLogin:         et.GitHubBotLogin,
					MockPullRequestContext: prCtx,
					MockListBranchProtectionRules: func(ctx context.Context, repoNodeID string) (*[]github.GQLBranchProtectionRule, error) {
						return &[]github.GQLBranchProtectionRule{
							{Pattern: "*", RequiresApprovingReviews: true},
						}, nil
					},
					MockListRepositoryRulesForBranch: func(ctx context.Context, ownerLogin, repoName, branchName string, excludeRulesetIDs []uint64) (*gg.BranchRules, error) {
						return &gg.BranchRules{}, nil
					},
				}, nil
			},
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, rulesGhFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

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
		// Process swallows expected errors (returns nil) after posting comment
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
		require.Equal(t, "expected", durationCall.tags["outcome"])
	})

	t.Run("returns nil and emits skipped counter when node ID cannot be resolved (deleted/transferred repo)", func(t *testing.T) {
		statter := &testStatter{}
		obsv := observability.NewNoopExporters()
		obsv.Statter = statter

		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		// Create a node-not-found GraphQL error to simulate deleted/transferred repo
		nodeNotFoundMsg := "Could not resolve to a node with the global id of 'R_deleted123'."
		nodeNotFoundErr := &github.GraphQLError{
			IsQueryError: true,
			Message:      nodeNotFoundMsg,
			QueryErrors: []github.QueryError{
				{Message: nodeNotFoundMsg},
			},
		}

		nodeNotFoundFactory := &github.NoopClientFactory{
			GitHubAppLogin:            et.GitHubAppLogin,
			GitHubBotLogin:            et.GitHubBotLogin,
			MockPullRequestContextErr: nodeNotFoundErr,
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, nodeNotFoundFactory)
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

		// Process should return nil (not an error) for node-not-found cases
		err := h.Process(context.Background(), event)
		require.NoError(t, err)

		// Verify the duration metric was emitted with "error" outcome: an error did
		// occur during processing but it is treated as an expected/skippable condition
		// rather than a handler failure, so Process returns nil.
		var durationCall *distributionCall
		for i := range statter.calls {
			if statter.calls[i].key == "events.handler_duration_ms" {
				durationCall = &statter.calls[i]
				break
			}
		}
		require.NotNil(t, durationCall, "expected events.handler_duration_ms metric to be emitted")
		require.Equal(t, "pull_request_comment_created", durationCall.tags["event_type"])
		require.Equal(t, "skipped", durationCall.tags["outcome"])

		// Verify the node_not_found_skipped counter was incremented
		var skippedCounter *counterCall
		for i := range statter.counterCalls {
			if statter.counterCalls[i].key == "events.node_not_found_skipped" {
				skippedCounter = &statter.counterCalls[i]
				break
			}
		}
		require.NotNil(t, skippedCounter, "expected events.node_not_found_skipped counter to be incremented")
		require.Equal(t, "pull_request_comment_created", skippedCounter.tags["event_type"])
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
		{"WorkflowRunCompletedEvent (agent run)", &WorkflowRunCompletedEvent{Kind: WorkflowRunKindAgentCompletion}, "workflow_run_completed"},
		{"WorkflowRunCompletedEvent (trigger)", &WorkflowRunCompletedEvent{Kind: WorkflowRunKindFailedTrigger}, "workflow_run_failed_trigger"},
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
