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
)

func createTestIssue(t *testing.T) *issue {
	i := &issue{
		baseHandler: baseHandler{log.NewNullLogger()},
		pb: &v1.Issue{
			ResourceId:            "http://gh.io/guacamole-bowl/vim/issues/2",
			UserResourceId:        "http://gh.io/user1",
			AttachmentResourceIds: []string{"attachmentURL"},
			AssigneesResourceIds:  []string{"http://gh.io/assignee1"},
			Body:                  "replace this attachmentURL with the new one and http://gh.io with the new base URL",
			Title:                 "this is the title",
			CreatedAt:             timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
			ClosedAt:              timestamppb.New(time.Date(2024, time.January, 2, 0, 0, 0, 0, time.UTC)),
		},
	}

	return i
}

func Test_issue_dependencies(t *testing.T) {
	issue := createTestIssue(t)
	dependencies, err := issue.dependencies()
	require.NoError(t, err)

	require.Equal(t, &transformedDeps{
		int64Deps: set.FromSlice([]string{"http://gh.io/guacamole-bowl/vim"}),
		strDeps:   set.FromSlice([]string{"http://gh.io/user1", "attachmentURL", "http://gh.io/assignee1", "http://gh.io"}),
	}, dependencies)

	k, err := keys.ToIssueKey(issue.pb.ResourceId)
	require.NoError(t, err)
	require.Equal(t, k, issue.key)
}

func Test_issue_transform(t *testing.T) {
	issue := createTestIssue(t)

	transformedIDs := resolvedIDsByResource{
		"attachmentURL": {
			strVal: "newAttachmentURL",
		},
		"http://gh.io": {strVal: "http://github.localhost"},
	}

	k, err := keys.ToIssueKey(issue.pb.ResourceId)
	require.NoError(t, err)
	issue.key = k

	err = issue.transform(transformedIDs)
	require.NoError(t, err)

	require.Equal(t, "replace this newAttachmentURL with the new one and http://github.localhost with the new base URL", issue.pb.Body)
}

func Test_issue_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	issue := createTestIssue(t)
	k, err := keys.ToIssueKey(issue.pb.ResourceId)
	require.NoError(t, err)
	issue.key = k

	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
		"http://gh.io/user1":              {strVal: "user1"},
		"http://gh.io/assignee1":          {strVal: "assignee1"},
	}

	err = issue.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.Issues, 1)

	require.Equal(t, &octov1.ImportIssueRequest{
		RepositoryId: 1,
		AuthorLogin:  "user1",
		Assignees:    []string{"assignee1"},
		Body:         "replace this attachmentURL with the new one and http://gh.io with the new base URL",
		Title:        "this is the title",
		Number:       2,
		CreatedAt:    timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		ClosedAt:     timestamppb.New(time.Date(2024, time.January, 2, 0, 0, 0, 0, time.UTC)),
	}, importer.Issues[0])
}

func Test_issue_dependenciesToUpdate(t *testing.T) {
	issue := createTestIssue(t)
	dependenciesToUpdate := issue.newResolvedIDs()
	require.Equal(t,
		resolvedIDsByResource{"http://gh.io/guacamole-bowl/vim/issues/2": {int64Val: issue.importedID}},
		dependenciesToUpdate)
}
