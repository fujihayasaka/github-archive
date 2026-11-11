package events

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
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
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

const testAgentID = int64(12345)

func TestOnPullRequestCommentCreated(t *testing.T) {
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)

		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("queues the agent job on PRs authored by Copilot but not assigned to it", func(t *testing.T) {
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)
		pr = et.AddAssigneesToPullRequest(pr, *et.UserWriter())

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)
	})

	t.Run("ignores events on PRs that are closed", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)
		pr.Closed = true

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("handles events on PRs not authored by Copilot when mentioning @copilot", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(et.ActorAdmin(), *et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("ignores comments where the commenter doesn't have repo write access", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorReader()
		pr := et.PullRequest()
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores comments created by bots", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		bot := et.ActorBot()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *bot)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(bot),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores comments on cross-repository pull requests", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)
		pr.IsCrossRepository = true

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
			},
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
			pr = et.AddCommentToPullRequest(pr, true, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
				Actor:       EventActor(actor),
				Repo:        EventRepository(),
				PullRequest: EventPullRequestIssue(),
				Comment: &PullRequestComment{
					ID:     pr.Comments.Nodes[0].GetID(),
					NodeID: pr.Comments.Nodes[0].NodeID,
					Body:   pr.Comments.Nodes[0].Body,
				},
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), tt.expectedQueueLen)
		})
	}

	t.Run("does not emit hydro event immediately when queuing", func(t *testing.T) {
		messageChan := make(chan hydro.Message, 1)
		sink, err := hydro.NewMemorySink(messageChan)
		require.NoError(t, err)
		publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
		obsvWithPublisher := obsv.WithPublisher(publisher)
		ffClient := featureflags.NewNoopClient(nil)
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, _, executor := NewTestHandler(t, obsvWithPublisher, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		assignment := et.Assignment()
		h.jobsStore.CreateAssignment(context.Background(), assignment)
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusPending))
		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		eventRepo := EventRepository()
		prComment := &PullRequestComment{
			ID:     pr.Comments.Nodes[0].GetID(),
			NodeID: pr.Comments.Nodes[0].NodeID,
		}

		err = h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        eventRepo,
			PullRequest: EventPullRequestIssue(),
			Comment:     prComment,
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
			AgentID: testAgentID,
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
			AgentID: testAgentID,
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
			AgentID: testAgentID,
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

	t.Run("handles wake logic properly", func(t *testing.T) {
		type scenario struct {
			bodyHasAtCopilot bool
			queued           bool
		}
		scenarios := []scenario{
			// Referencing @copilot should always launch
			{bodyHasAtCopilot: true, queued: true},
			{bodyHasAtCopilot: true, queued: true},
			// Not referencing @copilot should not launched
			{bodyHasAtCopilot: false, queued: false},
			{bodyHasAtCopilot: false, queued: false},
		}
		for _, s := range scenarios {
			skipsText := "does not launch"
			if s.queued {
				skipsText = "launches"
			}
			atCopilotText := "with @copilot"
			if !s.bodyHasAtCopilot {
				atCopilotText = "without @copilot"
			}
			t.Run(fmt.Sprintf("%s %s", skipsText, atCopilotText), func(t *testing.T) {
				jobStore := memory.NewStore()
				capiClient := capi.NewNoopClient()
				ghTwirp := githubtwirp.NewNoopClient()
				ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
					return &copilotUsersTwirp.GetCopilotUserResponse{
						UserDetails: &copilotUsersTwirp.CopilotUserDetails{
							CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
						},
					}, nil
				}
				h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

				h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
				h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

				actor := et.ActorWriter()
				pr := et.PullRequest(*et.UserCopilot())
				if s.bodyHasAtCopilot {
					pr = et.AddCommentToPullRequestWithBody(pr, s.bodyHasAtCopilot, *actor, "@copilot comment-body")
				} else {
					pr = et.AddCommentToPullRequestWithBody(pr, s.bodyHasAtCopilot, *actor, "comment-body")
				}

				ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

				err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
					Actor:       EventActor(actor),
					Repo:        EventRepository(),
					PullRequest: EventPullRequestIssue(),
					Comment: &PullRequestComment{
						ID:     pr.Comments.Nodes[0].GetID(),
						NodeID: pr.Comments.Nodes[0].NodeID,
						Body:   pr.Comments.Nodes[0].Body,
					},
				})

				require.NoError(t, err)
				if s.queued {
					require.Len(t, service.QueuedJobs(), 1)
				} else {
					require.Len(t, service.QueuedJobs(), 0)
				}
			})
		}
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
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

