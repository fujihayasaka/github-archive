package ghinternal

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/testutils"
)

func TestResolveAction(t *testing.T) {
	tests := []struct {
		desc            string
		statusCode      int
		errExpected     bool
		inputAction     string
		resolvedAction  string
		wantName        string
		errMessage      string
		wantErr         error
		version         string
		wantVersion     string
		responseHeaders map[string]string
	}{
		{
			desc:           "returns a resolved action for a valid request",
			statusCode:     http.StatusOK,
			inputAction:    "actions/checkout",
			wantName:       "actions/checkout",
			resolvedAction: "actions/checkout",
			version:        "v2",
			wantVersion:    "v2",
		},
		{
			desc:           "returns a resolved action for a valid request when the version contains special characters",
			statusCode:     http.StatusOK,
			inputAction:    "actions/checkout",
			wantName:       "actions/checkout",
			resolvedAction: "actions/checkout",
			version:        "plus+branch",
			wantVersion:    "plus+branch",
		},
		{
			desc:           "returns the proper resolved action when the resolved name does not match the inputted name",
			statusCode:     http.StatusOK,
			inputAction:    "actions/checkout",
			wantName:       "actions/checkout",
			resolvedAction: "actions/checkout-redirect",
			version:        "v2",
			wantVersion:    "v2",
		},
		{
			desc:           "returns APIError for 404s with an error message when it's semantic",
			statusCode:     http.StatusNotFound,
			errExpected:    true,
			wantName:       "actions/checkout",
			inputAction:    "actions/checkout",
			resolvedAction: "actions/checkout",
			errMessage:     "Unable to resolve action",
			wantErr: &APIError{
				ErrorMessage: "Unable to resolve action",
				StatusCode:   http.StatusNotFound,
			},
		},
		{
			desc:           "returns general rate limiting error when a repository exceeds it's rate limit",
			statusCode:     http.StatusForbidden,
			errExpected:    true,
			errMessage:     "API rate limit exceeded for installation ID 1337.",
			wantName:       "actions/checkout",
			inputAction:    "actions/checkout",
			resolvedAction: "actions/checkout",
			version:        "v2",
			wantVersion:    "v2",
			wantErr: &APIError{
				ErrorMessage: "API rate limit exceeded while resolving action `actions/checkout@v2`.",
				StatusCode:   http.StatusForbidden,
			},
			responseHeaders: map[string]string{
				"X-RateLimit-Limit":     "60",
				"X-RateLimit-Remaining": "0",
			},
		},
		{
			desc:           "returns APIError for 404s with a repository not found when error message is Not Found",
			statusCode:     http.StatusNotFound,
			errExpected:    true,
			errMessage:     "Not Found",
			wantName:       "actions/checkout",
			inputAction:    "actions/checkout",
			resolvedAction: "actions/checkout",
			version:        "v2",
			wantVersion:    "v2",
			wantErr: &APIError{
				ErrorMessage: "Unable to resolve action `actions/checkout@v2`, repository not found",
				StatusCode:   http.StatusNotFound,
			},
		},
		{
			desc:           "returns an error for all other errors",
			statusCode:     http.StatusInternalServerError,
			errExpected:    true,
			errMessage:     "Internal Server Error",
			wantName:       "actions/checkout",
			inputAction:    "actions/checkout",
			resolvedAction: "actions/checkout",
			version:        "v2",
			wantVersion:    "v2",
			wantErr: &APIError{
				ErrorMessage: "Internal Server Error",
				StatusCode:   http.StatusInternalServerError,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			mux := http.NewServeMux()
			workflowRunId := int64(128)
			jobId := "00000000-0000-0000-0000-000000000000"
			workflowRepoId := uint64(25)
			mux.HandleFunc("/repos/actions/checkout/actions/resolve/{version...}", func(w http.ResponseWriter, req *http.Request) {
				assert.Equal(t, req.Header.Get("Authorization"), "Bearer test-token")
				assert.Equal(t, req.URL.Query().Get("workflowRunId"), strconv.FormatInt(workflowRunId, 10))
				assert.Equal(t, req.URL.Query().Get("jobId"), jobId)
				assert.Equal(t, req.URL.Query().Get("workflowRepoId"), strconv.FormatUint(workflowRepoId, 10))

				assert.Equal(t, req.PathValue("version"), url.QueryEscape(tt.version))

				for k, v := range tt.responseHeaders {
					w.Header().Add(k, v)
				}
				w.WriteHeader(tt.statusCode)

				if tt.statusCode >= 400 {
					errJSON := fmt.Sprintf(`{"message": "%s", "documentation_url": "https://docs.github.com"}`, tt.errMessage)
					_, _ = w.Write([]byte(errJSON))
					return
				}

				_, _ = w.Write([]byte(fmt.Sprintf(`
			{
				"name": "%s",
				"resolved_name": "%s",
				"resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				"tar_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
				"version": "%s",
				"zip_url": "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip"
			}
		`, tt.resolvedAction, tt.resolvedAction, tt.wantVersion)))
			})

			_, serverURL, teardown := newRemoteServer(mux)
			defer teardown()

			recordingLogger := testutils.NewRecordingLogger()

			cf := NewFactory(serverURL, observability.New(recordingLogger.Logger, statter.NullStatter()), testutils.NewNoopBreaker(), []byte("testsigningkey"), apphttp.NewClient(), httpclient.NewClientHooks())
			client, err := cf.CreateWithAccessToken(&tokens.AccessToken{
				Token:  "test-token",
				Expiry: time.Now(),
			})
			require.NoError(t, err)

			action, err := client.ResolveAction(context.Background(), tt.inputAction, types.GitRef(tt.version), workflowRunId, jobId, workflowRepoId)

			if tt.errExpected {
				assert.Error(t, err)
				if tt.wantErr != nil {
					assert.Equal(t, tt.wantErr, err)
				}
			} else {
				require.NoError(t, err)
				assert.Equal(t, action, &ResolvedAction{
					Name:         tt.wantName,
					ResolvedName: tt.resolvedAction,
					ResolvedSha:  "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
					TarURL:       "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.tar.gz",
					ZipURL:       "https://ghes/actions/checkout/archive/2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3.zip",
					Version:      tt.wantVersion,
				})
			}
		})
	}
}
