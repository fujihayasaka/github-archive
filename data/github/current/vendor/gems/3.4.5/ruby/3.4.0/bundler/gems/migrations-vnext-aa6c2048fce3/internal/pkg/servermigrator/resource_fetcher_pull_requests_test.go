package servermigrator

import (
	"iter"
	"net/url"
	"testing"
	"time"

	"github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func Test_resourceFetcher_pullRequests(t *testing.T) {
	type fields struct {
		err                  error
		fetchAllPullRequests fetchPullRequests
	}
	tests := []struct {
		name   string
		fields fields
		want   []*v1.Resource
	}{
		{
			name: "returns all pull requests",
			fields: fields{
				fetchAllPullRequests: func(err *FetchErr) iter.Seq[*ogithub.PullRequest] {
					return func(yield func(request *ogithub.PullRequest) bool) {
						prs := []*ogithub.PullRequest{
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/pull/1"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/monalisa")},
							},
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/pull/2"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/lisamona")},
							},
						}
						for _, pr := range prs {
							if !yield(pr) {
								return
							}
						}
					}
				},
			},
			want: []*v1.Resource{
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: &v1.Mannequin{
							ResourceId: "http://github.test/monalisa",
						},
					},
				},
				{
					Resource: &v1.Resource_PullRequest{
						PullRequest: &v1.PullRequest{
							ResourceId:           "http://github.test/test-org/test-repo/pull/1",
							UserResourceId:       "http://github.test/monalisa",
							AssigneesResourceIds: make([]string, 0),
							ReviewersResourceIds: make([]string, 0),
							HeadRef:              &v1.RefDetails{},
							BaseRef:              &v1.RefDetails{},
						},
					},
				},
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: &v1.Mannequin{
							ResourceId: "http://github.test/lisamona",
						},
					},
				},
				{
					Resource: &v1.Resource_PullRequest{
						PullRequest: &v1.PullRequest{
							ResourceId:           "http://github.test/test-org/test-repo/pull/2",
							UserResourceId:       "http://github.test/lisamona",
							AssigneesResourceIds: make([]string, 0),
							ReviewersResourceIds: make([]string, 0),
							HeadRef:              &v1.RefDetails{},
							BaseRef:              &v1.RefDetails{},
						},
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &ResourceFetcher{
				err: tt.fields.err,
				fetchIssueComments: func(int, *FetchErr) iter.Seq[*ogithub.IssueComment] {
					return emptyIter[*ogithub.IssueComment]()
				},
				fetchIssueReactions: func(int, *FetchErr) iter.Seq[*ogithub.Reaction] {
					return emptyIter[*ogithub.Reaction]()
				},
				fetchPullRequestReviews: func(int, *FetchErr) iter.Seq[*ogithub.PullRequestReview] {
					return emptyIter[*ogithub.PullRequestReview]()
				},
				fetchAugmentedPullRequestReviews: func(number int) (map[string]githubv4.DateTime, error) {
					return nil, nil
				},
				fetchPullRequests: tt.fields.fetchAllPullRequests,
			}
			assert.Equal(t, tt.want, all(r.pullRequests()))
		})
	}
}

