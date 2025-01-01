package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestIssueConversion(t *testing.T) {
	body := "issue body"
	resourceID := "http://github.test/test-org/test-repo/issues/2"
	user := "http://github.test/monalisa"
	createdAt := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	assignees := []string{"http://github.test/alice", "http://github.test/bob"}
	reactions := []Reaction{
		{
			Content:     "+1",
			SubjectType: "issue",
			User:        user,
			CreatedAt:   createdAt,
		},
		{
			Content:     "+1",
			SubjectType: "issue",
			User:        user,
			CreatedAt:   createdAt,
		},
	}

	ic := &Issue{
		Body:      body,
		CreatedAt: createdAt,
		Reactions: reactions,
		Type:      "issue",
		URL:       resourceID,
		User:      user,
		// Add a duplicate assignee to the issue that we expect to not be in the result.
		Assignees: append(assignees, "http://github.test/bob"),
	}

	expected := &v1.Issue{
		ResourceId:            resourceID,
		UserResourceId:        user,
		Body:                  body,
		CreatedAt:             toTimestamp(createdAt),
		AssigneesResourceIds:  assignees,
		AttachmentResourceIds: nil,
	}

	v1c, err := ic.ToV1Issue()
	require.NoError(t, err)
	require.Equal(t, expected, v1c)

	v1rs := ic.Reactions.ExtractV1Reactions()
	require.Len(t, v1rs, 2)
}
