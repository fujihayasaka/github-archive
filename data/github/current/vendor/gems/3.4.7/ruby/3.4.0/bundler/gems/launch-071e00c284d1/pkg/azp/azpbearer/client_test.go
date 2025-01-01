package azpbearer

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachemock"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/launchhttp/httpmock"
)

type fakeProvider struct{}

func (f *fakeProvider) Provide(context.Context, string, string, string) (string, error) {
	return "", nil
}

type fakeTokenSource struct{}

func (f *fakeTokenSource) Get(context.Context, string, string) (string, error) {
	return "", nil
}

var testTokenSource = &fakeTokenSource{}
var testJWTProvider = &fakeProvider{}
var testAccessToken = "password"
var testBearerToken = &azp.BearerToken{AccessToken: testAccessToken, ExpiresIn: "3000"}

func TestClient_TokenSourceFor(t *testing.T) {
	ctx := context.Background()
	type httpResponse struct {
		resp *http.Response
		err  error
	}

	type cacheGetResponse struct {
		val []byte
		exp time.Time
		ok  bool
		err error
	}

	type cacheSetResponse struct {
		err error
	}

	type args struct {
		jwtProvider jwt.Provider
		requestURL  string
		clientID    string
		resource    string
	}

	defaultArgs := args{
		jwtProvider: testJWTProvider,
		requestURL:  "",
		clientID:    "",
		resource:    "",
	}

	defaultMock := func(m *httpmock.Client, _ *testing.T, resp *httpResponse, _ *cachemock.ExpiringCache, _ cacheGetResponse) {
		m.EXPECT().Do(mock.MatchedBy(func(req *http.Request) bool {
			ok := req.Header.Get("Content-Type") == "application/x-www-form-urlencoded"
			ok = ok && req.Header.Get("User-Agent") == "GitHubServices service:actions"
			ok = ok && req.Header.Get("X-VSS-E2EID") != ""
			ok = ok && req.Header.Get("Authorization") == ""
			ok = ok && req.Method == http.MethodPost
			return ok
		})).Return(resp.resp, resp.err).Once()
	}

	tests := []struct {
		name             string
		httpResponse     httpResponse
		cacheGetResponse cacheGetResponse
		cacheSetResponse cacheSetResponse
		withCache        bool
		mock             func(m *httpmock.Client, t *testing.T, resp *httpResponse, c *cachemock.ExpiringCache, cr cacheGetResponse)
		args             args
		want             string
		wantErr          bool
	}{
		{
			name: "get a token from token source",
			httpResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testBearerToken, t)))},
			},
			mock:    defaultMock,
			args:    defaultArgs,
			want:    testAccessToken,
			wantErr: false,
		},
		{
			name: "get an error from token source",
			httpResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 500},
			},
			mock:    defaultMock,
			args:    defaultArgs,
			wantErr: true,
		},
		{
			name: "get a token from cache: cache hit",
			cacheGetResponse: cacheGetResponse{
				val: []byte(testBearerToken.AccessToken),
				ok:  true,
				err: nil,
			},
			mock: func(_ *httpmock.Client, _ *testing.T, _ *httpResponse, c *cachemock.ExpiringCache, cr cacheGetResponse) {
				c.EXPECT().Get(mock.Anything, mock.Anything, mock.Anything).Return(&cache.ExpiringValue{
					Value:  cr.val,
					Expiry: cr.exp,
				}, cr.ok, cr.err)
			},
			args:      defaultArgs,
			want:      testAccessToken,
			withCache: true,
			wantErr:   false,
		},
		{
			name:             "get a token from cache: cache miss",
			cacheGetResponse: cacheGetResponse{},
			httpResponse: httpResponse{
				err:  nil,
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testBearerToken, t)))},
			},
			mock: func(m *httpmock.Client, _ *testing.T, resp *httpResponse, c *cachemock.ExpiringCache, cr cacheGetResponse) {
				c.EXPECT().Get(mock.Anything, mock.Anything, mock.Anything).Return(&cache.ExpiringValue{
					Value:  cr.val,
					Expiry: cr.exp,
				}, cr.ok, cr.err)
				m.EXPECT().Do(mock.Anything).Return(resp.resp, resp.err).Once()
				c.EXPECT().Set(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
			},
			args:      defaultArgs,
			want:      testAccessToken,
			withCache: true,
			wantErr:   false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, httpMock, cacheMock := newClientWithHTTPMocks(t, tt.withCache)
			tt.mock(httpMock, t, &tt.httpResponse, cacheMock, tt.cacheGetResponse)
			ts := c.TokenSourceFor(tt.args.jwtProvider, tt.args.requestURL, tt.args.clientID, tt.args.resource)

			gotToken, err := ts.Get(ctx)
			require.Equal(t, tt.wantErr, err != nil)
			require.Equal(t, tt.want, gotToken)
		})
	}
}

func newClientWithHTTPMocks(t *testing.T, withCache bool) (*Client, *httpmock.Client, *cachemock.ExpiringCache) {
	var testClientOpts = func(o *httpclient.ClientOptions) {
		o.ReqRetryDelay = 1 * time.Millisecond
		o.ReqRetryMultiplier = 0.0
		o.ReqRetryRandFactor = 0.0
		o.ReqMaxRetries = 3
	}

	mockHTTP := httpmock.NewClient(t)
	mockCache := cachemock.NewExpiringCache(t)

	var options []Option

	if withCache {
		cache := launchcache.NewNamespacedCache(mockCache, observability.NewNullObservability()).AzureProvider()
		options = append(options, WithCache(cache))
	}
	client := New(
		httpclient.New(mockHTTP, testClientOpts),
		options...,
	)
	return client, mockHTTP, mockCache
}

func toBytes(v any, t *testing.T) []byte {
	e, err := json.Marshal(&v)
	if err != nil {
		t.Fatal(errors.Wrap(err, "expected no error"))
	}
	return e
}
