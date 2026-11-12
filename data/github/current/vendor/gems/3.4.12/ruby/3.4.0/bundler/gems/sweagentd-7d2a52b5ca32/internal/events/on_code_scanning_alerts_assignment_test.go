package events

import (
	"context"
	"testing"
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestOnCodeScanningAlertsAssignment(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ffClient := featureflags.NewNoopClient(map[string]bool{})
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}

	t.Run("queues the agent job", func(t *testing.T) {
		ffc := featureflags.NewNoopClient(map[string]bool{})
		h, service, executor := NewDefaultTestHandler(t, obsv, ffc, ghFactory)

		assignee := et.UserCopilot()
		ghFactory.MockRepositoryContext = &github.RepositoryContext{
			Repository: *et.Repo(),
		}

		alert := EventCodeScanningAlert()

		err := h.OnCodeScanningAlertsAssigned(context.Background(), CodeScanningAlertsAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      EventRepository(),
			Alerts:    []*CodeScanningAlert{alert},
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)

		require.Len(t, service.QueuedJobs(), 1)
		require.Len(t, executor.LaunchAgentCalls(), 0)

		require.Equal(t, et.ActorWriter().GetID(), service.QueuedJobs()[0].ActorId)
	})

	t.Run("ignores events where Copilot was not assigned", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

		assignee := et.UserReader()
		ghFactory.MockRepositoryContext = &github.RepositoryContext{Repository: *et.Repo()}

		err := h.OnCodeScanningAlertsAssigned(context.Background(), CodeScanningAlertsAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      EventRepository(),
			Alerts:    []*CodeScanningAlert{EventCodeScanningAlert()},
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("ignores events where the assigner doesn't have repo write access", func(t *testing.T) {
		h, service, _ := NewDefaultTestHandler(t, obsv, ffClient, ghFactory)

		assignee := et.UserCopilot()
		ghFactory.MockRepositoryContext = &github.RepositoryContext{Repository: *et.Repo()}

		err := h.OnCodeScanningAlertsAssigned(context.Background(), CodeScanningAlertsAssignmentEvent{
			Actor:     EventActorReader(),
			Repo:      EventRepository(),
			Alerts:    []*CodeScanningAlert{EventCodeScanningAlert()},
			Assignees: []string{assignee.Login},
		})

		require.NoError(t, err)
		require.Len(t, service.QueuedJobs(), 0)
	})

	t.Run("emits job_created hydro event", func(t *testing.T) {
		messageChan := make(chan hydro.Message, 1)
		sink, err := hydro.NewMemorySink(messageChan)
		require.NoError(t, err)
		publisher, _ := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
		obsvWithPublisher := obsv.WithPublisher(publisher)
		ffClient := featureflags.NewNoopClient(nil)
		h, _, executor := NewDefaultTestHandler(t, obsvWithPublisher, ffClient, ghFactory)

		assignee := et.UserCopilot()
		ghFactory.MockRepositoryContext = &github.RepositoryContext{
			Repository: *et.Repo(),
		}

		alert := EventCodeScanningAlert()
		eventRepo := EventRepository()

		err = h.OnCodeScanningAlertsAssigned(context.Background(), CodeScanningAlertsAssignmentEvent{
			Actor:     EventActorWriter(),
			Repo:      eventRepo,
			Alerts:    []*CodeScanningAlert{alert},
			Assignees: []string{assignee.Login},
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
}
