package events

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/customagent"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobexecutor"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/jobservice/jobservicetest"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/github/sweagentd/internal/sweagentd"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

func simpleMentionChecker(body string) bool {
	return strings.Contains(body, "@copilot")
}

func TestOnPullRequestReviewSubmit(t *testing.T) {
	obsv := observability.NewNoopExporters()

	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	t.Run("queues the agent job", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		})
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)

		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("queues the agent job on PRs assigned to other users and not Copilot", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)
		pr = et.AddAssigneesToPullRequest(pr, *et.UserWriter())

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		})
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)

		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("ignores events on PRs that are closed", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		author := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *author, *author)
		pr.Closed = true

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(author),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(author),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores reviews on human-authored PRs without copilot mention", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		author := et.ActorWriter()
		pr := et.PullRequestWithAuthor(author, *et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, false, *author, *author)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(author),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(author),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("handles wake logic properly", func(t *testing.T) {
		ghTwirpAlt := githubtwirp.NewNoopClient()
		ghTwirpAlt.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		ffc := featureflags.NewNoopClient(map[string]bool{})

		type scenario struct {
			bodyHasAtCopilot bool
			changesRequested bool
			isAssignee       bool
			launched         bool
		}
		scenarios := []scenario{
			// We should always launch if @copilot is mentioned
			{bodyHasAtCopilot: true, changesRequested: true, isAssignee: false, launched: true},
			{bodyHasAtCopilot: true, changesRequested: false, isAssignee: false, launched: true},
			{bodyHasAtCopilot: true, changesRequested: true, isAssignee: true, launched: true},
			{bodyHasAtCopilot: true, changesRequested: false, isAssignee: true, launched: true},
			// If no @copilot, we should launch only if changes requested AND reviewer is assignee
			{bodyHasAtCopilot: false, changesRequested: true, isAssignee: true, launched: true},
			{bodyHasAtCopilot: false, changesRequested: true, isAssignee: false, launched: false},
			{bodyHasAtCopilot: false, changesRequested: false, isAssignee: true, launched: false},
			{bodyHasAtCopilot: false, changesRequested: false, isAssignee: false, launched: false},
		}
		for _, s := range scenarios {
			skipsText := "does not launch"
			if s.launched {
				skipsText = "launches"
			}
			atCopilotText := "with @copilot"
			if !s.bodyHasAtCopilot {
				atCopilotText = "without @copilot"
			}
			assigneeText := "assignee"
			if !s.isAssignee {
				assigneeText = "non-assignee"
			}
			t.Run(fmt.Sprintf("%s %s, changesRequested: %v, %s", skipsText, atCopilotText, s.changesRequested, assigneeText), func(t *testing.T) {
				jobStore := memory.NewStore()
				capiClient := capi.NewNoopClient()
				h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirpAlt, ghFactory)
				ctx := context.Background()
				_, err := h.jobsStore.CreateAssignment(ctx, et.Assignment())
				require.NoError(t, err)
				actor := et.ActorWriter()
				pr := et.PullRequest(*et.UserCopilot())
				pr = et.AddReviewToPullRequest(pr, s.bodyHasAtCopilot, *actor, *actor)
				if s.changesRequested {
					pr.Reviews.Nodes[0].State = github.GQLPullRequestReviewStateChangesRequested
				} else {
					pr.Reviews.Nodes[0].State = github.GQLPullRequestReviewStateApproved
				}
				// Add the actor as an assignee if needed
				if s.isAssignee {
					pr = et.AddAssigneesToPullRequest(pr, *et.UserWriter())
				}

				ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

				pullRequestReview := EventPullRequestReview(actor)
				repo := EventRepository()
				evt := PullRequestReviewSubmitEvent{
					Actor:             EventActor(actor),
					Repo:              repo,
					PullRequest:       EventPullRequest(),
					PullRequestReview: pullRequestReview,
				}
				err = h.OnPullRequestReviewSubmit(ctx, evt)

				require.NoError(t, err)
				if s.launched {
					require.Len(t, service.QueuedJobs(), 1)
				} else {
					require.Len(t, service.QueuedJobs(), 0)
				}
			})
		}
	})

	t.Run("creates job when webhook event mentions agent but GraphQL review does not", func(t *testing.T) {
		// Regression test: the webhook event payload may contain an @copilot mention
		// that the GraphQL PullRequestContext does not reflect (due to eventual
		// consistency or pagination limits). The wake logic should fall back to the
		// webhook-based mention detection to avoid silently dropping these reviews.
		ghTwirpAlt := githubtwirp.NewNoopClient()
		ghTwirpAlt.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		ffc := featureflags.NewNoopClient(map[string]bool{})
		jobStore := memory.NewStore()
		capiClient := capi.NewNoopClient()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirpAlt, ghFactory)
		ctx := context.Background()
		_, err := h.jobsStore.CreateAssignment(ctx, et.Assignment())
		require.NoError(t, err)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		// GraphQL review does NOT contain @copilot mention
		pr = et.AddReviewToPullRequest(pr, false, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Webhook event DOES contain @copilot mention
		err = h.OnPullRequestReviewSubmit(ctx, PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1, "job should be created via webhook mention fallback even when GraphQL review lacks the mention")
	})

	t.Run("ignores reviews where the commenter doesn't have repo write access", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		reader := et.ActorReader()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *reader, *reader)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(reader),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(reader),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores reviews created by bots", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		bot := et.ActorBot()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *bot, *bot)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(bot),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(bot),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores reviews on cross-repository pull requests", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)
		pr.IsCrossRepository = true

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	// Table-driven job status tests
	jobStatusTests := []struct {
		name             string
		existingJobs     []jobs.JobStatus
		expectedQueueLen int
	}{
		{"skips launch with pending and running jobs", []jobs.JobStatus{jobs.JobStatusRunning, jobs.JobStatusPending}, 0},
		{"launches with pending and completed jobs", []jobs.JobStatus{jobs.JobStatusCompleted, jobs.JobStatusPending}, 1},
		{"launches with no existing jobs", nil, 1},
		{"skips launch with existing running job", []jobs.JobStatus{jobs.JobStatusRunning}, 0},
		{"launches with existing terminal jobs", []jobs.JobStatus{jobs.JobStatusCompleted}, 1},
	}
	for _, tt := range jobStatusTests {
		t.Run(tt.name, func(t *testing.T) {
			capiClient, jobStore, ghTwirp := commonHandlerDependencies()
			ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
					},
				}, nil
			}
			h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
			h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
			for _, status := range tt.existingJobs {
				h.jobsStore.CreateJob(context.Background(), et.Job(status))
			}

			actor := et.ActorWriter()
			pr := et.PullRequest(*et.UserCopilot())
			pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
				Actor:             EventActor(actor),
				Repo:              EventRepository(),
				PullRequest:       EventPullRequest(),
				PullRequestReview: EventPullRequestReview(actor),
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), tt.expectedQueueLen)
		})
	}

	t.Run("published job_started telemetry event", func(t *testing.T) {
		messageChan := make(chan hydro.Message, 1)
		sink, err := hydro.NewMemorySink(messageChan)
		require.NoError(t, err)
		publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
		obsvWithPublisher := obsv.WithPublisher(publisher)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()

		ffClient := featureflags.NewNoopClient(nil)
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, _, executor := NewTestHandler(t, obsvWithPublisher, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		_, err = h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		require.NoError(t, err)
		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		pullRequestReview := EventPullRequestReview(actor)
		repo := EventRepository()
		err = h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              repo,
			PullRequest:       EventPullRequest(),
			PullRequestReview: pullRequestReview,
		})

		require.NoError(t, err)
		require.Len(t, executor.LaunchAgentCalls(), 0)

		select {
		case <-messageChan:
			t.Error("No hydro event should be emitted immediately when queuing is enabled")
		case <-time.After(100 * time.Millisecond):
			// no event emitted immediately as jobs are queued by default
		}
	})

	t.Run("inherits model from previous job in assignment", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		// Mock CAPI to return the super-cool-model so validation passes
		model := capi.Model{ID: "super-cool-model", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{model}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		// Create first job with a specific model
		job1 := et.Job(jobs.JobStatusCompleted)
		job1.Model = "sweagent-capi:" + model.ID
		h.jobsStore.CreateJob(context.Background(), job1)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Get the created job from the store
		assignment := et.Assignment()
		allJobs, err := service.Store.GetJobsForAssignment(context.Background(), assignment)
		require.NoError(t, err)

		// Find the newly created job (not the completed one)
		var newJob *jobs.Job
		for _, job := range allJobs {
			if job.Status == jobs.JobStatusQueued {
				newJob = job
				break
			}
		}

		require.NotNil(t, newJob, "should have created a new queued job")
		require.Equal(t, "sweagent-capi:super-cool-model", newJob.Model, "new job should inherit model from previous job")
	})

	t.Run("does not inherit model from job belonging to different agent", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		model := capi.Model{ID: "super-cool-model", Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{model}, nil
		}

		// Use a custom app provider with testAgentID
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffc)
		service := jobservicetest.New(t, obsv, ffc, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffc, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffc, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		// Create a completed job with a model but belonging to a different agent
		job1 := et.Job(jobs.JobStatusCompleted)
		job1.Model = "sweagent-capi:" + model.ID
		job1.AgentID = testAgentID + 999 // different agent
		h.jobsStore.CreateJob(context.Background(), job1)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
			AgentID:           testAgentID,
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Get the created job from the store
		assignment := et.Assignment()
		allJobs, err := service.Store.GetJobsForAssignment(context.Background(), assignment)
		require.NoError(t, err)

		// Find the newly created job (not the completed one)
		var newJob *jobs.Job
		for _, job := range allJobs {
			if job.Status == jobs.JobStatusQueued {
				newJob = job
				break
			}
		}

		require.NotNil(t, newJob, "should have created a new queued job")
		// Should not return super-cool-model because a model from a different agent should not be inherited.
		require.Equal(t, "auto", newJob.Model, "new job should not inherit model from a job belonging to a different agent")
	})

	t.Run("does not inherit opus model for old assignments", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		// Mock CAPI to return Opus and Sonnet models
		opusModel := capi.Model{ID: capi.ClaudeOpus45, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		sonnet46Model := capi.Model{ID: capi.ClaudeSonnet46, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		sonnetModel := capi.Model{ID: capi.ClaudeSonnet45, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{opusModel, sonnet46Model, sonnetModel}, nil
		}

		// Use a custom app provider with testAgentID
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffc)
		service := jobservicetest.New(t, obsv, ffc, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffc, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffc, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)

		// Create assignment with CreatedAt before December 8, 2025
		assignment := et.Assignment()
		assignment.CreatedAt = 1765151999 // One second before Dec 8, 2025
		h.jobsStore.CreateAssignment(context.Background(), assignment)

		// Create first job with Opus model
		job1 := et.Job(jobs.JobStatusCompleted)
		job1.Model = "sweagent-capi:claude-opus-4.5"
		job1.AgentID = testAgentID
		h.jobsStore.CreateJob(context.Background(), job1)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
			AgentID:           testAgentID,
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Get the created job from the store
		allJobs, err := service.Store.GetJobsForAssignment(context.Background(), assignment)
		require.NoError(t, err)

		// Find the newly created job (not the completed one)
		var newJob *jobs.Job
		for _, job := range allJobs {
			if job.Status == jobs.JobStatusQueued {
				newJob = job
				break
			}
		}

		require.NotNil(t, newJob, "should have created a new queued job")
		// Should fall back to Sonnet 4.6 instead of inheriting Opus
		require.Equal(t, "auto", newJob.Model, "new job should use auto instead of inheriting Opus for old assignments")
	})

	t.Run("inherits opus model for new assignments", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		// Mock CAPI to return Opus and Sonnet models
		opusModel := capi.Model{ID: capi.ClaudeOpus45, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		sonnetModel := capi.Model{ID: capi.ClaudeSonnet45, Policy: &capi.ModelPolicy{State: capi.ModelPolicyStateEnabled}}
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64, actorType string) ([]capi.Model, error) {
			return []capi.Model{opusModel, sonnetModel}, nil
		}

		// Use a custom app provider with testAgentID
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffc)
		service := jobservicetest.New(t, obsv, ffc, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffc, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffc, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)

		// Create assignment with CreatedAt on or after December 8, 2025
		assignment := et.Assignment()
		assignment.CreatedAt = 1765152000 // Exactly Dec 8, 2025
		h.jobsStore.CreateAssignment(context.Background(), assignment)

		// Create first job with Opus model
		job1 := et.Job(jobs.JobStatusCompleted)
		job1.Model = "sweagent-capi:claude-opus-4.5"
		job1.AgentID = testAgentID
		h.jobsStore.CreateJob(context.Background(), job1)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
			AgentID:           testAgentID,
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Get the created job from the store
		allJobs, err := service.Store.GetJobsForAssignment(context.Background(), assignment)
		require.NoError(t, err)

		// Find the newly created job (not the completed one)
		var newJob *jobs.Job
		for _, job := range allJobs {
			if job.Status == jobs.JobStatusQueued {
				newJob = job
				break
			}
		}

		require.NotNil(t, newJob, "should have created a new queued job")
		// Should inherit Opus for new assignments
		require.Equal(t, "sweagent-capi:claude-opus-4.5", newJob.Model, "new job should inherit Opus for assignments created on/after Dec 8, 2025")
	})

	t.Run("skips launching if the review was an approval with no comments", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		reviewer := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *reviewer)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(reviewer),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(reviewer),
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("creates stack PR when non-Copilot PR and @copilot mentioned in review, leaving a timeline comment", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		capiCallCount := 0
		capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			capiCallCount++
			if capiCallCount == 1 {
				require.NotNil(t, body.ResponseFormat.OfJSONSchema, "first CAPI call should be intent detection with JSON schema")
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: `{"create_pull_request": true}`}}},
				}, nil
			}
			require.Nil(t, body.ResponseFormat.OfJSONSchema, "subsequent CAPI calls should be title generation without JSON schema")
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: "Fix review feedback"}}},
			}, nil
		}
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		gh := &github.NoopClient{}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		ghFactory.MockNewClientFromRepo = func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			return gh, nil
		}

		// Use a custom app provider with non-zero app ID to properly test AgentID
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgentService := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgentService, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgentService, nil)

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor) // review with @copilot mention

		gh.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		queuedJob := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), queuedJob.ActorId)

		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypePullRequestReviewNonCopilotPullRequest, job.EventType)
		require.Equal(t, testAgentID, job.AgentID, "AgentID should be set to the app ID that was mentioned")

		require.True(t, gh.HasNMethodCalls("CreateComment", 1))
		require.True(t, gh.HasNMethodCalls("CreateCommentInReplyTo", 0))
		require.Equal(t, 2, capiCallCount, "expected exactly 2 CAPI calls: intent detection + title generation")
	})

	t.Run("creates stack PR with @copilot in review body but not inline comment, leaving a timeline comment", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentReplyToCommentMentionsOnNonCopilotPRs: true,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		capiCallCount := 0
		capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			capiCallCount++
			if capiCallCount == 1 {
				require.NotNil(t, body.ResponseFormat.OfJSONSchema, "first CAPI call should be intent detection with JSON schema")
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: `{"create_pull_request": true}`}}},
				}, nil
			}
			require.Nil(t, body.ResponseFormat.OfJSONSchema, "subsequent CAPI calls should be title generation without JSON schema")
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: "Fix review feedback"}}},
			}, nil
		}
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		gh := &github.NoopClient{}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		ghFactory.MockNewClientFromRepo = func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			return gh, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)

		// Manually create a review with @copilot in body but not in the inline comment
		id, nodeID := et.IDsFromStrings(et.NameForIDsPullRequestReview, actor.GetLogin())
		reviewWithCopilotInBody := github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				GqlCommentCore: github.GqlCommentCore{
					ID:        github.FullDatabaseID(id),
					NodeID:    nodeID,
					Author:    *actor,
					Body:      "@copilot please fix this",
					CreatedAt: time.Now().Add(-time.Hour),
				},
			},
			GQLMinimizable: github.GQLMinimizable{
				IsMinimized: false,
			},
		}

		// Add an inline comment WITHOUT @copilot mention
		commentID, commentNodeID := et.IDsFromStrings(et.NameForIDsPullRequestReviewComment, actor.GetLogin())
		inlineComment := github.GQLPullRequestReviewComment{
			GQLComment: github.GQLComment{
				GqlCommentCore: github.GqlCommentCore{
					ID:        github.FullDatabaseID(commentID),
					NodeID:    commentNodeID,
					Author:    *actor,
					Body:      "also check this line",
					CreatedAt: time.Now().Add(-time.Hour),
				},
			},
			GqlReviewCommentFields: github.GqlReviewCommentFields{
				SubjectType:  github.GQLPullRequestReviewThreadSubjectTypeLine,
				Path:         "path",
				Line:         10,
				OriginalLine: 10,
			},
			GQLMinimizable: github.GQLMinimizable{
				IsMinimized: false,
			},
		}

		reviewWithCopilotInBody.Comments = github.GQLConnection[github.GQLPullRequestReviewComment]{
			TotalCount: 1,
			Nodes:      []github.GQLPullRequestReviewComment{inlineComment},
		}

		pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
			TotalCount: 1,
			Nodes:      []github.GQLPullRequestReview{reviewWithCopilotInBody},
		}

		gh.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		queuedJob := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), queuedJob.ActorId)

		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypePullRequestReviewNonCopilotPullRequest, job.EventType)

		// Should create a timeline comment because @copilot is in the review body, not the inline comment
		require.True(t, gh.HasNMethodCalls("CreateComment", 1))
		require.True(t, gh.HasNMethodCalls("CreateCommentInReplyTo", 0))
		require.Equal(t, 2, capiCallCount, "expected exactly 2 CAPI calls: intent detection + title generation")
	})

	t.Run("creates stack PR with @copilot only in inline comment, replying to that comment", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentReplyToCommentMentionsOnNonCopilotPRs: true,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		capiCallCount := 0
		capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			capiCallCount++
			if capiCallCount == 1 {
				require.NotNil(t, body.ResponseFormat.OfJSONSchema, "first CAPI call should be intent detection with JSON schema")
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: `{"create_pull_request": true}`}}},
				}, nil
			}
			require.Nil(t, body.ResponseFormat.OfJSONSchema, "subsequent CAPI calls should be title generation without JSON schema")
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: "Fix review feedback"}}},
			}, nil
		}
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		gh := &github.NoopClient{}
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		ghFactory.MockNewClientFromRepo = func(ctx context.Context, repoID, ownerID int64) (github.ClientInterface, error) {
			return gh, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)

		// Manually create a review WITHOUT @copilot in body
		id, nodeID := et.IDsFromStrings(et.NameForIDsPullRequestReview, actor.GetLogin())
		reviewWithoutCopilotInBody := github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				GqlCommentCore: github.GqlCommentCore{
					ID:        github.FullDatabaseID(id),
					NodeID:    nodeID,
					Author:    *actor,
					Body:      "please fix this",
					CreatedAt: time.Now().Add(-time.Hour),
				},
			},
			GQLMinimizable: github.GQLMinimizable{
				IsMinimized: false,
			},
		}

		// Add an inline comment WITH @copilot mention
		commentID, commentNodeID := et.IDsFromStrings(et.NameForIDsPullRequestReviewComment, actor.GetLogin())
		inlineCommentWithCopilot := github.GQLPullRequestReviewComment{
			GQLComment: github.GQLComment{
				GqlCommentCore: github.GqlCommentCore{
					ID:        github.FullDatabaseID(commentID),
					NodeID:    commentNodeID,
					Author:    *actor,
					Body:      "@copilot check this line",
					CreatedAt: time.Now().Add(-time.Hour),
				},
			},
			GqlReviewCommentFields: github.GqlReviewCommentFields{
				SubjectType:  github.GQLPullRequestReviewThreadSubjectTypeLine,
				Path:         "path",
				Line:         10,
				OriginalLine: 10,
			},
			GQLMinimizable: github.GQLMinimizable{
				IsMinimized: false,
			},
		}

		reviewWithoutCopilotInBody.Comments = github.GQLConnection[github.GQLPullRequestReviewComment]{
			TotalCount: 1,
			Nodes:      []github.GQLPullRequestReviewComment{inlineCommentWithCopilot},
		}

		pr.Reviews = github.GQLConnection[github.GQLPullRequestReview]{
			TotalCount: 1,
			Nodes:      []github.GQLPullRequestReview{reviewWithoutCopilotInBody},
		}

		gh.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		queuedJob := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), queuedJob.ActorId)

		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypePullRequestReviewNonCopilotPullRequest, job.EventType)

		// Should reply to the inline comment because that's where the @copilot mention is
		require.True(t, gh.HasNMethodCalls("CreateCommentInReplyTo", 1))
		require.True(t, gh.HasNMethodCalls("CreateComment", 0))
		require.Equal(t, 2, capiCallCount, "expected exactly 2 CAPI calls: intent detection + title generation")
	})

	t.Run("creates stack PR for non-copilot PR with copilot mention in review", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor) // review with @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1) // Job should be queued
	})

	t.Run("does not create stack PR when review does not mention @copilot", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddReviewToPullRequest(pr, false, *actor, *actor) // review without @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("does not create stack PR when PR is authored by Copilot", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Use the default Copilot-authored PR
		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())                  // PR authored by Copilot
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor) // review with @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Create an assignment for the existing Copilot PR
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		// This will enqueue a job on the existing PR, not a stack PR. Verify that
		// the job was queued normally.
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("generates problem statement with stacked PR title and body", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})

		// Mock CAPI client to return intent=true then a specific title
		capiCallCount := 0
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				capiCallCount++
				if capiCallCount == 1 {
					require.NotNil(t, body.ResponseFormat.OfJSONSchema, "first CAPI call should be intent detection with JSON schema")
					return &openai.ChatCompletion{
						Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: `{"create_pull_request": true}`}}},
					}, nil
				}
				require.Nil(t, body.ResponseFormat.OfJSONSchema, "subsequent CAPI calls should be title generation without JSON schema")
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: "Address review feedback",
							},
						},
					},
				}, nil
			},
		}

		jobStore := memory.NewStore()
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create a PR authored by a non-Copilot user
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr.Number = 123
		pr.Title = "Original PR Title"
		pr.Body = "Original PR Body"
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor) // review with @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Get the job and verify problem statement contains stacked PR title and body
		queuedJob := service.QueuedJobs()[0]
		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)

		// Verify job features are set with generated stacked PR title and body
		require.NotNil(t, job.Features.PullRequest)
		require.Equal(t, "[WIP] Address review feedback", job.Features.PullRequest.TitlePlaceholder)
		require.Contains(t, job.Features.PullRequest.BodyPlaceholder, "Thanks for the feedback on #123")

		// Verify problem statement uses the stacked PR title and body
		require.Contains(t, job.ProblemStatement.Content, "<pr_title>")
		require.Contains(t, job.ProblemStatement.Content, "[WIP] Address review feedback")
		require.NotContains(t, job.ProblemStatement.Content, "Original PR Title")

		require.Contains(t, job.ProblemStatement.Content, "<pr_description>")
		require.Contains(t, job.ProblemStatement.Content, "Thanks for the feedback on #123")
		require.NotContains(t, job.ProblemStatement.Content, "Original PR Body")
		require.Equal(t, 2, capiCallCount, "expected exactly 2 CAPI calls: intent detection + title generation")
	})

	t.Run("inherits CanWriteWorkflows from previous job in assignment", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		falseVal := false
		prevJob := et.Job(jobs.JobStatusCompleted)
		prevJob.CanWriteWorkflows = &falseVal
		h.jobsStore.CreateJob(context.Background(), prevJob)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		})
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		allJobs, err := service.Store.GetJobsForAssignment(context.Background(), et.Assignment())
		require.NoError(t, err)

		var newJob *jobs.Job
		for _, job := range allJobs {
			if job.Status == jobs.JobStatusQueued {
				newJob = job
				break
			}
		}
		require.NotNil(t, newJob, "should have created a new queued job")
		require.NotNil(t, newJob.CanWriteWorkflows, "should inherit from prior same-agent job")
		require.False(t, *newJob.CanWriteWorkflows)
	})

	t.Run("does not set CanWriteWorkflows when no prior job has a checked value", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		prevJob := et.Job(jobs.JobStatusCompleted)
		h.jobsStore.CreateJob(context.Background(), prevJob)

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
		})
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		allJobs, err := service.Store.GetJobsForAssignment(context.Background(), et.Assignment())
		require.NoError(t, err)

		var newJob *jobs.Job
		for _, job := range allJobs {
			if job.Status == jobs.JobStatusQueued {
				newJob = job
				break
			}
		}
		require.NotNil(t, newJob, "should have created a new queued job")
		require.Nil(t, newJob.CanWriteWorkflows, "no prior checked value to inherit")
	})
}

