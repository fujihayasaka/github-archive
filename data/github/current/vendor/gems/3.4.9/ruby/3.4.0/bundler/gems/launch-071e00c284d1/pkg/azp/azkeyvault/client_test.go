package azkeyvault

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"reflect"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"

	"github.com/github/launch/workflowbuild/azp/azperrors"

	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/cache"
	"github.com/github/launch/pkg/cache/cachemock"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/pkg/launchhttp/httpmock"
)

const (
	testVault       = "vault"
	testSecret      = "secret"
	testSecretValue = "thesecret"
)

var testKeyVaultSecret = &azp.KeyVaultSecret{Value: testSecretValue}

var testAzpError = azperrors.AzpErrorResponse{
	TypeKey: "ActionsScaleUnitUnavailable",
	Message: "actions scale unit unavailable",
	Ref:     "Ref A: 123",
}

func TestClient_GetSecret(t *testing.T) {

	type httpResponse struct {
		resp *http.Response
		err  error
	}

	type cacheResponse struct {
		expVal *cache.ExpiringValue
		ok     bool
		err    error
	}

	defaultMock := func(m *httpmock.Client, resp *httpResponse, _ *cachemock.ExpiringCache, _ cacheResponse) {
		m.EXPECT().Do(mock.MatchedBy(func(req *http.Request) bool {
			ok := req.Header.Get("Authorization") == "Bearer tokenforkeyvault"
			ok = ok && req.Method == http.MethodGet
			return ok
		})).Return(resp.resp, resp.err).Once()
	}

	type args struct {
		ctx        context.Context
		vaultName  string
		secretName string
	}

	defaultArgs := args{
		ctx:        context.TODO(),
		vaultName:  testVault,
		secretName: testSecret,
	}
	tests := []struct {
		name          string
		mock          func(m *httpmock.Client, resp *httpResponse, c *cachemock.ExpiringCache, cr cacheResponse)
		httpResponse  httpResponse
		cacheResponse cacheResponse
		args          args
		withCache     bool
		want          *azp.KeyVaultSecret
		wantErr       bool
	}{
		{
			name: "can get a secret",
			mock: defaultMock,
			args: defaultArgs,
			httpResponse: httpResponse{
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testKeyVaultSecret, t)))},
			},
			want: testKeyVaultSecret,
		},
		{
			name: "can get an error",
			mock: func(m *httpmock.Client, resp *httpResponse, _ *cachemock.ExpiringCache, _ cacheResponse) {
				m.EXPECT().Do(mock.Anything).Return(resp.resp, resp.err)
			},
			args: defaultArgs,
			httpResponse: httpResponse{
				resp: &http.Response{StatusCode: 500, Body: io.NopCloser(bytes.NewReader(toBytes("this is a key vault internal error", t)))},
			},
			wantErr: true,
		},
		{
			name: "can get an azp error",
			mock: func(m *httpmock.Client, resp *httpResponse, _ *cachemock.ExpiringCache, _ cacheResponse) {
				m.EXPECT().Do(mock.Anything).Return(resp.resp, resp.err)
			},
			args: defaultArgs,
			httpResponse: httpResponse{
				resp: &http.Response{StatusCode: 503, Body: io.NopCloser(bytes.NewReader(toBytes(&testAzpError, t)))},
			},
			wantErr: true,
		},
		{
			name: "cache hit",
			cacheResponse: cacheResponse{
				expVal: &cache.ExpiringValue{
					Value: toBytes(testKeyVaultSecret, t),
				},
				ok: true,
			},
			mock: func(_ *httpmock.Client, _ *httpResponse, c *cachemock.ExpiringCache, cr cacheResponse) {
				c.EXPECT().Get(mock.Anything, mock.Anything, mock.Anything).Return(cr.expVal, cr.ok, cr.err)
			},
			withCache: true,
			args:      defaultArgs,
			want:      testKeyVaultSecret,
		},
		{
			name: "cache miss",
			httpResponse: httpResponse{
				resp: &http.Response{StatusCode: 200, Body: io.NopCloser(bytes.NewReader(toBytes(&testKeyVaultSecret, t)))},
			},
			cacheResponse: cacheResponse{
				ok: false,
			},
			mock: func(m *httpmock.Client, resp *httpResponse, c *cachemock.ExpiringCache, cr cacheResponse) {
				c.EXPECT().Get(mock.Anything, mock.Anything, mock.Anything).Return(cr.expVal, cr.ok, cr.err)
				m.EXPECT().Do(mock.Anything).Return(resp.resp, resp.err).Once()
				c.EXPECT().Set(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
			},
			withCache: true,
			args:      defaultArgs,
			want:      testKeyVaultSecret,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c, httpBackend, cacheBackend := newClientWithHTTPMocks(t, tt.withCache)
			tt.mock(httpBackend, &tt.httpResponse, cacheBackend, tt.cacheResponse)
			got, err := c.GetSecret(tt.args.ctx, tt.args.vaultName, tt.args.secretName)
			if (err != nil) != tt.wantErr {
				t.Errorf("Client.GetSecret() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("Client.GetSecret() = %v, want %v", got, tt.want)
			}
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

	options := []Option{
		WithTokenSource(&fakeTokenSource{}),
	}

	if withCache {
		cache := launchcache.NewNamespacedCache(mockCache, observability.NewNullObservability()).S2SProvider()
		options = append(options, WithCache(cache))
	}
	client := NewClient(
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

type fakeTokenSource struct{}

func (f *fakeTokenSource) Get(context.Context) (string, error) {
	return "tokenforkeyvault", nil
}
