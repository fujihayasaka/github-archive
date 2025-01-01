package apiservice

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/github-telemetry-go/log"
	ghhmac "github.com/github/go-auth/hmac"
	"github.com/github/go-exceptions"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/api"
	"github.com/github/notifyd/internal/pkg/job/middlewares/mocks"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	"github.com/github/notifyd/proto/services/test"
)

// Test server implements a basic echo server for twirp. Its only purpose is to serve as a server
// that we can use to test parts of our application and framework without depending on the whole
// baggage coming with the domain services as that would be too cumbersome.
//
// The only thing the service does is to echo the message that it receives on the request.
type testServer struct {
	t   *testing.T
	err error
}

func newTestServer(t *testing.T) *testServer {
	return &testServer{t, nil}
}

func (s *testServer) Handler(hooks *twirp.ServerHooks) api.Handler {
	return test.NewTestServer(s, hooks)
}

func (s *testServer) Echo(ctx context.Context, req *test.EchoRequest) (*test.EchoResponse, error) {
	s.t.Helper()
	s.t.Logf("received msg: %s", req.GetMsg())

	if s.err != nil {
		return nil, s.err
	}

	return &test.EchoResponse{Msg: req.GetMsg()}, nil
}

func (s *testServer) Timeout(ctx context.Context, _ *test.EchoRequest) (*test.EchoResponse, error) {
	s.t.Helper()

	// Timeout always sleeps for 3 seconds, to mimic a slow backend response
	// The test server's APITimeout is set to 200 milliseconds
	select {
	case <-time.After(3 * time.Second):
		return nil, fmt.Errorf("timeout")
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func Test_Ping(t *testing.T) {
	r := require.New(t)

	svc := testService(t, &twirp.ServerHooks{})
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	req, _ := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+"/_ping", http.NoBody)
	client := &http.Client{}
	resp, err := client.Do(req)

	r.NoError(err)
	defer resp.Body.Close()
	r.Equal(http.StatusOK, resp.StatusCode)
}

func Test_MandatorySecurityHeaders(t *testing.T) {
	r := require.New(t)

	svc := testService(t, &twirp.ServerHooks{})
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	ctx := context.Background()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, srv.URL, http.NoBody)
	r.NoError(err)

	client := &http.Client{}
	resp, err := client.Do(req)
	r.NoError(err)
	defer resp.Body.Close()

	r.Equal("max-age=31536000", resp.Header.Get("Strict-Transport-Security"), "expected HSTS header")
	r.Equal("default-src 'none'; sandbox", resp.Header.Get("Content-Security-Policy"), "expected CSP header")
}

func Test_HandlerSetup(t *testing.T) {
	r := require.New(t)

	svc := testService(t, &twirp.ServerHooks{})
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	client := test.NewTestProtobufClient(srv.URL, &http.Client{}, twirp.WithClientHooks(testAuthHook(t, testHMACKey)))
	resp, err := client.Echo(context.Background(), &test.EchoRequest{Msg: "foo"})

	r.NoError(err)
	r.Equal("foo", resp.GetMsg())
}

func Test_HmacValidation(t *testing.T) {
	r := require.New(t)

	tests := []struct {
		name    string
		options []twirp.ClientOption
		success bool
		error   twirp.ErrorCode
	}{
		{
			name:    "Valid HMAC Header",
			options: []twirp.ClientOption{twirp.WithClientHooks(testAuthHook(t, testHMACKey))},
		},
		{
			name:    "No HMAC Header",
			options: []twirp.ClientOption{},
			error:   twirp.Internal,
		},
		{
			name:    "Invalid HMAC Header",
			options: []twirp.ClientOption{twirp.WithClientHooks(testAuthHook(t, "this-is-not-the-key"))},
			error:   twirp.Unauthenticated,
		},
	}

	for _, tst := range tests {
		t.Run(tst.name, func(t *testing.T) {
			hooks, err := NewHooks(context.Background(), log.NewNullLogger(), stats.NullStatter)
			r.NoError(err)

			svc := testService(t, hooks)
			srv := httptest.NewServer(svc.Handler)
			defer srv.Close()

			client := test.NewTestProtobufClient(srv.URL, &http.Client{}, tst.options...)
			resp, err := client.Echo(context.Background(), &test.EchoRequest{Msg: "foo"})

			if tst.error == "" {
				r.NoError(err)
				r.NotNil(resp)

				return
			}

			var twirpErr twirp.Error
			r.ErrorAs(err, &twirpErr)
			r.Equal(tst.error, twirpErr.Code())
			r.Nil(resp)
		})
	}
}

