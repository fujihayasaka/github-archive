package plugins

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestParsePluginSpec_GitHubFormat(t *testing.T) {
	tests := []struct {
		name string
		spec string
	}{
		{"simple owner/repo", "owner/repo"},
		{"with path", "owner/repo:plugins/myplugin"},
		{"with .git suffix", "owner/repo.git"},
		{"with .git suffix and path", "owner/repo.git:path"},
		{"uppercase", "MyOrg/MyRepo"},
		{"with hyphens and numbers", "my-org-123/my-repo-456"},
		{"whitespace trimmed", "  owner/repo  "},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, PluginSpecTypeGitHub, parsed.Type)
			assert.NotEmpty(t, parsed.RawSpec)
		})
	}
}

func TestParsePluginSpec_URLFormat(t *testing.T) {
	tests := []struct {
		name string
		spec string
	}{
		{"https url", "https://github.com/owner/repo"},
		{"http url", "http://example.com/repo"},
		{"ssh url with scheme", "ssh://git@github.com/owner/repo"},
		{"git@ ssh url", "git@github.com:owner/repo.git"},
		{"git@ with custom host", "git@gitlab.company.com:group/project.git"},
		{"custom domain", "https://gitlab.company.com/group/project"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, PluginSpecTypeURL, parsed.Type)
			assert.Equal(t, tt.spec, parsed.RawSpec)
		})
	}
}

func TestParsePluginSpec_MarketplaceFormat(t *testing.T) {
	tests := []struct {
		name        string
		spec        string
		pluginName  string
		marketplace string
	}{
		{"simple marketplace", "sentry@copilot-plugins", "sentry", "copilot-plugins"},
		{"hyphenated plugin name", "my-cool-plugin@my-marketplace", "my-cool-plugin", "my-marketplace"},
		{"underscore plugin name", "my_plugin@marketplace_name", "my_plugin", "marketplace_name"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, PluginSpecTypeMarketplace, parsed.Type)
			assert.Equal(t, tt.pluginName, parsed.PluginName)
			assert.Equal(t, tt.marketplace, parsed.Marketplace)
		})
	}
}

func TestParsePluginSpec_LocalFormat(t *testing.T) {
	tests := []struct {
		name        string
		spec        string
		wantRawSpec string
	}{
		{"current dir relative", "./plugins/myplugin", "./plugins/myplugin"},
		{"just dot slash", "./", "./"},
		{"just dot", ".", "."},
		{"deeply nested", "./a/b/c/d/e/f", "./a/b/c/d/e/f"},
		{"absolute path normalized", "/plugins/myplugin", "./plugins/myplugin"},
		{"absolute root normalized", "/", "./"},
		{"multiple leading slashes pass-through", "//plugins/myplugin", "//plugins/myplugin"},
		{"parent traversal", "../plugins/myplugin", "../plugins/myplugin"},
		{"just parent dir", "..", ".."},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, PluginSpecTypeLocal, parsed.Type)
			assert.Equal(t, tt.wantRawSpec, parsed.RawSpec)
		})
	}
}

func TestParsePluginSpec_BareRelativeIsNotLocal(t *testing.T) {
	// Bare relative paths like "plugins/foo" are ambiguous with "owner/repo"
	// format and should NOT be classified as local. Users must use "./" prefix.
	tests := []struct {
		name string
		spec string
	}{
		{"bare relative with slash", "plugins/foo"},
		{"bare single segment", "myplugin"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.NotEqual(t, PluginSpecTypeLocal, parsed.Type)
		})
	}
}

func TestParsePluginSpec_EdgeCases(t *testing.T) {
	tests := []struct {
		name         string
		spec         string
		expectedType PluginSpecType
		pluginName   string
	}{
		{"empty string", "", PluginSpecTypeMarketplace, ""},
		{"bare plugin name", "my-plugin", PluginSpecTypeMarketplace, "my-plugin"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, tt.expectedType, parsed.Type)
			if tt.pluginName != "" {
				assert.Equal(t, tt.pluginName, parsed.PluginName)
				assert.Equal(t, "", parsed.Marketplace) // default marketplace
			}
		})
	}
}