// Tests for the stacked PR functionality when commenting on non-Copilot authored PRs
func TestOnPullRequestCommentCreated_HumanAuthoredPR(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("creates stack PR when intent detected, non-Copilot PR, and @copilot mentioned", func(t *testing.T) {
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
				Choices: []openai.ChatCompletionChoice{{Message: openai.ChatCompletionMessage{Content: "Fix comment feedback"}}},
			}, nil
		}
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		// Use a custom app provider with non-zero app ID to properly test AgentID
		appProvider := agenticapptest.NewTestProviderWithID(t, testAgentID)
		spokes := spokestest.NewClient(t)
		customAgents := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		service := jobservicetest.New(t, obsv, ffClient, jobStore, capiClient, ghFactory, ghTwirp, nil, nil, customAgents, appProvider)
		executor := jobexecutor.NewTestJobExecutor(obsv, ffClient, service.Store, ghFactory, ghTwirp, service.CAPI, service.Limiter, &service.Service)
		h := NewHandler(obsv, service.CAPI, ffClient, service, executor, service.Store, ghTwirp, ghFactory, appProvider, customAgents, nil)

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddCommentToPullRequest(pr, true, *actor) // comment with @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
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
		require.Equal(t, actor.GetID(), queuedJob.ActorId)

		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, jobs.EventTypePullRequestCommentNonCopilotPullRequest, job.EventType)
		require.Equal(t, testAgentID, job.AgentID, "AgentID should be set to the app ID that was mentioned")
		require.Equal(t, 2, capiCallCount, "expected exactly 2 CAPI calls: intent detection + title generation")
	})

	t.Run("creates job for non-copilot PR with copilot mention", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create assignment for the normal PR flow
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor, *et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1) // Job should be queued
	})

	t.Run("does not create stack PR when comment does not mention @copilot", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create assignment for the normal PR flow
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor, *et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, false, *actor) // comment WITHOUT @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0) // No job should be queued
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

		// Create assignment for the normal PR flow
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot()) // PR authored by Copilot
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)

		// This will enqueue a job on the existing PR, not a stack PR. Verify that
		// the job is created for the existing PR.
		require.Len(t, service.QueuedJobs(), 1)
		job := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), job.ActorId)
		require.Equal(t, pr.Number, int(job.PullRequestNumber))
	})
}

// Tests for the "work on current branch" functionality when commenting on non-Copilot authored PRs
func TestOnPullRequestCommentCreated_WorkOnCurrentBranch(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("works on current branch when @copilot mentioned on non-Copilot PR", func(t *testing.T) {
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

		// Create a PR authored by a non-Copilot user (ActorWriter)
		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr.Number = 42
		pr.HeadRef.Name = "feature-branch"
		pr = et.AddCommentToPullRequest(pr, true, *actor) // comment with @copilot mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
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
		require.Equal(t, actor.GetID(), queuedJob.ActorId)

		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, "feature-branch", job.BranchName)
		require.Equal(t, jobs.EventTypePullRequestCommentNonCopilotPullRequest, job.EventType)
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
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
		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.NotEmpty(t, job.AssignmentID, "Job should have an assignment ID")

		assignment, err := h.jobsStore.GetAssignment(context.Background(), EventRepository().OwnerID, EventRepository().ID, job.AssignmentID)
		require.NoError(t, err)
		require.NotNil(t, assignment)

		require.Len(t, assignment.Resources, 1)
		require.Equal(t, "pull_request", assignment.Resources[0].Type)
	})

	t.Run("reuses existing assignment when working on current branch", func(t *testing.T) {
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

		existingAssignment := et.Assignment()
		existingAssignment.PullRequestNumber = et.PullRequestNumber
		h.jobsStore.CreateAssignment(context.Background(), existingAssignment)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
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
		job, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, queuedJob.JobId)
		require.NoError(t, err)
		require.Equal(t, existingAssignment.ID, job.AssignmentID)
	})

	t.Run("does not queue when there is a running job on same assignment", func(t *testing.T) {
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

		existingAssignment := et.Assignment()
		existingAssignment.PullRequestNumber = et.PullRequestNumber
		existingAssignment, _ = h.jobsStore.CreateAssignment(context.Background(), existingAssignment)

		runningJob := et.Job(jobs.JobStatusRunning)
		runningJob.AssignmentID = existingAssignment.ID
		runningJob.PullRequestNumber = existingAssignment.PullRequestNumber
		h.jobsStore.CreateJob(context.Background(), runningJob)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor)
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
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
		require.Len(t, service.QueuedJobs(), 0)
	})
}

