package capi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
)

func Test_listModels(t *testing.T) {
	tests := []struct {
		name         string
		responseData listModelsResponse
		responseBody string
		statusCode   int
		expectError  bool
		expectedCode int
	}{
		{
			name: "success",
			responseData: listModelsResponse{
				Object: "list",
				Data: []Model{
					{
						ID:   "test-model",
						Name: "Test Model",
					},
				},
			},
			statusCode:   http.StatusOK,
			expectedCode: http.StatusOK,
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
			// Create test server
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				require.Equal(t, "/models", r.URL.Path)

				w.WriteHeader(tt.statusCode)
				if tt.statusCode == http.StatusOK {
					err := json.NewEncoder(w).Encode(tt.responseData)
					require.NoError(t, err)
				} else if tt.responseBody != "" {
					_, _ = w.Write([]byte(tt.responseBody))
				}
			}))
			defer server.Close()

			// Create client
			baseURL, err := url.Parse(server.URL)
			require.NoError(t, err)

			obsv := observability.NewNoopExporters()

			client := &HmacClient{
				baseURL: *baseURL,
				http:    &http.Client{},
				obsv:    obsv,
			}

			// Call the method
			response, err := client.listModels(context.Background(), 123, "")

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
				require.Equal(t, &tt.responseData, response)
			}
		})
	}
}

func Test_ListCodingAgentModels_FiltersModelPickerEnabled(t *testing.T) {
	tests := []struct {
		name        string
		models      []Model
		expectedIDs []string
	}{
		{
			name: "includes model when model_picker_enabled is true",
			models: []Model{
				{ID: GPT54, ModelPickerEnabled: gg.Ptr(true)},
			},
			expectedIDs: []string{GPT54},
		},
		{
			name: "includes model when model_picker_enabled is nil (not set)",
			models: []Model{
				{ID: GPT54, ModelPickerEnabled: nil},
			},
			expectedIDs: []string{GPT54},
		},
		{
			name: "excludes model when model_picker_enabled is false",
			models: []Model{
				{ID: GPT54, ModelPickerEnabled: gg.Ptr(false)},
			},
			expectedIDs: []string{},
		},
		{
			name: "filters mix of enabled and disabled models",
			models: []Model{
				{ID: GPT54, ModelPickerEnabled: gg.Ptr(false)},
				{ID: ClaudeSonnet46, ModelPickerEnabled: gg.Ptr(true)},
				{ID: GPT53Codex, ModelPickerEnabled: nil},
			},
			expectedIDs: []string{ClaudeSonnet46, GPT53Codex},
		},
		{
			name: "excludes non-coding-agent models regardless of model_picker_enabled",
			models: []Model{
				{ID: "some-other-model", ModelPickerEnabled: gg.Ptr(true)},
				{ID: ClaudeSonnet46, ModelPickerEnabled: gg.Ptr(true)},
			},
			expectedIDs: []string{ClaudeSonnet46},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				require.Equal(t, "/models", r.URL.Path)
				w.WriteHeader(http.StatusOK)
				err := json.NewEncoder(w).Encode(listModelsResponse{
					Object: "list",
					Data:   tt.models,
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

			models, err := client.ListCodingAgentModels(context.Background(), 123, "")
			require.NoError(t, err)

			gotIDs := make([]string, len(models))
			for i, m := range models {
				gotIDs[i] = m.ID
			}
			assert.ElementsMatch(t, tt.expectedIDs, gotIDs)
		})
	}
}

func TestCodingAgentModelPickerModelFlags_IncludesGeminiModels(t *testing.T) {
	assert.Equal(t, featureflags.CodingAgentModelPickerGemini31ProPreview, CodingAgentModelPickerModelFlags[Gemini31ProPreview])
	assert.Equal(t, featureflags.CodingAgentModelPickerGemini35Flash, CodingAgentModelPickerModelFlags[Gemini35Flash])
}

func Test_listModels_ActorTypeHeader(t *testing.T) {
	t.Run("sends X-GitHub-Actor-Type header when actorType is set", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, "org", r.Header.Get(GitHubActorTypeHeader))
			require.Equal(t, "12345", r.Header.Get(GitHubUserIDHeader))
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(listModelsResponse{Data: []Model{}, Object: "list"})
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)
		client := &HmacClient{baseURL: *baseURL, http: &http.Client{}, obsv: observability.NewNoopExporters()}
		_, err = client.listModels(context.Background(), 12345, "org")
		require.NoError(t, err)
	})

	t.Run("omits X-GitHub-Actor-Type header when actorType is empty", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Empty(t, r.Header.Get(GitHubActorTypeHeader))
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(listModelsResponse{Data: []Model{}, Object: "list"})
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)
		client := &HmacClient{baseURL: *baseURL, http: &http.Client{}, obsv: observability.NewNoopExporters()}
		_, err = client.listModels(context.Background(), 12345, "")
		require.NoError(t, err)
	})
}

func Test_listModels_IntegrationIDOverride(t *testing.T) {
	t.Run("overrides Copilot-Integration-Id header when context carries integration ID", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, "claude-code-cloud", r.Header.Get(IntegrationIDHeader))
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(listModelsResponse{Data: []Model{}, Object: "list"})
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)
		client := &HmacClient{baseURL: *baseURL, http: &http.Client{}, obsv: observability.NewNoopExporters()}

		ctx := ContextWithCAPIIntegrationID(context.Background(), "claude-code-cloud")
		_, err = client.listModels(ctx, 123, "")
		require.NoError(t, err)
	})

	t.Run("uses default integration ID when context has no override", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Empty(t, r.Header.Get(IntegrationIDHeader))
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(listModelsResponse{Data: []Model{}, Object: "list"})
		}))
		defer server.Close()

		baseURL, err := url.Parse(server.URL)
		require.NoError(t, err)
		client := &HmacClient{baseURL: *baseURL, http: &http.Client{}, obsv: observability.NewNoopExporters()}

		_, err = client.listModels(context.Background(), 123, "")
		require.NoError(t, err)
	})
}
