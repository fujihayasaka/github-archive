package plugins

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// =============================================================================
// GitHub Spec Tests
// =============================================================================

func TestResolvePluginRepos_GitHubSpec_Basic(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"owner/repo": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/owner/repo", repos[0].CloneURL)
	assert.Equal(t, "", repos[0].Path)
	assert.Equal(t, "", repos[0].MarketplaceName, "non-marketplace plugins should have empty MarketplaceName")
}

func TestResolvePluginRepos_GitHubSpec_WithPath(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name         string
		spec         string
		expectedURL  string
		expectedPath string
	}{
		{
			name:         "simple path",
			spec:         "owner/repo:plugins/myplugin",
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "plugins/myplugin",
		},
		{
			name:         "nested path",
			spec:         "owner/repo:src/plugins/deep/path",
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "src/plugins/deep/path",
		},
		{
			name:         "single directory path",
			spec:         "owner/repo:plugins",
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "plugins",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Equal(t, tt.expectedURL, repos[0].CloneURL)
			assert.Equal(t, tt.expectedPath, repos[0].Path)
		})
	}
}

func TestResolvePluginRepos_GitHubSpec_WithGitSuffix(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"owner/repo.git": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	// .git suffix should be stripped
	assert.Equal(t, "https://github.com/owner/repo", repos[0].CloneURL)
}

func TestResolvePluginRepos_GitHubSpec_VariousFormats(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name        string
		spec        string
		expectedURL string
	}{
		{"lowercase", "myorg/myrepo", "https://github.com/myorg/myrepo"},
		{"uppercase", "MyOrg/MyRepo", "https://github.com/MyOrg/MyRepo"},
		{"mixed case", "GitHub/copilot-Plugins", "https://github.com/GitHub/copilot-Plugins"},
		{"with numbers", "org123/repo456", "https://github.com/org123/repo456"},
		{"with hyphens", "my-org/my-repo", "https://github.com/my-org/my-repo"},
		{"with underscores", "my_org/my_repo", "https://github.com/my_org/my_repo"},
		{"with dots", "my.org/my.repo", "https://github.com/my.org/my.repo"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Equal(t, tt.expectedURL, repos[0].CloneURL)
		})
	}
}

func TestResolvePluginRepos_GitHubSpec_Invalid(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	t.Run("empty string", func(t *testing.T) {
		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"": true},
		}
		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		// Empty string parses as marketplace with empty plugin name → failure entry
		require.Len(t, repos, 1)
		assert.Contains(t, repos[0].ResolutionFailure, "empty plugin name")
	})

	t.Run("just owner", func(t *testing.T) {
		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"owner": true},
		}
		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		// "owner" parses as bare marketplace name → produces a failure entry
		require.Len(t, repos, 1)
		assert.NotEmpty(t, repos[0].ResolutionFailure)
		assert.Equal(t, "owner", repos[0].Spec)
	})

	t.Run("trailing slash", func(t *testing.T) {
		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"owner/": true},
		}
		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		// "owner/" parses as GitHub spec but repo is empty → falls through to marketplace
		require.Len(t, repos, 1)
		assert.NotEmpty(t, repos[0].ResolutionFailure)
		assert.Equal(t, "owner/", repos[0].Spec)
	})

	t.Run("leading slash", func(t *testing.T) {
		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"/repo": true},
		}
		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		// "/repo" is normalized to "./repo" and treated as a valid local path
		require.Len(t, repos, 1)
		assert.Equal(t, "", repos[0].CloneURL, "local plugins have empty CloneURL")
		assert.Equal(t, "./repo", repos[0].Path, "leading slash should be normalized to ./")
	})
}

// =============================================================================
// URL Spec Tests
// =============================================================================

func TestResolvePluginRepos_URLSpec_GitHub(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name        string
		spec        string
		expectedURL string
	}{
		{
			name:        "https github url",
			spec:        "https://github.com/myorg/myplugin",
			expectedURL: "https://github.com/myorg/myplugin",
		},
		{
			name:        "https github url with .git",
			spec:        "https://github.com/myorg/myplugin.git",
			expectedURL: "https://github.com/myorg/myplugin.git",
		},
		{
			name:        "ssh url",
			spec:        "ssh://git@github.com/myorg/myplugin",
			expectedURL: "ssh://git@github.com/myorg/myplugin",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Equal(t, tt.expectedURL, repos[0].CloneURL)
		})
	}
}

func TestResolvePluginRepos_URLSpec_NonGitHub(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name string
		spec string
	}{
		{
			name: "gitlab url",
			spec: "https://gitlab.com/myorg/myplugin",
		},
		{
			name: "bitbucket url",
			spec: "https://bitbucket.org/myorg/myplugin",
		},
		{
			name: "custom domain",
			spec: "https://git.mycompany.com/plugins/tool",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Empty(t, repos[0].CloneURL, "non-GitHub URL should not have clone URL")
			assert.Equal(t, tt.spec, repos[0].Spec)
			assert.Contains(t, repos[0].ResolutionFailure, "not hosted on GitHub")
		})
	}
}

// =============================================================================
// Local Spec Tests
// =============================================================================

func TestResolvePluginRepos_LocalSpec_Included(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name     string
		spec     string
		wantPath string
	}{
		{"current dir relative", "./plugins/myplugin", "./plugins/myplugin"},
		{"deeply nested", "./a/b/c/d/e", "./a/b/c/d/e"},
		{"just dot slash", "./", "./"},
		{"just dot", ".", "."},
		{"absolute path normalized", "/plugins/myplugin", "./plugins/myplugin"},
		{"absolute root normalized", "/", "./"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1, "local specs should be included with empty CloneURL")
			assert.Equal(t, "", repos[0].CloneURL, "local plugins have empty CloneURL")
			assert.Equal(t, tt.wantPath, repos[0].Path, "local plugin path should match normalized spec")
			assert.Equal(t, "", repos[0].MarketplaceName, "local plugins should have empty MarketplaceName")
		})
	}
}

// TestResolvePluginRepos_LocalPathSafety verifies the full accept/reject matrix for local path specs
// through the entire ResolvePluginRepos flow:
//
//	./ prefix   → accepted
//	.           → accepted
//	single /    → normalized to ./ and accepted
//	//          → rejected (invalid path)
//	../         → rejected (traversal)
func TestResolvePluginRepos_LocalPathSafety(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name        string
		spec        string
		wantPath    string // expected Path for accepted specs
		wantFailure bool   // true if spec should produce a ResolutionFailure
	}{
		// Accepted: ./ prefix resolves relative to repo root
		{"dot-slash relative", "./plugins/myplugin", "./plugins/myplugin", false},
		{"dot-slash root", "./", "./", false},
		{"just dot", ".", ".", false},

		// Accepted: single leading / normalized to ./
		{"single leading slash", "/plugins/myplugin", "./plugins/myplugin", false},
		{"bare root slash", "/", "./", false},

		// Rejected: multiple leading slashes
		{"double leading slashes", "//plugins/myplugin", "", true},
		{"triple leading slashes", "///a/b", "", true},

		// Rejected: parent traversal
		{"parent traversal with path", "../plugins/myplugin", "", true},
		{"bare parent dir", "..", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)

			if tt.wantFailure {
				assert.Contains(t, repos[0].ResolutionFailure, "invalid local plugin path")
				assert.Empty(t, repos[0].CloneURL)
				assert.Empty(t, repos[0].Path)
			} else {
				assert.Empty(t, repos[0].ResolutionFailure)
				assert.Empty(t, repos[0].CloneURL, "local plugins have empty CloneURL")
				assert.Equal(t, tt.wantPath, repos[0].Path)
			}
		})
	}
}

