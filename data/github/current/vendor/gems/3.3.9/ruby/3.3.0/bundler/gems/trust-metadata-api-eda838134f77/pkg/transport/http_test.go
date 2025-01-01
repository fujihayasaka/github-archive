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
		LegacyTMA: []auth.ClientConfig{},
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
		// NPM: uploading-worker
		LegacyTMA: []auth.ClientConfig{{
			ClientID: "uploading-worker",
			Domain:   "npm",
			Keys:     []string{"deadbeef"},
		}},
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
