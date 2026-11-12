package capi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_CreateModelSession(t *testing.T) {
	tests := []struct {
		name          string
		responseData  ModelSessionResponse
		responseBody  string
		statusCode    int
		existingToken string
		expectError   bool
		expectedCode  int
	}{
		{
			name: "success",
			responseData: ModelSessionResponse{
				AvailableModels: []string{"gpt-4"},
				SelectedModel:   "gpt-4",
				SessionToken:    "test-session-token",
				ExpiresAt:       1700000000,
			},
			statusCode: http.StatusOK,
		},
		{
			name: "success with existing token",
			responseData: ModelSessionResponse{
				AvailableModels: []string{"gpt-4"},
				SelectedModel:   "gpt-4",
				SessionToken:    "refreshed-session-token",
				ExpiresAt:       1700001000,
			},
			statusCode:    http.StatusOK,
			existingToken: "old-token",
		},
		{
			name:         "not authorized",
			responseBody: `{"error":"not authorized"}`,
			statusCode:   http.StatusUnauthorized,
			expectError:  true,
			expectedCode: http.StatusUnauthorized,
		},
		{
			name:         "too many requests",
			responseBody: `{"error":"rate limited"}`,
			statusCode:   http.StatusTooManyRequests,
			expectError:  true,
			expectedCode: http.StatusTooManyRequests,
		},
		{
			name:         "internal server error",
			responseBody: `{"error":"internal error"}`,
			statusCode:   http.StatusInternalServerError,
			expectError:  true,
			expectedCode: http.StatusInternalServerError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				require.Equal(t, "/models/session", r.URL.Path)
				require.Equal(t, http.MethodPost, r.Method)
				require.Equal(t, "application/json", r.Header.Get("Content-Type"))
				require.Equal(t, "123", r.Header.Get(GitHubUserIDHeader))

				// Verify request body
				body, err := io.ReadAll(r.Body)
				require.NoError(t, err)
				var reqBody ModelSessionRequest
				require.NoError(t, json.Unmarshal(body, &reqBody))
				require.NotNil(t, reqBody.AutoMode)
				require.Equal(t, []string{"test-model"}, reqBody.AutoMode.ModelHints)

				// Verify existing token header
				if tt.existingToken != "" {
					require.Equal(t, tt.existingToken, r.Header.Get("Copilot-Session-Token"))
				} else {
					require.Empty(t, r.Header.Get("Copilot-Session-Token"))
				}

				w.WriteHeader(tt.statusCode)
				if tt.statusCode == http.StatusOK {
					err := json.NewEncoder(w).Encode(tt.responseData)
					require.NoError(t, err)
				} else if tt.responseBody != "" {
					_, _ = w.Write([]byte(tt.responseBody))
				}
			}))
			defer server.Close()

			baseURL, err := url.Parse(server.URL)
			require.NoError(t, err)

			client := &HmacClient{
				baseURL: *baseURL,
				http:    &http.Client{},
				obsv:    observability.NewNoopExporters(),
			}

			response, err := client.CreateModelSession(context.Background(), 123, []string{"test-model"}, tt.existingToken)

			if tt.expectError {
				require.Nil(t, response)
				require.Error(t, err)
				var capiErr *joberrors.CAPIError
				if errors.As(err, &capiErr) {
					require.Equal(t, tt.expectedCode, capiErr.StatusCode())
				}
				if tt.responseBody != "" {
					require.Contains(t, err.Error(), tt.responseBody)
				}
			} else {
				require.NoError(t, err)
				require.NotNil(t, response)
				assert.Equal(t, tt.responseData.SessionToken, response.SessionToken)
				assert.Equal(t, tt.responseData.SelectedModel, response.SelectedModel)
				assert.Equal(t, tt.responseData.ExpiresAt, response.ExpiresAt)
				assert.Equal(t, tt.responseData.AvailableModels, response.AvailableModels)
			}
		})
	}
}

