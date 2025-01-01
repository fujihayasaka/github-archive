package refactortests

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/build"
)

func BuildsCompatTest(t *testing.T, clp func(string) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"queue":              builds_Queue,
		"runInfo":            builds_RunInfo,
		"cancel":             builds_Cancel,
		"deleteLogs":         builds_DeleteLogs,
		"deleteLogsByPlanID": builds_DeleteLogsByPlanID,
		"reportAdminEvent":   builds_ReportAdminEvent,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clp)
		})
	}
}

func builds_Queue(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/testProject/_apis/pipelines/0/runs?api-version=5.2-preview",
		method: "POST",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "multipart/related",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		want         *azp.Build
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testBuild, t)),
			},
			want:    testBuild,
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Failure path",
			giveResponse: httpResponse{
				code: 500,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.giveResponse.code)
				if tt.giveResponse.body != "" {
					io.WriteString(w, tt.giveResponse.body)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			got, err := clientProvider(ts.URL).Queue(ctx, newWFB(), "", "", "", map[string]string{}, map[string]string{}, nil, nil, map[string]bool{}, launchconfig.TestAppEnv)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func builds_RunInfo(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/testProject/_apis/pipelines/runinfo/00000000-0000-0000-0000-000000000000",
		method: "GET",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		want         *azp.RunInfoResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunInfoResponse, t)),
			},
			want:    testRunInfoResponse,
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Failure path",
			giveResponse: httpResponse{
				code: 500,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.giveResponse.code)
				if tt.giveResponse.body != "" {
					io.WriteString(w, tt.giveResponse.body)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			got, err := clientProvider(ts.URL).RunInfo(ctx, types.NilWorkflowExecutionID)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func builds_Cancel(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/testProject/_apis/pipelines/0/runs/?api-version=5.2-preview",
		method: "PATCH",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
			},
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Failure path",
			giveResponse: httpResponse{
				code: 500,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.giveResponse.code)
				if tt.giveResponse.body != "" {
					io.WriteString(w, tt.giveResponse.body)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			err := clientProvider(ts.URL).Cancel(ctx, "", nil)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func builds_DeleteLogs(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/testProject/_apis/pipelines/0/runs/00000000-0000-0000-0000-000000000000/logs?api-version=5.1-preview",
		method: "DELETE",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
			},
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Failure path",
			giveResponse: httpResponse{
				code: 500,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.giveResponse.code)
				if tt.giveResponse.body != "" {
					io.WriteString(w, tt.giveResponse.body)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			err := clientProvider(ts.URL).DeleteLogs(ctx, types.NilActionExecutionID.String())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func builds_DeleteLogsByPlanID(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/pipelines/plans/1/logs?api-version=6.0-preview",
		method: "DELETE",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
			},
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Failure path",
			giveResponse: httpResponse{
				code: 500,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.giveResponse.code)
				if tt.giveResponse.body != "" {
					io.WriteString(w, tt.giveResponse.body)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			err := clientProvider(ts.URL).DeleteLogsByPlanID(ctx, "1")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func builds_ReportAdminEvent(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/pipelines/adminevents?api-version=6.0-preview",
		method: "POST",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
			},
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Failure path",
			giveResponse: httpResponse{
				code: 500,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.giveResponse.code)
				if tt.giveResponse.body != "" {
					io.WriteString(w, tt.giveResponse.body)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			err := clientProvider(ts.URL).ReportAdminEvent(ctx, "", map[string]string{})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func newWFB() *build.WorkflowBuild {
	return &build.WorkflowBuild{
		SigningKey: &hkdf.DerivedKey{
			WorkflowID: "test-id",
			Timestamp:  time.Now(),
		},
		WorkflowFilePath: ".github/workflows/one.yml",
		ResolvedFiles: []types.ResolvedFile{
			{
				Path: ".github/workflows/one.yml",
				Text: "build-file-content",
				SHA:  "bbcc",
			},
		},
		EventPayload: []byte("{}"),
	}
}

var testBuild = &azp.Build{}
var testRunInfoResponse = &azp.RunInfoResponse{}