// Test individual code paths within handleCommentOnNonCopilotAuthoredPullRequest
func TestOnPullRequestCommentCreated_StackedPR(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})

	t.Run("fails when comment not found in PR", func(t *testing.T) {
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor, *et.UserCopilot())
		// Don't add any comments to PR

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     12345, // Non-existent comment ID
				NodeID: "non-existent",
				Body:   "@copilot please help",
			},
		})

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to get pull request comment")
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("successfully creates stack PR with basic setup", func(t *testing.T) {
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor, *et.UserCopilot())
		pr.Number = 42 // Set specific PR number for testing
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)

		// Verify a job was created for the stack PR
		job := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), job.ActorId)
	})

	t.Run("successfully copies copilot labels when model customization enabled", func(t *testing.T) {
		ffClientWithModelCustomization := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCanSelectModel: true,
		})
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClientWithModelCustomization, jobStore, ghTwirp, ghFactory)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor, *et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		// Add copilot labels to the original PR
		pr.Labels = github.GQLConnection[github.GQLLabel]{
			Nodes: []github.GQLLabel{
				{Name: "copilot:gpt-4"},
				{Name: "bug"},
				{Name: "copilot:experimental"},
				{Name: "enhancement"},
			},
		}

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips label copying when model customization disabled", func(t *testing.T) {
		ffClientWithoutModelCustomization := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentCanSelectModel: false,
		})
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClientWithoutModelCustomization, jobStore, ghTwirp, ghFactory)

		actor := et.ActorWriter()
		pr := et.PullRequestWithAuthor(actor, *et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		// Add copilot labels to the original PR
		pr.Labels = github.GQLConnection[github.GQLLabel]{
			Nodes: []github.GQLLabel{
				{Name: "copilot:gpt-4"},
				{Name: "copilot:experimental"},
			},
		}

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})
}

