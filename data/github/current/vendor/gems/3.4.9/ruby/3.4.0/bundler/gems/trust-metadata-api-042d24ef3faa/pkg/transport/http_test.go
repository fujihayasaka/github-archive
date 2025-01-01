package transport

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/service"
	"github.com/stretchr/testify/assert"
)

func TestNoServices(t *testing.T) {
	tma := service.NewTestTMA(t)

	testHMACConfig := ServerAuthConfig{
		// NPM
		PkgRead:  []auth.ClientConfig{},
		PkgWrite: []auth.ClientConfig{},
		// GitHub
		Dotcom: []auth.ClientConfig{},
	}

	httpOpts := make([]HTTPServerOption, 0)

	httpOpts = append(httpOpts, WithLogger(log.NewNullLogger()))
	httpOpts = append(httpOpts, WithMetrics(nil))
	httpOpts = append(httpOpts, WithExceptionReporter(nil))
	httpOpts = append(httpOpts, WithContext(context.TODO()))

	httpOpts = append(httpOpts, WithHMACConfig(testHMACConfig))

	// These routes should be unauthenticated. To prove this, let's set up the
	// WithHMAC option with the httptest Server.
	httpServer, err := NewHTTP(tma, "8888", httpOpts...)

	if !errors.Is(err, ErrNoService) {
		t.Fatalf("expected ErrNoService, got %s", err)
	}
	if httpServer != nil {
		t.Fatal("unexpected server returned")
	}
}

func TestStatusRoutes(t *testing.T) {
	tma := service.NewTestTMA(t)

	testHMACConfig := ServerAuthConfig{
		// NPM: PackageInfoRead
		PkgRead: []auth.ClientConfig{{
			ClientID: "npm/read",
			Domain:   "npm",
			Keys:     []string{"decafbad"},
		}},
		// NPM: PackageInfoWrite
		PkgWrite: []auth.ClientConfig{{
			ClientID: "uploading-worker",
			Domain:   "npm",
			Keys:     []string{"feedbeef"},
		}},
		// GitHubAPI
		Dotcom: []auth.ClientConfig{{
			ClientID: "dotcom",
			Domain:   "github",
			Keys:     []string{"dgweredr"},
		}},
	}

	httpOpts := make([]HTTPServerOption, 0)

	httpOpts = append(httpOpts, WithLogger(log.NewNullLogger()))
	httpOpts = append(httpOpts, WithMetrics(nil))
	httpOpts = append(httpOpts, WithExceptionReporter(nil))
	httpOpts = append(httpOpts, WithContext(context.TODO()))

	httpOpts = append(httpOpts, WithHMACConfig(testHMACConfig))

	// These routes should be unauthenticated. To prove this, let's set up the
	// WithHMAC option with the httptest Server.
	httpServer, err := NewHTTP(tma, "8888", httpOpts...)

	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(httpServer)
	defer server.Close()

	client := server.Client()

	t.Run("/status returns properly", func(t *testing.T) {
		resp, err := client.Get(server.URL + "/status")
		assert.Nil(t, err)

		assert.Equal(t, 200, resp.StatusCode)

		var statusBody map[string]string
		dec := json.NewDecoder(resp.Body)
		err = dec.Decode(&statusBody)

		assert.Nil(t, err, "should not error")
		assert.Equal(t, "ok", statusBody["state"], "status body should be ok")
	})

	t.Run("Not found handler fires properly", func(t *testing.T) {
		resp, err := client.Get(server.URL + "/notfound")

		assert.Nil(t, err)
		assert.Equal(t, 404, resp.StatusCode, "should return 404")
	})

	t.Run("Zen handler returns zen", func(t *testing.T) {
		resp, err := client.Get(server.URL)
		assert.Nil(t, err)

		assert.Equal(t, 200, resp.StatusCode)

		var zenMsg map[string]string
		dec := json.NewDecoder(resp.Body)
		err = dec.Decode(&zenMsg)

		assert.Nil(t, err)
		assert.NotEmpty(t, zenMsg["zen"])
	})
}