func TestExtractNWO(t *testing.T) {
	const ghServer = "https://github.com"

	t.Run("bare specs", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
			owner string
			repo  string
			path  string
		}{
			{"simple", "owner/repo", "owner", "repo", ""},
			{"with path", "owner/repo:plugins/tool", "owner", "repo", "plugins/tool"},
			{"with .git", "owner/repo.git", "owner", "repo", ""},
			{"with .git and path", "owner/repo.git:path", "owner", "repo", "path"},
			{"nested path", "owner/repo:a/b/c", "owner", "repo", "a/b/c"},
			{"with whitespace", "  owner/repo  ", "owner", "repo", ""},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, path := extractNWO(tt.input, ghServer)
				assert.Equal(t, tt.owner, owner)
				assert.Equal(t, tt.repo, repo)
				assert.Equal(t, tt.path, path)
			})
		}
	})

	t.Run("bare specs invalid", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
		}{
			{"empty", ""},
			{"whitespace only", "   "},
			{"just owner", "owner"},
			{"trailing slash", "owner/"},
			{"leading slash", "/repo"},
			{"too many segments", "owner/repo/extra"},
			{"just a dot", "."},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, _ := extractNWO(tt.input, ghServer)
				assert.Empty(t, owner, "should not extract owner from %q", tt.input)
				assert.Empty(t, repo, "should not extract repo from %q", tt.input)
			})
		}
	})

	t.Run("HTTPS URLs on GitHub", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
			owner string
			repo  string
		}{
			{"basic", "https://github.com/owner/repo", "owner", "repo"},
			{"with .git", "https://github.com/owner/repo.git", "owner", "repo"},
			{"mixed case host", "https://GitHub.COM/Owner/Repo", "Owner", "Repo"},
			{"mixed case host with .git", "https://GitHub.COM/Owner/Repo.git", "Owner", "Repo"},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, path := extractNWO(tt.input, ghServer)
				assert.Equal(t, tt.owner, owner)
				assert.Equal(t, tt.repo, repo)
				assert.Empty(t, path, "URLs should not have path component")
			})
		}
	})

	t.Run("HTTP URLs on GitHub", func(t *testing.T) {
		owner, repo, _ := extractNWO("http://github.com/owner/repo", ghServer)
		assert.Equal(t, "owner", owner)
		assert.Equal(t, "repo", repo)
	})

	t.Run("SSH URLs on GitHub", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
			owner string
			repo  string
		}{
			{"ssh protocol", "ssh://github.com/owner/repo", "owner", "repo"},
			{"ssh with .git", "ssh://github.com/owner/repo.git", "owner", "repo"},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, path := extractNWO(tt.input, ghServer)
				assert.Equal(t, tt.owner, owner)
				assert.Equal(t, tt.repo, repo)
				assert.Empty(t, path)
			})
		}
	})

	t.Run("git@ URLs on GitHub", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
			owner string
			repo  string
		}{
			{"basic", "git@github.com:owner/repo", "owner", "repo"},
			{"with .git", "git@github.com:owner/repo.git", "owner", "repo"},
			{"mixed case host", "git@GitHub.COM:owner/repo", "owner", "repo"},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, path := extractNWO(tt.input, ghServer)
				assert.Equal(t, tt.owner, owner)
				assert.Equal(t, tt.repo, repo)
				assert.Empty(t, path)
			})
		}
	})

	t.Run("non-GitHub URLs rejected", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
		}{
			{"gitlab https", "https://gitlab.com/owner/repo"},
			{"bitbucket https", "https://bitbucket.org/owner/repo"},
			{"custom domain", "https://git.mycompany.com/owner/repo"},
			{"gitlab git@", "git@gitlab.com:owner/repo"},
			{"gitlab ssh", "ssh://gitlab.com/owner/repo"},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, _ := extractNWO(tt.input, ghServer)
				assert.Empty(t, owner)
				assert.Empty(t, repo)
			})
		}
	})

	t.Run("URLs without valid owner/repo rejected", func(t *testing.T) {
		tests := []struct {
			name  string
			input string
		}{
			{"git@ no colon", "git@github.com"},
			{"git@ empty path", "git@github.com:"},
			{"git@ owner only", "git@github.com:owner"},
			{"https no path", "https://github.com"},
			{"https owner only", "https://github.com/owner"},
			{"https trailing slash", "https://github.com/owner/"},
			{"https extra path segments", "https://github.com/owner/repo/blob/main/file"},
			{"https with query string", "https://github.com/owner/repo?tab=code"},
			{"https with fragment", "https://github.com/owner/repo#readme"},
			{"https dot-segment owner", "https://github.com/../repo"},
			{"https dot-segment repo", "https://github.com/owner/.."},
			{"git@ extra path segments", "git@github.com:owner/repo/extra"},
			{"git@ dot-segment", "git@github.com:../repo"},
			{"ssh extra path segments", "ssh://github.com/owner/repo/extra"},
		}
		for _, tt := range tests {
			t.Run(tt.name, func(t *testing.T) {
				owner, repo, _ := extractNWO(tt.input, ghServer)
				assert.Empty(t, owner, "should not extract owner from %q", tt.input)
				assert.Empty(t, repo, "should not extract repo from %q", tt.input)
			})
		}
	})

	t.Run("GHES server URL", func(t *testing.T) {
		ghesServer := "https://github.mycompany.com"
		owner, repo, _ := extractNWO("https://github.mycompany.com/org/tool", ghesServer)
		assert.Equal(t, "org", owner)
		assert.Equal(t, "tool", repo)

		// Same URL rejected against github.com
		owner, repo, _ = extractNWO("https://github.mycompany.com/org/tool", ghServer)
		assert.Empty(t, owner)
		assert.Empty(t, repo)
	})

	t.Run("URLs never return path", func(t *testing.T) {
		// Even if the URL has extra path segments, we only extract owner/repo
		_, _, path := extractNWO("https://github.com/owner/repo", ghServer)
		assert.Empty(t, path)
		_, _, path = extractNWO("git@github.com:owner/repo.git", ghServer)
		assert.Empty(t, path)
	})
}

