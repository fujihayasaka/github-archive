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

func RunnersCompatTest(t *testing.T, clientMaker func(string) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"listRunners":        runners_ListRunnersV2,
		"deleteRunners":      runners_DeleteRunner,
		"updateRunners":      runners_UpdateRunners,
		"getRunners":         runners_GetRunner,
		"getAccessPolicy":    runners_GetAccessPolicy,
		"updateAccessPolicy": runners_UpdateAccessPolicy,
		"getRunnerCred":      runners_GetRunnerRegistrationCredentials,
		"listDownloads":      runners_ListDownloads,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clientMaker)
		})
	}
}

func runners_ListRunnersV2(t *testing.T, clp func(string) azp.RepositoryClient) {
	type args struct {
		page                   int64
		perPage                int64
		includeAssignedRequest bool
		poolID                 int64
		runnerName             string
		excludeElasticRunners  bool
	}

	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/1/agents?api-version=6.0-preview&includeAssignedRequest=true",
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
		wantRunners  []*azp.RunnerV2
		wantCount    int64
		wantErr      bool
		httpResponse httpResponse
	}{
		{
			name:        "find some runners",
			wantRunners: testRunnersList.Value,
			args: args{
				page:                   0,
				perPage:                30,
				includeAssignedRequest: true,
				poolID:                 1,
			},
			wantCount: 10,
			wantErr:   false,
			httpResponse: httpResponse{
				code: 200,
				header: map[string]string{
					"X-Total-Count": "10",
				},
				body: string(toBytes(&testRunnersList, t)),
			},
		},
		{
			name: "invalid X-Total-Count",
			args: args{
				page:                   0,
				perPage:                30,
				includeAssignedRequest: true,
				poolID:                 1,
			},
			wantErr: true,
			httpResponse: httpResponse{
				code: 200,
				header: map[string]string{
					"X-Total-Count": "invalid",
				},
				body: string(toBytes(&testRunnersList, t)),
			},
		},
		{
			name: "no X-Total-Count",
			args: args{
				page:                   0,
				perPage:                30,
				includeAssignedRequest: true,
				poolID:                 1,
			},
			wantErr: false,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnersList, t)),
			},
			wantRunners: testRunnersList.Value,
			wantCount:   1,
		},
		{
			name: "error",
			args: args{
				page:                   0,
				perPage:                30,
				includeAssignedRequest: true,
				poolID:                 1,
			},
			wantErr: true,
			httpResponse: httpResponse{
				code: 500,
			},
		},
		{
			name:        "filter by runner name",
			wantRunners: testRunnersList.Value,
			args: args{
				page:                   0,
				perPage:                30,
				includeAssignedRequest: true,
				poolID:                 1,
				runnerName:             "testRunner",
				excludeElasticRunners:  true,
			},
			wantCount: 1,
			wantErr:   false,
			httpResponse: httpResponse{
				code: 200,
				header: map[string]string{
					"X-Total-Count": "1",
				},
				body: string(toBytes(&testRunnersList, t)),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				for k, v := range tt.httpResponse.header {
					w.Header().Add(k, v)
				}
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			gotRunners, gotCount, err := clp(ts.URL).ListRunnersV2(context.Background(), tt.args.page, tt.args.perPage, tt.args.includeAssignedRequest, tt.args.poolID, tt.args.runnerName, tt.args.excludeElasticRunners)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.wantRunners, gotRunners)
			require.Equal(t, tt.wantCount, gotCount)
		})
	}
}