func TestGenerateStackPRTitle(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("generates title successfully", func(t *testing.T) {
		mockTitle := "Address performance concerns in database query"
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				return &openai.ChatCompletion{
					ID: "test-completion",
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: mockTitle,
							},
						},
					},
				}, nil
			},
		}

		ffClient := featureflags.NewNoopClient(nil)
		jobStore := memory.NewStore()
		ghTwirp := githubtwirp.NewNoopClient()

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create test data
		job := &jobs.Job{
			ID:      "test-job-id",
			ActorID: 12345,
		}
		pr := github.GQLPullRequest{
			Title:  "Optimize database performance",
			Number: 123,
		}
		comment := &github.GQLIssueComment{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "This query is really slow, can we optimize it?",
			}},
		}

		// Test the method
		title, err := h.generateStackPRTitle(context.Background(), job, pr.Title, comment.Body)

		require.NoError(t, err)
		require.Equal(t, "[WIP] Address performance concerns in database query", title)
	})

	t.Run("falls back to default title when CAPI fails", func(t *testing.T) {
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				return nil, errors.New("CAPI error")
			},
		}

		ffClient := featureflags.NewNoopClient(nil)
		jobStore := memory.NewStore()
		ghTwirp := githubtwirp.NewNoopClient()

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create test data
		job := &jobs.Job{
			ID:      "test-job-id",
			ActorID: 12345,
		}
		pr := github.GQLPullRequest{
			Title:  "Optimize database performance",
			Number: 123,
		}
		comment := &github.GQLIssueComment{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "This query is really slow, can we optimize it?",
			}},
		}

		// Test the method
		_, err := h.generateStackPRTitle(context.Background(), job, pr.Title, comment.Body)

		require.Error(t, err)
		require.Contains(t, err.Error(), "failed to get chat completions for title generation")
	})

	t.Run("handles empty response from CAPI", func(t *testing.T) {
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				return &openai.ChatCompletion{
					ID:      "test-completion",
					Choices: []openai.ChatCompletionChoice{},
				}, nil
			},
		}

		ffClient := featureflags.NewNoopClient(nil)
		jobStore := memory.NewStore()
		ghTwirp := githubtwirp.NewNoopClient()

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create test data
		job := &jobs.Job{
			ID:      "test-job-id",
			ActorID: 12345,
		}
		pr := github.GQLPullRequest{
			Title:  "Optimize database performance",
			Number: 123,
		}
		comment := &github.GQLIssueComment{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "This query is really slow, can we optimize it?",
			}},
		}

		// Test the method
		_, err := h.generateStackPRTitle(context.Background(), job, pr.Title, comment.Body)

		require.Error(t, err)
		require.Contains(t, err.Error(), "no choices in chat completions for title generation")
	})

	t.Run("handles empty title from CAPI", func(t *testing.T) {
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				return &openai.ChatCompletion{
					ID: "test-completion",
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: "   ",
							},
						},
					},
				}, nil
			},
		}

		ffClient := featureflags.NewNoopClient(nil)
		jobStore := memory.NewStore()
		ghTwirp := githubtwirp.NewNoopClient()

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		// Create test data
		job := &jobs.Job{
			ID:      "test-job-id",
			ActorID: 12345,
		}
		pr := github.GQLPullRequest{
			Title:  "Optimize database performance",
			Number: 123,
		}
		comment := &github.GQLIssueComment{
			GQLComment: github.GQLComment{GqlCommentCore: github.GqlCommentCore{
				Body: "This query is really slow, can we optimize it?",
			}},
		}

		// Test the method
		_, err := h.generateStackPRTitle(context.Background(), job, pr.Title, comment.Body)

		require.Error(t, err)
		require.Contains(t, err.Error(), "empty title generated by CAPI")
	})
}

// TestAgenticAppIntegration tests the agenticapp functionality
func TestAgenticAppIntegration(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("uses agenticapp for mention detection", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		// Create agenticapp provider
		appProvider := agenticapptest.NewTestProviderWithLogins(t, et.GitHubAppLogin, et.GitHubBotLogin)

		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   "@copilot please fix this",
			},
		})
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)
	})

	t.Run("ignores comment without agentic mention", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		appProvider := agenticapptest.NewTestProviderWithLogins(t, et.GitHubAppLogin, et.GitHubBotLogin)

		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, false, *actor) // No mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   "just a regular comment",
			},
		})
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 0)
		require.Len(t, executor.LaunchAgentCalls(), 0)
	})
}

func TestIsCopilotActor(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("uses agenticapp to check actor", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "github-copilot",
			GitHubBotLogin: "github-copilot-bot",
		}

		appProvider := agenticapptest.NewTestProviderWithLogins(t, "github-copilot", "github-copilot-bot")

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		copilotUser := et.UserCopilot()

		_, result := appProvider.IsAgenticActor(copilotUser)
		require.True(t, result)
	})

	t.Run("recognizes non-copilot actor", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "github-copilot",
			GitHubBotLogin: "github-copilot-bot",
		}

		appProvider := agenticapptest.NewTestProviderWithLogins(t, "github-copilot", "github-copilot-bot")

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		regularUser := et.UserWriter()

		_, result := appProvider.IsAgenticActor(regularUser)
		require.False(t, result)
	})
}

