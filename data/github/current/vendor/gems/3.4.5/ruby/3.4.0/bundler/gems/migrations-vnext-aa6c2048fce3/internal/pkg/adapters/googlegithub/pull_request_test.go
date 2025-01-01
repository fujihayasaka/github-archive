package googlegithub

import (
	"testing"
	"time"

	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
)

func TestPullRequest_ToV1PullRequest(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	type fields struct {
		PullRequest github.PullRequest
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.PullRequest
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should convert to v1 pull request",
			fields: fields{
				PullRequest: github.PullRequest{
					HTMLURL:        pointer.Of("http://github.test/test-org/test-repo/pulls/2"),
					Title:          pointer.Of("the title"),
					Body:           pointer.Of("the body"),
					CreatedAt:      &github.Timestamp{Time: someTime},
					UpdatedAt:      &github.Timestamp{Time: someTime},
					ClosedAt:       &github.Timestamp{Time: someTime},
					MergedAt:       &github.Timestamp{Time: someTime},
					User:           &github.User{HTMLURL: pointer.Of("http://github.test/monalisa")},
					Draft:          pointer.Of(false),
					MergeCommitSHA: pointer.Of("merge-sha"),
					Assignee:       &github.User{HTMLURL: pointer.Of("http://github.test/alice")},
					Assignees: []*github.User{
						{HTMLURL: pointer.Of("http://github.test/alice")},
						{HTMLURL: pointer.Of("http://github.test/bob")}},
					RequestedReviewers: []*github.User{
						{HTMLURL: pointer.Of("http://github.test/alice")},
						{HTMLURL: pointer.Of("http://github.test/bob")}},
					Head: &github.PullRequestBranch{
						Label: pointer.Of("head-label"),
						Ref:   pointer.Of("head-ref"),
						SHA:   pointer.Of("head-sha"),
					},
					Base: &github.PullRequestBranch{
						Label: pointer.Of("base-label"),
						Ref:   pointer.Of("base-ref"),
						SHA:   pointer.Of("base-sha"),
					},
				},
			},
			want: &v1.PullRequest{
				ResourceId:           "http://github.test/test-org/test-repo/pulls/2",
				UserResourceId:       "http://github.test/monalisa",
				Title:                "the title",
				Body:                 "the body",
				CreatedAt:            toTimestamp(&github.Timestamp{Time: someTime}),
				AssigneesResourceIds: []string{"http://github.test/alice", "http://github.test/bob"},
				ReviewersResourceIds: []string{"http://github.test/alice", "http://github.test/bob"},
				IsDraft:              false,
				BaseRef: &v1.RefDetails{
					Name:      "base-ref",
					CommitSha: "base-sha",
				},
				HeadRef: &v1.RefDetails{
					Name:      "head-ref",
					CommitSha: "head-sha",
				},
				ClosedAt:       toTimestamp(&github.Timestamp{Time: someTime}),
				MergedAt:       toTimestamp(&github.Timestamp{Time: someTime}),
				MergeCommitSha: "merge-sha",
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &PullRequest{
				PullRequest: tt.fields.PullRequest,
			}
			got, err := r.ToV1PullRequest()
			if !tt.wantErr(t, err, "ToV1PullRequest()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1PullRequest()")
		})
	}
}
