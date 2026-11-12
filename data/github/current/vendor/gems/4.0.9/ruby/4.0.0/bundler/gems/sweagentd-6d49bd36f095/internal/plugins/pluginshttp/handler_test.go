package pluginshttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	authd "github.com/github/authnd/client"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// enabledFFs returns a featureflags noop client with the plugins list API FF enabled.
func enabledFFs() featureflags.Client {
	return featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentPluginsListAPIEnabled: true,
	})
}

// testUserInfo creates a UserInfo with valid TokenInfo for testing.
func testUserInfo(userID uint64) *requestctx.UserInfo {
	return &requestctx.UserInfo{
		ID: userID,
		TokenInfo: &requestctx.TokenInfo{
			Type: string(authd.CredentialTypeUserToServerToken),
		},
	}
}

func TestHandler_ListPlugins(t *testing.T) {
	t.Run("returns empty when no settings file", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		spokes := spokestest.NewClient(t)
		ghTwirp := &mockGhTwirp{
			repos: map[string]*repositoriesTwirp.RepositoryListItem{
				"owner/repo": {Id: 123, Name: "repo", OwnerLogin: "owner"},
			},
		}
		svc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
		h := NewHandler(svc, obsv, ghTwirp, enabledFFs())

		// Set up router with handler
		r := chi.NewRouter()
		h.RegisterRoutes(r)

		// Create request with user context
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
			UserInfo: testUserInfo(123),
		})
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/plugins/owner/repo", http.NoBody)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		if w.Code != http.StatusOK {
			t.Logf("Response body: %s", w.Body.String())
		}
		require.Equal(t, http.StatusOK, w.Code)

		var resp listPluginsResponse
		err := json.Unmarshal(w.Body.Bytes(), &resp)
		require.NoError(t, err)

		assert.NotNil(t, resp.Settings)
		assert.Empty(t, resp.PluginRepos)
	})

	t.Run("returns 401 when no user", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		spokes := spokestest.NewClient(t)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
		h := NewHandler(svc, obsv, ghTwirp, enabledFFs())

		r := chi.NewRouter()
		h.RegisterRoutes(r)

		req := httptest.NewRequest(http.MethodGet, "/plugins/owner/repo", http.NoBody)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		require.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("returns plugins from settings", func(t *testing.T) {
		obsv := observability.NewNoopExporters()

		// Set up spokes to return a settings file
		settingsJSON := `{"enabledPlugins": {"octocat/my-plugin": true}}`
		spokes := spokestest.NewClient(t,
			spokestest.WithRepoBlob(123, ".github/copilot/settings.json", []byte(settingsJSON)),
		)

		ghTwirp := &mockGhTwirp{
			repos: map[string]*repositoriesTwirp.RepositoryListItem{
				"owner/repo": {Id: 123, Name: "repo", OwnerLogin: "owner"},
			},
		}
		svc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
		h := NewHandler(svc, obsv, ghTwirp, enabledFFs())

		r := chi.NewRouter()
		h.RegisterRoutes(r)

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
			UserInfo: testUserInfo(123),
		})
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/plugins/owner/repo", http.NoBody)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		require.Equal(t, http.StatusOK, w.Code)

		var resp listPluginsResponse
		err := json.Unmarshal(w.Body.Bytes(), &resp)
		require.NoError(t, err)

		assert.NotNil(t, resp.Settings)
		assert.Len(t, resp.Settings.EnabledPlugins, 1)
		assert.True(t, resp.Settings.EnabledPlugins["octocat/my-plugin"])

		// Should have resolved the plugin
		assert.Len(t, resp.PluginRepos, 1)
		assert.Equal(t, "https://github.com/octocat/my-plugin", resp.PluginRepos[0].CloneURL)
	})

	t.Run("returns 404 when FF disabled", func(t *testing.T) {
		obsv := observability.NewNoopExporters()
		spokes := spokestest.NewClient(t)
		ghTwirp := githubtwirp.NewNoopClient()
		svc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
		disabledFFs := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentPluginsListAPIEnabled: false,
		})
		h := NewHandler(svc, obsv, ghTwirp, disabledFFs)

		r := chi.NewRouter()
		h.RegisterRoutes(r)

		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
			UserInfo: testUserInfo(123),
		})
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/plugins/owner/repo", http.NoBody)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		require.Equal(t, http.StatusNotFound, w.Code)
	})
}