// Tests for intent-driven stacked PR creation
func TestOnPullRequestCommentCreated_IntentDriven(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	type scenario struct {
		name               string
		isCopilotAuthored  bool
		mockCAPIResult     string // "true", "false", or "error"
		commentBody        string
		expectedQueueCount int
		verifyJob          func(t *testing.T, h *Handler, jobID string)
	}

	scenarios := []scenario{
		{
			name:               "creates stacked PR when intent detected",
			isCopilotAuthored:  false,
			mockCAPIResult:     "true",
			commentBody:        "@copilot create a new PR for this",
			expectedQueueCount: 1,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.Equal(t, jobs.EventTypePullRequestCommentNonCopilotPullRequest, storedJob.EventType)
			},
		},
		{
			name:               "works on current branch when no intent detected",
			isCopilotAuthored:  false,
			mockCAPIResult:     "false",
			commentBody:        "@copilot please fix this bug",
			expectedQueueCount: 1,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.Equal(t, jobs.EventTypePullRequestCommentNonCopilotPullRequest, storedJob.EventType)
			},
		},
		{
			name:               "falls back to current branch when intent detection fails",
			isCopilotAuthored:  false,
			mockCAPIResult:     "error",
			commentBody:        "@copilot create a new PR for this",
			expectedQueueCount: 1,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.Equal(t, jobs.EventTypePullRequestCommentNonCopilotPullRequest, storedJob.EventType)
			},
		},
		{
			name:               "creates stacked PR when intent detected for Copilot-authored PR",
			isCopilotAuthored:  true,
			mockCAPIResult:     "true",
			commentBody:        "@copilot create a new PR for this",
			expectedQueueCount: 1,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.NotNil(t, storedJob.PullRequestID)
			},
		},
		{
			name:               "works on current branch when no intent detected for Copilot-authored PR",
			isCopilotAuthored:  true,
			mockCAPIResult:     "false",
			commentBody:        "@copilot please fix this bug",
			expectedQueueCount: 1,
			verifyJob: func(t *testing.T, h *Handler, jobID string) {
				storedJob, err := h.jobsStore.GetJob(context.Background(), EventRepository().OwnerID, EventRepository().ID, jobID)
				require.NoError(t, err)
				require.NotNil(t, storedJob.PullRequestID)
			},
		},
		{
			name:               "falls back to current branch when intent detection fails for Copilot-authored PR",
			isCopilotAuthored:  true,
			mockCAPIResult:     "error",
			commentBody:        "@copilot create a new PR for this",
			expectedQueueCount: 1,
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

			if s.isCopilotAuthored {
				h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
			}

			actor := et.ActorWriter()
			var pr *github.GQLPullRequest
			if s.isCopilotAuthored {
				pr = et.PullRequest(*et.UserCopilot())
			} else {
				pr = et.PullRequestWithAuthor(actor)
			}
			pr = et.AddCommentToPullRequest(pr, true, *actor)

			ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

			err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
				Actor:       EventActor(actor),
				Repo:        EventRepository(),
				PullRequest: EventPullRequestIssue(),
				Comment: &PullRequestComment{
					ID:     pr.Comments.Nodes[0].GetID(),
					NodeID: pr.Comments.Nodes[0].NodeID,
					Body:   s.commentBody,
				},
				AgentID: testAgentID,
			})

			require.NoError(t, err)
			require.Len(t, service.QueuedJobs(), s.expectedQueueCount)

			if s.verifyJob != nil && len(service.QueuedJobs()) > 0 {
				s.verifyJob(t, h, service.QueuedJobs()[0].JobId)
			}
		})
	}
}

func TestOnPullRequestCommentCreated_RulesViolation(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("blocks job and posts error comment when rules check fails with flag enabled", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPRCommentRulesCheck: true,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		prCtx := &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		// Create a client that returns blocking branch protection rules
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin:         et.GitHubAppLogin,
			GitHubBotLogin:         et.GitHubBotLogin,
			MockPullRequestContext: prCtx,
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
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

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		// Error should be a UserVisibleCommentForUnhandledError (rules violation)
		require.Error(t, err)
		require.Contains(t, err.Error(), "rules")

		// No job should have been queued
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("allows job when rules check fails but flag is disabled", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPRCommentRulesCheck: false,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		prCtx := &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin:         et.GitHubAppLogin,
			GitHubBotLogin:         et.GitHubBotLogin,
			MockPullRequestContext: prCtx,
			MockNewClientFromRepo: func(ctx context.Context, repoId, repoOwnerId int64) (github.ClientInterface, error) {
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

		h, service, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:     pr.Comments.Nodes[0].GetID(),
				NodeID: pr.Comments.Nodes[0].NodeID,
				Body:   pr.Comments.Nodes[0].Body,
			},
		})

		// With flag disabled, the job should still be queued despite blocking rules
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})
}

