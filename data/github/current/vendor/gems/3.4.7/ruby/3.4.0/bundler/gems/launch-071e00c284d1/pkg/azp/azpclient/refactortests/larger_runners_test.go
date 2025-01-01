package refactortests

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/types"
)

func LargerRunnersCompatTest(t *testing.T, clp func(string) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"reportAdminEvent":      largerrunners_ReportRunnerAdminEvent,
		"listRunnerPools":       largerrunners_ListRunnerPools,
		"getRunnerPools":        largerrunners_GetRunnerPool,
		"createRunnerPools":     largerrunners_CreateRunnerPool,
		"updateRunnerPools":     largerrunners_UpdateRunnerPool,
		"deleteRunnerPools":     largerrunners_DeleteRunnerPool,
		"createImageDefinition": largerrunners_CreateImageDefinition,
		"listImageDefinitions":  largerrunners_ListImageDefinitions,
		"getImageDefinition":    largerrunners_GetImageDefinition,
		"deleteImageDefinition": largerrunners_DeleteImageDefinition,
		"createImageVersion":    largerrunners_CreateImageVersion,
		"listPoolAgents":        largerrunners_ListPoolAgents,
		"listMachineSpecs":      largerrunners_ListMachineSpecs,
		"getImageVersion":       largerrunners_GetImageVersion,
		"listImageVersions":     largerrunners_ListImageVersions,
		"deleteImageVersion":    largerrunners_DeleteImageVersion,
		"listBetaFeatures":      largerrunners_ListBetaFeatures,
		"getBetaFeatures":       largerrunners_GetBetaFeature,
		"setBetaFeatures":       largerrunners_SetBetaFeature,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clp)
		})
	}
}

func largerrunners_ReportRunnerAdminEvent(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/adminevents?api-version=1.0",
		method: "POST",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json",
			"X-TFS-AllowFaultIn":  "false",
		},
	}

	tests := []struct {
		name         string
		httpResponse httpResponse
		wantErr      bool
		wantReq      httpRequest
		wantReqCount int
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 200,
			},
			wantErr:      false,
			wantReqCount: 1,
		},
		{
			name:    "Not Found - 404",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 404,
			},
			wantErr:      false,
			wantReqCount: 1,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr:      true,
			wantReqCount: 4,
		},
	}
	for _, tt := range tests {
		var reqCount int
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				reqCount++
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			err := clp(ts.URL).ReportRunnerAdminEvent(context.Background(), "", map[string]string{})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.wantReqCount, reqCount)
		})
	}
}