func TestHandler_ListPlugins_IncludeSources(t *testing.T) {
	const repoID = int64(123)
	const orgRepoID = int64(500)

	repoSettings := `{"enabledPlugins": {"repo-plugin": true}}`
	orgSettings := `{"enabledPlugins": {"org-plugin": true}}`

	makeHandler := func(t *testing.T) (*Handler, *chi.Mux) {
		t.Helper()
		obsv := observability.NewNoopExporters()
		spokes := spokestest.NewClient(t,
			spokestest.WithRepoBlob(uint64(repoID), ".github/copilot/settings.json", []byte(repoSettings)),
			spokestest.WithRepoBlob(uint64(orgRepoID), "copilot/settings.json", []byte(orgSettings)),
		)
		ghTwirp := &mockGhTwirp{
			repos: map[string]*repositoriesTwirp.RepositoryListItem{
				"owner/repo":    {Id: repoID, OwnerId: 42, Name: "repo", OwnerLogin: "owner"},
				"owner/.github": {Id: orgRepoID, Name: ".github", OwnerLogin: "owner"},
			},
		}
		svc := plugins.NewService(obsv, spokes, ghTwirp, "https://github.com")
		h := NewHandler(svc, obsv, ghTwirp, enabledFFs())
		r := chi.NewRouter()
		h.RegisterRoutes(r)
		return h, r
	}

	makeRequest := func(t *testing.T, url string) *httptest.ResponseRecorder {
		t.Helper()
		ctx := requestctx.AddData(context.Background(), &requestctx.CtxData{
			UserInfo: testUserInfo(123),
		})
		req := httptest.NewRequestWithContext(ctx, http.MethodGet, url, http.NoBody)
		w := httptest.NewRecorder()
		_, r := makeHandler(t)
		r.ServeHTTP(w, req)
		return w
	}

	t.Run("default includes all sources", func(t *testing.T) {
		w := makeRequest(t, "/plugins/owner/repo")
		require.Equal(t, http.StatusOK, w.Code)

		var resp listPluginsResponse
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.True(t, resp.Settings.EnabledPlugins["repo-plugin"], "repo plugin should be present")
		assert.True(t, resp.Settings.EnabledPlugins["org-plugin"], "org plugin should be present from default all-sources")
	})

	t.Run("include_sources=repo loads only repo", func(t *testing.T) {
		w := makeRequest(t, "/plugins/owner/repo?include_sources=repo")
		require.Equal(t, http.StatusOK, w.Code)

		var resp listPluginsResponse
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.True(t, resp.Settings.EnabledPlugins["repo-plugin"], "repo plugin should be present")
		assert.False(t, resp.Settings.EnabledPlugins["org-plugin"], "org plugin should NOT be present with repo-only")
	})

	t.Run("include_sources=repo,org loads both", func(t *testing.T) {
		w := makeRequest(t, "/plugins/owner/repo?include_sources=repo,org")
		require.Equal(t, http.StatusOK, w.Code)

		var resp listPluginsResponse
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
		assert.True(t, resp.Settings.EnabledPlugins["repo-plugin"])
		assert.True(t, resp.Settings.EnabledPlugins["org-plugin"])
	})

	t.Run("invalid include_sources returns 400", func(t *testing.T) {
		w := makeRequest(t, "/plugins/owner/repo?include_sources=bogus")
		require.Equal(t, http.StatusBadRequest, w.Code)
		assert.Contains(t, w.Body.String(), "invalid source type: bogus")
	})
}

type mockGhTwirp struct {
	githubtwirp.ClientInterface

	repos map[string]*repositoriesTwirp.RepositoryListItem
}

func (m *mockGhTwirp) GetRepoByName(ctx context.Context, owner, name string) (*repositoriesTwirp.RepositoryListItem, error) {
	key := owner + "/" + name
	if repo, ok := m.repos[key]; ok {
		return repo, nil
	}
	return nil, nil
}

func (m *mockGhTwirp) TokenHasAccess(ctx context.Context, user *requestctx.UserInfo, rules []*githubtwirp.HasAccessCheck) (bool, error) {
	// Always return true for tests
	return true, nil
}

func (m *mockGhTwirp) SweagentdAPI() sweagentdTwirp.SweagentdAPI {
	return &githubtwirp.NoopSweagentdAPI{}
}
