package client

import (
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/opentracing/opentracing-go"
	"github.com/pkg/errors"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
	"github.com/github/go-twirp/v2/client/requestid"
	"github.com/hashicorp/go-retryablehttp"
	twirptrace "github.com/twirp-ecosystem/twirp-opentracing"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

const (
	retriesMetric         = "authnd.client.retries"
	retriesExceededMetric = "authnd.client.retries.exceeded"
	defaultMaxAttempts    = 3
)

type httpClientOptions struct {
	DisableRequestIDForwarding bool
	Tracer                     opentracing.Tracer
	HMACOptions                *hmacOptions
	RetryOptions               *retryOptions
	RoundTripper               http.RoundTripper
	VerboseRequestLogging      bool
}

type retryOptions struct {
	Enabled               bool
	Attempts              int
	MinTimeBetweenRetries time.Duration
	MaxTimeBetweenRetries time.Duration
}

type hmacOptions struct {
	HMAC  string
	IsRaw bool
}

// defaultClientOptions represents the settings that will be used by default
// if no Options functions are supplied to the Authenticator client constructor.
func defaultHTTPClientOptions() *httpClientOptions {
	return &httpClientOptions{
		DisableRequestIDForwarding: false,
		Tracer:                     nil,
		HMACOptions:                nil,
		RetryOptions: &retryOptions{
			Enabled:               true,
			Attempts:              defaultMaxAttempts,
			MinTimeBetweenRetries: 1 * time.Millisecond,
			MaxTimeBetweenRetries: 10 * time.Second,
		},
		RoundTripper: nil,
	}
}

// createHTTPClient creates a HTTP client to be used when calling the authnd twirp API
// uses the set of options to build out production middleware like
// retries, request ID forwarding, tracing, HMAC auth, etc.
func createHTTPClient(options *httpClientOptions, statter stats.Client) pb.HTTPClient {
	transport := http.DefaultTransport
	if options.RoundTripper != nil {
		transport = options.RoundTripper
	}
	// auto-instrumentation for otel traces (see Freno client https://github.com/github/go-freno-client/commit/f5b15faff8c3127c0cdd3319aca6568f4b8beb06)
	var httpClient pb.HTTPClient = &http.Client{Transport: otelhttp.NewTransport(transport,
		otelhttp.WithSpanOptions(trace.WithAttributes(attribute.String("peer.service", "authnd"))),
	)}

	// if client retries are enabled, configure an HTTP client with retries, and backoff
	if options.RetryOptions.Enabled {
		retryableHttpClient := retryablehttp.NewClient()
		retryableHttpClient.RetryMax = options.RetryOptions.Attempts
		retryableHttpClient.RetryWaitMin = options.RetryOptions.MinTimeBetweenRetries
		retryableHttpClient.RetryWaitMax = options.RetryOptions.MaxTimeBetweenRetries
		retryableHttpClient.RequestLogHook = createRetryStats(statter, retryableHttpClient.RetryMax)
		retryableHttpClient.ErrorHandler = createErrorHandler(statter, retryableHttpClient.RetryMax)
		httpClient = retryableHttpClient.StandardClient()
	}

	// enable request ID forwarding as long as it's not explicitly disabled
	if !options.DisableRequestIDForwarding {
		httpClient = requestid.NewForwarder(httpClient)
	}

	// enable tracing as long as it's not explicitly disabled
	if options.Tracer != nil {
		httpClient = twirptrace.NewTraceHTTPClient(httpClient, options.Tracer)
	}

	// always apply HMAC options if they are provided
	if options.HMACOptions != nil {
		if options.HMACOptions.IsRaw {
			httpClient = middleware.ApplyHMAC(httpClient, options.HMACOptions.HMAC)
		} else {
			httpClient = middleware.ApplyHMACKey(httpClient, options.HMACOptions.HMAC)
		}
	}

	if options.VerboseRequestLogging {
		logger := log.New(os.Stderr, "", log.LstdFlags)
		httpClient = middleware.ApplyVerboseLoggingHTTPClient(httpClient, logger)
	}

	return httpClient
}

// used for the retryableHttpClient - send stat for any retries, don't send for initial request
func createRetryStats(statter stats.Client, maxRetries int) retryablehttp.RequestLogHook {
	return func(_ retryablehttp.Logger, req *http.Request, numTries int) {
		if numTries > 0 {
			tags := stats.Tags{
				"retry_number": strconv.Itoa(numTries),
				"max_retries":  strconv.Itoa(maxRetries),
			}
			statter.Counter(retriesMetric, tags, 1)
		}
	}
}

// used for the retryableHttpClient - this is the return from the http client in cases where there
// is an error from the http client, and we've ran out of retries
// the library may reach this point without an error, but it doesn't indicate a success
func createErrorHandler(statter stats.Client, maxRetries int) retryablehttp.ErrorHandler {
	return func(resp *http.Response, err error, numTries int) (*http.Response, error) {
		statusCode := -1
		if resp != nil {
			statusCode = resp.StatusCode
			defer resp.Body.Close()
		}

		tags := stats.Tags{
			"total_tries": strconv.Itoa(numTries),
			"max_retries": strconv.Itoa(maxRetries),
		}
		statter.Counter(retriesExceededMetric, tags, 1)

		if err == nil {
			return nil, errors.Errorf("gave up on retries after %d attempt(s) with unknown error. status code: %d.", numTries, statusCode)
		}
		return nil, errors.Wrapf(err, "gave up on retries after %d attempt(s). status code: %d.", numTries, statusCode)
	}
}
