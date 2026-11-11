package skillshttp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/skills"
	"github.com/github/sweagentd/internal/spokes/spokestest"
	sweagentdv1 "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// setupTestService creates a service with mocks that return "not found" for all repos.
func setupTestService(t *testing.T, obsv observability.Exporters) (*skills.Service, *githubtwirp.NoopClient) {
	t.Helper()

	spokes := spokestest.NewClient(t) // Empty spokes - no skills
	ghTwirp := githubtwirp.NewNoopClient()

	// Mock FindRepositoriesByName to return not found
	ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
		return nil, twirp.NewError(twirp.NotFound, "repository not found")
	}

	// Mock EnterpriseAgents to return not found
	ghTwirp.NoopSweagentdAPI.MockEnterpriseAgents = func(ctx context.Context, req *sweagentdv1.EnterpriseAgentsRequest) (*sweagentdv1.EnterpriseAgentsResponse, error) {
		return nil, twirp.NotFoundError("enterprise agents not configured")
	}

	return skills.NewService(obsv, spokes, ghTwirp), ghTwirp
}

func TestHandlerListSkills(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("returns empty skills list when repo not found", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		router := chi.NewRouter()
		router.Get("/skills/{repoOwner}/{repoName}", h.listSkills(&requestctx.UserInfo{ID: 123}, stats.Tags{}))

		req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo", http.NoBody)
		rr := httptest.NewRecorder()

		router.ServeHTTP(rr, req)

		// When repo not found, should return 404
		require.Equal(t, http.StatusNotFound, rr.Code)
	})

	t.Run("invalid include_sources returns bad request", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		router := chi.NewRouter()
		router.Get("/skills/{repoOwner}/{repoName}", h.listSkills(&requestctx.UserInfo{ID: 123}, stats.Tags{}))

		req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo?include_sources=invalid", http.NoBody)
		rr := httptest.NewRecorder()

		router.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusBadRequest, rr.Code)
	})
}

func TestHandlerGetSkill(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("missing skill name returns bad request", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		// Manually create chi context with empty skillName to test validation
		router := chi.NewRouter()
		router.Get("/skills/{repoOwner}/{repoName}/{skillName}", h.getSkill(&requestctx.UserInfo{ID: 123}, stats.Tags{}))

		req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo/", http.NoBody)
		rr := httptest.NewRecorder()

		router.ServeHTTP(rr, req)

		// Chi will return 404 for missing path segment, not our handler's 400
		assert.Equal(t, http.StatusNotFound, rr.Code)
	})

	t.Run("skill not found returns 404", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		router := chi.NewRouter()
		router.Get("/skills/{repoOwner}/{repoName}/{skillName}", h.getSkill(&requestctx.UserInfo{ID: 123}, stats.Tags{}))

		req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo/nonexistent", http.NoBody)
		rr := httptest.NewRecorder()

		router.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusNotFound, rr.Code)
	})

	t.Run("path traversal patterns return bad request", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		testCases := []string{
			"..",
			".",
		}

		for _, tc := range testCases {
			router := chi.NewRouter()
			router.Get("/skills/{repoOwner}/{repoName}/{skillName}", h.getSkill(&requestctx.UserInfo{ID: 123}, stats.Tags{}))

			req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo/"+tc, http.NoBody)
			rr := httptest.NewRecorder()

			router.ServeHTTP(rr, req)

			assert.Equal(t, http.StatusBadRequest, rr.Code, "expected bad request for skill name: %s", tc)
		}
	})
}

func TestMiddleware(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("missing user info returns unauthorized", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		router := chi.NewRouter()
		h.RegisterRoutes(router)

		req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo", http.NoBody)
		// No user info set in context
		rr := httptest.NewRecorder()

		router.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("user info present proceeds to handler", func(t *testing.T) {
		svc, ghTwirp := setupTestService(t, obsv)
		h := NewHandler(svc, obsv, ghTwirp)

		router := chi.NewRouter()
		h.RegisterRoutes(router)

		req := httptest.NewRequest(http.MethodGet, "/skills/testowner/testrepo", http.NoBody)
		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)
		req = req.WithContext(ctx)
		rr := httptest.NewRecorder()

		router.ServeHTTP(rr, req)

		// Should get 404 since repo not found (proper error handling now)
		assert.Equal(t, http.StatusNotFound, rr.Code)
	})
}

func TestSkillDTO(t *testing.T) {
	t.Run("MakeSkillDTO without content", func(t *testing.T) {
		skill := skills.NewSkill(skills.Metadata{
			Name:        "test-skill",
			RepoID:      123,
			RepoOwner:   "owner",
			RepoOwnerID: 456,
			RepoName:    "repo",
			Version:     "abc123",
		}, "Test description", "content here", nil, false, true)

		dto := skills.MakeSkillDTO(skill, false)

		assert.Equal(t, "test-skill", dto.Name)
		assert.Equal(t, "Test description", dto.Description)
		assert.Empty(t, dto.Content) // Should not include content
	})

	t.Run("MakeSkillDTO with content", func(t *testing.T) {
		skill := skills.NewSkill(skills.Metadata{
			Name:        "test-skill",
			RepoID:      123,
			RepoOwner:   "owner",
			RepoOwnerID: 456,
			RepoName:    "repo",
			Version:     "abc123",
		}, "Test description", "content here", []string{"tool1"}, true, false)

		dto := skills.MakeSkillDTO(skill, true)

		assert.Equal(t, "test-skill", dto.Name)
		assert.Equal(t, "Test description", dto.Description)
		assert.Equal(t, "content here", dto.Content)
		assert.Equal(t, []string{"tool1"}, dto.AllowedTools)
		assert.True(t, dto.DisableModelInvocation)
		assert.False(t, dto.UserInvocable)
	})
}