// TestReviewDoesMentionCopilot tests the reviewsWithCopilotMention function with different mention checkers
func TestReviewDoesMentionCopilot(t *testing.T) {
	copilot := agenticapptest.NewTestCopilot(t)
	appProvider := agenticapp.NewProvider(copilot, nil)

	mentionTests := []struct {
		name          string
		reviewBody    string
		commentBodies []string
		expectMatch   bool
	}{
		{"returns true when review body mentions copilot", "@copilot please review this", nil, true},
		{"returns true when review comment mentions copilot", "no mention in body", []string{"regular comment", "@copilot can you check this?"}, true},
		{"returns false when neither body nor comments mention copilot", "regular review body", []string{"regular comment 1", "regular comment 2"}, false},
		{"returns false when review has no comments", "regular review body", nil, false},
		{"handles empty body and comments", "", nil, false},
		{"checks all comments before returning false", "no mention", []string{"comment 1", "comment 2", "comment 3", "@copilot last comment"}, true},
	}
	for _, tt := range mentionTests {
		t.Run(tt.name, func(t *testing.T) {
			review := &github.GQLPullRequestReview{
				GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{Body: tt.reviewBody}},
			}
			if tt.commentBodies != nil {
				for _, body := range tt.commentBodies {
					review.Comments.Nodes = append(review.Comments.Nodes, github.GQLPullRequestReviewComment{
						GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{Body: body}},
					})
				}
			}
			result := reviewsWithCopilotMention(review, appProvider.IsAgenticMention)
			if tt.expectMatch {
				require.NotEmpty(t, result)
			} else {
				require.Empty(t, result)
			}
		})
	}

	t.Run("works with custom mention checker", func(t *testing.T) {
		customChecker := func(s string) (sweagentd.AgenticApp, bool) {
			if s == "custom trigger" {
				return copilot, true
			}
			return nil, false
		}

		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "custom trigger",
			}},
		}
		result := reviewsWithCopilotMention(review, customChecker)
		require.NotEmpty(t, result)

		review2 := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "@copilot",
			}},
		}
		result2 := reviewsWithCopilotMention(review2, customChecker)
		require.Empty(t, result2)
	})
}