func runners_DeleteRunner(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/0/agents/1?api-version=5.1",
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
		wantRunners  []*azp.RunnerV2
		wantCount    int64
		wantErr      bool
		httpResponse httpResponse
	}{
		{
			name:        "happy path",
			wantRunners: testRunnersList.Value,
			wantCount:   10,
			wantErr:     false,
			httpResponse: httpResponse{
				code: 204,
			},
		},
		{
			name:    "internal error",
			wantErr: true,
			httpResponse: httpResponse{
				code: 500,
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			err := clp(ts.URL).DeleteRunner(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func runners_UpdateRunners(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/0/agents?api-version=6.0-preview",
		method: "PATCH",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json-patch+json",
		},
	}

	type args struct {
		ctx        context.Context
		operations []*azp.RunnerOp
	}
	tests := []struct {
		name         string
		httpResponse httpResponse
		args         args
		want         []*azp.RunnerV2
		wantErr      bool
	}{
		{
			name: "Happy path",
			args: args{
				ctx:        context.TODO(),
				operations: testUpdateRunnerOperations,
			},
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnersList, t)),
			},
			want:    testRunnersV2,
			wantErr: false,
		},
		{
			name: "Failure path",
			args: args{
				ctx:        context.TODO(),
				operations: testUpdateRunnerOperations,
			},
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			got, err := clp(ts.URL).UpdateRunners(context.Background(), tt.args.operations)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runners_GetRunner(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/0/agents/1?api-version=6.0-preview&includeAssignedRequest=true&includeCapabilities=true",
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
		httpResponse httpResponse
		want         *azp.RunnerV2
		wantErr      bool
	}{
		{
			name: "Failure path",
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
		{
			name: "Happy Path",
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnersV2[0], t)),
			},
			wantErr: false,
			want:    testRunnersV2[0],
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			got, err := clp(ts.URL).GetRunner(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runners_GetAccessPolicy(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/1/accesspolicy?api-version=6.0-preview",
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
		httpResponse httpResponse
		want         *azp.AccessPolicy
		wantErr      bool
	}{
		{
			name: "Failure path",
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
		{
			name: "Happy Path",
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testAccessPolicy, t)),
			},
			wantErr: false,
			want:    &testAccessPolicy,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			got, err := clp(ts.URL).GetAccessPolicy(context.Background())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runners_UpdateAccessPolicy(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/1/accesspolicy?api-version=6.0-preview",
		method: "PATCH",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json-patch+json",
		},
	}
	tests := []struct {
		name         string
		httpResponse httpResponse
		want         *azp.AccessPolicy
		wantErr      bool
	}{
		{
			name: "Failure path",
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
		{
			name: "Happy Path",
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testAccessPolicy, t)),
			},
			wantErr: false,
			want:    &testAccessPolicy,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			got, err := clp(ts.URL).UpdateAccessPolicy(context.Background(), azp.PermissionOp{Op: "asdf"}, azp.SelectedReposOp{Op: "asdf"}, azp.SelectedReposOp{Op: "asdf"})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runners_GetRunnerRegistrationCredentials(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/pools/1/admintoken?api-version=5.0-preview",
		method: "POST",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}
	tests := []struct {
		name         string
		httpResponse httpResponse
		wantErr      bool
	}{
		{
			name: "Failure path",
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
		{
			name: "Happy Path",
			httpResponse: httpResponse{
				code: 200,
				body: "we need to know the url so setting this to non-nil and overiding in test",
			},
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {

			testRunnerCred := azp.RunnerRegistrationToken{Token: "secure"}
			testRunnerCredRegistration := azp.RunnerRegistrationCredentials{Data: &testRunnerCred, Scheme: "http"}

			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, string(toBytes(testRunnerCredRegistration, t)))
				}
			}))

			testRunnerCredRegistration.Data.HostURL = ts.URL + "/testTenant"

			defer ts.Close()

			got, err := clp(ts.URL).GetRunnerRegistrationCredentials(context.Background(), "ownerId", "billingOwnerId", "")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			if !tt.wantErr {
				require.Equal(t, &testRunnerCredRegistration, got)
			}
		})
	}
}

func runners_ListDownloads(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/packages/agent?$top=1&includeToken=true",
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
		httpResponse httpResponse
		want         []*azp.Download
		wantErr      bool
	}{
		{
			name: "Happy Path",
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(testDownloadsList, t)),
			},
			wantErr: false,
			want:    testDownloads,
		},
		{
			name: "Failure path",
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, defaultWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			got, err := clp(ts.URL).ListDownloads(context.Background())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}