// =============================================================================
// Marketplace Spec Tests
// =============================================================================

func TestResolvePluginRepos_MarketplaceSpec_ExternalRepo(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"sentry": {
				Name: "sentry",
				Source: PluginSource{
					Source: "github",
					Repo:   "sentry-io/sentry-mcp",
				},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"sentry@copilot-plugins": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/sentry-io/sentry-mcp", repos[0].CloneURL)
	assert.Equal(t, "", repos[0].Path)
	assert.Equal(t, "copilot-plugins", repos[0].MarketplaceName)
}

func TestResolvePluginRepos_MarketplaceSpec_LocalToMarketplace(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"builtin-tool": {
				Name: "builtin-tool",
				Source: PluginSource{
					Source: "plugins/builtin-tool",
				},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"builtin-tool@copilot-plugins": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/github/copilot-plugins", repos[0].CloneURL)
	assert.Equal(t, "plugins/builtin-tool", repos[0].Path)
	assert.Equal(t, "copilot-plugins", repos[0].MarketplaceName)
}

func TestResolvePluginRepos_MarketplaceSpec_URLSource(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"external-tool": {
				Name: "external-tool",
				Source: PluginSource{
					Source: "url",
					URL:    "https://gitlab.com/external/tool",
				},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"external-tool@copilot-plugins": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Empty(t, repos[0].CloneURL, "non-GitHub marketplace URL source should not produce a clone URL")
	assert.Equal(t, "external-tool@copilot-plugins", repos[0].Spec)
	assert.Contains(t, repos[0].ResolutionFailure, "not hosted on GitHub")
}

func TestResolvePluginRepos_MarketplaceSpec_UnknownMarketplace(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"plugin@unknown-marketplace": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1, "unknown marketplace should produce a failure entry")
	assert.Equal(t, "plugin@unknown-marketplace", repos[0].Spec)
	assert.Contains(t, repos[0].ResolutionFailure, "unknown marketplace")
}

func TestResolvePluginRepos_MarketplaceSpec_PluginNotInMarketplace(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"existing-plugin": {
				Name:   "existing-plugin",
				Source: PluginSource{Source: "github", Repo: "org/existing"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"nonexistent-plugin@copilot-plugins": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1, "plugin not in marketplace should produce a failure entry")
	assert.Equal(t, "nonexistent-plugin@copilot-plugins", repos[0].Spec)
	assert.Contains(t, repos[0].ResolutionFailure, "not found in marketplace")
}

func TestResolvePluginRepos_MarketplaceSpec_MarketplaceRepoNotFound(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return nil, errors.New("repository not found")
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"sentry@copilot-plugins": true,
		},
	}

	// Should not fail, but should produce a failure entry
	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "sentry@copilot-plugins", repos[0].Spec)
	assert.Contains(t, repos[0].ResolutionFailure, "unexpected error resolving marketplace plugin")
}

func TestResolvePluginRepos_MarketplaceSpec_InvalidMarketplaceJSON(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	// Invalid JSON
	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", []byte("not valid json {")),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"sentry@copilot-plugins": true,
		},
	}

	// Should not fail, but should produce a failure entry
	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "sentry@copilot-plugins", repos[0].Spec)
	assert.Contains(t, repos[0].ResolutionFailure, "unexpected error resolving marketplace plugin")
}

func TestResolvePluginRepos_MarketplaceSpec_PluginWithNoSource(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"no-source": {
				Name:   "no-source",
				Source: PluginSource{}, // Empty source
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"no-source@copilot-plugins": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1, "plugin with no source should produce a failure entry")
	assert.Equal(t, "no-source@copilot-plugins", repos[0].Spec)
	assert.Contains(t, repos[0].ResolutionFailure, "empty source")
}

