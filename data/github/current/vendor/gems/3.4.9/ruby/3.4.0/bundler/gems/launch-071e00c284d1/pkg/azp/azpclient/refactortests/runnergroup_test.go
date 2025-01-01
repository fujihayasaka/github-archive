package refactortests

// This test is a copy of an runnergroup_existing_ test clients/azp/runner_group_test.go

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
)

func RunnerGroupCompatTest(t *testing.T, clientMaker func(string) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"UpdateGroupTargets": runnergroup_UpdateGroupTargets,
		"RemoveTarget":       runnergroup_RemoveTarget,
		"UpdateVisibility":   runnergroup_UpdateVisibility,
		"AddTarget":          runnergroup_AddTarget,
		"UpdateGroupRunners": runnergroup_UpdateGroupRunners,
		"RemoveRunner":       runnergroup_RemoveRunner,
		"UpdateGroup":        runnergroup_UpdateGroup,
		"CreateGroup":        runnergroup_CreateGroup,
		"DeleteGroup":        runnergroup_DeleteGroup,
		"GetGroup":           runnergroup_GetGroup,
		"ListGroups":         runnergroup_ListGroups,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clientMaker)
		})
	}
}

func runnergroup_UpdateGroupTargets(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1/visibility?api-version=6.0-preview",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.Visibility
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testVisibility, t)),
			},
			wantReq: defaultWantReq,
			want:    testVisibility,
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

			identities := []*pbtypes.Identity{{GlobalId: "repositoryB"}}
			ctx := context.Background()
			got, err := clientProvider(ts.URL).UpdateGroupTargets(ctx, 1, identities)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_RemoveTarget(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1/visibility?api-version=6.0-preview",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.Visibility
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testVisibility, t)),
			},
			wantReq: defaultWantReq,
			want:    testVisibility,
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
			got, err := clientProvider(ts.URL).RemoveTarget(ctx, 1, nil)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_UpdateVisibility(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1/visibility?api-version=6.0-preview",
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
		giveResponse httpResponse
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testVisibility, t)),
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
			err := clientProvider(ts.URL).UpdateVisibility(ctx, 1, "", nil, azp.AllowPublicAllow, nil, azp.AllowPublicAllow)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func runnergroup_AddTarget(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1/visibility?api-version=6.0-preview",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.Visibility
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testVisibility, t)),
			},
			want:    testVisibility,
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
			got, err := clientProvider(ts.URL).AddTarget(ctx, 1, nil)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_UpdateGroupRunners(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1?api-version=6.0-preview&includeVisibility=true&excludeHostedRunnerGroups=true",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.RunnerGroup
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerGroup, t)),
			},
			want:    testRunnerGroup,
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
			got, err := clientProvider(ts.URL).UpdateGroupRunners(ctx, 1, []int64{1})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_RemoveRunner(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1?api-version=6.0-preview&includeVisibility=true&excludeHostedRunnerGroups=true",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.RunnerGroup
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerGroup, t)),
			},
			want:    testRunnerGroup,
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
			got, err := clientProvider(ts.URL).RemoveRunner(ctx, 1, 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_AddRunners(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1?api-version=6.0-preview&includeVisibility=true&excludeHostedRunnerGroups=true",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.RunnerGroup
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerGroup, t)),
			},
			want:    testRunnerGroup,
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
			got, err := clientProvider(ts.URL).AddRunners(ctx, 1, []int64{1})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_UpdateGroup(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1?api-version=6.0-preview&includeVisibility=true&excludeHostedRunnerGroups=true",
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
		giveResponse httpResponse
		wantReq      httpRequest
		want         *azp.RunnerGroup
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerGroup, t)),
			},
			want:    testRunnerGroup,
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
			got, err := clientProvider(ts.URL).UpdateGroup(ctx, types.NilGlobalID, 1, nil, "")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_CreateGroup(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups?api-version=6.0-preview",
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
		want         *azp.RunnerGroup
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerGroup, t)),
			},
			want:    testRunnerGroup,
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
				switch r.URL.Path {
				case "/testTenant/_apis/runtime/runnergroups":
					assertReq(t, tt.wantReq, r)
					w.WriteHeader(tt.giveResponse.code)
					if tt.giveResponse.body != "" {
						io.WriteString(w, tt.giveResponse.body)
					}
				case "/testTenant/_apis/runtime/runnergroups/0":
					w.WriteHeader(tt.giveResponse.code)
				}
			}))
			defer ts.Close()

			ctx := context.Background()
			got, err := clientProvider(ts.URL).CreateGroup(ctx, []int64{1}, "", nil, "", azp.AllowPublicAllow, []string{""}, azp.AllowPublicAllow)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_DeleteGroup(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1?api-version=6.0-preview&includeVisibility=true&excludeHostedRunnerGroups=true",
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
				code: 204,
				body: string(toBytes(&testRunnerGroup, t)),
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
			err := clientProvider(ts.URL).DeleteGroup(ctx, 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func runnergroup_GetGroup(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/1?api-version=6.0-preview&includeRunners=false&currentTenant=&isCurrentTenantEnterprise=false&includeVisibility=true&excludeHostedRunnerGroups=false&excludeElasticRunners=false",
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
		want         *azp.RunnerGroup
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerGroup, t)),
			},
			want:    testRunnerGroup,
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
			got, err := clientProvider(ts.URL).GetGroup(ctx, 1, types.NilGlobalID, types.NilGlobalID, "", false, false, false, false, false)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func runnergroup_ListGroups(t *testing.T, clientProvider func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runtime/runnergroups/?api-version=6.0-preview&includeRunners=false&currentTenant=&isCurrentTenantEnterprise=false&excludeHostedRunnerGroups=false&includeVisibility=true&excludeElasticRunners=false",
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
		want         []*azp.RunnerGroup
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testListRunnerGroupResp, t)),
			},
			want:    testListRunnerGroupResp.Value,
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
			got, err := clientProvider(ts.URL).ListGroups(ctx, types.NilGlobalID, types.NilGlobalID, "", false, false, false, false, false)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

var testVisibility = &azp.Visibility{}
var testRunnerGroup = &azp.RunnerGroup{}

var testListRunnerGroupResp = struct {
	Count int64              `json:"count"`
	Value []*azp.RunnerGroup `json:"value"`
}{
	Count: 1,
	Value: []*azp.RunnerGroup{testRunnerGroup},
}

var (
	repoID = &pbtypes.Identity{
		GlobalId: "R_kgDNA-c",
	}
	runnerGroupJSON = `{
		"id": 1,
		"name": "TestGroup",
		"size": 1,
		"isHosted": false,
		"visibility": {
			"visibilityType": "selected",
			"approvedChildren": [ "R_kgDNA-c" ]
		},
		"runners": [{
			"id": 1,
			"name": "TestRunner",
			"version": 1,
			"runnerGroupId": 1,
			"osDescription": "ubuntu-latest",
			"enabled": true,
			"status": "online",
			"currentParallelism": 0,
			"maxParallelism": 1,
			"labels": []
		}]
	}`
)
