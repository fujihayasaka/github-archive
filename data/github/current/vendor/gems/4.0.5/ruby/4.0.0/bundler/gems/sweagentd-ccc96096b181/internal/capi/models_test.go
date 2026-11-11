package capi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/observability"
)

func Test_listModels(t *testing.T) {
	tests := []struct {
		name         string
		responseData listModelsResponse
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
			statusCode:   http.StatusUnauthorized,
			expectError:  true,
			expectedCode: http.StatusUnauthorized,
		},
		{
			name:         "too many requests",
			statusCode:   http.StatusTooManyRequests,
			expectError:  true,
			expectedCode: http.StatusTooManyRequests,
		},
		{
			name:         "internal server error",
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
			response, err := client.listModels(context.Background(), 123)

			if tt.expectError {
				require.Nil(t, response)
				require.Error(t, err)
				var capiErr *joberrors.CAPIError
				if errors.As(err, &capiErr) {
					require.Equal(t, tt.expectedCode, capiErr.StatusCode())
				}
			} else {
				require.NoError(t, err)
				require.Equal(t, &tt.responseData, response)
			}
		})
	}
}
