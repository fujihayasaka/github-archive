package googlegithub

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestReaction_ToV1Reaction(t *testing.T) {
	aDate := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	timeNowFn = func() *timestamppb.Timestamp { return timestamppb.New(aDate) }

	type fields struct {
		Reaction github.Reaction
	}
	tests := []struct {
		name    string
		fields  fields
		want    *v1.Reaction
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should convert a github reaction to a v1 reaction",
			fields: fields{
				Reaction: github.Reaction{
					Content: github.String("+1"),
					User:    &github.User{HTMLURL: github.String("http://github.test/monalisa")},
				},
			},
			want: &v1.Reaction{
				Content:        "+1",
				UserResourceId: "http://github.test/monalisa",
				CreatedAt:      timestamppb.New(aDate),
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := &Reaction{
				Reaction: tt.fields.Reaction,
			}
			got, err := r.ToV1Reaction()
			if !tt.wantErr(t, err, "ToV1Reaction()") {
				return
			}
			assert.Equalf(t, tt.want, got, "ToV1Reaction()")
		})
	}
}
