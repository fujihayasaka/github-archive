package resource

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func createIssueEventBatch(t *testing.T) *issueEventBatch {
	t.Helper()

	batch := &issueEventBatch{
		baseBatchHandler: baseBatchHandler{logger: log.NewNullLogger()},
		pb: &v1.IssueEventBatch{
			ResourceId: "issue-event-batch-1",
			IssueResourceIds: []string{
				"http://gh.io/guacamole-bowl/vim/issues/1",
			},
			UserResourceIds: []string{
				"http://gh.io/user1",
			},
			PullRequestResourceIds: []string{
				"http://gh.io/guacamole-bowl/vim/pull/2",
			},
			RepositoryResourceIds: []string{
				"http://gh.io/guacamole-bowl/vim",
			},
			Events: []*v1.IssueEvent{
				{
					ResourceId:      "http://gh.io/guacamole-bowl/vim/issues/1#event-1",
					ActorResourceId: "http://gh.io/user1",
					Message:         "this is a message for an issue event",
				},
				{
					ResourceId:      "http://gh.io/guacamole-bowl/vim/pull/2#event-2",
					ActorResourceId: "http://gh.io/user1",
					Message:         "this is a message for a pull request event",
				},
			},
		},
	}

	return batch
}

func Test_issueEventBatch_itemIDs(t *testing.T) {
	t.Run("no events", func(t *testing.T) {
		batch := createIssueEventBatch(t)
		batch.pb.Events = nil
		require.Empty(t, batch.itemIDs())
	})

	t.Run("with events", func(t *testing.T) {
		batch := createIssueEventBatch(t)
		require.Len(t, batch.itemIDs(), 2)
		require.Equal(t, []string{"http://gh.io/guacamole-bowl/vim/issues/1#event-1", "http://gh.io/guacamole-bowl/vim/pull/2#event-2"}, batch.itemIDs())
	})
}

func Test_issueEventBatch_dependencies(t *testing.T) {
	batch := createIssueEventBatch(t)
	dependencies, err := batch.dependencies(make(idSet))
	require.NoError(t, err)

	require.Equal(t, &transformedDeps{
		int64Deps: set.FromSlice([]string{
			"http://gh.io/guacamole-bowl/vim",
		}),
		strDeps: set.FromSlice([]string{
			"http://gh.io/user1",
		}),
	}, dependencies)
}

func Test_issueEventBatch_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
		"http://gh.io/user1":              {strVal: "user1"},
	}

	batch := createIssueEventBatch(t)
	err := batch.load(context.Background(), importer, make(idSet), resolved)
	require.NoError(t, err)
	require.Len(t, importer.TimeLineEvents, 1)
	require.Equal(t, &octov1.ImportTimelineEventsRequest{
		TimelineEvents: []*octov1.TimelineEvent{
			{
				IssueNumber:  1,
				RepositoryId: 1,
				Actor:        "user1",
				Message:      "this is a message for an issue event",
			},
			{
				IssueNumber:  2,
				RepositoryId: 1,
				Actor:        "user1",
				Message:      "this is a message for a pull request event",
			},
		},
	}, importer.TimeLineEvents[0])
}
