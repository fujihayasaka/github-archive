package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
)

func TestReleaseConversion(t *testing.T) {
	user := "http://github.test/monalisa"
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	reactions := []Reaction{
		{
			Content:     "+1",
			SubjectType: "release",
			User:        user,
			CreatedAt:   someTime,
		},
		{
			Content:     "+1",
			SubjectType: "release",
			User:        user,
			CreatedAt:   someTime,
		},
	}

	r := &Release{
		Type:            "release",
		URL:             "http://github.test/test-org/test-repo/releases/tag/v0.0.1",
		Repository:      "http://github.test/test-org/test-repo",
		User:            "http://github.test/monalisa",
		Name:            "some-release",
		TagName:         "v0.0.1",
		Body:            "body",
		State:           "published",
		PreRelease:      false,
		TargetCommitish: "f0aeb1",
		Reactions:       reactions,
		PublishedAt:     someTime,
		CreatedAt:       someTime,
	}
	expected := &v1.Release{
		ResourceId:           r.URL,
		RepositoryResourceId: r.Repository,
		UserResourceId:       r.User,
		Name:                 r.Name,
		TagName:              r.TagName,
		Body:                 r.Body,
		State:                r.State,
		IsPreRelease:         r.PreRelease,
		TargetCommitish:      r.TargetCommitish,
		PublishedAt:          toTimestamp(r.PublishedAt),
		CreatedAt:            toTimestamp(r.CreatedAt),
	}
	v1r, err := r.ToV1Release()
	require.NoError(t, err)
	require.Equal(t, expected, v1r)

	v1rs := r.Reactions.ExtractV1Reactions()
	require.Len(t, v1rs, 2)
}

func TestReleaseBadState(t *testing.T) {
	r := &Release{
		State: "not-draft-or-published",
	}
	_, err := r.ToV1Release()
	require.Error(t, err)
	require.ErrorContains(t, err, "invalid release state")
}