func TestOnPullRequestCommentCreated_OriginatingAppPermissions(t *testing.T) {
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

	setup := func(t *testing.T, flagOn bool, mock func(context.Context, *sweagentdTwirp.GetRepositoryInstallationRequest) (*sweagentdTwirp.GetRepositoryInstallationResponse, error)) (*Handler, *jobservicetest.TestService, *github.NoopClientFactory) {
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
		pr = et.AddCommentToPullRequest(pr, true, *actor)
		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}
		return h, service, ghFactory
	}

	buildEvent := func(actor github.GQLActorOrUser, body, nodeID string, commentID int64, appID *int64) PullRequestCommentCreatedEvent {
		return PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			GitHubAppID: appID,
			Comment: &PullRequestComment{
				ID:     commentID,
				NodeID: nodeID,
				Body:   body,
			},
		}
	}

	actor := et.ActorWriter()
	commentPR := et.AddCommentToPullRequest(et.PullRequest(*et.UserCopilot()), true, *actor)
	comment := commentPR.Comments.Nodes[0]

	t.Run("nil GitHubAppID skips the originating app check and queues job", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "write"}, nil)
		h, service, _ := setup(t, true, mock)

		err := h.OnPullRequestCommentCreated(context.Background(), buildEvent(actor, comment.Body, comment.NodeID, comment.GetID(), nil))
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, 0, *calls, "originating-app RPC must not be called when GitHubAppID is nil")
	})

	t.Run("feature flag off skips the originating app check and queues job", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "read"}, nil)
		id := appID
		h, service, _ := setup(t, false, mock)

		err := h.OnPullRequestCommentCreated(context.Background(), buildEvent(actor, comment.Body, comment.NodeID, comment.GetID(), &id))
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, 0, *calls, "originating-app RPC must not be called when the FF is off")
	})

	t.Run("queues job when originating app has contents:write", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "write", "pull_requests": "write"}, nil)
		id := appID
		h, service, _ := setup(t, true, mock)

		err := h.OnPullRequestCommentCreated(context.Background(), buildEvent(actor, comment.Body, comment.NodeID, comment.GetID(), &id))
		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
		require.Equal(t, 1, *calls)
	})

	t.Run("drops event when originating app lacks contents:write", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "read", "pull_requests": "write"}, nil)
		id := appID
		h, service, _ := setup(t, true, mock)

		err := h.OnPullRequestCommentCreated(context.Background(), buildEvent(actor, comment.Body, comment.NodeID, comment.GetID(), &id))
		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
		require.Equal(t, 1, *calls)
	})

	t.Run("returns error when permission lookup fails so aqueduct retries", func(t *testing.T) {
		mock, _ := newAppMock(nil, errors.New("simulated dotcom outage"))
		id := appID
		h, service, _ := setup(t, true, mock)

		err := h.OnPullRequestCommentCreated(context.Background(), buildEvent(actor, comment.Body, comment.NodeID, comment.GetID(), &id))
		require.Error(t, err)
		require.Empty(t, service.QueuedJobs())
	})

	t.Run("drops event without calling RPC when GitHubAppID is zero", func(t *testing.T) {
		mock, calls := newAppMock(map[string]string{"contents": "write"}, nil)
		id := int64(0)
		h, service, _ := setup(t, true, mock)

		err := h.OnPullRequestCommentCreated(context.Background(), buildEvent(actor, comment.Body, comment.NodeID, comment.GetID(), &id))
		require.NoError(t, err)
		require.Empty(t, service.QueuedJobs())
		require.Equal(t, 0, *calls, "appID=0 must short-circuit before the RPC")
	})
}

func TestOnPullRequestCommentCreated_OriginatingAppWorkflows(t *testing.T) {
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
	commentPR := et.AddCommentToPullRequest(et.PullRequest(*et.UserCopilot()), true, *actor)
	comment := commentPR.Comments.Nodes[0]

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h, service := newAppWorkflowsHandler(t, tc.flags, tc.perms)

			event := PullRequestCommentCreatedEvent{
				Actor:       EventActor(actor),
				Repo:        EventRepository(),
				PullRequest: EventPullRequestIssue(),
				Comment:     &PullRequestComment{ID: comment.GetID(), NodeID: comment.NodeID, Body: comment.Body},
			}
			if !tc.nilAppID {
				id := appID
				event.GitHubAppID = &id
			}

			err := h.OnPullRequestCommentCreated(context.Background(), event)
			require.NoError(t, err)
			require.Equal(t, tc.want, queuedJobWorkflowsAccess(t, h, service))
		})
	}
}