func TestResolvePluginRepos_MarketplaceSpec_ExtraMarketplaces(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "my-marketplace",
		Plugins: map[string]PluginEntry{
			"custom-plugin": {
				Name:   "custom-plugin",
				Source: PluginSource{Source: "github", Repo: "myorg/custom-plugin"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(456, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 456, Name: "my-marketplace-repo", OwnerLogin: "myorg"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"custom-plugin@my-marketplace": true,
		},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"my-marketplace": {
				Source: MarketplaceSourceConfig{
					Source: "github",
					Repo:   "myorg/my-marketplace-repo",
				},
			},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/myorg/custom-plugin", repos[0].CloneURL)
	assert.Equal(t, "my-marketplace", repos[0].MarketplaceName)
}

func TestResolvePluginRepos_MarketplaceSpec_CachesMarketplaceData(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"plugin1": {Name: "plugin1", Source: PluginSource{Source: "github", Repo: "org/plugin1"}},
			"plugin2": {Name: "plugin2", Source: PluginSource{Source: "github", Repo: "org/plugin2"}},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	fetchCount := 0
	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		fetchCount++
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"plugin1@copilot-plugins": true,
			"plugin2@copilot-plugins": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	assert.Len(t, repos, 2)
	// Should only fetch marketplace once
	assert.Equal(t, 1, fetchCount, "marketplace should be cached and fetched only once")
}

// =============================================================================
// Deduplication Tests
// =============================================================================

func TestResolvePluginRepos_DuplicateURL_ProducesSeparateEntries(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"owner/repo":                    true,
			"https://github.com/owner/repo": true, // Same repo, different spec
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	assert.Len(t, repos, 2, "each enabled spec should produce its own entry; runtime handles clone dedup")
	// Both should resolve to the same clone URL
	for _, r := range repos {
		assert.Equal(t, "https://github.com/owner/repo", r.CloneURL)
	}
}

func TestResolvePluginRepos_MarketplaceAndDirect_ProducesSeparateEntries(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"sentry": {
				Name:   "sentry",
				Source: PluginSource{Source: "github", Repo: "sentry-io/sentry-mcp"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"sentry@copilot-plugins": true,
			"sentry-io/sentry-mcp":   true, // Same repo as marketplace resolution
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	assert.Len(t, repos, 2, "each enabled spec should produce its own entry; runtime handles clone dedup")
	// Both should resolve to the same clone URL
	for _, r := range repos {
		assert.Equal(t, "https://github.com/sentry-io/sentry-mcp", r.CloneURL)
	}
}

// =============================================================================
// Mixed Spec Tests
// =============================================================================

func TestResolvePluginRepos_MixedSpecs(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "copilot-plugins",
		Plugins: map[string]PluginEntry{
			"marketplace-plugin": {
				Name:   "marketplace-plugin",
				Source: PluginSource{Source: "github", Repo: "marketplace/plugin"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			// GitHub spec
			"owner/github-plugin": true,
			// URL spec
			"https://github.com/owner/url-plugin": true,
			// Marketplace spec
			"marketplace-plugin@copilot-plugins": true,
			// Local spec (should be included with empty CloneURL)
			"./local/plugin": true,
			// Disabled
			"disabled/plugin": false,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	assert.Len(t, repos, 4, "should include github, url, marketplace, and local plugins")

	// Verify all expected repos are present
	cloneURLs := make(map[string]bool)
	localPaths := make(map[string]bool)
	marketplaceNames := make(map[string]string) // cloneURL/path -> marketplace name
	for _, r := range repos {
		if r.CloneURL != "" {
			cloneURLs[r.CloneURL] = true
			marketplaceNames[r.CloneURL] = r.MarketplaceName
		} else {
			localPaths[r.Path] = true
			marketplaceNames[r.Path] = r.MarketplaceName
		}
	}
	assert.True(t, cloneURLs["https://github.com/owner/github-plugin"], "github spec should be resolved")
	assert.True(t, cloneURLs["https://github.com/owner/url-plugin"], "url spec should be resolved")
	assert.True(t, cloneURLs["https://github.com/marketplace/plugin"], "marketplace spec should be resolved")
	assert.True(t, localPaths["./local/plugin"], "local spec should be included")

	// Verify MarketplaceName is set only for marketplace-resolved plugins
	assert.Equal(t, "", marketplaceNames["https://github.com/owner/github-plugin"], "github spec should have empty MarketplaceName")
	assert.Equal(t, "", marketplaceNames["https://github.com/owner/url-plugin"], "url spec should have empty MarketplaceName")
	assert.Equal(t, "copilot-plugins", marketplaceNames["https://github.com/marketplace/plugin"], "marketplace spec should have MarketplaceName set")
	assert.Equal(t, "", marketplaceNames["./local/plugin"], "local spec should have empty MarketplaceName")
}

// =============================================================================
// Edge Cases and Error Handling
// =============================================================================

func TestResolvePluginRepos_NilSettings(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	repos, err := svc.ResolvePluginRepos(ctx, nil)
	require.NoError(t, err)
	assert.Nil(t, repos)
}

func TestResolvePluginRepos_EmptySettings(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	assert.Nil(t, repos)
}

func TestResolvePluginRepos_OnlyRejectedPlugins_NotSkipped(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:  map[string]bool{},
		RejectedPlugins: map[string]string{"./my-plugin": "some rejection reason"},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "./my-plugin", repos[0].Spec)
	assert.Equal(t, "some rejection reason", repos[0].ResolutionFailure)
}

func TestResolvePluginRepos_RejectedPlugins_EmitResolutionFailure(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"owner/valid-plugin": true,
		},
		RejectedPlugins: map[string]string{
			"./org-local-plugin": "local plugins from org .github-private sources cannot be used in the CCA environment",
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 2)

	var validPlugin, rejectedPlugin *PluginMetadata
	for i := range repos {
		switch repos[i].Spec {
		case "owner/valid-plugin":
			validPlugin = &repos[i]
		case "./org-local-plugin":
			rejectedPlugin = &repos[i]
		default:
			// ignore other specs
		}
	}
	require.NotNil(t, validPlugin, "valid plugin should be present")
	require.NotNil(t, rejectedPlugin, "rejected plugin should be present")

	assert.Equal(t, "https://github.com/owner/valid-plugin", validPlugin.CloneURL)
	assert.Empty(t, validPlugin.ResolutionFailure)

	assert.Empty(t, rejectedPlugin.CloneURL)
	assert.Empty(t, rejectedPlugin.Path)
	assert.Contains(t, rejectedPlugin.ResolutionFailure, ".github-private")
}

func TestResolvePluginRepos_AllDisabled(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"owner/repo1": false,
			"owner/repo2": false,
			"owner/repo3": false,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	assert.Len(t, repos, 0)
}

func TestResolvePluginRepos_PartialFailure_MarketplaceContinues(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	// Only one marketplace has valid data
	marketplaceData := MarketplaceData{
		Name: "good-marketplace",
		Plugins: map[string]PluginEntry{
			"good-plugin": {
				Name:   "good-plugin",
				Source: PluginSource{Source: "github", Repo: "org/good-plugin"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(456, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		// Check which repo is being requested
		if len(req.Nwos) > 0 {
			nwo := req.Nwos[0]
			// The default copilot-plugins marketplace fails
			if nwo == "github/copilot-plugins" {
				return nil, errors.New("not found")
			}
			// The custom good-marketplace succeeds
			if nwo == "org/good-marketplace-repo" {
				return &repositoriesTwirp.FindRepositoriesByNameResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{Id: 456, Name: "good-marketplace-repo", OwnerLogin: "org"},
					},
				}, nil
			}
		}
		return nil, errors.New("repo not found")
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"bad-plugin@copilot-plugins":   true, // Will fail
			"good-plugin@good-marketplace": true, // Will succeed
		},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"good-marketplace": {
				Source: MarketplaceSourceConfig{
					Source: "github",
					Repo:   "org/good-marketplace-repo",
				},
			},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	// Should have 2 entries: 1 failure + 1 success
	assert.Len(t, repos, 2)

	// Find the successful and failed entries
	var successCount, failCount int
	for _, r := range repos {
		if r.ResolutionFailure != "" {
			failCount++
			assert.Contains(t, r.ResolutionFailure, "unexpected error resolving marketplace plugin")
		} else {
			successCount++
			assert.Equal(t, "https://github.com/org/good-plugin", r.CloneURL)
		}
	}
	assert.Equal(t, 1, successCount, "should have 1 successful plugin")
	assert.Equal(t, 1, failCount, "should have 1 failed plugin")
}

func TestResolvePluginRepos_PreservesOriginalSpec(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"owner/repo:custom/path": true,
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/owner/repo", repos[0].CloneURL)
	assert.Equal(t, "custom/path", repos[0].Path)
}

func TestResolvePluginRepos_DirectorySourceSkipped(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	// Directory source should be skipped with a warning
	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"my-plugin@local-marketplace": true,
		},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"local-marketplace": {
				Source: MarketplaceSourceConfig{
					Source: "directory",
					Path:   "/some/local/path",
				},
			},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	// Directory source is skipped and marketplace removed, so plugin gets a failure entry for unknown marketplace
	require.Len(t, repos, 1)
	assert.Equal(t, "my-plugin@local-marketplace", repos[0].Spec)
	assert.NotEmpty(t, repos[0].ResolutionFailure)
}

func TestResolvePluginRepos_GitURLSource(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "git-marketplace",
		Plugins: map[string]PluginEntry{
			"git-plugin": {
				Name: "git-plugin",
				Source: PluginSource{
					Source: "github",
					Repo:   "external/plugin-repo",
				},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "marketplace-repo", OwnerLogin: "myorg"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"git-plugin@git-marketplace": true,
		},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"git-marketplace": {
				Source: MarketplaceSourceConfig{
					Source: "git",
					URL:    "https://github.com/myorg/marketplace-repo.git",
					Ref:    "main",
				},
			},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
	assert.Equal(t, "git-marketplace", repos[0].MarketplaceName)
}

func TestResolvePluginRepos_MarketplaceSpec_DotGitHubPluginPath(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "my-marketplace",
		Plugins: map[string]PluginEntry{
			"my-plugin": {
				Name:   "my-plugin",
				Source: PluginSource{Source: "github", Repo: "external/plugin-repo"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	// Register marketplace.json at ".github/plugin/marketplace.json" only (not at root)
	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, ".github/plugin/marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "copilot-plugins", OwnerLogin: "github"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"my-plugin@my-marketplace": true,
		},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"my-marketplace": {
				Source: MarketplaceSourceConfig{
					Source: "github",
					Repo:   "github/copilot-plugins",
				},
			},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
	assert.Equal(t, "my-marketplace", repos[0].MarketplaceName)
}

func TestResolvePluginRepos_MarketplaceSpec_SourcePathSubdir(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name: "my-marketplace",
		Plugins: map[string]PluginEntry{
			"my-plugin": {
				Name:   "my-plugin",
				Source: PluginSource{Source: "github", Repo: "external/plugin-repo"},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	// Register marketplace.json under a subdirectory only (not at root).
	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "vendored/marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "marketplace", OwnerLogin: "org"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"my-marketplace": {
				Source: MarketplaceSourceConfig{
					Source: "github",
					Repo:   "org/marketplace",
					Path:   "vendored",
				},
			},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
}

func TestResolvePluginRepos_MarketplaceSpec_SourcePathDotResolvesToRoot(t *testing.T) {
	// A Path that cleans to "." (e.g. ".", "./", "foo/..") is harmless and should
	// resolve to the repo-root candidates rather than being rejected as unsafe.
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	marketplaceData := MarketplaceData{
		Name:    "my-marketplace",
		Plugins: map[string]PluginEntry{"my-plugin": {Name: "my-plugin", Source: PluginSource{Source: "github", Repo: "external/plugin-repo"}}},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "marketplace", OwnerLogin: "org"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	for _, p := range []string{".", "./", "foo/.."} {
		t.Run(p, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
				ExtraKnownMarketplaces: map[string]ExtraMarketplace{
					"my-marketplace": {
						Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace", Path: p},
					},
				},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Empty(t, repos[0].ResolutionFailure)
			assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
		})
	}
}

func TestResolvePluginRepos_MarketplaceSpec_SourcePathUnsafeRejected(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	// Marketplace.json exists at the root, but the source.Path is a traversal — the
	// fetch must fail closed rather than fall back to the root.
	marketplaceData := MarketplaceData{
		Name:    "my-marketplace",
		Plugins: map[string]PluginEntry{"my-plugin": {Name: "my-plugin", Source: PluginSource{Source: "github", Repo: "external/plugin-repo"}}},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	spokes := spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123, Name: "marketplace", OwnerLogin: "org"},
			},
		}, nil
	}

	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	for _, badPath := range []string{"../escape", "/etc", ".."} {
		t.Run(badPath, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
				ExtraKnownMarketplaces: map[string]ExtraMarketplace{
					"my-marketplace": {
						Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace", Path: badPath},
					},
				},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Contains(t, repos[0].ResolutionFailure, "invalid marketplace path")
		})
	}
}

// =============================================================================
// Org Settings Tests
// =============================================================================

func TestLoadOrgSettings_ReadsFromDotGitHubRepo(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	orgRepoID := uint64(500)
	orgSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"org-plugin@copilot-plugins": true},
	}
	orgBlob, err := json.Marshal(orgSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", orgBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["org-plugin@copilot-plugins"])
}

func TestLoadOrgSettings_EmptyWhenNoOrgRepo(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokesClient := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "no-org")
	require.NoError(t, err)
	assert.Empty(t, settings.EnabledPlugins)
}

// =============================================================================
// Enterprise Settings Tests
// =============================================================================

func TestLoadEnterpriseSettings_ReadsFromEnterpriseRepo(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	enterpriseRepoID := uint64(900)
	entSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"enterprise-plugin": true},
	}
	entBlob, err := json.Marshal(entSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(enterpriseRepoID, "copilot/settings.json", entBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: enterpriseRepoID}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadEnterpriseSettings(ctx, 123)
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["enterprise-plugin"])
}

func TestLoadEnterpriseSettings_EmptyWhenNoEnterprise(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokesClient := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadEnterpriseSettings(ctx, 999)
	require.NoError(t, err)
	assert.Empty(t, settings.EnabledPlugins)
}

// =============================================================================
// Merged Settings Tests
// =============================================================================

func TestLoadMergedSettings_EnterpriseOverridesOrgOverridesRepo(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	orgRepoID := uint64(500)
	enterpriseRepoID := uint64(900)

	repoSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"plugin-a": true, "plugin-b": true},
	}
	repoBlob, err := json.Marshal(repoSettingsData)
	require.NoError(t, err)

	orgSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"plugin-b": false, "plugin-c": true},
	}
	orgBlob, err := json.Marshal(orgSettingsData)
	require.NoError(t, err)

	entSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"plugin-c": false},
	}
	entBlob, err := json.Marshal(entSettingsData)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
		spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", orgBlob),
		spokestest.WithRepoBlob(enterpriseRepoID, "copilot/settings.json", entBlob),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: enterpriseRepoID}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", []string{SourceTypeRepo, SourceTypeOrg, SourceTypeEnterprise})
	require.NoError(t, err)

	// plugin-a: enabled by repo, not overridden → true
	assert.True(t, settings.EnabledPlugins["plugin-a"])
	// plugin-b: enabled by repo, disabled by org → false
	assert.False(t, settings.EnabledPlugins["plugin-b"])
	// plugin-c: enabled by org, disabled by enterprise → false
	assert.False(t, settings.EnabledPlugins["plugin-c"])
}

