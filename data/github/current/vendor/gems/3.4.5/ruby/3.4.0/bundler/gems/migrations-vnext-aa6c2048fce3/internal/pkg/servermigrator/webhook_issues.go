package servermigrator

import (
	"context"
	"fmt"
	"slices"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var (
	supportedIssueActions        = []string{"opened", "edited", "assigned", "unassigned", "closed", "reopened"}
	supportedIssueCommentActions = []string{"created", "edited"}
)

// handleIssuesWebhook handles issues events.
func (m *ServerMigrator) handleIssuesWebhook(ctx context.Context, guid string, e *github.IssuesEvent) error {
	logger := m.logger.WithFields(kvp.String("event_guid", guid),
		kvp.String("event_type", "issues"), kvp.String("event_action", e.GetAction()))
	logger.Info("received issues event")

	// check if the issue action is supported
	if !slices.Contains(supportedIssueActions, e.GetAction()) {
		logger.Info("issue action not supported yet")
		return nil
	}

	// create mannequins for the issue author and assignees
	issue := googlegithub.Issue{
		Issue: *e.GetIssue(),
	}

	if err := m.createMannequins(ctx, append([]*github.User{issue.GetUser()}, issue.Assignees...)...); err != nil {
		return fmt.Errorf("error creating mannequins for issue: %w", err)
	}

	// convert the issue to a v1.Issue
	convI, err := issue.ToV1Issue()
	if err != nil {
		return fmt.Errorf("error converting issue to v1.Issue: %w", err)
	}

	if e.GetAction() == "opened" {
		// Create a new resource for opened issues
		err = m.migrationClient.SendResources(
			ctx,
			"",
			[]*v1.Resource{
				{
					Resource: &v1.Resource_Issue{
						Issue: convI,
					},
				},
			})
		if err != nil {
			return fmt.Errorf("error creating issue: %w", err)
		}
		return nil
	}

	// Any other actions is an edit, so we need to create an event for it.
	err = m.migrationClient.SendEvents(
		ctx,
		"",
		[]*v1.Event{
			{
				EventId:      e.Issue.GetHTMLURL() + ":" + guid,
				ResourceId:   e.Issue.GetHTMLURL(),
				EventAction:  v1.EventAction_EVENT_ACTION_EDITED,
				Timestamp:    toTimestamp(e.Issue.UpdatedAt),
				EventDetails: &v1.Event_IssueEvent{IssueEvent: convI},
			},
		})
	if err != nil {
		return fmt.Errorf("error storing issue edit event: %w", err)
	}

	return nil
}

// handleIssueCommentWebhook handles issue comment events.
func (m *ServerMigrator) handleIssueCommentWebhook(ctx context.Context, guid string, e *github.IssueCommentEvent) error {
	logger := m.logger.WithFields(kvp.String("event_guid", guid),
		kvp.String("event_type", "issue_comment"), kvp.String("event_action", e.GetAction()))
	logger.Info("received issue comment event")

	// check if the issue comment action is supported
	if !slices.Contains(supportedIssueCommentActions, e.GetAction()) {
		logger.Info("issue comment action not supported yet")
		return nil
	}

	// create mannequins for the issueComment author and assignees
	issueComment := googlegithub.IssueComment{
		IssueComment: *e.GetComment(),
	}

	if err := m.createMannequins(ctx, issueComment.User); err != nil {
		return fmt.Errorf("error creating mannequins for issue comment: %w", err)
	}

	// convert the issueComment to a v1.Issue
	convC, err := issueComment.ToV1IssueComment()
	if err != nil {
		return fmt.Errorf("error converting issue comment to v1.IssueComment: %w", err)
	}

	if e.GetAction() == "created" {
		// Create a new resource for created issue comment
		err = m.migrationClient.SendResources(
			ctx,
			"",
			[]*v1.Resource{
				{
					Resource: &v1.Resource_IssueComment{
						IssueComment: convC,
					},
				},
			})
		if err != nil {
			return fmt.Errorf("error creating issue comment: %w", err)
		}
		return nil
	}

	// Any other actions is an edit, so we need to create an event for it.
	err = m.migrationClient.SendEvents(
		ctx,
		"",
		[]*v1.Event{
			{
				EventId:      e.Comment.GetHTMLURL() + ":" + guid,
				ResourceId:   e.Comment.GetHTMLURL(),
				EventAction:  v1.EventAction_EVENT_ACTION_EDITED,
				Timestamp:    toTimestamp(e.Comment.UpdatedAt),
				EventDetails: &v1.Event_IssueCommentEvent{IssueCommentEvent: convC},
			},
		})
	if err != nil {
		return fmt.Errorf("error storing issueComment edit event: %w", err)
	}

	return nil
}

// toTimestamp is a helper function for converting a github.Timestamp
// to a timestamppb.Timestamp for use within a protobuf message.
func toTimestamp(t *github.Timestamp) *timestamppb.Timestamp {
	if t == nil || t.GetTime() == nil || t.GetTime().IsZero() {
		return nil
	}
	return timestamppb.New(*t.GetTime())
}
