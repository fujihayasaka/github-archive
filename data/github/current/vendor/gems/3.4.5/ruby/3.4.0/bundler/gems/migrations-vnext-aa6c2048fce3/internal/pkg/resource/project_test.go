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

func createTestProject(t *testing.T) *project {
	t.Helper()

	p := &project{
		baseHandler: baseHandler{log.NewNullLogger()},
		pb: &v1.Project{
			ResourceId:        "http://gh.io/guacamole-bowl/vim/projects/1",
			Name:              "first project",
			Number:            1,
			OwnerResourceId:   "http://gh.io/guacamole-bowl/vim",
			OwnerType:         v1.OwnerType_OWNER_TYPE_REPOSITORY,
			CreatorResourceId: "http://gh.io/user1",
			CreatedAt:         timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
			Body:              "this is the body",
			IsPublic:          false,
			UpdatedAt:         timestamppb.New(time.Date(2024, time.January, 2, 0, 0, 0, 0, time.UTC)),
			ClosedAt:          timestamppb.New(time.Date(2024, time.January, 3, 0, 0, 0, 0, time.UTC)),
		},
		importedProjectID: 12345,
	}

	return p
}

func Test_project_skip(t *testing.T) {
	tests := []struct {
		name      string
		ownerType v1.OwnerType
		want      bool
	}{
		{
			name:      "owner type is organization",
			ownerType: v1.OwnerType_OWNER_TYPE_ORGANIZATION,
			want:      false,
		},
		{
			name:      "owner type is repository",
			ownerType: v1.OwnerType_OWNER_TYPE_REPOSITORY,
			want:      false,
		},
		{
			name:      "owner type is user",
			ownerType: v1.OwnerType_OWNER_TYPE_USER,
			want:      true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := createTestProject(t)
			p.pb.OwnerType = tt.ownerType
			assert.Equal(t, tt.want, p.skip())
		})
	}
}

func Test_project_dependencies(t *testing.T) {
	t.Run("repo project", func(t *testing.T) {
		project := createTestProject(t)
		dependencies, err := project.dependencies()
		require.NoError(t, err)

		require.Equal(t, &transformedDeps{
			int64Deps: set.FromSlice([]string{"http://gh.io/guacamole-bowl/vim"}),
			strDeps:   set.FromSlice([]string{"http://gh.io/user1"}),
		}, dependencies)
	})

	t.Run("org project", func(t *testing.T) {
		project := createTestProject(t)
		project.pb.OwnerType = v1.OwnerType_OWNER_TYPE_ORGANIZATION
		dependencies, err := project.dependencies()
		require.NoError(t, err)

		require.Equal(t, &transformedDeps{
			int64Deps: set.New[string](),
			strDeps:   set.FromSlice([]string{"http://gh.io/user1", "http://gh.io/guacamole-bowl/vim"}),
		}, dependencies)
	})
}

func Test_project_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	project := createTestProject(t)

	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
		"http://gh.io/user1":              {strVal: "user1"},
	}

	err := project.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.Projects, 1)

	require.Equal(t, &octov1.ImportProjectRequest{
		Name:         "first project",
		Number:       1,
		OwnerLogin:   "http://gh.io/guacamole-bowl/vim",
		OwnerType:    octov1.OwnerType_OWNER_TYPE_REPOSITORY,
		CreatorLogin: "user1",
		CreatedAt:    timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		RepositoryId: 1,
		Body:         "this is the body",
		IsPublic:     false,
		UpdatedAt:    timestamppb.New(time.Date(2024, time.January, 2, 0, 0, 0, 0, time.UTC)),
		ClosedAt:     timestamppb.New(time.Date(2024, time.January, 3, 0, 0, 0, 0, time.UTC)),
	}, importer.Projects[0])
}

func TestProject_newResolvedIDs(t *testing.T) {
	project := createTestProject(t)

	expected := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim/projects/1": &transformedValues{
			int64Val: 12345,
		},
	}

	result := project.newResolvedIDs()

	assert.Equal(t, expected, result)
}