// BufWriteSyncer is a custom io.Writer implementation
// used to test the logger middleware
type BufWriteSyncer struct {
	bytes.Buffer
}

func (s BufWriteSyncer) Sync() error {
	return nil
}

func TestLoggerMiddleware(t *testing.T) {
	// create a logger using a custom io.Writer implementation
	// this allows use to change the destination of the logs, which
	// we use below to test logger middleware
	bufWrite := BufWriteSyncer{}
	logger, err := log.NewFromConfig(log.Config{
		LogLevel:           log.DebugLevel.String(),
		LogConsoleEncoding: "logfmt",
	}, log.WithWriteSyncer(&bufWrite))
	if err != nil {
		assert.FailNow(t, "failed to create test logger", err)
	}

	handler := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	middleware := loggerMiddleware(logger)

	// Test that the logger middleware logs the request
	request := httptest.NewRequest("GET", "/foo", nil)
	response := httptest.NewRecorder()
	middleware(handler).ServeHTTP(response, request)
	assert.Equal(t, http.StatusOK, response.Code)
	assert.Contains(t, bufWrite.String(), "http.method=GET http.target=/foo http.status_code=200")

	// Reset the log buffer
	bufWrite.Reset()

	// Test that the logger middleware does not log requests to /status
	request = httptest.NewRequest("GET", "/status", nil)
	response = httptest.NewRecorder()
	middleware(handler).ServeHTTP(response, request)
	assert.Equal(t, http.StatusOK, response.Code)
	assert.Empty(t, bufWrite.String())
}

type ccHandler struct {
	cc *CallerContext
}

func (c *ccHandler) ServeHTTP(_ http.ResponseWriter, r *http.Request) {
	cc, ok := r.Context().Value(CallerContextKeyName).(*CallerContext)

	if ok {
		c.cc = cc
	}
}

func TestLogCallerContext(t *testing.T) {
	// To avoid testing header retrievals using same const values,
	// the values here are copied from
	// https://github.com/github/github/blob/master/lib/github/faraday_middleware/request_analytics.rb
	var (
		headerActorID      = "X-GitHub-Actor-Id"
		headerInstallID    = "X-GitHub-Installation-Id"
		headerSSIITargetID = "X-GitHub-Site-Scoped-Integration-Installation-Target-Id"
		headerSSIIRepoID   = "X-GitHub-Site-Scoped-Integration-Installation-Repo-Id"
	)

	t.Run("noting set", func(t *testing.T) {
		var cch ccHandler

		r := httptest.NewRequest(http.MethodGet, "/foo", nil)
		fn := LogCallerContext(&cch)
		fn.ServeHTTP(nil, r)

		assert.NotNil(t, cch.cc)
	})

	t.Run("everything set", func(t *testing.T) {
		var cch ccHandler

		r := httptest.NewRequest(http.MethodGet, "/foo", nil)
		r.Header.Set(headerActorID, "123")
		r.Header.Set(headerInstallID, "456")
		r.Header.Set(headerSSIITargetID, "789")
		r.Header.Set(headerSSIIRepoID, "101112")
		fn := LogCallerContext(&cch)
		fn.ServeHTTP(nil, r)

		assert.NotNil(t, cch.cc)
		assert.Equal(t, uint64(123), cch.cc.ActorID)
		assert.Equal(t, uint64(456), cch.cc.InstallationID)
		assert.Equal(t, uint64(789), cch.cc.SSIITargetID)
		assert.Equal(t, uint64(101112), cch.cc.SSIIRepositoryID)
	})
}

func TestGetHeaderUInt64(t *testing.T) {
	var tc = []struct {
		v    string
		want uint64
	}{
		{
			v:    "123",
			want: 123,
		},
		{
			v:    "-123",
			want: 0,
		},
		{
			v:    "",
			want: 0,
		},
		{
			v:    "123a",
			want: 0,
		},
	}

	for _, tt := range tc {
		h := make(http.Header)
		h.Set("a", tt.v)
		got := getHeaderUInt64(h, "a")
		assert.Equal(t, tt.want, got)
	}
}
