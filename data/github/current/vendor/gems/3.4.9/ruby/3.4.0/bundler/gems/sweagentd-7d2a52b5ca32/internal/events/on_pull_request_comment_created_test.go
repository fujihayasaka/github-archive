package events

import (
	"context"
	"fmt"
	"testing"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/capi"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/require"
)

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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores events on PRs not authored by Copilot", func(t *testing.T) {
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("skips launch agent with pending and running jobs", func(t *testing.T) {
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		assignment := et.Assignment()
		h.jobsStore.CreateAssignment(context.Background(), assignment)
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusRunning))
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusPending))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("launches agent with pending and completed jobs", func(t *testing.T) {
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)
		assignment := et.Assignment()
		h.jobsStore.CreateAssignment(context.Background(), assignment)
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusPending))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("launches agent with pending and completed jobs", func(t *testing.T) {
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
			ID:              pr.Comments.Nodes[0].GetID(),
			NodeID:          pr.Comments.Nodes[0].NodeID,
			MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
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

	t.Run("launches the agent with no existing jobs", func(t *testing.T) {
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

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips launching the agent with existing running job", func(t *testing.T) {
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
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusRunning))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("launches the agent with existing terminal jobs", func(t *testing.T) {
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
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err := h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
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
						ID:              pr.Comments.Nodes[0].GetID(),
						NodeID:          pr.Comments.Nodes[0].NodeID,
						MentionsCopilot: github.DoesMentionCopilot(pr.Comments.Nodes[0].Body),
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
}

func TestOnPullRequestCommentCreated_DoesMentionCopilot(t *testing.T) {
	atMentionTests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			name:     "@-mention",
			body:     "@Copilot comment-body",
			expected: true,
		},
		{
			name:     "@-mention with leading space",
			body:     " @Copilot comment-body",
			expected: true,
		},
		{
			name:     "@-mention with comma",
			body:     "@Copilot, comment-body",
			expected: true,
		},
		{
			name:     "@-mention with colon",
			body:     "@Copilot: comment-body",
			expected: true,
		},
		{
			name:     "@-mention with exclamation mark",
			body:     "@Copilot! comment-body",
			expected: true,
		},
		{
			name:     "@-mention with question mark",
			body:     "@Copilot? comment-body",
			expected: true,
		},
		{
			name:     "@-mention with period",
			body:     "@Copilot. comment-body",
			expected: true,
		},
		{
			name:     "@-mention with ellipsis",
			body:     "@Copilot... comment-body",
			expected: true,
		},
		{
			name:     "@-mention with newline",
			body:     "@Copilot\ncomment-body",
			expected: true,
		},
		{
			name:     "@-mention with random casing",
			body:     "@cOpIlOt comment-body",
			expected: true,
		},
		{
			name:     "no @-mention",
			body:     "comment-body",
			expected: false,
		},
		{
			name:     "ee@copilot",
			body:     "ee@copilot comment-body",
			expected: false,
		},
	}
	for _, tt := range atMentionTests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expected, github.DoesMentionCopilot(tt.body))
		})
	}
}

// Tests for the stacked PR functionality when commenting on non-Copilot authored PRs
func TestOnPullRequestCommentCreated_NonCopilotAuthoredPR(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("creates stack PR when feature flag enabled, non-Copilot PR, and @copilot mentioned", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: true,
		})
		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan: copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
				},
			}, nil
		}
		h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: true,
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
	})

	t.Run("does not create stack PR when feature flag disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: false,
		})
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: true,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0) // No job should be queued
	})

	t.Run("does not create stack PR when comment does not mention @copilot", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: true,
		})
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: false,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0) // No job should be queued
	})

	t.Run("does not create stack PR when PR is authored by Copilot", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: true,
		})
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: true,
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

