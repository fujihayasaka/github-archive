package servermigrator

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/migrations-vnext/internal/pkg/adapters/googlegithub"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

var (
	// nowFn is a function that returns the current time. It can be overridden in tests.
	nowFn = time.Now

	// supportedPullRequestActions is a list of supported pull request actions.
	supportedPullRequestActions = []string{
		"opened", "closed", "reopened", "edited", "assigned", "unassigned", "converted_to_draft", "ready_for_review",
	}
)

// handlePullRequestsWebhook handles pr events.
func (m *ServerMigrator) handlePullRequestWebhook(ctx context.Context, guid string, e *github.PullRequestEvent) error {
	logger := m.logger.WithFields(kvp.String("event_guid", guid),
		kvp.String("event_type", "pull_requests"), kvp.String("event_action", e.GetAction()))
	logger.Info("received pull_request event")

	// check if the pr action is supported
	if !slices.Contains(supportedPullRequestActions, e.GetAction()) {
		logger.Info("pr action not supported yet")
		return nil
	}

	// create mannequins for the pr author and assignees
	pr := googlegithub.PullRequest{
		PullRequest: *e.GetPullRequest(),
	}

	if err := m.createMannequins(ctx, append([]*github.User{pr.GetUser()}, pr.Assignees...)...); err != nil {
		return fmt.Errorf("error creating mannequins for pr: %w", err)
	}

	// convert the pr to a v1.PullRequest
	convP, err := pr.ToV1PullRequest()
	if err != nil {
		return fmt.Errorf("error converting pr to v1.PullRequest: %w", err)
	}

	// create a new resource for opened prs
	if e.GetAction() == "opened" {
		err = m.migrationClient.SendResources(
			ctx,
			"",
			[]*v1.Resource{
				{
					Resource: &v1.Resource_PullRequest{
						PullRequest: convP,
					},
				},
			})
		if err != nil {
			return fmt.Errorf("error creating pr: %w", err)
		}
		return nil
	}

	// Any other actions is an update, so we need to create an event for it.
	err = m.migrationClient.SendEvents(
		ctx,
		"",
		[]*v1.Event{
			{
				EventId:      e.PullRequest.GetHTMLURL() + ":" + guid,
				ResourceId:   e.PullRequest.GetHTMLURL(),
				EventAction:  v1.EventAction_EVENT_ACTION_EDITED,
				Timestamp:    toTimestamp(e.PullRequest.UpdatedAt),
				EventDetails: &v1.Event_PullRequestEvent{PullRequestEvent: convP},
			},
		})
	if err != nil {
		return fmt.Errorf("error storing pull request edit event: %w", err)
	}

	return nil
}

// handlePullRequestReviewWebhook handles pr review events.
//
// The current implementation differs from the other webhooks. One could argue that it's a bit hacky and
// I wouldn't take offense :)
//
// As you can see, we're using the resource fetcher to fetch the pull request review data, instead of using
// the event data.
//
// The reason for this is that the pull request review event does not contain the pull request review comments.
// They are sent in separate events. So, we would need to have a mechanism to buffer the events until we have all.
// Unfortunately, we don't have a safe way to know whether we have received all events or not. So for now
// when we receive a pull request review event, we fetch the pull request review data using the resource fetcher.
//
// We need to revisit this approach post-alpha and consider the following:
//
//  1. Most importantly, we need to make sure that this process is not racy.
//  2. We could consider extending the webhook payload to include the number of expected comments.
//  3. If we want to use only webhooks, we'd need a buffer mechanism to wait until we have received all events.
//  4. We could consider to keep using the resource fetcher to fetch the pull request review data. However, we should
//     optimize it to only fetch the data that we need.
func (m *ServerMigrator) handlePullRequestReviewWebhook(ctx context.Context, guid string, e *github.PullRequestReviewEvent) error {
	logger := m.logger.WithFields(kvp.String("event_guid", guid),
		kvp.String("event_type", "pull_request_review"), kvp.String("event_action", e.GetAction()))
	logger.Info("received pull_request_review event")

	switch e.GetAction() {
	case "submitted":
		logger.Info("pull request review submitted, using resource fetcher to fetch pull request review data")

		fetchErr := &FetchErr{}
		resources := m.resourceFetcher.pullRequestReviews(e.GetPullRequest().GetNumber(), fetchErr)
		for r := range resources {
			// Skip other reviews
			if prReview, ok := r.GetResource().(*v1.Resource_PullRequestReview); ok {
				if prReview.PullRequestReview.ResourceId != e.GetReview().GetHTMLURL() {
					continue
				}
			}
			if err := m.migrationClient.SendResources(ctx, "", []*v1.Resource{r}); err != nil {
				return fmt.Errorf("error creating resource: %w", err)
			}
		}
		if fetchErr.Err() != nil {
			return fmt.Errorf("error fetching pr review resources from pr review webhook: %w", fetchErr.Err())
		}
	case "edited":
		// create mannequins for the pr review editor
		if err := m.createMannequins(ctx, e.GetSender()); err != nil {
			return fmt.Errorf("error creating mannequins for pr review: %w", err)
		}

		// edited events don't have an updated_at or resolved_at timestamp, so we use the current time
		// as a best-guess alternative. We should bring this up with team that owns this.
		updatedAt := toTimestamp(&github.Timestamp{Time: nowFn().UTC()})

		err := m.migrationClient.SendEvents(
			ctx,
			"",
			[]*v1.Event{
				{
					EventId:     e.GetReview().GetHTMLURL() + ":" + guid,
					ResourceId:  e.GetReview().GetHTMLURL(),
					EventAction: v1.EventAction_EVENT_ACTION_EDITED,
					Timestamp:   updatedAt,
					EventDetails: &v1.Event_PullRequestReviewEvent{
						PullRequestReviewEvent: &v1.PullRequestReviewEventEdit{
							UserResourceId: e.Sender.GetHTMLURL(),
							Body:           e.Review.GetBody(),
							UpdatedAt:      updatedAt,
						},
					},
				},
			},
		)
		if err != nil {
			return fmt.Errorf("error creating pr review: %w", err)
		}
	default:
		logger.Info("pr review action not supported yet")
		return nil
	}
	return nil
}

