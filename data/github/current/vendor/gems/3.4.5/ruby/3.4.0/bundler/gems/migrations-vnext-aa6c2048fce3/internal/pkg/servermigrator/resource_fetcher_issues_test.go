package servermigrator

import (
	"iter"
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
)

func Test_resourceFetcher_issues(t *testing.T) {
	type fields struct {
		err                           error
		fetchAllIssues                fetchIssues
		fetchAllIssueComments         fetchIssueComments
		fetchAllIssueReactions        fetchIssueReactions
		fetchAllIssueCommentReactions fetchIssueCommentReactions
	}
	tests := []struct {
		name   string
		fields fields
		want   []*v1.Resource
	}{
		{
			name: "returns all issues without issue comments",
			fields: fields{
				fetchAllIssues: func(err *FetchErr) iter.Seq[*ogithub.Issue] {
					return func(yield func(*ogithub.Issue) bool) {
						issues := []*ogithub.Issue{
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/issues/1"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/monalisa")},
							},
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/issues/2"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/lisamona")},
							},
						}
						for _, issue := range issues {
							if !yield(issue) {
								return
							}
						}
					}
				},
				fetchAllIssueComments: func(int, *FetchErr) iter.Seq[*ogithub.IssueComment] {
					return func(yield func(*ogithub.IssueComment) bool) {}
				},
				fetchAllIssueReactions: func(int, *FetchErr) iter.Seq[*ogithub.Reaction] {
					return func(yield func(*ogithub.Reaction) bool) {}
				},
				fetchAllIssueCommentReactions: func(int64, *FetchErr) iter.Seq[*ogithub.Reaction] {
					return func(yield func(*ogithub.Reaction) bool) {}
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
					Resource: &v1.Resource_Issue{
						Issue: &v1.Issue{
							ResourceId:           "http://github.test/test-org/test-repo/issues/1",
							UserResourceId:       "http://github.test/monalisa",
							AssigneesResourceIds: make([]string, 0),
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
					Resource: &v1.Resource_Issue{
						Issue: &v1.Issue{
							ResourceId:           "http://github.test/test-org/test-repo/issues/2",
							UserResourceId:       "http://github.test/lisamona",
							AssigneesResourceIds: make([]string, 0),
						},
					},
				},
			},
		},
		{
			name: "returns all issues with issue comments",
			fields: fields{
				fetchAllIssues: func(err *FetchErr) iter.Seq[*ogithub.Issue] {
					return func(yield func(*ogithub.Issue) bool) {
						issues := []*ogithub.Issue{
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/issues/1"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/monalisa")},
							},
						}
						for _, issue := range issues {
							if !yield(issue) {
								return
							}
						}
					}
				},
				fetchAllIssueComments: func(_ int, _ *FetchErr) iter.Seq[*ogithub.IssueComment] {
					return func(yield func(*ogithub.IssueComment) bool) {
						comments := []*ogithub.IssueComment{
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/issues/1#issuecomment-1"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/monalisa")},
							},
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/issues/1#issuecomment-2"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/lisamona")},
							},
						}
						for _, comment := range comments {
							if !yield(comment) {
								return
							}
						}
					}
				},
				fetchAllIssueReactions: func(_ int, _ *FetchErr) iter.Seq[*ogithub.Reaction] {
					return func(yield func(*ogithub.Reaction) bool) {}
				},
				fetchAllIssueCommentReactions: func(int64, *FetchErr) iter.Seq[*ogithub.Reaction] {
					return func(yield func(*ogithub.Reaction) bool) {}
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
					Resource: &v1.Resource_Issue{
						Issue: &v1.Issue{
							ResourceId:           "http://github.test/test-org/test-repo/issues/1",
							UserResourceId:       "http://github.test/monalisa",
							AssigneesResourceIds: make([]string, 0),
						},
					},
				},
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: &v1.Mannequin{
							ResourceId: "http://github.test/monalisa",
						},
					},
				},
				{
					Resource: &v1.Resource_IssueComment{
						IssueComment: &v1.IssueComment{
							ResourceId:     "http://github.test/test-org/test-repo/issues/1#issuecomment-1",
							UserResourceId: "http://github.test/monalisa",
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
					Resource: &v1.Resource_IssueComment{
						IssueComment: &v1.IssueComment{
							ResourceId:     "http://github.test/test-org/test-repo/issues/1#issuecomment-2",
							UserResourceId: "http://github.test/lisamona",
						},
					},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &ResourceFetcher{
				err:                        tt.fields.err,
				fetchIssues:                tt.fields.fetchAllIssues,
				fetchIssueComments:         tt.fields.fetchAllIssueComments,
				fetchIssueReactions:        tt.fields.fetchAllIssueReactions,
				fetchIssueCommentReactions: tt.fields.fetchAllIssueCommentReactions,
			}
			assert.Equal(t, tt.want, all(r.issues()))
		})
	}
}