// Test individual code paths within handleCommentOnNonCopilotAuthoredPullRequest
func TestHandleCommentOnNonCopilotAuthoredPullRequest_CodePaths(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{
		featureflags.CodingAgentStackPRs: true,
	})

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
				ID:              12345, // Non-existent comment ID
				NodeID:          "non-existent",
				MentionsCopilot: true,
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: true,
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
			featureflags.CodingAgentStackPRs:           true,
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: true,
			},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 1)
	})

	t.Run("skips label copying when model customization disabled", func(t *testing.T) {
		ffClientWithoutModelCustomization := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs:           true,
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				MentionsCopilot: true,
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
			GQLComment: github.GQLComment{
				Body: "This query is really slow, can we optimize it?",
			},
		}

		// Test the method
		title, err := h.generateStackPRTitle(context.Background(), job, pr.Title, comment.Body)

		require.NoError(t, err)
		require.Equal(t, "[WIP] Address performance concerns in database query", title)
	})

	t.Run("falls back to default title when CAPI fails", func(t *testing.T) {
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				return nil, fmt.Errorf("CAPI error")
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
			GQLComment: github.GQLComment{
				Body: "This query is really slow, can we optimize it?",
			},
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
			GQLComment: github.GQLComment{
				Body: "This query is really slow, can we optimize it?",
			},
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
			GQLComment: github.GQLComment{
				Body: "This query is really slow, can we optimize it?",
			},
		}

		// Test the method
		_, err := h.generateStackPRTitle(context.Background(), job, pr.Title, comment.Body)

		require.Error(t, err)
		require.Contains(t, err.Error(), "empty title generated by CAPI")
	})
}

// TestAgenticAppIntegration tests the new agenticapp functionality with feature flags
func TestAgenticAppIntegration(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("with feature flag enabled - uses agenticapp for mention detection", func(t *testing.T) {
		// Setup feature flag to enable agenticapp
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

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
		copilot, err := agenticapp.NewCopilot(et.GitHubAppLogin, et.GitHubBotLogin)
		require.NoError(t, err)
		appProvider := agenticapp.NewProvider(copilot)

		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider // Set the appProvider
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, true, *actor)

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err = h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				Body:            "@copilot please fix this",
				MentionsCopilot: false, // Old field should be ignored when feature flag is enabled
			},
		})
		require.NoError(t, err)

		// Should queue job because agenticapp detected the mention
		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)
	})

	t.Run("with feature flag enabled - ignores comment without agentic mention", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		copilot, err := agenticapp.NewCopilot(et.GitHubAppLogin, et.GitHubBotLogin)
		require.NoError(t, err)
		appProvider := agenticapp.NewProvider(copilot)

		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())

		actor := et.ActorWriter()
		pr := et.PullRequest(*et.UserCopilot())
		pr = et.AddCommentToPullRequest(pr, false, *actor) // No mention

		ghFactory.MockPullRequestContext = &github.PullRequestContext{Repository: *et.Repo(), PullRequest: *pr}

		err = h.OnPullRequestCommentCreated(context.Background(), PullRequestCommentCreatedEvent{
			Actor:       EventActor(actor),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				Body:            "just a regular comment",
				MentionsCopilot: true, // Old field says true, but agenticapp should check body
			},
		})
		require.NoError(t, err)

		// Should not queue job because there's no agentic mention in the body
		require.Len(t, service.QueuedJobs(), 0)
		require.Len(t, executor.LaunchAgentCalls(), 0)
	})

	t.Run("with feature flag disabled - uses old MentionsCopilot field", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: false,
		})

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

		h, service, executor := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		// Don't set appProvider - simulating old behavior
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
				ID:              pr.Comments.Nodes[0].GetID(),
				NodeID:          pr.Comments.Nodes[0].NodeID,
				Body:            "no mention here",
				MentionsCopilot: true, // Old field controls behavior
			},
		})
		require.NoError(t, err)

		// Should queue job because MentionsCopilot is true
		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)
	})
}