func TestLoadMergedSettings_NilSourcesDefaultsToAllLevels(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	repoSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"repo-plugin": true},
	}
	repoBlob, err := json.Marshal(repoSettingsData)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
	)
	ghTwirp := githubtwirp.NewNoopClient()

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	// nil includeSources defaults to all levels (repo, org, enterprise)
	settings, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", nil)
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["repo-plugin"])
}

func TestLoadMergedSettings_RepoOnlySkipsOrgAndEnterprise(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	repoSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"repo-plugin": true},
	}
	repoBlob, err := json.Marshal(repoSettingsData)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
	)
	ghTwirp := githubtwirp.NewNoopClient()

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", []string{SourceTypeRepo})
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["repo-plugin"])
	assert.Len(t, settings.EnabledPlugins, 1)
}

func TestLoadOrgSettings_ReadsFromDotGitHubPrivateRepo(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	privateRepoID := uint64(501)
	orgSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"private-plugin": true},
	}
	orgBlob, err := json.Marshal(orgSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(privateRepoID, "copilot/settings.json", orgBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github-private") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(privateRepoID), Name: ".github-private", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["private-plugin"])
}

func TestLoadOrgSettings_PrivateOverridesPublic(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	publicRepoID := uint64(500)
	privateRepoID := uint64(501)

	publicSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"shared-plugin": true},
	}
	publicBlob, err := json.Marshal(publicSettings)
	require.NoError(t, err)

	privateSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"shared-plugin": false},
	}
	privateBlob, err := json.Marshal(privateSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(publicRepoID, "copilot/settings.json", publicBlob),
		spokestest.WithRepoBlob(privateRepoID, "copilot/settings.json", privateBlob),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		var repos []*repositoriesTwirp.RepositoryListItem
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			repos = append(repos, &repositoriesTwirp.RepositoryListItem{Id: int64(publicRepoID), Name: ".github", OwnerLogin: "my-org"})
		}
		if slices.Contains(req.GetNwos(), "my-org/.github-private") {
			repos = append(repos, &repositoriesTwirp.RepositoryListItem{Id: int64(privateRepoID), Name: ".github-private", OwnerLogin: "my-org"})
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{Repositories: repos}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)
	// .github-private is iterated after .github, so it wins on collision
	assert.False(t, settings.EnabledPlugins["shared-plugin"])
}