// TestMentionsCopilot tests the Handler.mentionsCopilot method
func TestMentionsCopilot(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("uses agenticapp for mention detection", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "test-copilot",
			GitHubBotLogin: "test-copilot-bot",
		}

		appProvider := agenticapptest.NewTestProviderWithLogins(t, "test-copilot", "test-copilot-bot")

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "@copilot please review",
			}},
		}
		result := h.mentionsCopilot(review)
		require.NotEmpty(t, result)

		// Test without mention
		review2 := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "regular review",
			}},
		}
		result2 := h.mentionsCopilot(review2)
		require.Empty(t, result2)
	})

	t.Run("checks review comments when body has no mention", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		appProvider := agenticapptest.NewTestProviderWithLogins(t, et.GitHubAppLogin, et.GitHubBotLogin)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "regular body",
			}},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{
					{
						GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
							Body: "@copilot can you fix this?",
						}},
					},
				},
			},
		}
		result := h.mentionsCopilot(review)
		require.NotEmpty(t, result)
	})

	t.Run("detects agentic mention in review comments when not in body", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "test-copilot",
			GitHubBotLogin: "test-copilot-bot",
		}

		appProvider := agenticapptest.NewTestProviderWithLogins(t, "test-copilot", "test-copilot-bot")

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		reviewID, _ := et.IDsFromStrings(et.NameForIDsPullRequestReview, actor.GetLogin())
		event := PullRequestReviewSubmitEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequest(),
			PullRequestReview: &PullRequestReview{
				ID:       reviewID,
				Body:     "Review body without mention",
				Comments: []string{"First comment", "@copilot please fix this", "Another comment"},
			},
		}

		err := h.OnPullRequestReviewSubmit(context.Background(), event)
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		queuedJob := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), queuedJob.ActorId)
	})
}

