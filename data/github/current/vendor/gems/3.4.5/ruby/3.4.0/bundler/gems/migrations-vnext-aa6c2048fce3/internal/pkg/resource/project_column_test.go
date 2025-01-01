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
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func createTestProjectColumn(t *testing.T) *projectColumn {
	t.Helper()

	pc := &projectColumn{
		baseHandler: baseHandler{log.NewNullLogger()},
		pb: &v1.ProjectColumn{
			ResourceId:        "http://gh.io/guacamole-bowl/vim/projects/1/columns/1",
			Name:              "To do",
			Color:             "color1",
			CreatedAt:         timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
			UpdatedAt:         timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
			Purpose:           "todo",
			Position:          1,
			HiddenAt:          timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
			ProjectResourceId: "http://gh.io/guacamole-bowl/vim/projects/1",
			Workflows: []*v1.ProjectWorkflow{
				{
					CreatorResourceId:     "http://gh.io/user1",
					TriggerType:           "issue_closed",
					CreatedAt:             timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					LastUpdaterResourceId: "http://gh.io/user1",
					UpdatedAt:             timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					Actions: []*v1.ProjectWorkflowAction{
						{
							CreatorResourceId:     "http://gh.io/user1",
							CreatedAt:             timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
							LastUpdaterResourceId: "http://gh.io/user1",
							UpdatedAt:             timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
						},
					},
				},
			},
		},
		importedProjectColumnID: 12345,
	}

	return pc
}

func Test_project_column_dependencies(t *testing.T) {
	pc := createTestProjectColumn(t)
	dependencies, err := pc.dependencies()
	require.NoError(t, err)

	require.Equal(t, &transformedDeps{
		int64Deps: set.FromSlice([]string{"http://gh.io/guacamole-bowl/vim/projects/1"}),
		strDeps:   set.FromSlice([]string{"http://gh.io/user1"}),
	}, dependencies)
}

func Test_project_column_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	pc := createTestProjectColumn(t)

	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim/projects/1": {int64Val: 1},
		"http://gh.io/user1":                         {strVal: "user1"},
	}

	err := pc.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.ProjectColumns, 1)

	require.Equal(t, &octov1.ImportProjectColumnRequest{
		ImportedProjectId: 1,
		Name:              "To do",
		Color:             "color1",
		CreatedAt:         timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		UpdatedAt:         timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		Purpose:           octov1.ColumnPurpose_COLUMN_PURPOSE_TODO,
		Position:          1,
		HiddenAt:          timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		Workflows: []*octov1.ProjectWorkflow{
			{
				CreatorLogin:     "user1",
				TriggerType:      octov1.TriggerType_TRIGGER_TYPE_ISSUE_CLOSED_TRIGGER,
				CreatedAt:        timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
				LastUpdaterLogin: "user1",
				UpdatedAt:        timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
				Actions: []*octov1.ProjectWorkflowAction{
					{
						CreatorLogin:     "user1",
						CreatedAt:        timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
						LastUpdaterLogin: "user1",
						UpdatedAt:        timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
					},
				},
			},
		},
	}, importer.ProjectColumns[0])
}

func TestProjectColumn_newResolvedIDs(t *testing.T) {
	pc := createTestProjectColumn(t)

	expected := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim/projects/1/columns/1": &transformedValues{
			int64Val: 12345,
		},
	}

	result := pc.newResolvedIDs()

	assert.Equal(t, expected, result)
}