func TestLoadOrgSettings_LocalPlugin_DotGitHub_ConvertedToRemote(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	publicRepoID := uint64(500)
	orgSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{
			"./my-local-plugin":             true,
			"./plugins/nested":              true,
			".":                             true,
			"remote-plugin@copilot-plugins": true,
			"../traversal-path":             true,
		},
	}
	orgBlob, err := json.Marshal(orgSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(publicRepoID, "copilot/settings.json", orgBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(publicRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)

	// Local specs should be converted to GitHub specs pointing to the org's .github repo
	assert.True(t, settings.EnabledPlugins["my-org/.github:my-local-plugin"], "simple local path converted to GitHub spec")
	assert.True(t, settings.EnabledPlugins["my-org/.github:plugins/nested"], "nested local path converted to GitHub spec")
	assert.True(t, settings.EnabledPlugins["my-org/.github"], "root local path converted to bare owner/repo spec")

	// Original local specs should no longer be present
	assert.NotContains(t, settings.EnabledPlugins, "./my-local-plugin")
	assert.NotContains(t, settings.EnabledPlugins, "./plugins/nested")
	assert.NotContains(t, settings.EnabledPlugins, ".")

	// Traversal path is unsafe but we convert blindly, since the runtime is equipped to catch remote plugins w/ bad paths
	assert.True(t, settings.EnabledPlugins["my-org/.github:../traversal-path"], "traversal path converted; runtime will block the escape")
	assert.NotContains(t, settings.EnabledPlugins, "../traversal-path")

	// Non-local plugins remain unchanged
	assert.True(t, settings.EnabledPlugins["remote-plugin@copilot-plugins"])

	// No rejections for public .github
	assert.Empty(t, settings.RejectedPlugins)
}

func TestLoadOrgSettings_LocalPlugin_DotGitHubPrivate_Rejected(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	privateRepoID := uint64(501)
	orgSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{
			"./my-local-plugin": true,
			"./disabled-local":  false,
			"remote-plugin":     true,
		},
	}
	orgBlob, err := json.Marshal(orgSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(privateRepoID, "copilot/settings.json", orgBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github-private") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(privateRepoID), Name: ".github-private", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)

	// Enabled local spec should be rejected
	assert.Contains(t, settings.RejectedPlugins, "./my-local-plugin")
	assert.Contains(t, settings.RejectedPlugins["./my-local-plugin"], ".github-private")

	// Disabled local spec should NOT be rejected (only enabled specs are processed)
	assert.NotContains(t, settings.RejectedPlugins, "./disabled-local")

	// Local spec removed from EnabledPlugins
	assert.NotContains(t, settings.EnabledPlugins, "./my-local-plugin")

	// Non-local plugin remains
	assert.True(t, settings.EnabledPlugins["remote-plugin"])
}

func TestLoadEnterpriseSettings_NotFoundReturnsEmpty(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokesClient := spokestest.NewClient(t)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return nil, twirp.NotFoundError("no enterprise")
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadEnterpriseSettings(ctx, 999)
	require.NoError(t, err)
	assert.Empty(t, settings.EnabledPlugins)
}

func TestLoadEnterpriseSettings_ZeroRepoIDReturnsEmpty(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokesClient := spokestest.NewClient(t)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: 0}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadEnterpriseSettings(ctx, 123)
	require.NoError(t, err)
	assert.Empty(t, settings.EnabledPlugins)
}

func TestLoadEnterpriseSettings_LocalPlugin_Rejected(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	enterpriseRepoID := uint64(900)
	entSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{
			"./my-local-plugin": true,
			"./disabled-local":  false,
			"remote-plugin":     true,
		},
	}
	entBlob, err := json.Marshal(entSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(enterpriseRepoID, "copilot/settings.json", entBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: enterpriseRepoID}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadEnterpriseSettings(ctx, 123)
	require.NoError(t, err)

	// Enabled local spec should be rejected
	assert.Contains(t, settings.RejectedPlugins, "./my-local-plugin")
	assert.Contains(t, settings.RejectedPlugins["./my-local-plugin"], "enterprise")

	// Disabled local spec should NOT be rejected
	assert.NotContains(t, settings.RejectedPlugins, "./disabled-local")

	// Local spec removed from EnabledPlugins
	assert.NotContains(t, settings.EnabledPlugins, "./my-local-plugin")

	// Non-local plugin remains
	assert.True(t, settings.EnabledPlugins["remote-plugin"])
}

func TestLoadOrgSettings_MalformedJSONReturnsEmpty(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	orgRepoID := uint64(500)
	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", []byte("not valid json")))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)
	assert.Empty(t, settings.EnabledPlugins)
}

func TestLoadMergedSettings_OrgOnlySkipsRepoAndEnterprise(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	orgRepoID := uint64(500)

	repoSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"repo-plugin": true},
	}
	repoBlob, err := json.Marshal(repoSettingsData)
	require.NoError(t, err)

	orgSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"org-plugin": true},
	}
	orgBlob, err := json.Marshal(orgSettingsData)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
		spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", orgBlob),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", []string{SourceTypeOrg})
	require.NoError(t, err)
	// Org plugin should be present
	assert.True(t, settings.EnabledPlugins["org-plugin"])
	// Repo plugin should NOT be loaded
	_, repoPluginPresent := settings.EnabledPlugins["repo-plugin"]
	assert.False(t, repoPluginPresent, "repo settings should not be loaded when only org is requested")
}