func Test_CreateModelSession_WithDiscountedCosts(t *testing.T) {
	expectedCosts := map[string]float64{
		"gpt-4":    0.5,
		"claude-4": 0.3,
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		err := json.NewEncoder(w).Encode(ModelSessionResponse{
			SessionToken:    "token-with-costs",
			ExpiresAt:       1700000000,
			DiscountedCosts: expectedCosts,
		})
		require.NoError(t, err)
	}))
	defer server.Close()

	baseURL, err := url.Parse(server.URL)
	require.NoError(t, err)

	client := &HmacClient{
		baseURL: *baseURL,
		http:    &http.Client{},
		obsv:    observability.NewNoopExporters(),
	}

	response, err := client.CreateModelSession(context.Background(), 123, []string{"gpt-4"}, "")
	require.NoError(t, err)
	require.NotNil(t, response)
	assert.Equal(t, expectedCosts, response.DiscountedCosts)
}

func Test_CreateModelSessionIntent(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, "/models/session/intent", r.URL.Path)
			require.Equal(t, http.MethodPost, r.Method)
			require.Equal(t, "application/json", r.Header.Get("Content-Type"))
			require.Equal(t, "123", r.Header.Get(GitHubUserIDHeader))
			require.Equal(t, "session-token", r.Header.Get("Copilot-Session-Token"))

			body, err := io.ReadAll(r.Body)
			require.NoError(t, err)
			var reqBody ModelSessionIntentRequest
			require.NoError(t, json.Unmarshal(body, &reqBody))
			require.Equal(t, "Refactor this", reqBody.Prompt)
			require.Equal(t, []string{"claude-sonnet-4.6", "gpt-5-mini"}, reqBody.AvailableModels)

			w.WriteHeader(http.StatusOK)
			err = json.NewEncoder(w).Encode(ModelSessionIntentResponse{
				ChosenModel:     "gpt-5-mini",
				CandidateModels: []string{"gpt-5-mini", "claude-sonnet-4.6"},
				Confidence:      0.82,
				Fallback:        false,
			})
			require.NoError(t, err)
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &HmacClient{
			baseURL: *baseURL,
			http:    &http.Client{},
			obsv:    observability.NewNoopExporters(),
		}

		resp, err := client.CreateModelSessionIntent(context.Background(), 123, "session-token", ModelSessionIntentRequest{
			Prompt:          "Refactor this",
			AvailableModels: []string{"claude-sonnet-4.6", "gpt-5-mini"},
		})
		require.NoError(t, err)
		require.NotNil(t, resp)
		assert.Equal(t, "gpt-5-mini", resp.ChosenModel)
		assert.False(t, resp.Fallback)
	})

	t.Run("missing session token returns error without HTTP call", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			t.Fatal("HTTP call should not be made when session token is missing")
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &HmacClient{
			baseURL: *baseURL,
			http:    &http.Client{},
			obsv:    observability.NewNoopExporters(),
		}

		resp, err := client.CreateModelSessionIntent(context.Background(), 123, "", ModelSessionIntentRequest{
			Prompt:          "hi",
			AvailableModels: []string{"gpt-5-mini"},
		})
		require.Error(t, err)
		require.Nil(t, resp)
	})

	t.Run("non-200 returns CAPI error", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
			_, _ = w.Write([]byte(`{"error":"invalid session token"}`))
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)

		client := &HmacClient{
			baseURL: *baseURL,
			http:    &http.Client{},
			obsv:    observability.NewNoopExporters(),
		}

		resp, err := client.CreateModelSessionIntent(context.Background(), 123, "session-token", ModelSessionIntentRequest{
			Prompt:          "hi",
			AvailableModels: []string{"gpt-5-mini"},
		})
		require.Error(t, err)
		require.Nil(t, resp)
		var capiErr *joberrors.CAPIError
		if errors.As(err, &capiErr) {
			require.Equal(t, http.StatusUnauthorized, capiErr.StatusCode())
		}
	})
}
