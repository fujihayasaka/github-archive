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

	t.Run("ignores events on PRs not authored by Copilot", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)
		h.jobsStore.CreateAssignment(context.Background(), et.Assignment())
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusCompleted))

		author := et.ActorWriter()
		pr := et.PullRequestWithAuthor(author, *et.UserCopilot())
		pr = et.AddReviewToPullRequest(pr, true, *author, *author)

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
		type scenario struct {
			bodyHasAtCopilot bool
			changesRequested bool
			launched         bool
		}
		scenarios := []scenario{
			// We should always launch if @copilot is mentioned
			{bodyHasAtCopilot: true, changesRequested: true, launched: true},
			{bodyHasAtCopilot: true, changesRequested: false, launched: true},
			// If no @copilot, we should not launch
			{bodyHasAtCopilot: false, changesRequested: true, launched: false},
			{bodyHasAtCopilot: false, changesRequested: false, launched: false},
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
			t.Run(fmt.Sprintf("%s %s, changesRequested: %v ", skipsText, atCopilotText, s.changesRequested), func(t *testing.T) {
				jobStore := memory.NewStore()
				capiClient := capi.NewNoopClient()
				h, service, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirpAlt, ghFactory)
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

	t.Run("skips launching the agent with pending and running jobs", func(t *testing.T) {
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
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusPending))

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
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("launches the agent with pending and completed jobs", func(t *testing.T) {
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
		h.jobsStore.CreateJob(context.Background(), et.Job(jobs.JobStatusPending))

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
	})

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
		pr = et.AddReviewToPullRequest(pr, true, *actor, *actor)

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

	t.Run("creates stack PR when feature flag enabled, non-Copilot PR, and @copilot mentioned in review", func(t *testing.T) {
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
		require.Equal(t, jobs.EventTypePullRequestReviewNonCopilotPullRequest, job.EventType)
	})

	t.Run("does not create stack PR when feature flag disabled", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: false,
		})
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
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("does not create stack PR when review does not mention @copilot", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: true,
		})
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
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CodingAgentStackPRs: true,
		})

		// Mock CAPI client to return a specific title
		capiClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userId, interactionId string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
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
	})
}

// TestReviewDoesMentionCopilot tests the reviewDoesMentionCopilot function with different mention checkers
func TestReviewDoesMentionCopilot(t *testing.T) {
	t.Run("returns true when review body mentions copilot", func(t *testing.T) {
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "@copilot please review this",
			},
		}
		result := reviewsWithCopilotMention(review, github.DoesMentionCopilot)
		require.NotEmpty(t, result)
	})

	t.Run("returns true when review comment mentions copilot", func(t *testing.T) {
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "no mention in body",
			},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{
					{
						GQLComment: github.GQLComment{
							Body: "regular comment",
						},
					},
					{
						GQLComment: github.GQLComment{
							Body: "@copilot can you check this?",
						},
					},
				},
			},
		}
		result := reviewsWithCopilotMention(review, github.DoesMentionCopilot)
		require.NotEmpty(t, result)
	})

	t.Run("returns false when neither body nor comments mention copilot", func(t *testing.T) {
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "regular review body",
			},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{
					{
						GQLComment: github.GQLComment{
							Body: "regular comment 1",
						},
					},
					{
						GQLComment: github.GQLComment{
							Body: "regular comment 2",
						},
					},
				},
			},
		}
		result := reviewsWithCopilotMention(review, github.DoesMentionCopilot)
		require.Empty(t, result)
	})

	t.Run("returns false when review has no comments", func(t *testing.T) {
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "regular review body",
			},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{},
			},
		}
		result := reviewsWithCopilotMention(review, github.DoesMentionCopilot)
		require.Empty(t, result)
	})

	t.Run("works with custom mention checker", func(t *testing.T) {
		customChecker := func(s string) bool {
			return s == "custom trigger"
		}

		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "custom trigger",
			},
		}
		result := reviewsWithCopilotMention(review, customChecker)
		require.NotEmpty(t, result)

		review2 := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "@copilot",
			},
		}
		result2 := reviewsWithCopilotMention(review2, customChecker)
		require.Empty(t, result2)
	})

	t.Run("handles empty body and comments", func(t *testing.T) {
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "",
			},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{},
			},
		}
		result := reviewsWithCopilotMention(review, github.DoesMentionCopilot)
		require.Empty(t, result)
	})

	t.Run("checks all comments before returning false", func(t *testing.T) {
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "no mention",
			},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{
					{
						GQLComment: github.GQLComment{
							Body: "comment 1",
						},
					},
					{
						GQLComment: github.GQLComment{
							Body: "comment 2",
						},
					},
					{
						GQLComment: github.GQLComment{
							Body: "comment 3",
						},
					},
					{
						GQLComment: github.GQLComment{
							Body: "@copilot last comment",
						},
					},
				},
			},
		}
		result := reviewsWithCopilotMention(review, github.DoesMentionCopilot)
		require.NotEmpty(t, result)
	})
}

