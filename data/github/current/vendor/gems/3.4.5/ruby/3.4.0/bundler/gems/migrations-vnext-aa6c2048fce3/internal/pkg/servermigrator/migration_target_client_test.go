package servermigrator

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
)

func TestSendResources(t *testing.T) {
	tests := []struct {
		name           string
		sourceURL      string
		resources      []*v1.Resource
		mockStatusCode int
		mockResponse   string
		expectedError  bool
	}{
		{
			name:      "successful request",
			sourceURL: "http://github.dev",
			resources: []*v1.Resource{
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: &v1.Mannequin{
							ResourceId: "http://github.dev/monalisa",
						},
					},
				},
			},
			mockStatusCode: http.StatusAccepted,
			mockResponse:   "",
			expectedError:  false,
		},
		{
			name:      "failed request",
			sourceURL: "http://github.dev",
			resources: []*v1.Resource{
				{
					Resource: &v1.Resource_Mannequin{
						Mannequin: &v1.Mannequin{
							ResourceId: "http://github.dev/monalisa",
						},
					},
				},
			},
			mockStatusCode: http.StatusBadRequest,
			mockResponse:   "bad request",
			expectedError:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assert.Equal(t, "/enterprise/migration/resources", r.URL.Path)
				assert.Equal(t, "application/json", r.Header.Get("Content-Type"))

				body, err := io.ReadAll(r.Body)
				assert.NoError(t, err)

				var payload map[string]interface{}
				err = json.Unmarshal(body, &payload)
				assert.NoError(t, err)
				assert.Equal(t, tt.sourceURL, payload["source_url"])

				resourcesJSON, ok := payload["resources"].([]interface{})
				assert.True(t, ok)
				assert.Equal(t, len(tt.resources), len(resourcesJSON))

				w.WriteHeader(tt.mockStatusCode)
				w.Write([]byte(tt.mockResponse))
			}))
			defer mockServer.Close()

			client := NewMigrationTargetClient(mockServer.URL, "test-token")

			err := client.SendResources(context.Background(), tt.sourceURL, tt.resources)
			if tt.expectedError {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}