func TestIsCopilotActor(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("with feature flag enabled - uses agenticapp to check actor", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "github-copilot",
			GitHubBotLogin: "github-copilot-bot",
		}

		copilot, err := agenticapp.NewCopilot("github-copilot", "github-copilot-bot")
		require.NoError(t, err)
		appProvider := agenticapp.NewProvider(copilot)

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		// Create a mock actor that implements the interface
		copilotUser := et.UserCopilot()

		// Should recognize copilot actor via agenticapp
		result := h.isCopilotActor(context.Background(), ghFactory, copilotUser)
		require.True(t, result)
	})

	t.Run("with feature flag enabled - recognizes non-copilot actor", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "github-copilot",
			GitHubBotLogin: "github-copilot-bot",
		}

		copilot, err := agenticapp.NewCopilot("github-copilot", "github-copilot-bot")
		require.NoError(t, err)
		appProvider := agenticapp.NewProvider(copilot)

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		regularUser := et.UserWriter()

		// Should not recognize regular user as copilot
		result := h.isCopilotActor(context.Background(), ghFactory, regularUser)
		require.False(t, result)
	})

	t.Run("with feature flag disabled - uses old IsCopilot method", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: false,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "github-copilot",
			GitHubBotLogin: "github-copilot-bot",
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		// Don't set appProvider

		copilotUser := et.UserCopilot()

		// Should still recognize copilot via old method
		result := h.isCopilotActor(context.Background(), ghFactory, copilotUser)
		require.True(t, result)
	})
}

func TestOpenStackedPR(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("with both flags enabled and agentic mention - returns true", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs:           true,
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		event := PullRequestCommentCreatedEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				MentionsCopilot: true,
			},
		}

		result := h.openStackedPR(context.Background(), &event, event.Comment, true)
		require.True(t, result)
	})

	t.Run("with both flags enabled but no agentic mention - returns false", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs:           true,
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		event := PullRequestCommentCreatedEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				MentionsCopilot: false,
			},
		}

		result := h.openStackedPR(context.Background(), &event, event.Comment, false)
		require.False(t, result)
	})

	t.Run("with stack PRs enabled but agenticapp disabled - uses old MentionsCopilot", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs:           true,
			featureflags.CopilotSWEAgenticAppsProvider: false,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		event := PullRequestCommentCreatedEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				MentionsCopilot: true,
			},
		}

		// commentMentionsAgenticActor parameter is ignored when flag is disabled
		result := h.openStackedPR(context.Background(), &event, event.Comment, false)
		require.True(t, result) // Should be true because event.Comment.MentionsCopilot is true
	})

	t.Run("with stack PRs disabled - returns false", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs:           false,
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		event := PullRequestCommentCreatedEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequestIssue(),
			Comment: &PullRequestComment{
				MentionsCopilot: true,
			},
		}

		result := h.openStackedPR(context.Background(), &event, event.Comment, true)
		require.False(t, result) // Stack PRs disabled, so always false
	})
}

// TestMentionableInterface tests that the mentionable interface works correctly
func TestMentionableInterface(t *testing.T) {
	t.Run("PullRequestComment implements mentionable", func(t *testing.T) {
		var m mentionable = &PullRequestComment{
			MentionsCopilot: true,
		}
		require.True(t, m.HasCopilotMention())
	})

	t.Run("PullRequestReview implements mentionable", func(t *testing.T) {
		var m mentionable = &PullRequestReview{
			MentionsCopilot: true,
		}
		require.True(t, m.HasCopilotMention())
	})

	t.Run("can be used polymorphically", func(t *testing.T) {
		testCases := []struct {
			name     string
			m        mentionable
			expected bool
		}{
			{
				name: "comment with mention",
				m: &PullRequestComment{
					MentionsCopilot: true,
				},
				expected: true,
			},
			{
				name: "comment without mention",
				m: &PullRequestComment{
					MentionsCopilot: false,
				},
				expected: false,
			},
			{
				name: "review with mention",
				m: &PullRequestReview{
					MentionsCopilot: true,
				},
				expected: true,
			},
			{
				name: "review without mention",
				m: &PullRequestReview{
					MentionsCopilot: false,
				},
				expected: false,
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				require.Equal(t, tc.expected, tc.m.HasCopilotMention())
			})
		}
	})
}

