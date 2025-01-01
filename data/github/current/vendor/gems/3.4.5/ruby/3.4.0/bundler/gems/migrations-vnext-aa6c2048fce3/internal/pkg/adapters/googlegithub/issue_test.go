package googlegithub

import (
	"testing"
	"time"

	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestIssue_ToV1Issue(t *testing.T) {
	tests := map[string]struct {
		has   *Issue
		wants *v1.Issue
	}{
		"should properly convert the issue": {
			has: &Issue{github.Issue{
				Assignee: &github.User{HTMLURL: pointer.Of("http://localhost.test/user")},
				Assignees: []*github.User{
					{HTMLURL: pointer.Of("http://localhost.test/user")},
					{HTMLURL: pointer.Of("http://localhost.test/user2")},
					{HTMLURL: pointer.Of("http://localhost.test/user3")},
				},
				Body:      pointer.Of("test body"),
				ClosedAt:  &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
				CreatedAt: &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
				HTMLURL:   pointer.Of("http://localhost.test/foo/bar/1"),
				Title:     pointer.Of("test title"),
				UpdatedAt: &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
				User:      &github.User{HTMLURL: pointer.Of("http://localhost.test/user")},
			}},
			wants: &v1.Issue{
				AssigneesResourceIds: []string{
					"http://localhost.test/user",
					"http://localhost.test/user2",
					"http://localhost.test/user3",
				},
				ClosedAt:       timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
				CreatedAt:      timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
				Body:           "test body",
				ResourceId:     "http://localhost.test/foo/bar/1",
				Title:          "test title",
				UpdatedAt:      timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
				UserResourceId: "http://localhost.test/user",
			},
		},
		"should not populate AssigneesResourceIds with a slice of empty string when Assignee is nil": {
			has: &Issue{github.Issue{
				Assignee:  nil,
				Body:      pointer.Of("test body"),
				ClosedAt:  &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
				CreatedAt: &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
				HTMLURL:   pointer.Of("http://localhost.test/foo/bar/1"),
				Title:     pointer.Of("test title"),
				UpdatedAt: &github.Timestamp{Time: time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)},
				User:      &github.User{HTMLURL: pointer.Of("http://localhost.test/user")},
			}},
			wants: &v1.Issue{
				ClosedAt:       timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
				CreatedAt:      timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
				Body:           "test body",
				ResourceId:     "http://localhost.test/foo/bar/1",
				Title:          "test title",
				UpdatedAt:      timestamppb.New(time.Date(2024, 1, 1, 0o0, 0o0, 0o0, 0o0, time.UTC)),
				UserResourceId: "http://localhost.test/user",
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			conv, err := test.has.ToV1Issue()
			require.NoError(t, err)

			assert.Equal(t, len(test.wants.GetAssigneesResourceIds()), len(conv.GetAssigneesResourceIds()))
			for _, assignee := range test.wants.AssigneesResourceIds {
				assert.Contains(t, conv.GetAssigneesResourceIds(), assignee)
			}
			assert.Equal(t, test.wants.GetBody(), conv.GetBody())
			assert.Equal(t, test.wants.GetClosedAt(), conv.GetClosedAt())
			assert.Equal(t, test.wants.GetCreatedAt(), conv.GetCreatedAt())
			assert.Equal(t, test.wants.GetResourceId(), conv.GetResourceId())
			assert.Equal(t, test.wants.GetTitle(), conv.GetTitle())
			assert.Equal(t, test.wants.GetUpdatedAt(), conv.GetUpdatedAt())
			assert.Equal(t, test.wants.GetUserResourceId(), conv.GetUserResourceId())
		})
	}
}