func TestParsePluginSpec_RawSpecPreserved(t *testing.T) {
	specs := []string{
		"owner/repo",
		"https://github.com/owner/repo",
		"plugin@marketplace",
		"./local/path",
	}

	for _, spec := range specs {
		t.Run(spec, func(t *testing.T) {
			parsed := parsePluginSpec(spec)
			assert.NotEmpty(t, parsed.RawSpec)
		})
	}
}

func TestParsePluginSpec_GitHubSHAPinned(t *testing.T) {
	const sha = "abcdef0123456789abcdef0123456789abcdef01"
	tests := []struct {
		name        string
		spec        string
		wantRawSpec string
		wantSHA     string
	}{
		{"owner/repo with sha", "owner/repo@" + sha, "owner/repo", sha},
		{"owner/repo with path with sha", "owner/repo:plugins/myplugin@" + sha, "owner/repo:plugins/myplugin", sha},
		{"owner/repo.git with sha", "owner/repo.git@" + sha, "owner/repo.git", sha},
		// The parser preserves the token after `@` verbatim. The resolver
		// is responsible for validating that it's a full commit SHA.
		{"owner/repo with short token", "owner/repo@abc1234", "owner/repo", "abc1234"},
		{"owner/repo with non-hex token", "owner/repo@main", "owner/repo", "main"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, PluginSpecTypeGitHub, parsed.Type)
			assert.Equal(t, tt.wantRawSpec, parsed.RawSpec)
			assert.Equal(t, tt.wantSHA, parsed.SHA)
			assert.Empty(t, parsed.PluginName)
			assert.Empty(t, parsed.Marketplace)
		})
	}
}

func TestParsePluginSpec_SHADisambiguationFromMarketplace(t *testing.T) {
	// The `@` SHA-pin syntax must not interfere with marketplace specs.
	// Disambiguation rule: only treat `@<token>` as a SHA pin when the LHS
	// looks like a GitHub spec (contains `/`).
	const sha = "abcdef0123456789abcdef0123456789abcdef01"
	tests := []struct {
		name         string
		spec         string
		expectedType PluginSpecType
	}{
		{"bare plugin name with marketplace", "sentry@copilot-plugins", PluginSpecTypeMarketplace},
		{"hyphenated plugin name with marketplace", "my-plugin@marketplace", PluginSpecTypeMarketplace},
		{"owner/repo with sha is github", "owner/repo@" + sha, PluginSpecTypeGitHub},
		{"owner/repo with path with sha is github", "owner/repo:path@" + sha, PluginSpecTypeGitHub},
		// git@host:owner/repo form is matched by the URL branch before any
		// of the @-handling branches below it.
		{"git@ ssh url is url", "git@github.com:owner/repo.git", PluginSpecTypeURL},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			parsed := parsePluginSpec(tt.spec)
			assert.Equal(t, tt.expectedType, parsed.Type)
		})
	}
}