func Test_RequestLogging(t *testing.T) {
	r := require.New(t)
	logger := mocks.NewLoggerMock(t)
	logger.On("Named", mock.Anything).Return(logger)
	logger.On("Info", "request", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything)

	hooks, err := NewHooks(context.Background(), logger, stats.NullStatter)
	r.NoError(err)

	svc := testService(t, hooks)
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	client := test.NewTestProtobufClient(srv.URL, &http.Client{}, twirp.WithClientHooks(testAuthHook(t, testHMACKey)))
	_, err = client.Echo(context.Background(), &test.EchoRequest{Msg: "foo"})
	r.NoError(err)
}

func Test_HandlerTimeouts(t *testing.T) {
	r := require.New(t)

	svc := testService(t, &twirp.ServerHooks{})
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	t.Logf("Server timeouts: read: %v write: %v", svc.Server.ReadTimeout, svc.Server.WriteTimeout)

	client := test.NewTestProtobufClient(srv.URL, &http.Client{}, twirp.WithClientHooks(testAuthHook(t, testHMACKey)))
	resp, err := client.Timeout(context.Background(), &test.EchoRequest{})

	// Timeout takes 3 seconds, so we should get no response and a timeout error
	// The error is given by the http.TimeoutHandler and results in a 503
	r.Nil(resp)
	r.Contains(err.Error(), "Service Unavailable")
}

func Test_HandlerTenantMiddleware_SingleTenant(t *testing.T) {
	spec := &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			tenant, err := tenancy.FromContext(ctx)
			require.NoError(t, err)
			require.Equal(t, "", tenant.Slug())
			require.Equal(t, int64(0), tenant.ID())

			return ctx, nil
		},
	}
	svc := testServiceWithTenant(t, tenancy.NewSingleTenant(), spec)
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	client := test.NewTestProtobufClient(
		srv.URL,
		&http.Client{},
		twirp.WithClientHooks(twirp.ChainClientHooks(
			testAuthHook(t, testHMACKey),
			testTenantHook(t, "avocado", "123"),
		)),
	)

	resp, err := client.Echo(context.Background(), &test.EchoRequest{Msg: "foo"})

	require.NoError(t, err)
	require.Equal(t, "foo", resp.GetMsg())
}

func Test_HandlerTenantMiddleware_MultiTenant(t *testing.T) {
	spec := &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			tenant, err := tenancy.FromContext(ctx)
			require.NoError(t, err)
			require.Equal(t, "avocado", tenant.Slug())
			require.Equal(t, int64(123), tenant.ID())

			return ctx, nil
		},
	}
	svc := testServiceWithTenant(t, tenancy.NewMultiTenant(), spec)
	srv := httptest.NewServer(svc.Handler)
	defer srv.Close()

	client := test.NewTestProtobufClient(
		srv.URL,
		&http.Client{},
		twirp.WithClientHooks(twirp.ChainClientHooks(
			testAuthHook(t, testHMACKey),
			testTenantHook(t, "avocado", "123"),
		)),
	)

	resp, err := client.Echo(context.Background(), &test.EchoRequest{Msg: "foo"})

	require.NoError(t, err)
	require.Equal(t, "foo", resp.GetMsg())
}

// Creates a twirp client hook that will add the Request-HMAC header to the request signed
// with the given hmacKey
func testAuthHook(t *testing.T, key string) *twirp.ClientHooks {
	t.Helper()

	return &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, r *http.Request) (context.Context, error) {
			r.Header.Set(headers.RequestHMAC, ghhmac.NewRequestHMAC(key).String())
			return ctx, nil
		},
	}
}

func testTenantHook(t *testing.T, slug, id string) *twirp.ClientHooks {
	t.Helper()

	return &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, r *http.Request) (context.Context, error) {
			r.Header.Set(tenancy.HeaderTenantSlug, slug)
			r.Header.Set(tenancy.HeaderTenantID, id)
			return ctx, nil
		},
	}
}

const testHMACKey string = "TEST_KEY"

func testService(t *testing.T, hooks *twirp.ServerHooks) Service {
	return testServiceWithTenant(t, tenancy.NewSingleTenant(), hooks)
}

func testServiceWithTenant(t *testing.T, tenant tenancy.Tenant, hooks *twirp.ServerHooks) Service {
	t.Helper()

	cfg := Config{Timeout: 200 * time.Millisecond}

	hmacValidator := &hmac.Validator{
		Secrets: []string{testHMACKey},
		Logger:  log.NewNullLogger(),
	}

	return NewService(
		cfg,
		tenant,
		clock.NewMock(),
		logs.NullTelem,
		exceptions.NullReporter,
		hooks,
		hmacValidator,
		newTestServer(t),
	)
}
