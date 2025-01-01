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
)

func createTestRelease() *release {
	return newRelease(&v1.Release{
		ResourceId:           "http://gh.io/guacamole-bowl/vim/releases/tag/v0.0.1",
		RepositoryResourceId: "http://gh.io/guacamole-bowl/vim",
		UserResourceId:       "http://gh.io/user1",
		Name:                 "some-release",
		TagName:              "v0.0.1",
		Body:                 "release body",
		State:                "published",
		IsPreRelease:         false,
		TargetCommitish:      "f01ac00",
		CreatedAt:            timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
		PublishedAt:          timestamppb.New(time.Date(2024, time.January, 1, 0, 0, 0, 0, time.UTC)),
	}, log.NewNullLogger())
}
func Test_release_dependencies(t *testing.T) {
	release := createTestRelease()
	dependencies, err := release.dependencies()
	require.NoError(t, err)

	require.Equal(t, &transformedDeps{
		int64Deps: set.FromSlice([]string{"http://gh.io/guacamole-bowl/vim"}),
		strDeps:   set.FromSlice([]string{"http://gh.io/user1"}),
	}, dependencies)
}

func Test_release_load(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	release := createTestRelease()
	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
		"http://gh.io/user1":              {strVal: "user1"},
	}

	err := release.load(context.Background(), importer, resolved)
	require.NoError(t, err)
	require.Len(t, importer.Releases, 1)

	require.Equal(t, &octov1.ImportReleaseRequest{
		RepositoryId:    1,
		AuthorLogin:     "user1",
		Name:            release.pb.Name,
		TagName:         release.pb.TagName,
		Body:            release.pb.Body,
		State:           octov1.ReleaseState_RELEASE_STATE_PUBLISHED,
		PendingTag:      release.pb.PendingTag,
		IsPreRelease:    release.pb.IsPreRelease,
		TargetCommitish: release.pb.TargetCommitish,
		PublishedAt:     release.pb.PublishedAt,
		CreatedAt:       release.pb.CreatedAt,
	}, importer.Releases[0])
}

func Test_release_load_bad_release_state(t *testing.T) {
	logger := log.NewNullLogger()
	importer := client.NewDummyImporter(logger)

	release := createTestRelease()
	release.pb.State = "random-state"
	resolved := resolvedIDsByResource{
		"http://gh.io/guacamole-bowl/vim": {int64Val: 1},
		"http://gh.io/user1":              {strVal: "user1"},
	}

	err := release.load(context.Background(), importer, resolved)
	require.Error(t, err)
	require.ErrorContains(t, err, "invalid release state")
}
