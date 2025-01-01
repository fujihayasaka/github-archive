package googlegithub

import (
	"net/url"
	"testing"
	"time"

	mvngithub "github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestPullRequestReview_ToV1PullRequestReview(t *testing.T) {
	var someTime = time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	type fields struct {
		Review    github.PullRequestReview
		Comments  []*github.PullRequestComment
		Threads   []*mvngithub.PullRequestReviewThread
		CreatedAt githubv4.DateTime
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.PullRequestReview
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should convert a single comment review to v1 pull request review",
			fields: fields{
				Review: github.PullRequestReview{
					HTMLURL:        pointer.Of("http://github.test/test-org/test-repo/pull/2#pullrequestreview-80"),
					PullRequestURL: pointer.Of("http://github.test/test-org/test-repo/pull/2"),
					User:           &github.User{HTMLURL: pointer.Of("http://github.test/monalisa")},
					Body:           pointer.Of("pr review body"),
					CommitID:       pointer.Of("pr-commit-id"),
					SubmittedAt:    &github.Timestamp{Time: someTime},
					State:          pointer.Of("APPROVED"),
				},
				Comments: []*github.PullRequestComment{
					{
						ID:               pointer.Of(int64(1)),
						PullRequestURL:   pointer.Of("http://github.test/test-org/test-repo/pull/2"),
						User:             &github.User{HTMLURL: pointer.Of("http://github.test/monalisa")},
						CreatedAt:        &github.Timestamp{Time: someTime},
						Body:             pointer.Of("comment body"),
						CommitID:         pointer.Of("comment-commit-id"),
						OriginalCommitID: pointer.Of("original-commit-id"),
						Path:             pointer.Of("path"),
						StartSide:        pointer.Of("RIGHT"),
						Side:             pointer.Of("RIGHT"),
						DiffHunk:         pointer.Of("diff-hunk"),
						Position:         pointer.Of(2),
						OriginalPosition: pointer.Of(3),
						SubjectType:      pointer.Of("LINE"),
						StartLine:        pointer.Of(4),
						Line:             pointer.Of(5),
					},
				},
				Threads: []*mvngithub.PullRequestReviewThread{
					{
						ResolvedBy: &struct {
							URL githubv4.URI
						}{URL: toURL("http://github.test/monalisa", t)},
						IsResolved: true,
						IsOutdated: true,
						Comments: struct {
							Nodes []struct {
								FullDatabaseID githubv4.String
							}
						}{Nodes: []struct {
							FullDatabaseID githubv4.String
						}{{FullDatabaseID: githubv4.String("1")}}},
					},
				},
				CreatedAt: githubv4.DateTime{Time: someTime},
			},
			want: &v1.PullRequestReview{
				ResourceId:     "http://github.test/test-org/test-repo/pull/2#pullrequestreview-80",
				UserResourceId: "http://github.test/monalisa",
				HeadSha:        "pr-commit-id",
				CreatedAt:      toTimestamp(&github.Timestamp{Time: someTime}),
				SubmittedAt:    toTimestamp(&github.Timestamp{Time: someTime}),
				State:          v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_APPROVED,
				Body:           "pr review body",
				Threads: []*v1.PullRequestReviewThread{
					{
						ResourceId:                  "http://github.test/test-org/test-repo/pull/2-thread-1",
						PullRequestReviewResourceId: "http://github.test/test-org/test-repo/pull/2#pullrequestreview-80",
						CreatedAt:                   toTimestamp(&github.Timestamp{Time: someTime}),
						BaseCommitId:                "comment-commit-id",
						CommitId:                    "original-commit-id",
						Path:                        "path",
						StartSide:                   v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT,
						EndSide:                     v1.PullRequestReviewDiffSideType_PULL_REQUEST_REVIEW_DIFF_SIDE_TYPE_RIGHT,
						DiffHunk:                    wrapperspb.String("diff-hunk"),
						Position:                    wrapperspb.Int64(2),
						OriginalPosition:            wrapperspb.Int64(3),
						SubjectType:                 v1.PullRequestReviewSubjectType_PULL_REQUEST_REVIEW_SUBJECT_TYPE_LINE,
						StartLine:                   wrapperspb.Int64(4),
						EndLine:                     wrapperspb.Int64(5),
						Outdated:                    true,
						ResolvedAt:                  toTimestamp(&github.Timestamp{Time: someTime}),
						ResolvedUserResourceId:      "http://github.test/monalisa",
						Comments: []*v1.PullRequestReviewComment{
							{
								ResourceId:                        "http://github.test/test-org/test-repo/pull/2-comment-1",
								UserResourceId:                    "http://github.test/monalisa",
								PullRequestReviewResourceId:       "http://github.test/test-org/test-repo/pull/2#pullrequestreview-80",
								PullRequestReviewThreadResourceId: "http://github.test/test-org/test-repo/pull/2-thread-1",
								Body:                              "comment body",
								CreatedAt:                         toTimestamp(&github.Timestamp{Time: someTime}),
							},
						},
					},
				},
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &PullRequestReview{
				Review:             tt.fields.Review,
				Comments:           tt.fields.Comments,
				AugmentedThreads:   tt.fields.Threads,
				AugmentedCreatedAt: tt.fields.CreatedAt,
			}
			got, err := r.ToV1PullRequestReview()
			if !tt.wantErr(t, err, "ToV1PullRequestReview()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1PullRequestReview()")
		})
	}
}

// toURL is a util function that converts a string to a githubv4.URI.
func toURL(u string, t *testing.T) githubv4.URI {
	uri, err := url.Parse(u)
	require.NoError(t, err)
	return githubv4.URI{URL: uri}
}
