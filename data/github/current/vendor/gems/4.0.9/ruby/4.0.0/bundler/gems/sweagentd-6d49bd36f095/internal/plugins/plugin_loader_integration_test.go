package plugins

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestPluginLoader_Integration drives a realistic settings.json (kept as a
// canonical fixture in github/cca-automated-testing) through the full
// LoadRepoSettings -> ResolvePluginRepos pipeline. Each subtest covers one
// enabledPlugins source variant the CCA plugin loader supports.
func TestPluginLoader_Integration(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	settingsBlob, err := os.ReadFile(filepath.Join("testdata", "bugbash_settings.json"))
	require.NoError(t, err)
	marketplaceBlob, err := os.ReadFile(filepath.Join("testdata", "bugbash_marketplace_git.json"))
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(1, ".github/copilot/settings.json", settingsBlob),
		spokestest.WithRepoBlob(2, "marketplace.json", marketplaceBlob),
		spokestest.WithMockGetObjectIDForRef(func(_ context.Context, repoID uint64, ref string) (string, error) {
			if repoID == 2 && ref == "main" {
				return "marketplace-oid", nil
			}
			return "", errors.New("no such ref: " + ref)
		}),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(_ context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		// Only the configured git-marketplace target resolves.
		if slices.Contains(req.GetNwos(), "github/test-marketplace-git") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: 2, Name: "test-marketplace-git", OwnerLogin: "github"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings, err := svc.LoadRepoSettings(ctx, 1)
	require.NoError(t, err)
	require.NotNil(t, settings)

	metas, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)

	t.Run("LoadRepoSettings parses the full settings.json", func(t *testing.T) {
		assert.Len(t, settings.EnabledPlugins, 19)
		assert.Contains(t, settings.ExtraKnownMarketplaces, "git-marketplace")
		assert.Contains(t, settings.ExtraKnownMarketplaces, "broken-marketplace")
		assert.Contains(t, settings.ExtraKnownMarketplaces, "bad-ref-marketplace")
		assert.False(t, settings.EnabledPlugins["my-custom-plugin@my-marketplace"])
	})

	t.Run("resolves GitHub owner/repo specs with and without subpaths", func(t *testing.T) {
		assertResolved(t, metas, "https://github.com/github/test-plugin-repo", "")
		assertResolved(t, metas, "https://github.com/github/test-plugin-repo", "plugins/subdir-plugin")
		assertResolved(t, metas, "https://github.com/github/test-plugin-repo", "plugins/another-subdir")
		// Non-existent repos still resolve; clone errors surface later.
		assertResolved(t, metas, "https://github.com/github/nonexistent-repo-12345", "")
	})

	t.Run("resolves GitHub URL scheme variants verbatim and rejects non-GitHub hosts", func(t *testing.T) {
		assertResolved(t, metas, "https://github.com/github/test-plugin-https.git", "")
		assertResolved(t, metas, "http://github.com/github/test-plugin-http.git", "")
		assertResolved(t, metas, "ssh://github.com/github/test-plugin-ssh.git", "")
		assertResolved(t, metas, "git@github.com:github/test-plugin-git-at.git", "")
		assert.Nil(t, findResolved(metas, "https://gitlab.com/someone/some-plugin.git", ""))
	})

	t.Run("resolves marketplace plugin to local path in marketplace repo", func(t *testing.T) {
		meta := assertResolved(t, metas, "https://github.com/github/test-marketplace-git.git", "plugins/marketplace-git-local-plugin")
		assert.Equal(t, "test-marketplace-git", meta.MarketplaceName)
		assert.Equal(t, "git-plugin", meta.MarketplacePluginName)
		assert.Equal(t, "marketplace-oid", meta.SHA)
	})

	t.Run("skips unknown, broken, and bad-ref marketplaces", func(t *testing.T) {
		assert.Nil(t, findResolved(metas, "https://github.com/github/nonexistent-marketplace-repo.git", ""))
		for _, m := range metas {
			assert.NotContains(t, m.Path, "does-not-exist")
		}
	})

	t.Run("accepts relative local paths and normalizes absolute paths", func(t *testing.T) {
		assertResolved(t, metas, "", ".")
		assertResolved(t, metas, "", "./local-plugin")
		// `/tmp/absolute-plugin` is normalized to `./tmp/absolute-plugin`.
		assertResolved(t, metas, "", "./tmp/absolute-plugin")
		assert.Nil(t, findResolved(metas, "", "/tmp/absolute-plugin"))
	})

	t.Run("skips plugins set to false", func(t *testing.T) {
		for _, m := range metas {
			assert.NotContains(t, m.Path, "my-custom-plugin")
		}
	})

	t.Run("rejects ../escape-attempt traversal as unsafe local path", func(t *testing.T) {
		assert.Nil(t, findResolved(metas, "https://github.com/../escape-attempt", ""))
		assert.Nil(t, findResolved(metas, "", "../escape-attempt"))
	})
}

// findResolved returns the resolved PluginMetadata matching (cloneURL, path),
// or nil if no match exists.
func findResolved(metas []PluginMetadata, cloneURL, path string) *PluginMetadata {
	for i := range metas {
		if metas[i].CloneURL == cloneURL && metas[i].Path == path {
			return &metas[i]
		}
	}
	return nil
}

// assertResolved fails the test if no PluginMetadata matches (cloneURL, path)
// and returns the match for further assertions.
func assertResolved(t *testing.T, metas []PluginMetadata, cloneURL, path string) PluginMetadata {
	t.Helper()
	m := findResolved(metas, cloneURL, path)
	require.NotNilf(t, m, "expected resolved plugin with CloneURL=%q Path=%q", cloneURL, path)
	return *m
}