func Test_resourceFetcher_pullRequestReviews(t *testing.T) {
	var someTime = time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	type fields struct {
		err                               error
		fetchAllPullRequestReviews        fetchPullRequestReviews
		fetchAllPullRequestReviewComments fetchReviewComments
		fetchAugmentedPullRequestThreads  fetchAugmentedPullRequestThreads
		fetchAugmentedPullRequestReviews  fetchAugmentedPullRequestReviews
	}
	tests := []struct {
		name   string
		fields fields
		want   []*v1.Resource
	}{
		{
			name: "returns all pull request reviews",
			fields: fields{
				fetchAllPullRequestReviews: func(int, *FetchErr) iter.Seq[*ogithub.PullRequestReview] {
					return func(yield func(request *ogithub.PullRequestReview) bool) {
						reviews := []*ogithub.PullRequestReview{
							{
								ID:             pointer.Of(int64(1)),
								HTMLURL:        pointer.Of("http://github.test/test-org/test-repo/pull/2#pullrequestreview-80"),
								PullRequestURL: pointer.Of("http://github.test/test-org/test-repo/pull/2"),
								User:           &ogithub.User{HTMLURL: pointer.Of("http://github.test/monalisa")},
								Body:           pointer.Of("pr review body"),
								CommitID:       pointer.Of("pr-commit-id"),
								SubmittedAt:    &ogithub.Timestamp{Time: someTime},
								State:          pointer.Of("APPROVED"),
							},
						}
						for _, review := range reviews {
							if !yield(review) {
								return
							}
						}
					}
				},
				fetchAllPullRequestReviewComments: func(int, int64, *FetchErr) iter.Seq[*ogithub.PullRequestComment] {
					return func(yield func(request *ogithub.PullRequestComment) bool) {
						comments := []*ogithub.PullRequestComment{
							{
								ID:               pointer.Of(int64(1)),
								PullRequestURL:   pointer.Of("http://github.test/test-org/test-repo/pull/2"),
								User:             &ogithub.User{HTMLURL: pointer.Of("http://github.test/monalisa")},
								CreatedAt:        &ogithub.Timestamp{Time: someTime},
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
						}
						for _, comment := range comments {
							if !yield(comment) {
								return
							}
						}
					}
				},
				fetchAugmentedPullRequestThreads: func(number int) ([]*github.PullRequestReviewThread, error) {
					return []*github.PullRequestReviewThread{
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
							}{{FullDatabaseID: "1"}}},
						},
					}, nil
				},
				fetchAugmentedPullRequestReviews: func(number int) (map[string]githubv4.DateTime, error) {
					return map[string]githubv4.DateTime{
						"1": {Time: someTime.Add(time.Hour)},
					}, nil
				},
			},
			want: []*v1.Resource{
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: &v1.Mannequin{
							ResourceId: "http://github.test/monalisa",
						},
					},
				},
				{
					Resource: &v1.Resource_PullRequestReview{
						PullRequestReview: &v1.PullRequestReview{
							ResourceId:     "http://github.test/test-org/test-repo/pull/2#pullrequestreview-80",
							UserResourceId: "http://github.test/monalisa",
							HeadSha:        "pr-commit-id",
							CreatedAt:      timestamppb.New(someTime.Add(time.Hour)),
							SubmittedAt:    timestamppb.New(someTime),
							State:          v1.PullRequestReviewState_PULL_REQUEST_REVIEW_STATE_APPROVED,
							Body:           "pr review body",
							Threads: []*v1.PullRequestReviewThread{
								{
									ResourceId:                  "http://github.test/test-org/test-repo/pull/2-thread-1",
									PullRequestReviewResourceId: "http://github.test/test-org/test-repo/pull/2#pullrequestreview-80",
									CreatedAt:                   timestamppb.New(someTime),
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
									ResolvedAt:                  timestamppb.New(someTime),
									ResolvedUserResourceId:      "http://github.test/monalisa",
									Comments: []*v1.PullRequestReviewComment{
										{
											ResourceId:                        "http://github.test/test-org/test-repo/pull/2-comment-1",
											UserResourceId:                    "http://github.test/monalisa",
											PullRequestReviewResourceId:       "http://github.test/test-org/test-repo/pull/2#pullrequestreview-80",
											PullRequestReviewThreadResourceId: "http://github.test/test-org/test-repo/pull/2-thread-1",
											Body:                              "comment body",
											CreatedAt:                         timestamppb.New(someTime),
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &ResourceFetcher{
				err: tt.fields.err,
				fetchIssueComments: func(int, *FetchErr) iter.Seq[*ogithub.IssueComment] {
					return emptyIter[*ogithub.IssueComment]()
				},
				fetchIssueReactions: func(int, *FetchErr) iter.Seq[*ogithub.Reaction] {
					return emptyIter[*ogithub.Reaction]()
				},
				fetchPullRequests: func(err *FetchErr) iter.Seq[*ogithub.PullRequest] {
					return emptyIter[*ogithub.PullRequest]()
				},
				fetchPullRequestReviews:          tt.fields.fetchAllPullRequestReviews,
				fetchReviewComments:              tt.fields.fetchAllPullRequestReviewComments,
				fetchAugmentedPullRequestReviews: tt.fields.fetchAugmentedPullRequestReviews,
				fetchAugmentedPullRequestThreads: tt.fields.fetchAugmentedPullRequestThreads,
			}
			assert.Equal(t, tt.want, all(r.pullRequestReviews(1, &FetchErr{})))
		})
	}
}

// toURL is a util function that converts a string to a githubv4.URI.
func toURL(u string, t *testing.T) githubv4.URI {
	uri, err := url.Parse(u)
	require.NoError(t, err)
	return githubv4.URI{URL: uri}
}