// handlePullRequestReviewThreadWebhook handles pr review thread events.
func (m *ServerMigrator) handlePullRequestReviewThreadWebhook(ctx context.Context, guid string, e *github.PullRequestReviewThreadEvent) error {
	logger := m.logger.WithFields(kvp.String("event_guid", guid),
		kvp.String("event_type", "pull_request_review_thread"), kvp.String("event_action", e.GetAction()))
	logger.Info("received pull_request_review event")

	var resolved bool
	switch e.GetAction() {
	case "resolved", "unresolved":
		resolved = e.GetAction() == "resolved"
	default:
		return fmt.Errorf("invalid pr review thread action: %s", e.GetAction())
	}

	thread := e.GetThread()
	if thread == nil {
		return errors.New("no thread found in pr review thread event")
	}

	if len(thread.Comments) == 0 {
		return errors.New("no comments found in pr review thread")
	}

	comment := thread.Comments[0]

	// Unresolved/Resolved events don't have an updated_at or resolved_at timestamp, so we use the current time
	// as a best-guess alternative. We should bring this up with team that owns this.
	updatedAt := toTimestamp(&github.Timestamp{Time: nowFn().UTC()})

	err := m.migrationClient.SendEvents(
		ctx,
		"",
		[]*v1.Event{
			{
				EventId:     googlegithub.ToThreadResourceID(comment, comment.GetID()) + ":" + guid,
				ResourceId:  googlegithub.ToThreadResourceID(comment, comment.GetID()),
				EventAction: v1.EventAction_EVENT_ACTION_EDITED,
				Timestamp:   updatedAt,
				EventDetails: &v1.Event_PullRequestReviewThreadEvent{
					PullRequestReviewThreadEvent: &v1.PullRequestReviewThreadEventEdit{
						UserResourceId: e.Sender.GetHTMLURL(),
						ThreadId:       thread.GetID(),
						FirstCommentId: comment.GetID(),
						Resolved:       resolved,
						UpdatedAt:      updatedAt,
					},
				},
			},
		})

	if err != nil {
		return fmt.Errorf("error creating pr review thread comment: %w", err)
	}

	return nil
}

// handlePullRequestReviewCommentWebhook handles pr review comment events.
func (m *ServerMigrator) handlePullRequestReviewCommentWebhook(ctx context.Context, guid string, e *github.PullRequestReviewCommentEvent) error {
	logger := m.logger.WithFields(kvp.String("event_guid", guid),
		kvp.String("event_type", "pull_request_review_comment"), kvp.String("event_action", e.GetAction()))
	logger.Info("received pull_request_review_comment event")

	// check if the pr action is supported
	if e.GetAction() != "edited" {
		logger.Info("pr review comment action not supported yet")
		return nil
	}

	// create mannequins for the pr review comment editor
	if err := m.createMannequins(ctx, e.GetSender()); err != nil {
		return fmt.Errorf("error creating mannequins for pr review: %w", err)
	}

	err := m.migrationClient.SendEvents(
		ctx,
		"",
		[]*v1.Event{
			{

				EventId:     googlegithub.ToResourceCommentID(e.GetComment(), e.GetComment().GetID()) + ":" + guid,
				ResourceId:  googlegithub.ToResourceCommentID(e.GetComment(), e.GetComment().GetID()),
				EventAction: v1.EventAction_EVENT_ACTION_EDITED,
				Timestamp:   toTimestamp(e.GetComment().UpdatedAt),
				EventDetails: &v1.Event_PullRequestReviewCommentEvent{
					PullRequestReviewCommentEvent: &v1.PullRequestReviewCommentEventEdit{
						UserResourceId: e.Sender.GetHTMLURL(),
						Body:           e.GetComment().GetBody(),
						UpdatedAt:      toTimestamp(e.GetComment().UpdatedAt),
					},
				},
			},
		},
	)
	if err != nil {
		return fmt.Errorf("error creating pr review comment event: %w", err)
	}

	return nil
}
