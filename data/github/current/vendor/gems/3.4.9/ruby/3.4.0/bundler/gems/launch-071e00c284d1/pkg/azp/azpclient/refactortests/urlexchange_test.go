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

func URLExchangeCompatTest(t *testing.T, clp func(string) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"get": urlexchange_GetAuthenticatedURL,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clp)
		})
	}
}

func urlexchange_GetAuthenticatedURL(t *testing.T, clp func(string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/urlsign",
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
		wantReq      httpRequest
		want         *azp.GetAuthenticatedURLResponse
		wantReqCount int
		wantErr      bool
	}{
		{
			name:    "Happy Path - 201",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 201,
				body: string(toBytes(&testAuthenticatedURLResponse, t)),
			},
			want:         testAuthenticatedURLResponse,
			wantReqCount: 1,
			wantErr:      false,
		},
		{
			name:    "Happy Path - 200",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testAuthenticatedURLResponse, t)),
			},
			want:         testAuthenticatedURLResponse,
			wantReqCount: 1,
			wantErr:      false,
		},
		{
			name:    "Not Found - 404",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 404,
			},
			wantReqCount: 1,
			wantErr:      true,
		},
		{
			name:    "Failure path",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 500,
			},
			wantReqCount: 4,
			wantErr:      true,
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
			got, err := clp(ts.URL).GetAuthenticatedURL(context.Background(), ts.URL+"/urlsign")
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.wantReqCount, reqCount)
			require.Equal(t, tt.want, got)
		})
	}
}

var testSignedContent = &azp.SignedContent{URL: "http://github.com"}
var testAuthenticatedURLResponse = &azp.GetAuthenticatedURLResponse{SignedContent: testSignedContent}
