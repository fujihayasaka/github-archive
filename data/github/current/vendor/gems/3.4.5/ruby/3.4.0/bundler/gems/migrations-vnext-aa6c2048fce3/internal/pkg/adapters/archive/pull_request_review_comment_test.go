package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
)

func TestPullRequestReviewComment_ToV1PullRequestReviewComment(t *testing.T) {
	someTime := time.Now()

	type fields struct {
		URL                     string
		PullRequest             string
		PullRequestReview       string
		PullRequestReviewThread string
		User                    string
		Body                    string
		Reactions               []Reaction
		InReplyTo               string
		CreatedAt               time.Time
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.PullRequestReviewComment
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "all fields are set",
			fields: fields{
				URL:                     "url",
				PullRequest:             "pull_request",
				PullRequestReview:       "pull_request_review",
				PullRequestReviewThread: "pull_request_review_thread",
				User:                    "user",
				Body:                    "body",
				Reactions:               []Reaction{},
				InReplyTo:               "in_reply_to",
				CreatedAt:               someTime,
			},
			want: &v1.PullRequestReviewComment{
				ResourceId:                        "url",
				UserResourceId:                    "user",
				PullRequestReviewResourceId:       "pull_request_review",
				InReplyToCommentResourceId:        "in_reply_to",
				PullRequestReviewThreadResourceId: "pull_request_review_thread",
				Body:                              "body",
				CreatedAt:                         toTimestamp(someTime),
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &PullRequestReviewComment{
				URL:                     tt.fields.URL,
				PullRequest:             tt.fields.PullRequest,
				PullRequestReview:       tt.fields.PullRequestReview,
				PullRequestReviewThread: tt.fields.PullRequestReviewThread,
				User:                    tt.fields.User,
				Body:                    tt.fields.Body,
				Reactions:               tt.fields.Reactions,
				InReplyTo:               tt.fields.InReplyTo,
				CreatedAt:               tt.fields.CreatedAt,
			}
			got, err := r.ToV1PullRequestReviewComment()
			if !tt.wantErr(t, err, "ToV1PullRequestReviewComment()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1PullRequestReviewComment()")
		})
	}
}