func TestLoadMergedSettings_ExtraKnownMarketplacesMerge(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	orgRepoID := uint64(500)

	repoSettingsData := SettingsJSON{
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"repo-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "repo-org/marketplace"}},
			"shared":           {Source: MarketplaceSourceConfig{Source: "github", Repo: "repo-org/shared"}},
		},
	}
	repoBlob, err := json.Marshal(repoSettingsData)
	require.NoError(t, err)

	orgSettingsData := SettingsJSON{
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{
			"org-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"}},
			"shared":          {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/shared-override"}},
		},
	}
	orgBlob, err := json.Marshal(orgSettingsData)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
		spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", orgBlob),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", []string{SourceTypeRepo, SourceTypeOrg})
	require.NoError(t, err)

	// Repo-only marketplace preserved
	assert.Equal(t, "repo-org/marketplace", settings.ExtraKnownMarketplaces["repo-marketplace"].Source.Repo)
	// Org-only marketplace preserved
	assert.Equal(t, "org/marketplace", settings.ExtraKnownMarketplaces["org-marketplace"].Source.Repo)
	// Shared marketplace overridden by org
	assert.Equal(t, "org/shared-override", settings.ExtraKnownMarketplaces["shared"].Source.Repo)
}

func TestLoadMergedSettings_LocalPlugins_OrgAndEnterpriseHandledCorrectly(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	orgPublicRepoID := uint64(500)
	orgPrivateRepoID := uint64(501)
	enterpriseRepoID := uint64(900)

	repoSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"./repo-local": true},
	}
	repoBlob, err := json.Marshal(repoSettingsData)
	require.NoError(t, err)

	orgPublicSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"./public-local": true},
	}
	orgPublicBlob, err := json.Marshal(orgPublicSettingsData)
	require.NoError(t, err)

	orgPrivateSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"./private-local": true},
	}
	orgPrivateBlob, err := json.Marshal(orgPrivateSettingsData)
	require.NoError(t, err)

	entSettingsData := SettingsJSON{
		EnabledPlugins: map[string]bool{"./enterprise-local": true},
	}
	entBlob, err := json.Marshal(entSettingsData)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
		spokestest.WithRepoBlob(orgPublicRepoID, "copilot/settings.json", orgPublicBlob),
		spokestest.WithRepoBlob(orgPrivateRepoID, "copilot/settings.json", orgPrivateBlob),
		spokestest.WithRepoBlob(enterpriseRepoID, "copilot/settings.json", entBlob),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		var repos []*repositoriesTwirp.RepositoryListItem
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			repos = append(repos, &repositoriesTwirp.RepositoryListItem{Id: int64(orgPublicRepoID), Name: ".github", OwnerLogin: "my-org"})
		}
		if slices.Contains(req.GetNwos(), "my-org/.github-private") {
			repos = append(repos, &repositoriesTwirp.RepositoryListItem{Id: int64(orgPrivateRepoID), Name: ".github-private", OwnerLogin: "my-org"})
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{Repositories: repos}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: enterpriseRepoID}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", []string{SourceTypeRepo, SourceTypeOrg, SourceTypeEnterprise})
	require.NoError(t, err)

	// Repo-level local plugin passes through unchanged
	assert.True(t, settings.EnabledPlugins["./repo-local"])

	// Org .github (public) local plugin is converted to a remote GitHub spec
	assert.True(t, settings.EnabledPlugins["my-org/.github:public-local"])
	assert.NotContains(t, settings.EnabledPlugins, "./public-local")

	// Org .github-private and enterprise local plugins are rejected
	assert.Contains(t, settings.RejectedPlugins, "./private-local")
	assert.Contains(t, settings.RejectedPlugins["./private-local"], ".github-private")
	assert.NotContains(t, settings.EnabledPlugins, "./private-local")

	assert.Contains(t, settings.RejectedPlugins, "./enterprise-local")
	assert.Contains(t, settings.RejectedPlugins["./enterprise-local"], "enterprise")
	assert.NotContains(t, settings.EnabledPlugins, "./enterprise-local")
}

// =============================================================================
// StrictKnownMarketplaces Tests
// =============================================================================

func TestStrictKnownMarketplaces_NilAllowsAll(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
	ghTwirp := makeGhTwirpWithMarketplaceRepo()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:          map[string]bool{"my-plugin@my-marketplace": true},
		ExtraKnownMarketplaces:  map[string]ExtraMarketplace{"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"}}},
		StrictKnownMarketplaces: nil, // no restrictions
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
}

func TestStrictKnownMarketplaces_EmptyBlocksAll(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:          map[string]bool{"my-plugin@my-marketplace": true},
		ExtraKnownMarketplaces:  map[string]ExtraMarketplace{"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"}}},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{}, // lockdown
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Contains(t, repos[0].ResolutionFailure, "strictKnownMarketplaces")
}

func TestStrictKnownMarketplaces_AllowlistPermitsMatching(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
	ghTwirp := makeGhTwirpWithMarketplaceRepo()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:         map[string]bool{"my-plugin@my-marketplace": true},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"}}},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "org/marketplace"},
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
}

func TestStrictKnownMarketplaces_AllowlistBlocksNonMatching(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:         map[string]bool{"my-plugin@my-marketplace": true},
		ExtraKnownMarketplaces: map[string]ExtraMarketplace{"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"}}},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "other-org/other-marketplace"}, // doesn't match
		},
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Contains(t, repos[0].ResolutionFailure, "strictKnownMarketplaces")
}

func TestStrictKnownMarketplaces_DefaultMarketplaceAlwaysAllowed(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := makeSpokesWithMarketplace(t, DefaultMarketplaceName, "spark", "github/copilot-plugins")
	ghTwirp := makeGhTwirpWithMarketplaceRepo()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:          map[string]bool{"spark": true}, // bare name = default marketplace
		StrictKnownMarketplaces: []MarketplaceSourceConfig{},    // lockdown — but default should still work
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
}

func TestStrictKnownMarketplaces_DirectGitHubSpecNotAffected(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	settings := &SettingsJSON{
		EnabledPlugins:          map[string]bool{"owner/repo": true},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{}, // lockdown
	}

	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	assert.Equal(t, "https://github.com/owner/repo", repos[0].CloneURL)
}

