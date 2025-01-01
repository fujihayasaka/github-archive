package apphttp

import (
	"context"
	"crypto/tls"
	"net"
	"net/http"
	"net/http/httptrace"
	"time"

	"github.com/CGA1123/shed"
	"go.opentelemetry.io/contrib/instrumentation/net/http/httptrace/otelhttptrace"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/orchestrationid"
	"github.com/github/launch/utils/roundtrippers"
)

const (
	// AzureFrontDoorMaxTimeout is set to 55s such that we terminate the request on the client
	// side before the connection is dropped by Azure Front door.
	AzureFrontDoorMaxTimeout time.Duration = 55 * time.Second
)

type options struct {
	MaxTimeout          time.Duration
	DialTimeout         time.Duration
	MaxIdleConnsPerHost int
	FollowRedirects     bool
	TLSClientConfig     *tls.Config
	Observability       *observability.Observability
	RoundTripperConfig  *roundtrippers.RoundTripperConfig
	ApplyMiddlewareFunc func(http.RoundTripper) http.RoundTripper
}

type Option func(*options)

// With AzureFrontDoorMaxTimeout enforces a client-side timeout of 55s
// to ensure that the request terminates on the client
// before the connection is dropped by Azure Front Door.
func WithAzureFrontDoorMaxTimeout() Option {
	return WithMaxTimeout(AzureFrontDoorMaxTimeout)
}

func WithMaxTimeout(d time.Duration) Option {
	return func(o *options) {
		o.MaxTimeout = d
	}
}

func WithIgnoreRedirects() Option {
	return func(o *options) {
		o.FollowRedirects = false
	}
}

func WithTLSClientConfig(c *tls.Config) Option {
	return func(o *options) {
		o.TLSClientConfig = c
	}
}

func WithObservability(obs *observability.Observability, cfg roundtrippers.RoundTripperConfig) Option {
	return func(o *options) {
		o.Observability = obs
		o.RoundTripperConfig = &cfg
	}
}

func WithMiddleware(apply func(http.RoundTripper) http.RoundTripper) Option {
	return func(o *options) {
		o.ApplyMiddlewareFunc = apply
	}
}

// NewClient instantiates an http.Client with the given options.
// Note that, by default, the returned client will enforce a MaxTimeout of 10s.
// If you plan to send requests with a Request-Timeout header greater than 10s,
// you should include a corresponding MaxTimeout Option when instantiating an apphttp client.
func NewClient(opts ...Option) *http.Client {
	o := &options{
		MaxTimeout:          time.Second * 10,
		DialTimeout:         time.Second * 10,
		MaxIdleConnsPerHost: 10,
		FollowRedirects:     true,
		TLSClientConfig:     nil,
		Observability:       nil,
		RoundTripperConfig:  nil,
		ApplyMiddlewareFunc: func(rt http.RoundTripper) http.RoundTripper { return rt },
	}

	for _, f := range opts {
		f(o)
	}

	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		Dial:  (&net.Dialer{Timeout: o.DialTimeout}).Dial,
		// "ResponseHeaderTimeout" is a misnomer in go/net/http.
		// It's actually enforced within the client and is never embedded in a RESPONSE header
		// (though it is sometimes embedded in a REQUEST header, in the form of 'X-Client-Timeout-Ms').
		ResponseHeaderTimeout: o.MaxTimeout,
		MaxIdleConnsPerHost:   o.MaxIdleConnsPerHost,
		TLSClientConfig:       o.TLSClientConfig,
	}

	// Send the orchestration ID to any service Launch calls
	orchIdRoundTripper := orchestrationid.NewOrchestrationIdRequestHeadersTransport(transport)

	// RoundTripper are called in LIFO
	otelRoundTripper := otelhttp.NewTransport(
		orchIdRoundTripper,
		otelhttp.WithClientTrace(func(ctx context.Context) *httptrace.ClientTrace {
			return otelhttptrace.NewClientTrace(ctx)
		}),
	)
	roundTripper := roundtrippers.PropagateTimeout(otelRoundTripper, shed.WithMaxTimeout(o.MaxTimeout))

	if o.RoundTripperConfig != nil && o.Observability != nil {
		hooks := make([]roundtrippers.Hook, 0, 2)
		if o.RoundTripperConfig.TelemetryRoundTripperEnableLogs {
			hooks = append(hooks, roundtrippers.RequestLoggingHook(o.Observability.Logger))
		}
		roundTripper = roundtrippers.NewTelemetryRoundTripper(roundTripper, hooks...)
	}

	roundTripper = o.ApplyMiddlewareFunc(roundTripper)

	return &http.Client{
		Transport: roundTripper,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if !o.FollowRedirects {
				return http.ErrUseLastResponse
			}
			// If we have a redirect, we want to make sure that we copy the headers that
			// we had from the first request to the subsequent one, in case we hit a
			// cache host.
			// Copying logic is from Go's standard library: https://github.com/golang/go/blob/master/src/net/http/client.go#L796
			if len(via) > 0 {
				initialReq := via[0]
				initialReqHeaders := initialReq.Header.Clone()
				for k, vv := range initialReqHeaders {
					req.Header[k] = vv
				}
			}

			// Honor the default of stopping after 10 redirects before returning an
			// error.
			if len(via) >= 10 {
				return http.ErrUseLastResponse
			}

			return nil
		},
		// REVIEW: Consider also setting the following:
		// Timeout: o.MaxTimeout,
	}
}
