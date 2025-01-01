package refactortests

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/azp"
)

func ArtifactsCompatTest(t *testing.T, clp func(string) azp.RepositoryClient) {
	testArtifactsService_DeleteArtifact(t, clp)
	testArtifactsService_DeleteArtifactByPlanID(t, clp)
}

func testArtifactsService_DeleteArtifact(t *testing.T, clp func(string) azp.RepositoryClient) {
	type args struct {
		ctx           context.Context
		workflowRunID string
		artifactName  string
	}

	defaultArgs := args{
		ctx:           context.TODO(),
		workflowRunID: "wfid",
		artifactName:  "artifact",
	}

	defaultWantReq := httpRequest{
		uri:    "/testTenant/testProject/_apis/pipelines/0/runs/wfid/artifacts?artifactName=artifact&api-version=5.2-preview",
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
		args         args
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			args: defaultArgs,
			giveResponse: httpResponse{
				code: 204,
			},
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Permanent error, 400 <= statuscode <= 499",
			args: defaultArgs,
			giveResponse: httpResponse{
				code: 429,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
		{
			name:    "Ignore 404s",
			args:    defaultArgs,
			wantReq: defaultWantReq,
			giveResponse: httpResponse{
				code: 404,
			},
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
			err := clp(ts.URL).DeleteArtifact(tt.args.ctx, tt.args.workflowRunID, tt.args.artifactName)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func testArtifactsService_DeleteArtifactByPlanID(t *testing.T, clp func(url string) azp.RepositoryClient) {
	type args struct {
		ctx          context.Context
		planID       string
		artifactName string
	}
	defaultArgs := args{
		ctx:          context.TODO(),
		planID:       "planid",
		artifactName: "artifact",
	}

	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/pipelines/plans/planid/artifacts?artifactName=artifact&api-version=6.0-preview",
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
		args         args
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			args: defaultArgs,
			giveResponse: httpResponse{
				code: 204,
			},
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Permanent error, 400 <= statuscode <= 499",
			args: defaultArgs,
			giveResponse: httpResponse{
				code: 429,
			},
			wantReq: defaultWantReq,
			wantErr: true,
		},
		{
			name:    "Ignore 404s",
			args:    defaultArgs,
			wantReq: defaultWantReq,
			giveResponse: httpResponse{
				code: 404,
			},
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
			err := clp(ts.URL).DeleteArtifactByPlanID(tt.args.ctx, tt.args.planID, tt.args.artifactName)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}
