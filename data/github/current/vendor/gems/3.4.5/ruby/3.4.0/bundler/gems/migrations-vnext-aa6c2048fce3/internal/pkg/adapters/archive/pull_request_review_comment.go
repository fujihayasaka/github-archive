package archive

import (
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// PullRequestReviewComment represents the structure of the JSON for parsing
type PullRequestReviewComment struct {
	URL                     string    `json:"url"`
	PullRequest             string    `json:"pull_request"`
	PullRequestReview       string    `json:"pull_request_review"`
	PullRequestReviewThread string    `json:"pull_request_review_thread"`
	User                    string    `json:"user"`
	Body                    string    `json:"body"`
	Reactions               Reactions `json:"reactions"`
	InReplyTo               string    `json:"in_reply_to"`
	CreatedAt               time.Time `json:"created_at"`
}

// ToV1PullRequestReviewComment converts an archive pull request review comment to a v1.PullRequestReviewComment
func (r *PullRequestReviewComment) ToV1PullRequestReviewComment() (*v1.PullRequestReviewComment, error) {
	return &v1.PullRequestReviewComment{
		ResourceId:                        r.URL,
		UserResourceId:                    r.User,
		PullRequestReviewResourceId:       r.PullRequestReview,
		InReplyToCommentResourceId:        r.InReplyTo,
		PullRequestReviewThreadResourceId: r.PullRequestReviewThread,
		Body:                              r.Body,
		CreatedAt:                         toTimestamp(r.CreatedAt),
	}, nil
}