func largerrunners_ListRunnerPools(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/pools?api-version=1.0&currentTenant=ownerID&parentTenant=planOwnerID&parentTenantName=ptenant&parentTenantID=ptenantID&filterTenant=entityID&isFilterTenantPrivate=true",
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
		wantErr      bool
		wantReq      httpRequest
		want         []*azp.RunnerPool
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testRunnerPools,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testListRunnerPoolsResponse, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()

			got, err := clp(ts.URL).ListRunnerPools(
				context.Background(),
				types.GlobalID("entityID"),
				types.GlobalID("ownerID"),
				types.GlobalID("planOwnerID"),
				"ptenant",
				"ptenantID",
				true,
				nil,
			)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_GetRunnerPool(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/pools/1?api-version=1.0",
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
		wantErr      bool
		wantReq      httpRequest
		want         *azp.RunnerPool
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testRunnerPool,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerPool, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).GetRunnerPool(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_CreateRunnerPool(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/pools?api-version=1.0",
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
		httpResponse httpResponse
		wantErr      bool
		wantReq      httpRequest
		want         *azp.RunnerPool
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testRunnerPool,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerPool, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).CreateRunnerPool(context.Background(), azp.CreatePoolRequest{})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_UpdateRunnerPool(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/pools/1?api-version=1.0",
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
		wantErr      bool
		wantReq      httpRequest
		want         *azp.RunnerPool
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testRunnerPool,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnerPool, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).UpdateRunnerPool(context.Background(), 1, azp.UpdatePoolRequest{})
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_DeleteRunnerPool(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/pools/1?api-version=1.0",
		method: "DELETE",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	deletedTestRunnerPool := testRunnerPool
	deletedTestRunnerPool.State = "deleting"

	tests := []struct {
		name         string
		httpResponse httpResponse
		wantErr      bool
		wantReq      httpRequest
		want         *azp.RunnerPool
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    deletedTestRunnerPool,
			httpResponse: httpResponse{
				code: 202,
				body: string(toBytes(&deletedTestRunnerPool, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).DeleteRunnerPool(context.Background(), 1)
			require.Equal(t, tt.want, got)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func largerrunners_CreateImageDefinition(t *testing.T, clp func(string) azp.RepositoryClient) {
	createWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom?api-version=6.0-preview",
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
		name                    string
		createResponse          httpResponse
		imageDefinitionResponse httpResponse
		want                    *azp.ImageDefinition
		wantErr                 bool
	}{
		{
			name:                    "Happy Path",
			createResponse:          httpResponse{code: 200, body: string(toBytes(&testImageDefinition, t))},
			imageDefinitionResponse: httpResponse{code: 200, body: string(toBytes(&testImageDefinition, t))},
			want:                    testImageDefinition,
			wantErr:                 false,
		},
		{
			name:           "Failure path - create",
			createResponse: httpResponse{code: 500},
			wantErr:        true,
		},
		{
			name:                    "Failure path - image version",
			createResponse:          httpResponse{code: 500},
			imageDefinitionResponse: httpResponse{code: 500},
			wantErr:                 true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/testTenant/_apis/runner/images/custom":
					assertReq(t, createWantReq, r)
					w.WriteHeader(tt.createResponse.code)
					if tt.createResponse.body != "" {
						io.WriteString(w, tt.createResponse.body)
					}
				default:
					w.WriteHeader(500)
					io.WriteString(w, "unexpected path")
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).CreateImageDefinition(context.Background(), "testOSType", "testPoolName")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_ListImageDefinitions(t *testing.T, clp func(string) azp.RepositoryClient) {
	listWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom?api-version=6.0-preview",
		method: "GET",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name                     string
		imageDefinitionsResponse httpResponse
		want                     []*azp.ImageDefinition
		wantErr                  bool
		wantReq                  httpRequest
	}{
		{
			name:                     "Happy Path",
			wantReq:                  listWantReq,
			imageDefinitionsResponse: httpResponse{code: 200, body: string(toBytes(&testListImageDefinitionsResponse, t))},
			want:                     testImageDefinitions,
			wantErr:                  false,
		},
		{
			name:                     "Failure path - image definition",
			wantReq:                  listWantReq,
			imageDefinitionsResponse: httpResponse{code: 500},
			wantErr:                  true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.imageDefinitionsResponse.code)
				if tt.imageDefinitionsResponse.body != "" {
					io.WriteString(w, tt.imageDefinitionsResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).ListImageDefinitions(context.Background())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_GetImageDefinition(t *testing.T, clp func(string) azp.RepositoryClient) {
	getWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom/1?api-version=6.0-preview",
		method: "GET",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name                    string
		imageDefinitionResponse httpResponse
		want                    *azp.ImageDefinition
		wantErr                 bool
		wantReq                 httpRequest
	}{
		{
			name:                    "Happy Path",
			wantReq:                 getWantReq,
			imageDefinitionResponse: httpResponse{code: 200, body: string(toBytes(&testImageDefinition, t))},
			want:                    testImageDefinition,
			wantErr:                 false,
		},
		{
			name:                    "Failure path - image definition",
			wantReq:                 getWantReq,
			imageDefinitionResponse: httpResponse{code: 500},
			wantErr:                 true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.imageDefinitionResponse.code)
				if tt.imageDefinitionResponse.body != "" {
					io.WriteString(w, tt.imageDefinitionResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).GetImageDefinition(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_DeleteImageDefinition(t *testing.T, clp func(string) azp.RepositoryClient) {
	deleteWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom/1?api-version=6.0-preview",
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
		httpResponse httpResponse
		wantErr      bool
		wantReq      httpRequest
	}{
		{
			name:    "Happy Path",
			wantReq: deleteWantReq,
			httpResponse: httpResponse{
				code: 202,
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: deleteWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, deleteWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			err := clp(ts.URL).DeleteImageDefinition(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func largerrunners_CreateImageVersion(t *testing.T, clp func(string) azp.RepositoryClient) {
	updateWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom/1/versions?api-version=6.0-preview",
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
		name                 string
		createResponse       httpResponse
		imageVersionResponse httpResponse
		want                 *azp.ImageVersion
		wantErr              bool
	}{
		{
			name:                 "Happy Path",
			createResponse:       httpResponse{code: 200, body: string(toBytes(&testImageVersion, t))},
			imageVersionResponse: httpResponse{code: 200, body: string(toBytes(&testImageVersion, t))},
			want:                 testImageVersion,
			wantErr:              false,
		},
		{
			name:           "Failure path - create",
			createResponse: httpResponse{code: 500},
			wantErr:        true,
		},
		{
			name:                 "Failure path - image version",
			createResponse:       httpResponse{code: 500},
			imageVersionResponse: httpResponse{code: 500},
			wantErr:              true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				switch r.URL.Path {
				case "/testTenant/_apis/runner/images/custom/1/versions":
					assertReq(t, updateWantReq, r)
					w.WriteHeader(tt.imageVersionResponse.code)
					if tt.imageVersionResponse.body != "" {
						io.WriteString(w, tt.imageVersionResponse.body)
					}
				default:
					w.WriteHeader(500)
					io.WriteString(w, "unexpected path")
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).CreateImageVersion(context.Background(), "testURI", 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_GetImageVersion(t *testing.T, clp func(string) azp.RepositoryClient) {
	getWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom/1/versions/1.0.0?api-version=6.0-preview",
		method: "GET",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name                 string
		imageVersionResponse httpResponse
		want                 *azp.ImageVersion
		wantReq              httpRequest
		wantErr              bool
	}{
		{
			name:                 "Happy Path",
			wantReq:              getWantReq,
			imageVersionResponse: httpResponse{code: 200, body: string(toBytes(&testImageVersion, t))},
			want:                 testImageVersion,
			wantErr:              false,
		},
		{
			name:                 "Failure path - image version",
			wantReq:              getWantReq,
			imageVersionResponse: httpResponse{code: 500},
			wantErr:              true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.imageVersionResponse.code)
				if tt.imageVersionResponse.body != "" {
					io.WriteString(w, tt.imageVersionResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).GetImageVersion(context.Background(), 1, "1.0.0")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_ListImageVersions(t *testing.T, clp func(string) azp.RepositoryClient) {
	listWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom/1/versions?api-version=6.0-preview",
		method: "GET",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}
	pattern := "6.*"

	listWantPatternReq := httpRequest{
		uri:    fmt.Sprintf("/testTenant/_apis/runner/images/custom/1/versions?api-version=6.0-preview&pattern=%s", url.QueryEscape(pattern)),
		method: "GET",
		header: map[string]string{
			"Authorization":       "Bearer fakeToken",
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
		},
	}

	tests := []struct {
		name                  string
		imageVersionsResponse httpResponse
		want                  []*azp.ImageVersion
		wantErr               bool
		wantReq               httpRequest
		pattern               *string
	}{
		{
			name:                  "Happy Path",
			wantReq:               listWantReq,
			imageVersionsResponse: httpResponse{code: 200, body: string(toBytes(&testListImageVersionsResponse, t))},
			want:                  testImageVersions,
			wantErr:               false,
			pattern:               nil,
		},
		{
			name:                  "Failure path - image version",
			wantReq:               listWantReq,
			imageVersionsResponse: httpResponse{code: 500},
			wantErr:               true,
			pattern:               nil,
		},
		{
			name:                  "Happy path - image version query with a pattern query param",
			wantReq:               listWantPatternReq,
			imageVersionsResponse: httpResponse{code: 200, body: string(toBytes(&testListImageVersionsPatternResponse, t))},
			want:                  testPatternImageVersions,
			wantErr:               false,
			pattern:               &pattern,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.imageVersionsResponse.code)
				if tt.imageVersionsResponse.body != "" {
					io.WriteString(w, tt.imageVersionsResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).ListImageVersions(context.Background(), 1, tt.pattern)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_DeleteImageVersion(t *testing.T, clp func(string) azp.RepositoryClient) {
	deleteWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/images/custom/1/versions/1.0.0?api-version=6.0-preview",
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
		httpResponse httpResponse
		wantErr      bool
		wantReq      httpRequest
	}{
		{
			name:    "Happy Path",
			wantReq: deleteWantReq,
			httpResponse: httpResponse{
				code: 202,
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: deleteWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, deleteWantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			err := clp(ts.URL).DeleteImageVersion(context.Background(), 1, "1.0.0")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func largerrunners_ListPoolAgents(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/pools/1/agents?api-version=6.0-preview",
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
		wantErr      bool
		wantReq      httpRequest
		want         []*azp.RunnerV2
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testRunnersV2,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testRunnersList, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).ListPoolAgents(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_ListMachineSpecs(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/machinespecs?api-version=6.0-preview",
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
		wantErr      bool
		wantReq      httpRequest
		want         []*azp.MachineSpec
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testMachineSpecs,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testMachineSpecList, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).ListMachineSpecs(context.Background())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_ListBetaFeatures(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/betafeatures?api-version=6.0-preview",
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
		wantErr      bool
		wantReq      httpRequest
		want         []*azp.BetaFeature
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testBetaFeatures,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testBetaFeaturesList, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).ListBetaFeatures(context.Background())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_GetBetaFeature(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/betafeatures/feature1?api-version=6.0-preview",
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
		wantErr      bool
		wantReq      httpRequest
		want         *azp.BetaFeature
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testBetaFeature,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testBetaFeature, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).GetBetaFeature(context.Background(), "feature1")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func largerrunners_SetBetaFeature(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/runner/betafeatures/feature1?api-version=6.0-preview",
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
		wantReq      httpRequest
		want         *azp.BetaFeature
	}{
		{
			name:    "Happy Path",
			wantReq: defaultWantReq,
			want:    testBetaFeature,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testBetaFeature, t)),
			},
			wantErr: false,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assertReq(t, tt.wantReq, r)
				w.WriteHeader(tt.httpResponse.code)
				if tt.httpResponse.body != "" {
					io.WriteString(w, tt.httpResponse.body)
				}
			}))
			defer ts.Close()
			got, err := clp(ts.URL).SetBetaFeature(context.Background(), "feature1", true)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

var testUpdatePoolRequest = azp.UpdatePoolRequest{Name: "pool"}
var testRunnerPool = &azp.RunnerPool{ID: 1, Name: "pool"}
var testRunnerPools = []*azp.RunnerPool{testRunnerPool}
var testListRunnerPoolsResponse = struct {
	Count int64             `json:"count"`
	Value []*azp.RunnerPool `json:"value"`
}{
	Count: 1, Value: testRunnerPools,
}
var testImageVersion = &azp.ImageVersion{Version: "1.0.0", ImageDefinitionID: 1}
var testPatternImageVersion = &azp.ImageVersion{Version: "6.1.0", ImageDefinitionID: 1}
var testImageDefinition = &azp.ImageDefinition{Name: "image", ID: 1, OsType: "Linux", ImageDefinitionState: "Ready"}
var testImageDefinitions = []*azp.ImageDefinition{testImageDefinition}
var testListImageDefinitionsResponse = struct {
	Count int64                  `json:"count"`
	Value []*azp.ImageDefinition `json:"value"`
}{
	Count: 1, Value: testImageDefinitions,
}
var testImageVersions = []*azp.ImageVersion{testImageVersion}
var testListImageVersionsResponse = struct {
	Count int64               `json:"count"`
	Value []*azp.ImageVersion `json:"value"`
}{
	Count: 1, Value: testImageVersions,
}

var testPatternImageVersions = []*azp.ImageVersion{testPatternImageVersion}
var testListImageVersionsPatternResponse = struct {
	Count int64               `json:"count"`
	Value []*azp.ImageVersion `json:"value"`
}{
	Count: 1, Value: testPatternImageVersions,
}
var testMachineSpec = &azp.MachineSpec{ID: "spec"}
var testMachineSpecs = []*azp.MachineSpec{testMachineSpec}
var testMachineSpecList = &azp.MachineSpecsList{Count: 1, Value: testMachineSpecs}
var testBetaFeature = &azp.BetaFeature{Name: "feature1", EnabledForUser: true, EnabledGlobally: false}
var testBetaFeatures = []*azp.BetaFeature{testBetaFeature}
var testBetaFeaturesList = &azp.BetaFeaturesList{Count: 1, Value: testBetaFeatures}

var (
	testRunnersV2   = []*azp.RunnerV2{{ID: 1}}
	testRunnersList = &azp.RunnersListV2{
		Count: 1,
		Value: testRunnersV2,
	}
	testUpdateRunnerOperations = []*azp.RunnerOp{{Op: "test"}}
	testAccessPolicy           = azp.AccessPolicy{PermissionType: "whatever"}
	testDownloads              = []*azp.Download{{Platform: "Linux"}}
	testDownloadsList          = azp.DownloadsList{Count: 1, Value: testDownloads}
)
