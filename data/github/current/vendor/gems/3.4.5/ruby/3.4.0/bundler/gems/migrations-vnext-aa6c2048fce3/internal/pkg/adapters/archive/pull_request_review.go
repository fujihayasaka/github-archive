package archive

import (
	"sort"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// PullRequestReview represents a pull request review in a GitHub repository
type PullRequestReview struct {
	Type        string    `json:"type"`
	URL         string    `json:"url"`
	User        string    `json:"user"`
	PullRequest string    `json:"pull_request"`
	Title       string    `json:"title"`
	Body        string    `json:"body"`
	HeadSha     string    `json:"head_sha"`
	Reactions   Reactions `json:"reactions"`
	State       int32     `json:"state"`
	CreatedAt   time.Time `json:"created_at"`
	SubmittedAt time.Time `json:"submitted_at"`
}

// ToV1PullRequestReview converts an archive pull request review to a v1.PullRequestReview
func (r *PullRequestReview) ToV1PullRequestReview() (*v1.PullRequestReview, error) {
	var state v1.PullRequestReviewState
	switch r.State {
	case 40:
		state = v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_APPROVED
	case 30:
		state = v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_CHANGES_REQUESTED
	case 50:
		state = v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_DISMISSED
	case 1:
		state = v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_COMMENTED
	default:
		state = v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_PENDING
	}

	return &v1.PullRequestReview{
		ResourceId:     r.URL,
		UserResourceId: r.User,
		HeadSha:        r.HeadSha,
		Body:           r.Body,
		CreatedAt:      toTimestamp(r.CreatedAt),
		SubmittedAt:    toTimestamp(r.SubmittedAt),
		State:          state,
	}, nil
}

// reviewComments given a review, returns the comments for that review
// octoshift: PullRequestReview.comments
func reviewComments(reviewID string, comments []*v1.PullRequestReviewComment) []*v1.PullRequestReviewComment {
	var result []*v1.PullRequestReviewComment
	for _, c := range comments {
		if c.InReplyToCommentResourceId == "" {
			continue
		}
		if c.PullRequestReviewThreadResourceId == "" {
			continue
		}
		if c.PullRequestReviewResourceId == reviewID {
			result = append(result, c)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.AsTime().Before(result[j].CreatedAt.AsTime())
	})
	return result
}

// reviewThreads given a review, returns the threads for that review
// octoshift: PullRequestReview.threads
func reviewThreads(reviewID string, threads []*v1.PullRequestReviewThread) []*v1.PullRequestReviewThread {
	var result []*v1.PullRequestReviewThread
	for _, t := range threads {
		if t.PullRequestReviewResourceId == reviewID {
			result = append(result, t)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.AsTime().Before(result[j].CreatedAt.AsTime())
	})
	return result
}

// threadCommentsForReview given a review and a thread, returns the comments for that thread and review
// octoshift: PullRequestReviewThread.comments_for_review
func threadCommentsForReview(reviewID, threadID string, comments []*v1.PullRequestReviewComment) []*v1.PullRequestReviewComment {
	var result []*v1.PullRequestReviewComment
	for _, c := range comments {
		if c.PullRequestReviewResourceId == reviewID && c.PullRequestReviewThreadResourceId == threadID {
			result = append(result, c)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.AsTime().Before(result[j].CreatedAt.AsTime())
	})
	return result
}

// threadComments given a thread, returns the comments for that thread
// octoshift: PullRequestReviewThread.comments
func threadComments(threadID string, comments []*v1.PullRequestReviewComment) []*v1.PullRequestReviewComment {
	var result []*v1.PullRequestReviewComment
	for _, c := range comments {
		if c.PullRequestReviewThreadResourceId == threadID {
			result = append(result, c)
		}
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.AsTime().Before(result[j].CreatedAt.AsTime())
	})
	return result
}
