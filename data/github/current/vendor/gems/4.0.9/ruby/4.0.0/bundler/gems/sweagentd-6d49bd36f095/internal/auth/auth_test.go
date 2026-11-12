package auth

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/agenticapp/agenticapptest"
	"github.com/github/sweagentd/internal/authnd"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/require"
)

func TestAuth_Middleware(t *testing.T) {
	githubAppID := int64(123)

	t.Run("missing authorization header", func(t *testing.T) {
		a := NewAuthenticator(observability.NewNoopExporters(), nil, nil, nil)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		r := httptest.NewRecorder()
		a.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Fail(t, "should not have called this handler")
		})).ServeHTTP(r, req)

		require.Equal(t, http.StatusUnauthorized, r.Code, r.Body)
	})

	testCases := []struct {
		token string
		valid bool
	}{
		{token: "Bearer ghu_123abc", valid: true},
		{token: "bearer ghu_123abc", valid: true},
		{token: "token ghu_123abc", valid: true},
		{token: "Bearer blahhhh", valid: false},   // Bad token
		{token: "meepmorp blahhhh", valid: false}, // Bad format
	}

	for _, token := range testCases {
		t.Run(fmt.Sprintf("correctly handles %s", token.token), func(t *testing.T) {
			authndClient := authnd.NoopClient{
				UserLogin:     "test",
				ApplicationID: uint64(githubAppID),
			}
			ffAltClient := featureflags.NewNoopClient(map[string]bool{})
			ghTwirp := githubtwirp.NewNoopClient()
			ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
				return &copilotUsersTwirp.GetCopilotUserResponse{
					UserDetails: &copilotUsersTwirp.CopilotUserDetails{
						AnalyticsTrackingId: "test-tracking-id",
					},
				}, nil
			}
			a := NewAuthenticator(observability.NewNoopExporters(), authndClient, ghTwirp, ffAltClient)

			req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
			req.Header.Add("Authorization", token.token)

			r := httptest.NewRecorder()
			didCall := false
			a.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				didCall = true

				u, ok := requestctx.User(r.Context())
				require.True(t, ok)
				require.Equal(t, authndClient.UserLogin, u.Login)

				w.WriteHeader(http.StatusOK)
				w.Write([]byte(u.Login))
			})).ServeHTTP(r, req)

			if token.valid {
				require.Equal(t, http.StatusOK, r.Code, r.Body)
				require.True(t, didCall)
			} else {
				require.Equal(t, http.StatusUnauthorized, r.Code, r.Body)
				require.False(t, didCall)
			}
		})
	}
}

func TestAuth_Middleware_CachesCopilotUserDetails(t *testing.T) {
	t.Run("copilot user details are cached in context", func(t *testing.T) {
		actorID := uint64(456)
		expectedTrackingID := "test-tracking-id"

		authndClient := authnd.NoopClient{
			UserLogin: "test",
			ActorID:   actorID,
		}
		ffAltClient := featureflags.NewNoopClient(map[string]bool{})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			userDetails := &copilotUsersTwirp.CopilotUserDetails{
				Id:                  req.Id,
				AnalyticsTrackingId: expectedTrackingID,
			}
			// Cache the user details in the context, like the real client does
			_ = requestctx.AddCopilotUserDetails(ctx, int64(req.Id), userDetails)
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: userDetails,
			}, nil
		}
		a := NewAuthenticator(observability.NewNoopExporters(), authndClient, ghTwirp, ffAltClient)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req.Header.Add("Authorization", "Bearer ghu_123abc")

		r := httptest.NewRecorder()
		a.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Verify that the copilot user details are cached in the context
			cachedDetails, ok := requestctx.CopilotUserDetails(r.Context(), int64(actorID))
			require.True(t, ok, "CopilotUserDetails should be cached in context")
			require.NotNil(t, cachedDetails)
			require.Equal(t, expectedTrackingID, cachedDetails.AnalyticsTrackingId)
			require.Equal(t, actorID, cachedDetails.Id)

			w.WriteHeader(http.StatusOK)
		})).ServeHTTP(r, req)

		require.Equal(t, http.StatusOK, r.Code)
	})
}

func TestAuth_Middleware_PopulatesAgentSlug(t *testing.T) {
	const testAgentID = int64(1234)

	t.Run("populates CtxAgent slug when flag is on and appProvider configured", func(t *testing.T) {
		authndClient := authnd.NoopClient{
			UserLogin:     "test",
			ApplicationID: uint64(testAgentID),
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentEmitAgentSlugTelemetry: true,
		})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{},
			}, nil
		}

		a := NewAuthenticator(observability.NewNoopExporters(), authndClient, ghTwirp, ffClient)
		a.SetAppProvider(agenticapptest.NewTestProviderWithID(t, testAgentID))

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req.Header.Add("Authorization", "Bearer ghu_123abc")

		r := httptest.NewRecorder()
		a.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctxAgent, ok := requestctx.Agent(r.Context())
			require.True(t, ok, "CtxAgent should be populated")
			require.Equal(t, "copilot", ctxAgent.Slug)
			w.WriteHeader(http.StatusOK)
		})).ServeHTTP(r, req)

		require.Equal(t, http.StatusOK, r.Code)
	})

	t.Run("does not populate CtxAgent when appProvider is unset", func(t *testing.T) {
		authndClient := authnd.NoopClient{
			UserLogin:     "test",
			ApplicationID: uint64(testAgentID),
		}
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentEmitAgentSlugTelemetry: true,
		})
		ghTwirp := githubtwirp.NewNoopClient()
		ghTwirp.NoopUserDetailAPI.MockGetCopilotUser = func(ctx context.Context, req *copilotUsersTwirp.GetCopilotUserRequest) (*copilotUsersTwirp.GetCopilotUserResponse, error) {
			return &copilotUsersTwirp.GetCopilotUserResponse{
				UserDetails: &copilotUsersTwirp.CopilotUserDetails{},
			}, nil
		}

		a := NewAuthenticator(observability.NewNoopExporters(), authndClient, ghTwirp, ffClient)

		req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
		req.Header.Add("Authorization", "Bearer ghu_123abc")

		r := httptest.NewRecorder()
		a.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctxAgent, ok := requestctx.Agent(r.Context())
			if ok {
				require.Empty(t, ctxAgent.Slug)
			}
			w.WriteHeader(http.StatusOK)
		})).ServeHTTP(r, req)

		require.Equal(t, http.StatusOK, r.Code)
	})
}
