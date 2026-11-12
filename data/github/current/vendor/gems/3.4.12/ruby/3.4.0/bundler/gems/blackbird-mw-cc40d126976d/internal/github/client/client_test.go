package client

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/dnaeon/go-vcr/recorder"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/types"
)

const (
	baseURL = "http://api.github.localhost"
	hmacKey = "octocat"
	pat     = "octocat"
)

func Test_GetPullForCommit(t *testing.T) {
	r, err := recorder.New("fixtures/get-pulls-for-commit")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	pulls, err := client.GetPullsForCommit(ctx, types.NWOFromString("github/blackbird"), "13240fd24fb480312e66adac4b8375c1a0727edb")
	require.NoError(t, err)
	require.NotNil(t, pulls)
	require.Len(t, pulls, 1)
	pull := pulls[0]
	require.EqualValues(t, 7920, pull.GetNumber())
	require.EqualValues(t, "http://github.localhost/github/blackbird/pull/7920", pull.GetHTMLURL())
	require.EqualValues(t, "Always index both code and markdown embeddings", pull.GetTitle())
	require.EqualValues(t, "tclem", pull.GetUser().GetLogin())
}

func Test_GetRepository(t *testing.T) {
	r, err := recorder.New("fixtures/get-repository")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	repo, err := client.GetRepository(ctx, 1)
	require.NoError(t, err)
	assertRepo(t, repo)
}

func Test_GetRepositoryNwo(t *testing.T) {
	r, err := recorder.New("fixtures/get-repository-nwo")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	repo, err := client.GetRepositoryByNWO(ctx, types.NWOFromString("github/private-server"))
	require.NoError(t, err)
	assertRepo(t, repo)
}

func Test_GetRepositoriesByIds(t *testing.T) {
	r, err := recorder.New("fixtures/get-repositories-by-ids")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	repos, err := client.GetRepositoriesByIds(ctx, []types.RepoID{3, 253831084})
	require.NoError(t, err)
	require.Len(t, repos, 2)
	// Validate repo metadata fields match expected values for both repos.
	repo1 := repos[0]
	require.EqualValues(t, 3, repo1.ID)
	require.Equal(t, "github", repo1.Name)
	require.EqualValues(t, 9919, repo1.OwnerID)
	require.Equal(t, "github", repo1.OwnerLogin)
	require.False(t, repo1.Public)
	require.False(t, repo1.Archived)
	require.Equal(t, types.RepoSeqNo(1), repo1.RepoSeqNo)

	repo2 := repos[1]
	require.EqualValues(t, 253831084, repo2.ID)
	require.Equal(t, "blackbird", repo2.Name)
	require.EqualValues(t, 9919, repo2.OwnerID)
	require.Equal(t, "github", repo2.OwnerLogin)
	require.False(t, repo2.Public)
	require.True(t, repo2.Archived)
	require.Equal(t, types.RepoSeqNo(2), repo2.RepoSeqNo)
}

func Test_GetRepositoriesByCursor(t *testing.T) {
	r, err := recorder.New("fixtures/get-repositories-by-cursor-with-next-cursor")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	limit := 1
	repos, nextCursor, err := client.GetRepositoriesByCursor(ctx, "1", limit)
	require.NoError(t, err)
	require.Len(t, repos, limit)
	require.Equal(t, "253831084", nextCursor)

	// Validate repo metadata fields match expected values for both repos.
	repo1 := repos[0]
	require.EqualValues(t, 3, repo1.ID)
	require.Equal(t, "github", repo1.Name)
	require.EqualValues(t, 9919, repo1.OwnerID)
	require.Equal(t, "github", repo1.OwnerLogin)
	require.False(t, repo1.Public)
	require.False(t, repo1.Archived)
	require.Equal(t, types.RepoSeqNo(1), repo1.RepoSeqNo)

	// Fetch next page using the previous result's `next_cursor`.
	r, err = recorder.New("fixtures/get-repositories-by-cursor-without-next-cursor")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient = &http.Client{Transport: r}

	client = NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	repos, nextCursor, err = client.GetRepositoriesByCursor(ctx, nextCursor, limit)
	require.NoError(t, err)
	require.Len(t, repos, limit)
	require.Equal(t, "", nextCursor)
}

func Test_GetRepositoryNullFields(t *testing.T) {
	r, err := recorder.New("fixtures/get-repository-null-fields")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	repo, err := client.GetRepository(ctx, 1)
	require.NoError(t, err)
	require.Zero(t, repo.PushedAt)
	require.Equal(t, "", repo.LicenseName)
	require.EqualValues(t, 0, repo.NumWatchers)
	require.EqualValues(t, 0, repo.NumStars)
}

func Test_GetRepositoryNotFound(t *testing.T) {
	r, err := recorder.New("fixtures/get-repository-not-found")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	ctx := context.Background()
	client := NewInternalAPIClient(httpClient, baseURL, hmacKey, pat)
	repo, err := client.GetRepository(ctx, 12345)
	require.Nil(t, repo)
	require.Error(t, err)
	require.ErrorIs(t, err, github.ErrRepoNotFound)
}

func assertRepo(t *testing.T, repo *github.Repository) {
	t.Helper()
	expectedDate := time.Date(2022, time.August, 26, 17, 15, 13, 0, time.UTC)
	require.EqualValues(t, 1, repo.ID)
	require.EqualValues(t, 1, repo.NetworkID)
	require.EqualValues(t, 4, repo.OwnerID)
	require.Equal(t, "github", repo.OwnerLogin)
	require.False(t, repo.OwnerSpammy)
	require.Equal(t, "private-server", repo.Name)
	require.False(t, repo.Public)
	require.False(t, repo.Archived)
	require.EqualValues(t, 0, repo.DiskUsage)
	require.Equal(t, expectedDate, repo.PushedAt)
	require.Equal(t, expectedDate, repo.CreatedAt)
	require.Equal(t, "MIT License", repo.LicenseName)
	require.EqualValues(t, 1, repo.NumWatchers)
	require.EqualValues(t, 2, repo.NumStars)
	require.False(t, repo.HasReadme)
	require.EqualValues(t, 0, repo.PublicForkCount)
	require.Equal(t, "1", repo.Experiments["blackbird_enable_code_embedding"])
}
