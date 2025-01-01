package googlegithub

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestIssueComment_ToV1IssueComment(t *testing.T) {
	type fields struct {
		IssueComment github.IssueComment
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.IssueComment
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should convert an IssueComment to a v1.IssueComment",
			fields: fields{
				IssueComment: github.IssueComment{
					Body:      github.String("body"),
					CreatedAt: &github.Timestamp{Time: time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)},
					HTMLURL:   github.String("http://github.test/test-org/test-repo/issues/2#issuecomment-1326"),
					User:      &github.User{HTMLURL: github.String("http://github.test/monalisa")},
				},
			},
			want: &v1.IssueComment{
				ResourceId:     "http://github.test/test-org/test-repo/issues/2#issuecomment-1326",
				UserResourceId: "http://github.test/monalisa",
				Body:           "body",
				CreatedAt:      timestamppb.New(time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)),
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &IssueComment{
				IssueComment: tt.fields.IssueComment,
			}
			got, err := r.ToV1IssueComment()
			if !tt.wantErr(t, err, "ToV1IssueComment()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1IssueComment()")
		})
	}
}
