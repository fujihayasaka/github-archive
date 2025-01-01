package refactortests

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/pkg/azp"
)

func GatesCompatTest(t *testing.T, clp func(string, map[string]bool) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string, map[string]bool) azp.RepositoryClient){
		"updateGateConclusion": gatesService_UpdateGateConclusion,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clp)
		})
	}
}

func gatesService_UpdateGateConclusion(t *testing.T, clp func(url string, flags map[string]bool) azp.RepositoryClient) {
	fakeGateToken := "fakeGateToken"
	requestWithGateAuth := httpRequest{
		uri:    "/testTenant/_apis/actions/gates/gateID?api-version=6.0-preview",
		method: "PATCH",
		header: map[string]string{
			"Authorization":       "Bearer " + fakeGateToken,
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json",
		},
	}

	requestWithDefaultAuth := httpRequest{
		uri:    "/testTenant/_apis/actions/gates/gateID?api-version=6.0-preview",
		method: "PATCH",
		header: map[string]string{
			"Authorization":       "Bearer " + DefaultToken,
			"User-Agent":          "GitHubServices service:actions",
			"X-Client-Timeout-Ms": "10000",
			"Accept-Encoding":     "gzip",
			"Content-Type":        "application/json",
		},
	}

	tests := []struct {
		name         string
		giveResponse httpResponse
		authFlag     bool
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
			},
			wantReq: requestWithGateAuth,
			wantErr: false,
		},
		{
			name: "Permanent error, 400 <= statuscode <= 499",
			giveResponse: httpResponse{
				code: 429,
			},
			wantReq: requestWithGateAuth,
			wantErr: true,
		},
		{
			name: "Happy Path with auth flag enabled",
			giveResponse: httpResponse{
				code: 200,
			},
			authFlag: true,
			wantReq:  requestWithDefaultAuth,
			wantErr:  false,
		},
		{
			name: "Permanent error with auth flag enabled, 400 <= statuscode <= 499",
			giveResponse: httpResponse{
				code: 429,
			},
			authFlag: true,
			wantReq:  requestWithDefaultAuth,
			wantErr:  true,
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

			flags := map[string]bool{
				github.ConstructScaleUnitURL: true,
				github.PlumbRunnerHostURL:    true,
				github.GatesUseDefaultAuth:   tt.authFlag,
			}
			err := clp(ts.URL, flags).UpdateGateConclusion(context.Background(), "gateID", "", "", fakeGateToken, false)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}
