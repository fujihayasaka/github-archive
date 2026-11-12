package customagenthttp

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	authd "github.com/github/authnd/client"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/customagent/customagenttest"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMiddleware(t *testing.T) {
	obsv := observability.NewNoopExporters()

	// Simple handler that always succeeds
	successHandler := func(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("success"))
		}
	}

	t.Run("returns 400 when repo owner is missing", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		// Create request without chi route context (missing repo params)
		req := httptest.NewRequest(http.MethodGet, "/custom-agents/testowner/testrepo", http.NoBody)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusBadRequest, rr.Code)
		assert.Contains(t, rr.Body.String(), "repository owner and name cannot be empty")
	})

	t.Run("returns 400 when repo name is missing", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := context.Background()
		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		// repoName is missing
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusBadRequest, rr.Code)
		assert.Contains(t, rr.Body.String(), "repository owner and name cannot be empty")
	})

	t.Run("returns 401 when user info is missing from context", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := context.Background()
		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("returns 401 when token type is SSH certificate", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "token",
				Type:  string(authd.CredentialTypeSSHCertificate),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusUnauthorized, rr.Code)
	})

	t.Run("returns 404 when repository is not found", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		// Mock the repository API to return empty list (not found)
		ghTwirp.NoopRepositoriesAPI.MockFindRepositoriesByName = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesByNameRequest) (*repositoriesTwirp.FindRepositoriesByNameResponse, error) {
			return &repositoriesTwirp.FindRepositoriesByNameResponse{
				Repositories: []*repositoriesTwirp.RepositoryListItem{},
			}, nil
		}
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "token",
				Type:  string(authd.CredentialTypeUserToServerToken),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusNotFound, rr.Code)
	})

	t.Run("returns 404 when custom agents are not enabled for repository", func(t *testing.T) {
		// Enable the disallow flag to disable custom agents
		ffClient := featureflags.NewNoopClient(map[string]bool{
			string(featureflags.CopilotSWEAgentCustomAgentsDisallow): true,
		})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "token",
				Type:  string(authd.CredentialTypeUserToServerToken),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusNotFound, rr.Code)
	})

	t.Run("returns 404 when token does not have access to repository", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		// Configure the mock to return no access
		ghTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
			return &coreTwirp.BatchControlAccessResponse{
				Decisions: []*coreTwirp.AuthorizationDecision{
					{
						Id:       "test-id",
						Decision: false,
					},
				},
			}, nil
		}
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "token",
				Type:  string(authd.CredentialTypeUserToServerToken),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusNotFound, rr.Code)
	})

	t.Run("returns 500 when token access check fails with error", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		// Configure the mock to return an error
		ghTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
			return nil, goerrors.New("authorization service unavailable")
		}
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "token",
				Type:  string(authd.CredentialTypeUserToServerToken),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusInternalServerError, rr.Code)
	})

	t.Run("calls route handler when all checks pass", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "token",
				Type:  string(authd.CredentialTypeUserToServerToken),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(successHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusOK, rr.Code)
		assert.Equal(t, "success", rr.Body.String())
	})

	t.Run("passes userInfo and baseTags to route handler", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		var capturedUserInfo *requestctx.UserInfo
		var capturedBaseTags stats.Tags
		captureHandler := func(userInfo *requestctx.UserInfo, baseTags stats.Tags) http.HandlerFunc {
			return func(w http.ResponseWriter, r *http.Request) {
				capturedUserInfo = userInfo
				capturedBaseTags = baseTags
				w.WriteHeader(http.StatusOK)
			}
		}

		ctx := requestctx.NewContext(context.Background())
		userInfo := &requestctx.UserInfo{
			ID: 456,
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
				Type:  string(authd.CredentialTypeUserToServerToken),
			},
		}
		err := requestctx.AddUser(ctx, userInfo)
		require.NoError(t, err)

		rctx := chi.NewRouteContext()
		rctx.URLParams.Add("repoOwner", "testowner")
		rctx.URLParams.Add("repoName", "testrepo")
		ctx = context.WithValue(ctx, chi.RouteCtxKey, rctx)

		req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/custom-agents/testowner/testrepo", nil)
		rr := httptest.NewRecorder()

		handler := h.middleware(captureHandler, "test_endpoint")
		handler.ServeHTTP(rr, req)

		assert.Equal(t, http.StatusOK, rr.Code)
		assert.NotNil(t, capturedUserInfo)
		assert.Equal(t, uint64(456), capturedUserInfo.ID)
		assert.NotNil(t, capturedBaseTags)
		assert.Equal(t, "test_endpoint", capturedBaseTags["endpoint"])
	})
}

func TestVerifyTokenAccess(t *testing.T) {
	obsv := observability.NewNoopExporters()

	t.Run("returns true when token has access", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := context.Background()
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
			},
		}

		hasAccess, err := h.verifyTokenAccess(ctx, userInfo, "testowner", "testrepo")
		require.NoError(t, err)
		assert.True(t, hasAccess)
	})

	t.Run("returns false when token does not have access", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
			return &coreTwirp.BatchControlAccessResponse{
				Decisions: []*coreTwirp.AuthorizationDecision{
					{
						Id:       "test-id",
						Decision: false,
					},
				},
			}, nil
		}
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := context.Background()
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
			},
		}

		hasAccess, err := h.verifyTokenAccess(ctx, userInfo, "testowner", "testrepo")
		require.NoError(t, err)
		assert.False(t, hasAccess)
	})

	t.Run("returns error when authorization check fails", func(t *testing.T) {
		ffClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopAuthorizationAPI.MockBatchControlAccess = func(ctx context.Context, req *coreTwirp.BatchControlAccessRequest) (*coreTwirp.BatchControlAccessResponse, error) {
			return nil, goerrors.New("authorization service error")
		}
		spokes := customagenttest.MakeSpokes(t, map[string]string{})
		svc := customagent.NewService(obsv, spokes, ghTwirp, ffClient)
		h := NewHandler(obsv, ffClient, ghTwirp, svc)

		ctx := context.Background()
		userInfo := &requestctx.UserInfo{
			ID: 123,
			TokenInfo: &requestctx.TokenInfo{
				Token: "test-token",
			},
		}

		hasAccess, err := h.verifyTokenAccess(ctx, userInfo, "testowner", "testrepo")
		require.Error(t, err)
		assert.False(t, hasAccess)
		assert.Contains(t, err.Error(), "authorization service error")
	})
}
