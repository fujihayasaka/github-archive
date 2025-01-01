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

func LabelsCompatTest(t *testing.T, clp func(string) azp.RepositoryClient) {
	tests := map[string]func(*testing.T, func(string) azp.RepositoryClient){
		"list":   labels_ListLabels,
		"delete": labels_DeleteLabel,
		"create": labels_CreateLabel,
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			test(t, clp)
		})
	}
}

func labels_ListLabels(t *testing.T, clp func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/labels?api-version=6.0-preview",
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
		want         []*azp.Label
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testListLabelsResponse, t)),
			},
			want:    testLabels,
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Permanent error, 400 <= statuscode <= 499",
			giveResponse: httpResponse{
				code: 429,
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
			got, err := clp(ts.URL).ListLabels(context.Background())
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

func labels_DeleteLabel(t *testing.T, clp func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/labels/1?api-version=6.0-preview",
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
		want         []*azp.Label
		wantReq      httpRequest
		wantErr      bool
	}{
		{
			name: "Happy Path",
			giveResponse: httpResponse{
				code: 204,
				body: string(toBytes(&testListLabelsResponse, t)),
			},
			want:    testLabels,
			wantReq: defaultWantReq,
			wantErr: false,
		},
		{
			name: "Permanent error, 400 <= statuscode <= 499",
			giveResponse: httpResponse{
				code: 429,
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
			err := clp(ts.URL).DeleteLabel(context.Background(), 1)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
		})
	}
}

func labels_CreateLabel(t *testing.T, clp func(url string) azp.RepositoryClient) {
	defaultWantReq := httpRequest{
		uri:    "/testTenant/_apis/distributedtask/labels?api-version=6.0-preview",
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
		wantReq      httpRequest
		want         *azp.Label
		wantErr      bool
	}{
		{
			name:    "Happy Path - 201",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 201,
				body: string(toBytes(&testLabel, t)),
			},
			want:    &testLabel,
			wantErr: false,
		},
		{
			name:    "Happy Path - 200",
			wantReq: defaultWantReq,
			httpResponse: httpResponse{
				code: 200,
				body: string(toBytes(&testLabel, t)),
			},
			want:    &testLabel,
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
			got, err := clp(ts.URL).CreateLabel(context.Background(), testFields)
			require.Equal(t, tt.wantErr, (err != nil), fmt.Sprintf("unexpected error %v", err))
			require.Equal(t, tt.want, got)
		})
	}
}

var testFields = azp.LabelFields{Name: "field"}
var testLabel = azp.Label{ID: 1, Name: "label"}
var testLabels = []*azp.Label{&testLabel}
var testListLabelsResponse = struct {
	Count int64        `json:"count"`
	Value []*azp.Label `json:"value"`
}{
	Count: 1,
	Value: testLabels,
}