func TestOnPullRequestReviewSubmit_WorkOnCurrentBranch(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("works on current branch when feature flag enabled and @copilot mentioned on non-Copilot PR", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgentService := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgentService, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgentService, nil)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr.Number = 42
		pr.HeadRef.Name = "feature-branch"
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor) // review with @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		queuedJob := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), queuedJob.ActorId)

		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, "feature-branch", job.BranchName)
		require.Equal(t, jobs.EventTypePullRequestReviewNonCopilotPullRequest, job.EventType)
		require.Equal(t, testAgentID, job.AgentID)
	})

	t.Run("creates assignment when working on current branch if none exists", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgentService := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgentService, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgentService, nil)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr.Number = 42
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
			EventUrl:          "https://example.com/event",
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		assignment, err := h.jobsStore.GetAssignment(context.Background(), EventRepository().OwnerID, EventRepository().ID, service.QueuedJobs()[0].AssignmentId)
		require.NoError(t, err)
		require.NotNil(t, assignment)
		require.Len(t, assignment.Resources, 1)
		require.Equal(t, "pull_request", assignment.Resources[0].Type)
	})
}

// Tests for intent-driven stacked PR creation on Copilot-authored PRs via reviews
func TestOnPullRequestReviewSubmit_IntentDriven(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	type scenario struct {
		name              string
		isCopilotAuthored bool
		mockCAPIResult    string // "true", "false", or "error"
		createAssignment  bool
		setupPR           func(pr *github.GQLPullRequest)
		verifyJob         func(t *testing.T, h *Handler, jobID string)
	}

	scenarios := []scenario{
		{
			name:              "creates stacked PR when intent detected for Copilot-authored PR",
			isCopilotAuthored: true,
			mockCAPIResult:    "true",
			createAssignment:  true,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.NotNil(t, storedJob.PullRequestID)
			},
		},
		{
			name:              "works on current branch when no intent detected for Copilot-authored PR",
			isCopilotAuthored: true,
			mockCAPIResult:    "false",
			createAssignment:  true,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.NotNil(t, storedJob.PullRequestID)
			},
		},
		{
			name:              "falls back to current branch when intent detection fails for Copilot-authored PR",
			isCopilotAuthored: true,
			mockCAPIResult:    "error",
			createAssignment:  true,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.NotNil(t, storedJob.PullRequestID)
			},
		},
	}

	for _, s := range scenarios {
		t.Run(s.name, func(t *testing.T) {
			ffClient := featureflags.NewNoopClient(map[string]bool{})
			capiClient, jobStore, ghTwirp := commonHandlerDependencies()

			switch s.mockCAPIResult {
			case "true":
				capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
					return &openai.ChatCompletion{
						Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: `{"create_pull_request": true}`}}},
					}, nil
				}
			case "false":
				capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
					return &openai.ChatCompletion{
						Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: `{"create_pull_request": false}`}}},
					}, nil
				}
			case "error":
				capiClient.MockChatCompletions = func(ctx context.Context, userID, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
					return nil, errors.New("CAPI error")
				}
			}

			ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
					},
				}, nil
			}

			appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
			spokes := spokestest.NewClient(t)
			customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
			service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
			executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
			h := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)

			if s.createAssignment {
				h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
			}

			actor := et.ActorWriter()
			var pr *github.GQLPullRequest
			if s.isCopilotAuthored {
				pr = et.PullRequest(*et.UserCopilot())
			} else {
				pr = et.PullRequestWithAuthor(actor)
			}
			if s.setupPR != nil {
				s.setupPR(pr)
			}
			pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			err := h.OnPullRequestReviewSubmit(context.Background(), PullRequestReviewSubmitEvent{
				Actor:             EventActor(actor),
				Repo:              EventRepository(),
				PullRequest:       EventPullRequest(),
				PullRequestReview: EventPullRequestReviewWithCopilotMention(actor),
				EventUrl:          "https://example.com/event",
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), 1)

			if s.verifyJob != nil {
				s.verifyJob(t, h, service.QueuedJobs()[0].JobId)
			}
		})
	}
}

