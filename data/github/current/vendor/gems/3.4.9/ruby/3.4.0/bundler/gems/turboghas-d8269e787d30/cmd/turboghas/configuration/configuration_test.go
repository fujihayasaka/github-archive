package configuration

import (
	"net"
	"net/http"
	"net/url"
	"strings"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mocks"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

type mockLogger struct {
	mock.Mock
}

func (m *mockLogger) Log(level log.Level, msg string, fields ...kvp.Field) {
	m.Called(level, msg, fields)
}

var _ logAdaptor = &mockLogger{}

func TestIsNetworkError(t *testing.T) {
	require.False(t, isNetworkError(errors.New("not a network error")))
	require.True(t, isNetworkError(&net.OpError{
		Op:     "dial",
		Net:    "db-mysql-turboghas-prod-ro.service.github.net",
		Source: nil,
		Addr:   &net.IPAddr{IP: net.ParseIP("10.127.5.10")},
	}))
}

func TestRollupFunc(t *testing.T) {
	msg, ok := rollupFunc(errors.Wrap(twirp.InternalError("twirp broke"), "wrapped twirp error"))
	require.True(t, ok)
	require.Equal(t, "twirp error: internal", msg)
}

func TestError(t *testing.T) {
	logger := mocks.Cleanup(t, &mockLogger{})
	logger.On("Log", log.ErrorLevel, "test", []kvp.Field{kvp.Any("key", 1)}).Return()
	leveledLogger{logger}.Error("test", "key", 1)

	// check the logger will not crash on bad args
	leveledLogger{log.NewNullLogger()}.Error("test", "key")
	leveledLogger{log.NewNullLogger()}.Error("test", 1)
	leveledLogger{log.NewNullLogger()}.Error("test")
}

func mustQuery(t *testing.T, v string) url.Values {
	t.Helper()
	i := strings.Index(v, "?")
	if i >= 0 {
		values, err := url.ParseQuery(v[i+1:])
		require.NoError(t, err)
		return values
	}
	require.Fail(t, "missing ?")
	return url.Values{}
}

func TestDatabaseConfig(t *testing.T) {
	testCfg := dbtest.Config()
	cfg, err := LoadConfiguration()
	require.NoError(t, err)
	prodCfg, _ := cfg.MysqlConfig()
	prodCfg.FormatDSN()
	testCfg.FormatDSN()
	prod := mustQuery(t, prodCfg.FormatDSN())
	test := mustQuery(t, testCfg.FormatDSN())
	// we do not mind if the tls config is different in test
	prod.Del("tls")
	test.Del("tls")
	require.Equal(t, prod, test)
}

type mockRoundTripper struct {
}

var _ http.RoundTripper = &mockRoundTripper{}

func (m *mockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	return &http.Response{Body: http.NoBody}, nil
}

func TestClientVersion(t *testing.T) {
	ctx := fromctx.App.With(t.Context(), "sync")
	client := AppTransport(ctx, &mockRoundTripper{})
	req := &http.Request{Header: http.Header{}}
	resp, err := client.RoundTrip(req)
	require.NoError(t, err)
	require.NoError(t, resp.Body.Close())
	require.Contains(t, req.Header.Get("User-Agent"), "github/turboghas#sync")
	require.Contains(t, req.Header.Get("User-Agent"), "(#code-scanning)")
}

func TestSpokesClient(t *testing.T) {
	ctx := fromctx.App.With(t.Context(), "test")
	_, err := (&Configuration{}).SpokesTransport(ctx)
	require.NoError(t, err)
}

func TestIsEnterprise(t *testing.T) {
	ctx := fromctx.Env.With(t.Context(), "enterprise")

	require.True(t, fromctx.Env.Value(ctx).IsEnterprise())
	require.False(t, fromctx.Env.Value(ctx).IsTest())
	require.False(t, fromctx.Env.Value(ctx).IsDevelopment())
}
