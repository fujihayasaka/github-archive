package servermigrator

import (
	"iter"
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	ogithub "github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
)

func TestResourceFetcher_commitComments(t *testing.T) {
	type fields struct {
		err                    error
		fetchAllCommitComments fetchAllCommitComments
	}

	tests := []struct {
		name   string
		fields fields
		want   []*v1.Resource
	}{
		{
			name: "returns all commit comments with authors",
			fields: fields{
				fetchAllCommitComments: func(fetchErr *FetchErr) iter.Seq[*ogithub.RepositoryComment] {
					return func(yield func(*ogithub.RepositoryComment) bool) {
						comments := []*ogithub.RepositoryComment{
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/comments/1"),
								User:    &ogithub.User{HTMLURL: ogithub.String("http://github.test/monalisa")},
							},
							{
								HTMLURL: ogithub.String("http://github.test/test-org/test-repo/comments/2"),
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
					Resource: &v1.Resource_CommitComment{
						CommitComment: &v1.CommitComment{
							ResourceId:     "http://github.test/test-org/test-repo/comments/1",
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
					Resource: &v1.Resource_CommitComment{
						CommitComment: &v1.CommitComment{
							ResourceId:     "http://github.test/test-org/test-repo/comments/2",
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
				err:                    tt.fields.err,
				fetchAllCommitComments: tt.fields.fetchAllCommitComments,
			}
			assert.Equal(t, tt.want, all(r.commitComments()))
		})
	}
}
