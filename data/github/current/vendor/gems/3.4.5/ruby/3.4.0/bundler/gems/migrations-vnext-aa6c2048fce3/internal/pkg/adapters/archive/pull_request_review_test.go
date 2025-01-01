package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPullRequestReviewConversion(t *testing.T) {
	body := "pr review body"
	resourceID := "http://github.test/test-org/test-repo/pulls/2/files#pullrequestreview-1"
	user := "http://github.test/monalisa"
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	reactions := []Reaction{
		{
			Content:     "+1",
			SubjectType: "PullRequestReview",
			User:        user,
			CreatedAt:   someTime,
		},
		{
			Content:     "+1",
			SubjectType: "PullRequestReview",
			User:        user,
			CreatedAt:   someTime,
		},
	}

	ic := &PullRequestReview{
		Body:        body,
		CreatedAt:   someTime,
		SubmittedAt: someTime,
		Reactions:   reactions,
		URL:         resourceID,
		User:        user,
		State:       40,
		HeadSha:     "xyf120",
		PullRequest: "http://github.test/test-org/test-repo/pulls/2",
	}

	expected := &v1.PullRequestReview{
		ResourceId:     resourceID,
		UserResourceId: user,
		Body:           body,
		CreatedAt:      toTimestamp(someTime),
		SubmittedAt:    toTimestamp(someTime),
		State:          v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_APPROVED,
		HeadSha:        ic.HeadSha,
	}

	v1c, err := ic.ToV1PullRequestReview()
	require.NoError(t, err)
	require.Equal(t, expected, v1c)
}

func Test_reviewComments(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	type args struct {
		reviewID string
		comments []*v1.PullRequestReviewComment
	}
	tests := []struct {
		name string
		args args
		want []*v1.PullRequestReviewComment
	}{
		{
			name: "no comments",
			args: args{
				reviewID: "http://github.test/test-org/test-repo/pulls/2/reviews/1",
				comments: []*v1.PullRequestReviewComment{},
			},
			want: nil,
		},
		{
			name: "comments for another review",
			args: args{
				reviewID: "a review",
				comments: []*v1.PullRequestReviewComment{
					{
						PullRequestReviewResourceId:       "a review",
						UserResourceId:                    "a user",
						PullRequestReviewThreadResourceId: "a thread",
						InReplyToCommentResourceId:        "a comment",
						Body:                              "a body",
						CreatedAt:                         toTimestamp(someTime),
						AttachmentResourceIds:             []string{"attachment"},
					},
					{
						PullRequestReviewResourceId:       "another review",
						UserResourceId:                    "a user",
						PullRequestReviewThreadResourceId: "a thread",
						InReplyToCommentResourceId:        "a comment",
						Body:                              "a body",
						CreatedAt:                         toTimestamp(someTime),
						AttachmentResourceIds:             []string{"attachment"},
					},
				},
			},
			want: []*v1.PullRequestReviewComment{
				{
					PullRequestReviewResourceId:       "a review",
					UserResourceId:                    "a user",
					PullRequestReviewThreadResourceId: "a thread",
					InReplyToCommentResourceId:        "a comment",
					Body:                              "a body",
					CreatedAt:                         toTimestamp(someTime),
					AttachmentResourceIds:             []string{"attachment"},
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, reviewComments(tt.args.reviewID, tt.args.comments), "reviewComments(%v, %v)", tt.args.reviewID, tt.args.comments)
		})
	}
}

func Test_reviewThreads(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	type args struct {
		reviewID string
		threads  []*v1.PullRequestReviewThread
	}
	tests := []struct {
		name string
		args args
		want []*v1.PullRequestReviewThread
	}{
		{
			name: "no threads",
			args: args{
				reviewID: "a review",
				threads:  []*v1.PullRequestReviewThread{},
			},
			want: nil,
		},
		{
			name: "threads for another review",
			args: args{
				reviewID: "a review",
				threads: []*v1.PullRequestReviewThread{
					{
						PullRequestReviewResourceId: "a review",
						ResolvedUserResourceId:      "a user",
						ResolvedAt:                  toTimestamp(someTime),
					},
					{
						PullRequestReviewResourceId: "another review",
						ResolvedUserResourceId:      "a user",
						ResolvedAt:                  toTimestamp(someTime),
					},
				},
			},
			want: []*v1.PullRequestReviewThread{
				{
					PullRequestReviewResourceId: "a review",
					ResolvedUserResourceId:      "a user",
					ResolvedAt:                  toTimestamp(someTime),
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, reviewThreads(tt.args.reviewID, tt.args.threads), "reviewThreads(%v, %v)", tt.args.reviewID, tt.args.threads)
		})
	}
}

func Test_threadCommentsForReview(t *testing.T) {
	type args struct {
		reviewID string
		threadID string
		comments []*v1.PullRequestReviewComment
	}
	tests := []struct {
		name string
		args args
		want []*v1.PullRequestReviewComment
	}{
		{
			name: "no comments",
			args: args{
				reviewID: "a review",
				threadID: "a thread",
				comments: []*v1.PullRequestReviewComment{},
			},
			want: nil,
		},
		{
			name: "comments for another review",
			args: args{
				reviewID: "a review",
				threadID: "a thread",
				comments: []*v1.PullRequestReviewComment{
					{
						PullRequestReviewResourceId:       "a review",
						UserResourceId:                    "a user",
						PullRequestReviewThreadResourceId: "a thread",
					},
					{
						PullRequestReviewResourceId:       "a review",
						UserResourceId:                    "a user",
						PullRequestReviewThreadResourceId: "another thread",
					},
					{
						PullRequestReviewResourceId:       "another review",
						UserResourceId:                    "a user",
						PullRequestReviewThreadResourceId: "a thread",
					},
				},
			},
			want: []*v1.PullRequestReviewComment{
				{
					PullRequestReviewResourceId:       "a review",
					UserResourceId:                    "a user",
					PullRequestReviewThreadResourceId: "a thread",
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, threadCommentsForReview(tt.args.reviewID, tt.args.threadID, tt.args.comments), "threadCommentsForReview(%v, %v, %v)", tt.args.reviewID, tt.args.threadID, tt.args.comments)
		})
	}
}