func TestStrictKnownMarketplaces_GitHubSource_RefAndPathMustMatch(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	t.Run("ref mismatch blocks", func(t *testing.T) {
		spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
		ghTwirp := makeGhTwirpWithMarketplaceRepo()
		svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
			ExtraKnownMarketplaces: map[string]ExtraMarketplace{
				"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace", Ref: "main"}},
			},
			StrictKnownMarketplaces: []MarketplaceSourceConfig{
				{Source: "github", Repo: "org/marketplace", Ref: "v1.0"},
			},
		}

		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		require.Len(t, repos, 1)
		assert.Contains(t, repos[0].ResolutionFailure, "strictKnownMarketplaces")
	})

	t.Run("ref match permits", func(t *testing.T) {
		spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
		ghTwirp := makeGhTwirpWithMarketplaceRepo()
		svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
			ExtraKnownMarketplaces: map[string]ExtraMarketplace{
				"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace", Ref: "v1.0"}},
			},
			StrictKnownMarketplaces: []MarketplaceSourceConfig{
				{Source: "github", Repo: "org/marketplace", Ref: "v1.0"},
			},
		}

		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		require.Len(t, repos, 1)
		assert.Equal(t, "https://github.com/external/plugin-repo", repos[0].CloneURL)
	})

	t.Run("path mismatch blocks", func(t *testing.T) {
		spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
		ghTwirp := makeGhTwirpWithMarketplaceRepo()
		svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
			ExtraKnownMarketplaces: map[string]ExtraMarketplace{
				"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace", Path: "marketplace"}},
			},
			StrictKnownMarketplaces: []MarketplaceSourceConfig{
				{Source: "github", Repo: "org/marketplace", Path: "other"},
			},
		}

		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		require.Len(t, repos, 1)
		assert.Contains(t, repos[0].ResolutionFailure, "strictKnownMarketplaces")
	})

	t.Run("rule with ref blocks ref-less source", func(t *testing.T) {
		// Defensive: a rule that pins a ref must not match a source that omits ref.
		spokes := makeSpokesWithMarketplace(t, "my-marketplace", "my-plugin", "external/plugin-repo")
		ghTwirp := makeGhTwirpWithMarketplaceRepo()
		svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

		settings := &SettingsJSON{
			EnabledPlugins: map[string]bool{"my-plugin@my-marketplace": true},
			ExtraKnownMarketplaces: map[string]ExtraMarketplace{
				"my-marketplace": {Source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"}},
			},
			StrictKnownMarketplaces: []MarketplaceSourceConfig{
				{Source: "github", Repo: "org/marketplace", Ref: "v1.0"},
			},
		}

		repos, err := svc.ResolvePluginRepos(ctx, settings)
		require.NoError(t, err)
		require.Len(t, repos, 1)
		assert.Contains(t, repos[0].ResolutionFailure, "strictKnownMarketplaces")
	})
}

func TestSourceMatches_GitSourceRefAndPath(t *testing.T) {
	tests := []struct {
		name   string
		source MarketplaceSourceConfig
		rule   MarketplaceSourceConfig
		want   bool
	}{
		{
			name:   "url and ref both match",
			source: MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Ref: "v1"},
			rule:   MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Ref: "v1"},
			want:   true,
		},
		{
			name:   "url matches but ref differs",
			source: MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Ref: "v1"},
			rule:   MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Ref: "v2"},
			want:   false,
		},
		{
			name:   "url and path both match, ref empty",
			source: MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Path: "sub"},
			rule:   MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Path: "sub"},
			want:   true,
		},
		{
			name:   "path differs",
			source: MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Path: "sub"},
			rule:   MarketplaceSourceConfig{Source: "git", URL: "https://example.com/x.git", Path: "other"},
			want:   false,
		},
		{
			name:   "hostPattern rule type is not supported and falls through to non-match",
			source: MarketplaceSourceConfig{Source: "github", Repo: "org/marketplace"},
			rule:   MarketplaceSourceConfig{Source: "hostPattern"},
			want:   false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := sourceMatches(tc.source, tc.rule)
			assert.Equal(t, tc.want, got)
		})
	}
}

// =============================================================================
// strictKnownMarketplaces source-precedence tests
// =============================================================================
//
// strictKnownMarketplaces is an admin-only allowlist control: it is only
// honored when supplied from enterprise managed settings. Repo- and org-level
// declarations must be stripped at load time so they never reach
// ResolvePluginRepos.

func TestLoadRepoSettings_StripsStrictKnownMarketplaces(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	repoSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"repo-plugin": true},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "repo-allowed/marketplace"},
		},
	}
	repoBlob, err := json.Marshal(repoSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob))
	ghTwirp := githubtwirp.NewNoopClient()

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadRepoSettings(ctx, repoID)
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["repo-plugin"], "non-strict fields should still load normally")
	assert.Nil(t, settings.StrictKnownMarketplaces, "repo-level strictKnownMarketplaces must be stripped")
}

func TestLoadOrgSettings_StripsStrictKnownMarketplaces(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	orgRepoID := uint64(500)
	orgSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"org-plugin": true},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "org-allowed/marketplace"},
		},
	}
	orgBlob, err := json.Marshal(orgSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", orgBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadOrgSettings(ctx, "my-org")
	require.NoError(t, err)
	assert.True(t, settings.EnabledPlugins["org-plugin"], "non-strict fields should still load normally")
	assert.Nil(t, settings.StrictKnownMarketplaces, "org-level strictKnownMarketplaces must be stripped")
}

func TestLoadEnterpriseSettings_KeepsStrictKnownMarketplaces(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	enterpriseRepoID := uint64(900)
	entSettings := SettingsJSON{
		EnabledPlugins: map[string]bool{"enterprise-plugin": true},
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "enterprise-allowed/marketplace"},
		},
	}
	entBlob, err := json.Marshal(entSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t, spokestest.WithRepoBlob(enterpriseRepoID, "copilot/settings.json", entBlob))

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: enterpriseRepoID}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")
	settings, err := svc.LoadEnterpriseSettings(ctx, 123)
	require.NoError(t, err)
	require.Len(t, settings.StrictKnownMarketplaces, 1, "enterprise-level strictKnownMarketplaces must be preserved")
	assert.Equal(t, "enterprise-allowed/marketplace", settings.StrictKnownMarketplaces[0].Repo)
}

