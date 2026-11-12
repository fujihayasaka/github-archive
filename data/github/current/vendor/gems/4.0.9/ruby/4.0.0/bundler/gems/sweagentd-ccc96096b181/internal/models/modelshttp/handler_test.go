package modelshttp

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	authd "github.com/github/authnd/client"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/models"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// setupTestHandler creates a new handler with test dependencies
func setupTestHandler(t *testing.T, capiClient *capi.NoopClient, ghTwirpClient *githubtwirp.NoopClient, ffs featureflags.Client) (context.Context, *chi.Mux) {
	t.Helper()
	obsv := observability.NewNoopExporters()

	// Create authenticated request
	ctx := t.Context()
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID:    123,
			Login: "testuser",
			TokenInfo: &requestctx.TokenInfo{
				ApplicationID: 12345,
				Type:          string(authd.CredentialTypeUserToServerToken),
				Token:         "test-token",
			},
		},
	})

	svc := models.NewService(capiClient)
	h := NewHandler(obsv, svc, ghTwirpClient, ffs)

	r := chi.NewRouter()
	h.RegisterRoutes(r)

	return ctx, r
}

func TestListModels(t *testing.T) {
	t.Run("requires authenticated user", func(t *testing.T) {
		_, r := setupTestHandler(t, nil, nil, nil)

		// Make request without authentication context
		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert unauthorized
		assert.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("returns autoModel when CAPI returns empty list", func(t *testing.T) {
		// Create a noop CAPI client with mock that returns empty list
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{}, nil
		}

		// Create a noop GitHub Twirp client with mock that returns individual plan
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess: true,
				},
			}, nil
		}

		// Create a noop feature flags client
		ffs := featureflags.NewNoopClient(map[string]bool{})

		ctx, r := setupTestHandler(t, capiClient, ghTwirpClient, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert success
		require.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

		// Parse response
		var resp listModelsResponse
		err := json.NewDecoder(w.Body).Decode(&resp)
		require.NoError(t, err)

		// Assert structure
		assert.Equal(t, "list", resp.Object)
		assert.NotNil(t, resp.Data)

		// Assert autoModel is always returned and is first
		require.Equal(t, 1, len(resp.Data))
		assert.Equal(t, capi.AutoMode, resp.Data[0].ID)
		assert.Equal(t, "Auto", resp.Data[0].Name)
	})

	t.Run("returns autoModel first followed by CAPI models", func(t *testing.T) {
		// Create a noop CAPI client with mock that returns models
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{
					ID:      "claude-sonnet-4.5",
					Name:    "Claude Sonnet 4.5",
					Object:  "model",
					Version: "4.5",
				},
				{
					ID:      "gpt-5.1",
					Name:    "GPT 5.1",
					Object:  "model",
					Version: "5.1",
				},
			}, nil
		}

		// Create a noop GitHub Twirp client with mock that returns individual plan
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_INDIVIDUAL,
					HasPaidAccess: true,
				},
			}, nil
		}

		// Create a noop feature flags client
		ffs := featureflags.NewNoopClient(map[string]bool{})

		ctx, r := setupTestHandler(t, capiClient, ghTwirpClient, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert success
		require.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

		// Parse response
		var resp listModelsResponse
		err := json.NewDecoder(w.Body).Decode(&resp)
		require.NoError(t, err)

		// Assert structure
		assert.Equal(t, "list", resp.Object)
		assert.NotNil(t, resp.Data)

		// Assert autoModel is always returned and is first, followed by CAPI models
		require.Equal(t, 3, len(resp.Data))
		assert.Equal(t, capi.AutoMode, resp.Data[0].ID)
		assert.Equal(t, "Auto", resp.Data[0].Name)

		// Assert CAPI models follow autoModel
		assert.Equal(t, "claude-sonnet-4.5", resp.Data[1].ID)
		assert.Equal(t, "gpt-5.1", resp.Data[2].ID)
	})

	t.Run("returns empty list for Business users", func(t *testing.T) {
		// Create a noop CAPI client
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{
					ID:      "claude-sonnet-4.5",
					Name:    "Claude Sonnet 4.5",
					Object:  "model",
					Version: "4.5",
				},
			}, nil
		}

		// Create a noop GitHub Twirp client with mock that returns business plan
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
					HasPaidAccess: true,
				},
			}, nil
		}

		// Create a noop feature flags client (flag disabled by default)
		ffs := featureflags.NewNoopClient(map[string]bool{})

		ctx, r := setupTestHandler(t, capiClient, ghTwirpClient, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert success
		require.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

		// Parse response
		var resp listModelsResponse
		err := json.NewDecoder(w.Body).Decode(&resp)
		require.NoError(t, err)

		// Assert structure
		assert.Equal(t, "list", resp.Object)
		assert.NotNil(t, resp.Data)

		// Assert empty list for Business users
		require.Equal(t, 0, len(resp.Data))
	})

	t.Run("returns empty list for Enterprise users", func(t *testing.T) {
		// Create a noop CAPI client
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{
					ID:      "claude-sonnet-4.5",
					Name:    "Claude Sonnet 4.5",
					Object:  "model",
					Version: "4.5",
				},
			}, nil
		}

		// Create a noop GitHub Twirp client with mock that returns enterprise plan
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
					HasPaidAccess: true,
				},
			}, nil
		}

		// Create a noop feature flags client (flag disabled by default)
		ffs := featureflags.NewNoopClient(map[string]bool{})

		ctx, r := setupTestHandler(t, capiClient, ghTwirpClient, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert success
		require.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

		// Parse response
		var resp listModelsResponse
		err := json.NewDecoder(w.Body).Decode(&resp)
		require.NoError(t, err)

		// Assert structure
		assert.Equal(t, "list", resp.Object)
		assert.NotNil(t, resp.Data)

		// Assert empty list for Enterprise users
		require.Equal(t, 0, len(resp.Data))
	})

	t.Run("returns models for Business users when feature flag is enabled", func(t *testing.T) {
		// Create a noop CAPI client
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{
					ID:      "claude-sonnet-4.5",
					Name:    "Claude Sonnet 4.5",
					Object:  "model",
					Version: "4.5",
				},
			}, nil
		}

		// Create a noop GitHub Twirp client with mock that returns business plan
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_BUSINESS,
					HasPaidAccess: true,
				},
			}, nil
		}

		// Create a noop feature flags client with the flag enabled
		ffs := featureflags.NewNoopClient(map[string]bool{
			"coding_agent_model_selection_all_skus": true,
		})

		ctx, r := setupTestHandler(t, capiClient, ghTwirpClient, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert success
		require.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

		// Parse response
		var resp listModelsResponse
		err := json.NewDecoder(w.Body).Decode(&resp)
		require.NoError(t, err)

		// Assert structure
		assert.Equal(t, "list", resp.Object)
		assert.NotNil(t, resp.Data)

		// Assert models are returned for Business users when flag is enabled
		require.Equal(t, 2, len(resp.Data))
		assert.Equal(t, capi.AutoMode, resp.Data[0].ID)
		assert.Equal(t, "claude-sonnet-4.5", resp.Data[1].ID)
	})

	t.Run("returns models for Enterprise users when feature flag is enabled", func(t *testing.T) {
		// Create a noop CAPI client
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return []capi.Model{
				{
					ID:      "gpt-5.1",
					Name:    "GPT 5.1",
					Object:  "model",
					Version: "5.1",
				},
			}, nil
		}

		// Create a noop GitHub Twirp client with mock that returns enterprise plan
		ghTwirpClient := githubtwirp.NewNoopClient()
		ghTwirpClient.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{
					CopilotPlan:   copilotUsersTwirp.CopilotPlan_COPILOT_PLAN_ENTERPRISE,
					HasPaidAccess: true,
				},
			}, nil
		}

		// Create a noop feature flags client with the flag enabled
		ffs := featureflags.NewNoopClient(map[string]bool{
			"coding_agent_model_selection_all_skus": true,
		})

		ctx, r := setupTestHandler(t, capiClient, ghTwirpClient, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		// Assert success
		require.Equal(t, http.StatusOK, w.Code)
		assert.Equal(t, "application/json", w.Header().Get("Content-Type"))

		// Parse response
		var resp listModelsResponse
		err := json.NewDecoder(w.Body).Decode(&resp)
		require.NoError(t, err)

		// Assert structure
		assert.Equal(t, "list", resp.Object)
		assert.NotNil(t, resp.Data)

		// Assert models are returned for Enterprise users when flag is enabled
		require.Equal(t, 2, len(resp.Data))
		assert.Equal(t, capi.AutoMode, resp.Data[0].ID)
		assert.Equal(t, "gpt-5.1", resp.Data[1].ID)
	})

	t.Run("propagates 403 from CAPI", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return nil, joberrors.NewCAPIError(&http.Response{StatusCode: http.StatusForbidden}, "forbidden")
		}

		ffs := featureflags.NewNoopClient(map[string]bool{})

		ctx, r := setupTestHandler(t, capiClient, nil, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("propagates 401 from CAPI", func(t *testing.T) {
		capiClient := capi.NewNoopClient()
		capiClient.MockListCodingAgentModels = func(ctx context.Context, userID uint64) ([]capi.Model, error) {
			return nil, joberrors.NewCAPIError(&http.Response{StatusCode: http.StatusUnauthorized}, "unauthorized")
		}

		ffs := featureflags.NewNoopClient(map[string]bool{})

		ctx, r := setupTestHandler(t, capiClient, nil, ffs)

		req := httptest.NewRequest(http.MethodGet, "/models", http.NoBody)
		req = req.WithContext(ctx)
		w := httptest.NewRecorder()

		r.ServeHTTP(w, req)

		assert.Equal(t, http.StatusUnauthorized, w.Code)
	})
}
