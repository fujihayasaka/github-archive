package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestIssueCommentConversion(t *testing.T) {
	body := "comment body"
	resourceID := "http://github.test/test-org/test-repo/issues/2#issuecomment-1326"
	user := "http://github.test/monalisa"
	createdAt := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	reactions := []Reaction{
		{
			Content:     "+1",
			SubjectType: "issuecomment",
			User:        user,
			CreatedAt:   createdAt,
		},
		{
			Content:     "+1",
			SubjectType: "issuecomment",
			User:        user,
			CreatedAt:   createdAt,
		},
	}

	ic := &IssueComment{
		Body:      body,
		CreatedAt: createdAt,
		Formatter: "unused",
		Issue:     "unused",
		Reactions: reactions,
		Type:      "issuecomment",
		URL:       resourceID,
		User:      user,
	}

	expected := &v1.IssueComment{
		ResourceId:            resourceID,
		UserResourceId:        user,
		Body:                  body,
		CreatedAt:             toTimestamp(createdAt),
		AttachmentResourceIds: nil,
	}

	v1c, err := ic.ToV1IssueComment()
	require.NoError(t, err)
	require.Equal(t, expected, v1c)
}