// TestMentionsCopilot tests the Handler.mentionsCopilot method
func TestMentionsCopilot(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("uses agenticapp when feature flag enabled", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "test-copilot",
			GitHubBotLogin: "test-copilot-bot",
		}

		copilot, err := agenticapp.NewCopilot("test-copilot", "test-copilot-bot")
		require.NoError(t, err)
		appProvider := agenticapp.NewProvider(copilot)

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)
		h.appProvider = appProvider

		event := PullRequestReviewSubmitEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequest(),
		}

		// Test with agenticapp mention (@copilot, not the specific login)
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "@copilot please review",
			},
		}
		result := h.mentionsCopilot(context.Background(), event, review)
		require.NotEmpty(t, result)

		// Test without mention
		review2 := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "regular review",
			},
		}
		result2 := h.mentionsCopilot(context.Background(), event, review2)
		require.Empty(t, result2)
	})

	t.Run("uses DoesMentionCopilot when feature flag disabled", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: false,
		})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		event := PullRequestReviewSubmitEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequest(),
		}

		// Test with @copilot mention
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "@copilot please review",
			},
		}
		result := h.mentionsCopilot(context.Background(), event, review)
		require.NotEmpty(t, result)

		// Test without mention
		review2 := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "regular review",
			},
		}
		result2 := h.mentionsCopilot(context.Background(), event, review2)
		require.Empty(t, result2)
	})

	t.Run("checks review comments when body has no mention", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: false,
		})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: et.GitHubAppLogin,
			GitHubBotLogin: et.GitHubBotLogin,
		}

		capiClient, jobStore, ghTwirp := commonHandlerDependencies()
		h, _, _ := NewTestHandler(t, obsv, capiClient, ffc, jobStore, ghTwirp, ghFactory)

		event := PullRequestReviewSubmitEvent{
			Actor:       EventActor(et.ActorWriter()),
			Repo:        EventRepository(),
			PullRequest: EventPullRequest(),
		}

		// Test with mention in comment
		review := &github.GQLPullRequestReview{
			GQLComment: github.GQLComment{
				Body: "regular body",
			},
			Comments: github.GQLConnection[github.GQLPullRequestReviewComment]{
				Nodes: []github.GQLPullRequestReviewComment{
					{
						GQLComment: github.GQLComment{
							Body: "@copilot can you fix this?",
						},
					},
				},
			},
		}
		result := h.mentionsCopilot(context.Background(), event, review)
		require.NotEmpty(t, result)
	})

	t.Run("detects agentic mention in review comments when not in body", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgenticAppsProvider: true,
		})

		ghFactory := &github.NoopClientFactory{
			GitHubAppLogin: "test-copilot",
			GitHubBotLogin: "test-copilot-bot",
		}

		copilot, err := agenticapp.NewCopilot("test-copilot", "test-copilot-bot")
		require.NoError(t, err)
		appProvider := agenticapp.NewProvider(copilot)

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
				ID:              reviewID,
				Body:            "Review body without mention",
				Comments:        []string{"First comment", "@copilot please fix this", "Another comment"},
				MentionsCopilot: false,
			},
		}

		err = h.OnPullRequestReviewSubmit(context.Background(), event)
		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		queuedJob := service.QueuedJobs()[0]
		require.Equal(t, actor.GetID(), queuedJob.ActorId)
	})
}