func TestLoadMergedSettings_OnlyEnterpriseStrictKnownMarketplacesSurvives(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()

	repoID := uint64(100)
	orgRepoID := uint64(500)
	enterpriseRepoID := uint64(900)

	repoSettings := SettingsJSON{
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "repo-allowed/marketplace"},
		},
	}
	repoBlob, err := json.Marshal(repoSettings)
	require.NoError(t, err)

	orgSettings := SettingsJSON{
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "org-allowed/marketplace"},
		},
	}
	orgBlob, err := json.Marshal(orgSettings)
	require.NoError(t, err)

	entSettings := SettingsJSON{
		StrictKnownMarketplaces: []MarketplaceSourceConfig{
			{Source: "github", Repo: "enterprise-allowed/marketplace"},
		},
	}
	entBlob, err := json.Marshal(entSettings)
	require.NoError(t, err)

	spokesClient := spokestest.NewClient(t,
		spokestest.WithRepoBlob(repoID, ".github/copilot/settings.json", repoBlob),
		spokestest.WithRepoBlob(orgRepoID, "copilot/settings.json", orgBlob),
		spokestest.WithRepoBlob(enterpriseRepoID, "copilot/settings.json", entBlob),
	)

	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		if slices.Contains(req.GetNwos(), "my-org/.github") {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{
					{Id: int64(orgRepoID), Name: ".github", OwnerLogin: "my-org"},
				},
			}, nil
		}
		return &repositoriesTwirp.FindRepositoriesByNameResponse{}, nil
	}
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return &sweagentdv1.EnterpriseAgentsResponse{RepositoryId: enterpriseRepoID}, nil
	}

	svc := NewService(obsv, spokesClient, ghTwirp, "https://github.com")

	// All three sources: enterprise wins, repo/org are stripped before they can contribute.
	merged, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", nil)
	require.NoError(t, err)
	require.Len(t, merged.StrictKnownMarketplaces, 1)
	assert.Equal(t, "enterprise-allowed/marketplace", merged.StrictKnownMarketplaces[0].Repo)

	// Without enterprise in the mix: repo/org strict declarations are ignored, so no allowlist is in effect.
	noEnterprise, err := svc.LoadMergedSettings(ctx, repoID, 123, "my-org", []string{SourceTypeRepo, SourceTypeOrg})
	require.NoError(t, err)
	assert.Nil(t, noEnterprise.StrictKnownMarketplaces, "repo/org strict declarations must not produce an allowlist")
}

// =============================================================================
// Test helpers
// =============================================================================

// makeSpokesWithMarketplace creates a spokes mock with a marketplace.json containing a single plugin.
func makeSpokesWithMarketplace(t *testing.T, marketplaceName, pluginName, pluginSourceRepo string) *spokestest.Client {
	t.Helper()
	marketplaceData := struct {
		Name    string        `json:"name"`
		Plugins []PluginEntry `json:"plugins"`
	}{
		Name: marketplaceName,
		Plugins: []PluginEntry{
			{
				Name: pluginName,
				Source: PluginSource{
					Source: "github",
					Repo:   pluginSourceRepo,
				},
			},
		},
	}
	marketplaceJSON, err := json.Marshal(marketplaceData)
	require.NoError(t, err)

	return spokestest.NewClient(t,
		spokestest.WithRepoBlob(123, "marketplace.json", marketplaceJSON),
	)
}

// makeGhTwirpWithMarketplaceRepo creates a ghTwirp noop client that resolves marketplace repos to ID 123.
func makeGhTwirpWithMarketplaceRepo() *githubtwirp.NoopClient {
	ghTwirp := githubtwirp.NewNoopClient()
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return &repositoriesTwirp.FindRepositoriesByNameResponse{
			Repositories: []*repositoriesTwirp.RepositoryListItem{
				{Id: 123},
			},
		}, nil
	}
	return ghTwirp
}

// =============================================================================
// GitHub Spec SHA-pinning Tests
// =============================================================================

func TestResolvePluginRepos_GitHubSpec_SHAPinned(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	const sha1 = "abcdef0123456789abcdef0123456789abcdef01"
	const sha256 = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456701"

	tests := []struct {
		name         string
		spec         string
		expectedURL  string
		expectedPath string
		expectedSHA  string
	}{
		{
			name:         "owner/repo at sha1",
			spec:         "owner/repo@" + sha1,
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "",
			expectedSHA:  sha1,
		},
		{
			name:         "owner/repo at sha256",
			spec:         "owner/repo@" + sha256,
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "",
			expectedSHA:  sha256,
		},
		{
			name:         "owner/repo with subpath at sha",
			spec:         "owner/repo:plugins/myplugin@" + sha1,
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "plugins/myplugin",
			expectedSHA:  sha1,
		},
		{
			name:         "owner/repo.git at sha",
			spec:         "owner/repo.git@" + sha1,
			expectedURL:  "https://github.com/owner/repo",
			expectedPath: "",
			expectedSHA:  sha1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.Empty(t, repos[0].ResolutionFailure)
			assert.Equal(t, tt.expectedURL, repos[0].CloneURL)
			assert.Equal(t, tt.expectedPath, repos[0].Path)
			assert.Equal(t, tt.expectedSHA, repos[0].SHA)
			assert.Equal(t, tt.spec, repos[0].Spec)
		})
	}
}

func TestResolvePluginRepos_GitHubSpec_InvalidSHA(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := githubtwirp.NewNoopClient()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	tests := []struct {
		name string
		spec string
	}{
		{"branch ref instead of sha", "owner/repo@main"},
		{"tag ref instead of sha", "owner/repo@v1.0.0"},
		{"short sha", "owner/repo@abc1234"},
		{"39-char near-sha", "owner/repo@abcdef0123456789abcdef0123456789abcdef0"},
		{"41-char near-sha", "owner/repo@abcdef0123456789abcdef0123456789abcdef010"},
		{"with subpath and invalid sha", "owner/repo:plugins/x@main"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := &SettingsJSON{
				EnabledPlugins: map[string]bool{tt.spec: true},
			}
			repos, err := svc.ResolvePluginRepos(ctx, settings)
			require.NoError(t, err)
			require.Len(t, repos, 1)
			assert.NotEmpty(t, repos[0].ResolutionFailure, "expected ResolutionFailure for %q", tt.spec)
			assert.Contains(t, repos[0].ResolutionFailure, "full commit SHA")
			assert.Equal(t, tt.spec, repos[0].Spec)
			assert.Empty(t, repos[0].CloneURL)
			assert.Empty(t, repos[0].SHA)
		})
	}
}

func TestResolvePluginRepos_MarketplaceSpec_NotAffectedBySHASyntax(t *testing.T) {
	// Regression guard: `plugin@marketplace` specs must still parse as
	// marketplace specs after the SHA-pin syntax was added. The
	// disambiguator is "LHS contains `/`", so bare plugin names route to
	// marketplace.
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	spokes := spokestest.NewClient(t)
	ghTwirp := makeGhTwirpWithMarketplaceRepo()
	svc := NewService(obsv, spokes, ghTwirp, "https://github.com")

	// `copilot-plugins` is a default marketplace, so this resolves through
	// the marketplace branch even with no extraKnownMarketplaces configured.
	// We just need to assert it doesn't get hijacked into the GitHub+SHA
	// branch — exact resolution behavior is covered by other tests.
	settings := &SettingsJSON{
		EnabledPlugins: map[string]bool{
			"sentry@copilot-plugins": true,
		},
	}
	repos, err := svc.ResolvePluginRepos(ctx, settings)
	require.NoError(t, err)
	require.Len(t, repos, 1)
	// Marketplace resolution will fail in this minimal test setup (no
	// marketplace.json contents are mocked), but the failure must be from
	// the marketplace branch, not from the GitHub-SHA branch.
	assert.NotContains(t, repos[0].ResolutionFailure, "40-character commit SHA")
	assert.NotContains(t, repos[0].ResolutionFailure, "could not extract owner and repo")
}
