package googlegithub

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestRepositoryComment_ToV1CommitComment(t *testing.T) {
	type fields struct {
		RepositoryComment github.RepositoryComment
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.CommitComment
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should convert an RepositoryComment to a v1.CommitComment",
			fields: fields{
				RepositoryComment: github.RepositoryComment{
					Path:      github.String("/internal/pkg/adapters/googlegithub/commit_comment_test.go"),
					Position:  github.Int(1),
					Body:      github.String("body"),
					CreatedAt: &github.Timestamp{Time: time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)},
					HTMLURL:   github.String("http://github.dev/guacamole-bowl/vim/commit/123456789abcdef#commitcomment-3"),
					User:      &github.User{HTMLURL: github.String("http://github.test/monalisa")},
				},
			},
			want: &v1.CommitComment{
				ResourceId:     "http://github.dev/guacamole-bowl/vim/commit/123456789abcdef#commitcomment-3",
				UserResourceId: "http://github.test/monalisa",
				Body:           "body",
				Path:           "/internal/pkg/adapters/googlegithub/commit_comment_test.go",
				Position:       1,
				CreatedAt:      timestamppb.New(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &CommitComment{
				RepositoryComment: tt.fields.RepositoryComment,
			}
			got, err := r.ToV1CommitComment()
			if !tt.wantErr(t, err, "ToV1IssueComment()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1IssueComment()")
		})
	}
}
