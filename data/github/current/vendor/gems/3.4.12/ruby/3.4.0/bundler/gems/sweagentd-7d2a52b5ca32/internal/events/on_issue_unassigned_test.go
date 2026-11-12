package events

import (
	"context"
	"testing"

	et "github.com/github/sweagentd/internal/events/eventstest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestOnIssueUnassigned(t *testing.T) {
	obsv := observability.NewNoopExporters()
	ghFactory := &github.NoopClientFactory{
		GitHubAppLogin: et.GitHubAppLogin,
		GitHubBotLogin: et.GitHubBotLogin,
	}
	capiClient, jobStore, ghTwirp := commonHandlerDependencies()

	t.Run("ignores events where Copilot was not assigned/unassigned", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(nil)
		ghFactory.MockIssueContext = &github.IssueContext{Repository: *et.Repo(), Issue: *et.Issue()}

		h, _, _ := NewTestHandler(t, obsv, capiClient, ffClient, jobStore, ghTwirp, ghFactory)

		err := h.OnIssueUnassigned(context.Background(), IssueAssignmentEvent{
			Actor:     EventActorReader(),
			Repo:      EventRepository(),
			Issue:     EventIssue(),
			Action:    IssueAssignmentEventActionUnassigned,
			Assignees: []string{et.ActorLoginNone},
			Assignee:  et.ActorLoginNone,
		})

		require.NoError(t, err)
	})
}
