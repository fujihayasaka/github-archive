package resource

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func createTestProjectCardsBatch(t *testing.T) *projectCardsBatch {
	t.Helper()

	pcb := &projectCardsBatch{
		baseHandler: baseHandler{log.NewNullLogger()},
		pb: &v1.ProjectCardsBatch{
			ResourceId:              "project-cards-batch-1",
			ProjectColumnResourceId: "http://gh.io/guacamole-bowl/vim/projects/1/columns/1",
			Cards: []*v1.ProjectCard{
				{
					ResourceId:              "project-card-1",
					CreatorResourceId:       "http://gh.io/user1",
					ContentResourceId:       "",
					Note:                    "this is a note",
					Priority:                wrapperspb.UInt64(1),
					CreatedAt:               timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					UpdatedAt:               timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					ArchivedAt:              timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					HiddenAt:                timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					ProjectColumnResourceId: "http://gh.io/guacamole-bowl/vim/projects/1/columns/1",
				},
			},
		},
	}

	return pcb
}

func Test_project_cards_batch_dependencies(t *testing.T) {
	t.Run("card with content", func(t *testing.T) {
		batch := createTestProjectCardsBatch(t)
		batch.pb.Cards[0].ContentResourceId = "http://gh.io/guacamole-bowl/vim/issues/1"
		dependencies, err := batch.dependencies()
		require.NoError(t, err)

		require.Equal(t, &transformedDeps{
			int64Deps: set.FromSlice([]string{
				"http://gh.io/guacamole-bowl/vim/projects/1/columns/1",
				"http://gh.io/guacamole-bowl/vim/issues/1",
			}),
			strDeps: set.FromSlice([]string{"http://gh.io/user1"}),
		}, dependencies)
	})

	t.Run("card without content", func(t *testing.T) {
		batch := createTestProjectCardsBatch(t)
		dependencies, err := batch.dependencies()
		require.NoError(t, err)

		require.Equal(t, &transformedDeps{
			int64Deps: set.FromSlice([]string{"http://gh.io/guacamole-bowl/vim/projects/1/columns/1"}),
			strDeps:   set.FromSlice([]string{"http://gh.io/user1"}),
		}, dependencies)
	})
}

func Test_project_cards_batch_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	batch := createTestProjectCardsBatch(t)

	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim/projects/1/columns/1": {int64Val: 1},
		"http://gh.io/user1": {strVal: "user1"},
	}

	err := batch.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.ProjectCards, 1)

	require.Equal(t, &octov1.ImportProjectCardsRequest{
		ImportedProjectColumnId: 1,
		ProjectCards: []*octov1.ProjectCard{
			{
				CreatorLogin:   "user1",
				ContentType:    octov1.ContentType_CONTENT_TYPE_NOTE,
				ContentId:      0,
				Note:           "this is a note",
				Priority:       1,
				CreatedAt:      timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
				UpdatedAt:      timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
				ArchivedAt:     timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
				HiddenAt:       timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
				HasNilPriority: false,
			},
		},
	}, importer.ProjectCards[0])
}