func TestOnPullRequestReviewSubmit_OriginatingAppPermissions(t *testing.T) {
	obsv := observability.NewNoopExporters()
	const appID = int64(54321)

	newAppMock := func(perms map[string]string, returnErr error) (func(context.Context, *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error), *int) {
		calls := 0
		fn := func(_ context.Context, _ *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error) {
			calls++
			if returnErr != nil {
				return nil, returnErr
			}
			return &sweagentdTwirp.GetRepositoryInstallationResponse{Permissions: perms}, nil
		}
		return fn, &calls
	}

	setup := func(t *testing.T, flagOn bool, mock func(context.Context, *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error)) (*Handler, *jobservicetest.TestService, *github.GQLActor) {
		t.Helper()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCheckGitHubAppPermissions: flagOn,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		if mock != nil {
			ghTwirp.NoopSweagentdAPI.MockGetRepositoryInstallation = mock
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)
		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}
		return h, service, actor
	}

	buildEvent := func(actor *github.GQLActor, appID *int64) PullRequestReviewSubmitEvent {
		return PullRequestReviewSubmitEvent{
			Actor:             EventActor(actor),
			Repo:              EventRepository(),
			PullRequest:       EventPullRequest(),
			PullRequestReview: EventPullRequestReview(actor),
			GitHubAppID:       appID,
		}
	}

	t.Run("nil GitHubAppID skips the originating app check and queues job", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "write"}, nil)
		h, service, actor := setup(t, true, mock)

		err := h.OnPullRequestReviewSubmit(context.Background(), buildEvent(actor, nil))
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, 0, *calls)
	})

	t.Run("feature flag off skips the originating app check and queues job", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "read"}, nil)
		id := appID
		h, service, actor := setup(t, false, mock)

		err := h.OnPullRequestReviewSubmit(context.Background(), buildEvent(actor, &id))
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, 0, *calls)
	})

	t.Run("queues job when originating app has contents:write", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "write", "pull_requests": "write"}, nil)
		id := appID
		h, service, actor := setup(t, true, mock)

		err := h.OnPullRequestReviewSubmit(context.Background(), buildEvent(actor, &id))
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, 1, *calls)
	})

	t.Run("drops event when originating app lacks contents:write", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "read", "pull_requests": "write"}, nil)
		id := appID
		h, service, actor := setup(t, true, mock)

		err := h.OnPullRequestReviewSubmit(context.Background(), buildEvent(actor, &id))
		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
		require.Equal(t, 1, *calls)
	})

	t.Run("returns error when permission lookup fails so aqueduct retries", func(t *testing.T) {
		mock, _ := newAppMock(nil, errors.New("simulated dotcom outage"))
		id := appID
		h, service, actor := setup(t, true, mock)

		err := h.OnPullRequestReviewSubmit(context.Background(), buildEvent(actor, &id))
		require.Error(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("drops event without calling RPC when GitHubAppID is zero", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "write"}, nil)
		id := int64(0)
		h, service, actor := setup(t, true, mock)

		err := h.OnPullRequestReviewSubmit(context.Background(), buildEvent(actor, &id))
		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
		require.Equal(t, 0, *calls)
	})
}

