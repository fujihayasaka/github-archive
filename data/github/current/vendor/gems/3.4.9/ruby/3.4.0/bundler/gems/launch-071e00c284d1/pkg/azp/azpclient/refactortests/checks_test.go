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

var testChangeIDResponseSteps = []*azp.ChangeIDResponseSteps{
	{Name: "build step"},
}

var testChangeIDResponseJobSteps = []*azp.ChangeIDResponseJobSteps{
	{ID: "asdf", Steps: testChangeIDResponseSteps},
}
var testChangeIDResponse = &azp.ChangeIDResponse{Steps: testChangeIDResponseSteps}
var testChangeIDResponseJobs = &azp.ChangeIDResponseForRun{Jobs: testChangeIDResponseJobSteps}

func ChecksCompatTest(t *testing.T, clp func(string) azp.RepositoryClient) {
	testChecksService_StepsFromChangeID(t, clp)
}

func testChecksService_StepsFromChangeID(t *testing.T, clp func(string) azp.RepositoryClient) {
	type args struct {
		ctx      context.Context
		changeID int64
		jobID    string
		planID   string
	}

	defaultArgs := args{
		ctx:      context.TODO(),
		changeID: 1,
		jobID:    "asdf",
		planID:   "asdf",
	}

	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/pipelines/plans/asdf/jobs/asdf/steps?api-version=6.0-preview&changeId=1",
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
		args         args
		giveResponse httpResponse
		wantReq      httpRequest
		want         []*azp.ChangeIDResponseSteps
		wantErr      bool
	}{
		{
			name: "Happy Path",
			args: defaultArgs,
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testChangeIDResponse, t)),
			},
			wantReq: defaultWantReq,
			want:    testChangeIDResponseSteps,
			wantErr: false,
		},
		{
			name: "Failure path",
			args: defaultArgs,
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

			got, err := clp(ts.URL).StepsFromChangeID(tt.args.ctx, tt.args.changeID, tt.args.jobID, tt.args.planID)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func testChecksService_JobStepsFromChangeID(t *testing.T, clp func(string) azp.RepositoryClient) {
	type args struct {
		ctx                context.Context
		changeID           int64
		planID             string
		onlyInProgressJobs bool
	}

	defaultArgs := args{
		ctx:                context.TODO(),
		changeID:           1,
		planID:             "asdf",
		onlyInProgressJobs: true,
	}

	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/pipelines/plans/asdf/jobs?api-version=6.0-preview&changeId=1&onlyInProgressJobs=true",
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
		args         args
		giveResponse httpResponse
		wantReq      httpRequest
		want         []*azp.ChangeIDResponseJobSteps
		wantErr      bool
	}{
		{
			name: "Happy Path",
			args: defaultArgs,
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testChangeIDResponseJobs, t)),
			},
			wantReq: defaultWantReq,
			want:    testChangeIDResponseJobSteps,
			wantErr: false,
		},
		{
			name: "Failure path",
			args: defaultArgs,
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

			got, err := clp(ts.URL).StepsFromChangeIDForRun(tt.args.ctx, tt.args.changeID, tt.args.planID, tt.args.onlyInProgressJobs)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}
