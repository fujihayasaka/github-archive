package resource

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func createTestCommitComment(t *testing.T) *commitComment {
	c := &commitComment{
		baseHandler: baseHandler{log.NewNullLogger()},
		pb: &v1.CommitComment{
			ResourceId:     "http://gh.io/guacamole-bowl/vim/commit/8e950bc74aafc1105236fc2b36322754aac5d725#commitcomment-2",
			UserResourceId: "http://gh.io/user1",
			Body:           "this commit is pure awesomeness",
			Path:           "path/to/file",
			Position:       1,
			CreatedAt:      timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		},
	}

	return c
}

func Test_commit_comment_dependencies(t *testing.T) {
	comment := createTestCommitComment(t)
	dependencies, err := comment.dependencies()
	require.NoError(t, err)

	require.Equal(t, &transformedDeps{
		int64Deps: set.FromSlice([]string{"http://gh.io/guacamole-bowl/vim"}),
		strDeps:   set.FromSlice([]string{"http://gh.io/user1"}),
	}, dependencies)

	k, err := keys.ToCommitCommentKey(comment.pb.ResourceId)
	require.NoError(t, err)
	require.Equal(t, k, comment.key)
}

func Test_commit_comment_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	comment := createTestCommitComment(t)
	k, err := keys.ToCommitCommentKey(comment.pb.ResourceId)
	require.NoError(t, err)
	comment.key = k

	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
		"http://gh.io/user1":              {strVal: "user1"},
	}

	err = comment.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.CommitComments, 1)

	require.Equal(t, &octov1.ImportCommitCommentRequest{
		RepositoryId: 1,
		AuthorLogin:  "user1",
		Body:         "this commit is pure awesomeness",
		Path:         wrapperspb.String("path/to/file"),
		CommitId:     "8e950bc74aafc1105236fc2b36322754aac5d725",
		Position:     wrapperspb.Int64(1),
		CreatedAt:    timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
	}, importer.CommitComments[0])
}

func Test_commit_comment_dependenciesToUpdate(t *testing.T) {
	comment := createTestCommitComment(t)
	dependenciesToUpdate := comment.newResolvedIDs()
	require.Equal(t,
		resolvedIDsByResource{"http://gh.io/guacamole-bowl/vim/commit/8e950bc74aafc1105236fc2b36322754aac5d725#commitcomment-2": {int64Val: comment.importedCommentID}},
		dependenciesToUpdate)
}