func TestOnPullRequestReviewSubmit_OriginatingAppWorkflows(t *testing.T) {
	const appID = int64(54321)

	bothFFs := map[string]bool{
		featureflags.CopilotSWEAgentCheckGitHubAppPermissions: true,
		featureflags.CopilotSWEAgentScopeGitTokenWorkflows:    true,
	}
	contentsOnly := map[string]string{"contents": "write"}
	contentsAndWorkflows := map[string]string{"contents": "write", "workflows": "write"}

	cases := []struct {
		name     string
		flags    map[string]bool
		perms    map[string]string
		nilAppID bool
		want     *bool
	}{
		{
			name:  "workflows FF off keeps CanWriteWorkflows nil",
			flags: map[string]bool{featureflags.CopilotSWEAgentCheckGitHubAppPermissions: true},
			perms: contentsOnly,
			want:  nil,
		},
		{
			name:  "app has workflows:write defers to actor-side check (nil)",
			flags: bothFFs,
			perms: contentsAndWorkflows,
			want:  nil,
		},
		{
			name:  "app lacks workflows:write → &false",
			flags: bothFFs,
			perms: contentsOnly,
			want:  ptrBool(false),
		},
		{
			name:     "nil GitHubAppID skips the check",
			flags:    bothFFs,
			perms:    contentsOnly,
			nilAppID: true,
			want:     nil,
		},
	}

	actor := et.ActorWriter()

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h, service := newAppWorkflowsHandler(t, tc.flags, tc.perms)

			event := PullRequestReviewSubmitEvent{
				Actor:             EventActor(actor),
				Repo:              EventRepository(),
				PullRequest:       EventPullRequest(),
				PullRequestReview: EventPullRequestReview(actor),
			}
			if !tc.nilAppID {
				id := appID
				event.GitHubAppID = &id
			}

			err := h.OnPullRequestReviewSubmit(context.Background(), event)
			require.NoError(t, err)
			require.Equal(t, tc.want, queuedJobWorkflowsAccess(t, h, service))
		})
	}
}
