package servermigrator

import (
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/google/go-github/v65/github"
)

func (m *ServerMigrator) webhookHandler(w http.ResponseWriter, r *http.Request) {
	// Extract the GUID from the request headers
	guid := r.Header.Get("X-GitHub-Delivery") //nolint:canonicalheader // "GitHub", not "Github"
	if guid == "" {
		m.logger.Error("event missing GitHub delivery header, discarding")
		http.Error(w, "missing GitHub delivery header", http.StatusBadRequest)
		return
	}
	logger := m.logger.WithFields(kvp.String("event_guid", guid))

	// Validate the payload. This also validates the signature of the request
	// against the provided token.
	buf, err := github.ValidatePayload(r, m.secretToken)
	if err != nil {
		logger.WithError(err).Error("could not validate webhook payload")
		http.Error(w, "could not validate webhook payload", http.StatusBadRequest)
		return
	}

	// Parse the event
	hook, err := github.ParseWebHook(github.WebHookType(r), buf)
	if err != nil {
		logger.WithError(err).Error("error parsing webhook")
		http.Error(w, "could not parse webhook", http.StatusBadRequest)
		return
	}
	logger = logger.WithFields(kvp.String("event_type", github.WebHookType(r)))

	switch e := hook.(type) {
	case *github.IssuesEvent:
		if err := m.handleIssuesWebhook(r.Context(), guid, e); err != nil {
			logger.WithError(err).Error("error handling event")
		}
	case *github.IssueCommentEvent:
		if err := m.handleIssueCommentWebhook(r.Context(), guid, e); err != nil {
			logger.WithError(err).Error("error handling event")
		}
	case *github.PullRequestEvent:
		if err := m.handlePullRequestWebhook(r.Context(), guid, e); err != nil {
			logger.WithError(err).Error("error handling event")
		}
	case *github.PullRequestReviewEvent:
		if err := m.handlePullRequestReviewWebhook(r.Context(), guid, e); err != nil {
			logger.WithError(err).Error("error handling event")
		}
	case *github.PullRequestReviewCommentEvent:
		if err := m.handlePullRequestReviewCommentWebhook(r.Context(), guid, e); err != nil {
			logger.WithError(err).Error("error handling event")
		}
	case *github.PullRequestReviewThreadEvent:
		if err := m.handlePullRequestReviewThreadWebhook(r.Context(), guid, e); err != nil {
			logger.WithError(err).Error("error handling event")
		}
	default:
		logger.Info("unhandled event type")
		return
	}
}
