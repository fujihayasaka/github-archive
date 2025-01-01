package servermigrator

import (
	"context"
	"fmt"
	"iter"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	mvngithub "github.com/github/migrations-vnext/internal/pkg/github"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/shurcooL/githubv4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestServerMigrator_handlePullRequestWebhook(t *testing.T) {
	type fields struct {
		clientSetup func(api *MockMigrationTargetAPI)
	}
	type args struct {
		guid string
		e    *github.PullRequestEvent
	}
	tests := []struct {
		name    string
		fields  fields
		args    args
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should create a new pr and author",
			fields: fields{
				clientSetup: func(api *MockMigrationTargetAPI) {
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
						{
							Resource: &v1.Resource_Mannequin{
								Mannequin: &v1.Mannequin{
									ResourceId:    "http://github.test/monalisa",
									OrgResourceId: "http://github.test/acme",
								},
							},
						},
					}).Return(nil, nil)
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
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
					}).Return(nil, nil)
				},
			},
			args: args{
				guid: "test-guid",
				e: &github.PullRequestEvent{
					Action: pointer.Of("opened"),
					PullRequest: &github.PullRequest{
						HTMLURL: github.String("http://github.test/test-org/test-repo/pull/1"),
						User:    &github.User{HTMLURL: github.String("http://github.test/monalisa")},
					},
				},
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockMigration := NewMockMigrationTargetAPI(t)
			if tt.fields.clientSetup != nil {
				tt.fields.clientSetup(mockMigration)
			}
			m := &ServerMigrator{
				logger:          log.NewNullLogger(),
				migrationClient: mockMigration,
				statter:         stats.NullStatter,
				org:             "http://github.test/acme",
			}
			tt.wantErr(t, m.handlePullRequestWebhook(context.Background(), tt.args.guid, tt.args.e), fmt.Sprintf("handlePullRequestWebhook(%v, %v)", tt.args.guid, tt.args.e))
		})
	}
}

func TestServerMigrator_handlePullRequestReviewWebhook(t *testing.T) {
	var someTime = time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)

	type fields struct {
		clientSetup                       func(api *MockMigrationTargetAPI)
		fetchAllPullRequestReviews        fetchPullRequestReviews
		fetchAllPullRequestReviewComments fetchReviewComments
		fetchAugmentedPullRequestThreads  fetchAugmentedPullRequestThreads
		fetchAugmentedPullRequestReviews  fetchAugmentedPullRequestReviews
	}
	type args struct {
		guid string
		e    *github.PullRequestReviewEvent
	}
	tests := []struct {
		name    string
		fields  fields
		args    args
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should create a new pr review and author",
			fields: fields{
				fetchAllPullRequestReviews: func(int, *FetchErr) iter.Seq[*github.PullRequestReview] {
					return func(yield func(request *github.PullRequestReview) bool) {
						reviews := []*github.PullRequestReview{
							{
								ID:             pointer.Of(int64(1)),
								HTMLURL:        pointer.Of("http://github.test/test-org/test-repo/pull/2#pullrequestreview-80"),
								PullRequestURL: pointer.Of("http://github.test/test-org/test-repo/pull/2"),
								User:           &github.User{HTMLURL: pointer.Of("http://github.test/monalisa")},
								Body:           pointer.Of("pr review body"),
								CommitID:       pointer.Of("pr-commit-id"),
								SubmittedAt:    &github.Timestamp{Time: someTime},
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
				fetchAllPullRequestReviewComments: func(int, int64, *FetchErr) iter.Seq[*github.PullRequestComment] {
					return func(yield func(request *github.PullRequestComment) bool) {
						comments := []*github.PullRequestComment{
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
						}
						for _, comment := range comments {
							if !yield(comment) {
								return
							}
						}
					}
				},
				fetchAugmentedPullRequestReviews: func(number int) (map[string]githubv4.DateTime, error) {
					return map[string]githubv4.DateTime{
						"1": {Time: someTime.Add(time.Hour)},
					}, nil
				},
				fetchAugmentedPullRequestThreads: func(number int) ([]*mvngithub.PullRequestReviewThread, error) {
					return []*mvngithub.PullRequestReviewThread{
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
				clientSetup: func(api *MockMigrationTargetAPI) {
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
						{
							Resource: &v1.Resource_Mannequin{
								Mannequin: &v1.Mannequin{
									ResourceId:    "http://github.test/monalisa",
									OrgResourceId: "http://github.test/acme",
								},
							},
						},
					}).Return(nil, nil)
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
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
					}).Return(nil, nil)
				},
			},
			args: args{
				guid: "test-guid",
				e: &github.PullRequestReviewEvent{
					Action: pointer.Of("submitted"),
					Review: &github.PullRequestReview{
						HTMLURL: github.String("http://github.test/test-org/test-repo/pull/2#pullrequestreview-80"),
						User:    &github.User{HTMLURL: github.String("http://github.test/monalisa")},
					},
					Organization: &github.Organization{HTMLURL: github.String("http://github.test/acme")},
				},
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockMigration := NewMockMigrationTargetAPI(t)
			if tt.fields.clientSetup != nil {
				tt.fields.clientSetup(mockMigration)
			}
			r := &ResourceFetcher{
				fetchIssueComments: func(int, *FetchErr) iter.Seq[*github.IssueComment] {
					return emptyIter[*github.IssueComment]()
				},
				fetchIssueReactions: func(int, *FetchErr) iter.Seq[*github.Reaction] {
					return emptyIter[*github.Reaction]()
				},
				fetchPullRequests: func(err *FetchErr) iter.Seq[*github.PullRequest] {
					return emptyIter[*github.PullRequest]()
				},
				fetchPullRequestReviews:          tt.fields.fetchAllPullRequestReviews,
				fetchReviewComments:              tt.fields.fetchAllPullRequestReviewComments,
				fetchAugmentedPullRequestReviews: tt.fields.fetchAugmentedPullRequestReviews,
				fetchAugmentedPullRequestThreads: tt.fields.fetchAugmentedPullRequestThreads,
				org:                              "http://github.test/acme",
			}
			m := &ServerMigrator{
				logger:          log.NewNullLogger(),
				migrationClient: mockMigration,
				resourceFetcher: r,
				statter:         stats.NullStatter,
				org:             "http://github.test/acme",
			}
			tt.wantErr(t, m.handlePullRequestReviewWebhook(context.Background(), tt.args.guid, tt.args.e), fmt.Sprintf("handlePullRequestReviewWebhook(%v, %v)", tt.args.guid, tt.args.e))
		})
	}
}
