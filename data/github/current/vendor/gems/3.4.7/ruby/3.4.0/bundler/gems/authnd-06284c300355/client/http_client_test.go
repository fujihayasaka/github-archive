package client

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/opentracing/opentracing-go"
	"github.com/stretchr/testify/require"
)

type mockTracer struct {
	injectCallback func()
}

func (mt mockTracer) StartSpan(operationName string, opts ...opentracing.StartSpanOption) opentracing.Span {
	return nil
}
func (mt mockTracer) Inject(sm opentracing.SpanContext, format interface{}, carrier interface{}) error {
	mt.injectCallback()
	return nil
}
func (mt mockTracer) Extract(format interface{}, carrier interface{}) (opentracing.SpanContext, error) {
	return nil, nil
}

func TestHTTPClientWithDefaults(t *testing.T) {
	theRequestIDValue := "the-request-id"
	var receivedRequestID string
	server := httptest.NewServer(requestid.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedRequestID = requestid.GetGitHubRequestID(r.Context())
	})))
	defer server.Close()

	httpClient := createHTTPClient(defaultHTTPClientOptions(), stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	ctx := requestid.WithGitHubRequestID(context.Background(), theRequestIDValue)
	req = req.WithContext(ctx)
	_, err = httpClient.Do(req)
	require.NoError(t, err)
	require.Equal(t, theRequestIDValue, receivedRequestID)
}

func TestHTTPClientWithHMAC(t *testing.T) {
	theHMACValue := "the-hmac"
	var receivedHMAC string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedHMAC = r.Header.Get("Request-HMAC")
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	options.HMACOptions = &hmacOptions{
		HMAC: theHMACValue,
	}
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	_, err = httpClient.Do(req)
	require.NoError(t, err)
	require.Equal(t, hmac.NewRequestHMAC(theHMACValue).String(), receivedHMAC)
}

func TestHTTPClientWithRawHMAC(t *testing.T) {
	theHMACValue := "the-hmac"
	var receivedHMAC string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedHMAC = r.Header.Get("Request-HMAC")
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	options.HMACOptions = &hmacOptions{
		HMAC:  theHMACValue,
		IsRaw: true,
	}
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	_, err = httpClient.Do(req)
	require.NoError(t, err)
	require.Equal(t, theHMACValue, receivedHMAC)
}

func TestHTTPClientWithDisabledRequestIDForwarding(t *testing.T) {
	theRequestIDValue := "the-request-id"
	var receivedRequestID string
	server := httptest.NewServer(requestid.Handler(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedRequestID = requestid.GetGitHubRequestID(r.Context())
	})))
	defer server.Close()

	options := defaultHTTPClientOptions()
	options.DisableRequestIDForwarding = true
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	ctx := requestid.WithGitHubRequestID(context.Background(), theRequestIDValue)
	req = req.WithContext(ctx)
	_, err = httpClient.Do(req)
	require.NoError(t, err)
	// shouldn't equal the GitHub request ID set above (will be a uuid)
	require.NotEqual(t, theRequestIDValue, receivedRequestID)
}

func TestHTTPClientWithTracer(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	defer server.Close()

	calledInject := false
	testTracer := &mockTracer{
		injectCallback: func() {
			calledInject = true
		},
	}

	options := defaultHTTPClientOptions()
	options.Tracer = testTracer
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	_, err = httpClient.Do(req)
	require.NoError(t, err)
	require.True(t, calledInject)
}

func TestHTTPClientRetriesExceeded(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	resp, err := httpClient.Do(req)
	require.Nil(t, resp)
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "status code: 503"))
	require.Equal(t, options.RetryOptions.Attempts+1, callCount)
}

func TestHTTPClientRetriesDoesntRetryOnBadRequests(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	resp, err := httpClient.Do(req)
	require.NotNil(t, resp)
	require.NoError(t, err)
	require.Equal(t, 1, callCount)
	require.Equal(t, http.StatusBadRequest, resp.StatusCode)
}

func TestHTTPClientRetriesCanExtendRetries(t *testing.T) {
	customMaxRetries := 10
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	options.RetryOptions.Attempts = customMaxRetries
	// set max time between retries to microseconds to keep this test fast
	options.RetryOptions.MaxTimeBetweenRetries = time.Microsecond
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	resp, err := httpClient.Do(req)
	require.Nil(t, resp)
	require.Error(t, err)
	require.Equal(t, customMaxRetries+1, callCount)
}

func TestHTTPClientRetriesCanDisableRetries(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	options.RetryOptions.Enabled = false
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	resp, err := httpClient.Do(req)
	require.NoError(t, err)
	require.Equal(t, 1, callCount)
	require.Equal(t, http.StatusServiceUnavailable, resp.StatusCode)
}

func TestHTTPClientRetriesFailOnceSucceedAfter(t *testing.T) {
	callCount := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if callCount > 0 {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		callCount++
	}))
	defer server.Close()

	options := defaultHTTPClientOptions()
	httpClient := createHTTPClient(options, stats.NullStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	resp, err := httpClient.Do(req)
	require.NotNil(t, resp)
	require.NoError(t, err)
	require.Equal(t, 2, callCount)
	require.Equal(t, http.StatusOK, resp.StatusCode)
}

func TestHTTPClientRetryMetrics(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)
	options := defaultHTTPClientOptions()

	for i := 1; i <= options.RetryOptions.Attempts; i++ {
		mockStatter.Mock.On(
			"Counter",
			retriesMetric,
			stats.Tags{
				"retry_number": fmt.Sprint(i),
				"max_retries":  fmt.Sprint(options.RetryOptions.Attempts),
			},
			int64(1),
		).Return()
	}
	mockStatter.Mock.On(
		"Counter",
		retriesExceededMetric,
		stats.Tags{
			"total_tries": fmt.Sprint(options.RetryOptions.Attempts + 1),
			"max_retries": fmt.Sprint(options.RetryOptions.Attempts),
		},
		int64(1),
	).Return()

	httpClient := createHTTPClient(options, &mockStatter)
	require.NotNil(t, httpClient)

	req, err := http.NewRequest("GET", server.URL, nil)
	require.NoError(t, err)

	resp, err := httpClient.Do(req)
	require.Nil(t, resp)
	require.Error(t, err)
	require.True(t, strings.Contains(err.Error(), "status code: 503"))
}
