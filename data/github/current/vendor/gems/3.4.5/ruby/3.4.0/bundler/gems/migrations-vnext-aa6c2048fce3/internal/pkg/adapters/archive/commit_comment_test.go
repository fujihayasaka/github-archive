package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestCommitComment_ToV1CommitComment(t *testing.T) {
	createAt := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	c := &CommitComment{
		URL:       "http://github.test/test-org/test-repo/commit/123abc#commitcomment-1",
		User:      "http://github.test/monalisa",
		Body:      "comment body",
		Path:      "path/to/file",
		Position:  1,
		CreatedAt: createAt,
	}

	expected := &v1.CommitComment{
		ResourceId:     c.URL,
		UserResourceId: c.User,
		Body:           c.Body,
		Path:           c.Path,
		Position:       c.Position,
		CreatedAt:      toTimestamp(createAt),
	}

	v1Comment, err := c.ToV1CommitComment()
	require.NoError(t, err)

	require.Equal(t, expected, v1Comment)
}
