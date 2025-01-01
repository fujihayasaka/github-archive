package http

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	net_http "net/http"
	"os"
	"strconv"
	"time"

	"github.com/github/go-telemetry/statting"
)

const (
	// DefaultNetHTTPDialerTimeout is an extremely verbose way of describing the net/http.Client's default Dialer timeout.
	// See: https://golang.org/pkg/net/http/#RoundTripper
	DefaultNetHTTPDialerTimeout = 30 * time.Second

	// DefaultNetHTTPDialerKeepAlive is an extremely verbose way of describing the net/http.Client's default Dialer keep alive.
	// See: https://golang.org/pkg/net/http/#RoundTripper
	DefaultNetHTTPDialerKeepAlive = 30 * time.Second

	defaultConnectTimeout = 1 * time.Second
	defaultTLSTimeout     = 2 * time.Second
)

// spokesRoundTripper records a metric for gitmon delay.
type spokesRoundTripper struct {
	rt net_http.RoundTripper
}

// RoundTrip inspecs the response and records a metric for gitmon delay if the
// header is found in the response.
func (s *spokesRoundTripper) RoundTrip(req *net_http.Request) (*net_http.Response, error) {
	res, err := s.rt.RoundTrip(req)
	if err != nil {
		return res, err
	}

	// Delay added by gitmon in fractional seconds
	// See: https://github.com/github/spokes-proto/blob/main/docs/gitmon.md#response
	const gitmonDelay = "X-Gitmon-Delay"

	if delay := res.Header.Get(gitmonDelay); delay != "" {
		if delaySeconds, err := strconv.ParseFloat(delay, 64); err == nil {
			statting.DistributionMs(req.Context(), "gitmon_delay.duration", time.Duration(delaySeconds*float64(time.Second)))
		}
	}

	return res, err
}

// SpokesRoundTripper returns a RoundTripper that will record spokes API
// specific metrics that are not accessible at the Twirp response level.
//
// See https://twitchtv.github.io/twirp/docs/headers.html#read-http-headers-from-responses
func SpokesRoundTripper(rt net_http.RoundTripper) net_http.RoundTripper {
	return &spokesRoundTripper{rt: rt}
}

// uaTransport sets the User-Agent header for all HTTP requests.
type uaTransport struct {
	rt        net_http.RoundTripper
	userAgent string
}

// RoundTrip adds the User-Agent header.
func (u *uaTransport) RoundTrip(req *net_http.Request) (*net_http.Response, error) {
	req.Header.Add("User-Agent", u.userAgent)
	return u.rt.RoundTrip(req)
}

// Config is a functional configuration type for configuring Go's net/http client.
type Config func(client *net_http.Client, transport *net_http.Transport, dial *net.Dialer)

// ConnectTimeout overrides the dial connection timeout.
func ConnectTimeout(timeout time.Duration) Config {
	return func(client *net_http.Client, transport *net_http.Transport, dial *net.Dialer) {
		dial.Timeout = timeout
	}
}

// TLSHandshakeTimeout sets the TLSHandShakeTimeout on the transport.
func TLSHandshakeTimeout(timeout time.Duration) Config {
	return func(_ *net_http.Client, transport *net_http.Transport, _ *net.Dialer) {
		transport.TLSHandshakeTimeout = timeout
	}
}

// ConfigureTLS injects cert and key material for http.Transport set up for TLS
// TODO: builder API should probably return function that can error from these option setters
func ConfigureTLS(pathToKey, pathToCert, pathToBundle string) Config {
	return func(client *net_http.Client, transport *net_http.Transport, dial *net.Dialer) {
		// callers should validate supplied paths!
		cert, err := tls.LoadX509KeyPair(pathToCert, pathToKey)
		if err != nil {
			panic(fmt.Sprintf("failed to load x509 key at %s and/or cert at %s - got: %s",
				pathToKey, pathToCert, err))
		}

		// callers should validate supplied paths!
		bundle, err := os.ReadFile(pathToBundle) //nolint:gosec
		if err != nil {
			panic(fmt.Sprintf("failed to read bundle file at %s, got: %s", pathToBundle, err))
		}

		caCertPool, err := x509.SystemCertPool()
		if err != nil {
			panic(fmt.Sprintf("failed to obtain ref to CA cert pool, got: %s", err))
		}
		caCertPool.AppendCertsFromPEM(bundle)

		transport.TLSClientConfig = &tls.Config{
			Certificates: []tls.Certificate{cert},
			RootCAs:      caCertPool,
			MinVersion:   tls.VersionTLS12,
		}
	}
}

// ConfigureTLSByPEM injects cert and key material for to setup http.Transport for TLS.
// TODO: builder API should probably return function that can error from these option setters
func ConfigureTLSByPEM(keyPEM, certPEM, certChainPEM []byte) Config {
	return func(client *net_http.Client, transport *net_http.Transport, dial *net.Dialer) {
		// callers should validate supplied values
		cert, err := tls.X509KeyPair(certPEM, keyPEM)
		if err != nil {
			panic(fmt.Sprintf("failed to load x509 key and/or cert from PEM data - got: %s", err))
		}

		caCertPool, err := x509.SystemCertPool()
		if err != nil {
			panic(fmt.Sprintf("failed to obtain ref to CA cert pool, got: %s", err))
		}
		caCertPool.AppendCertsFromPEM(certChainPEM)

		transport.TLSClientConfig = &tls.Config{
			Certificates: []tls.Certificate{cert},
			RootCAs:      caCertPool,
			MinVersion:   tls.VersionTLS12,
		}
	}
}

// Disables http2 on the transport, this function supplies an empty tls config when one is not already setup since
// a non-nil tls config is required for disabling to work correctly.
func DisableHttp2() Config {
	return func(client *net_http.Client, transport *net_http.Transport, dial *net.Dialer) {
		transport.ForceAttemptHTTP2 = false
		if transport.TLSClientConfig == nil {
			transport.TLSClientConfig = &tls.Config{
				MinVersion: tls.VersionTLS12,
			}
		}
	}
}

// KeepAlive ovrrides the dial keep alive.
func KeepAlive(timeout time.Duration) Config {
	return func(_ *net_http.Client, _ *net_http.Transport, dial *net.Dialer) {
		dial.KeepAlive = timeout
	}
}

// RequestTimeout sets the overall request timeout (this uses context cancellation).
// NOTE: Be careful using this with http calls to blackbird or spokesd as
// blackbird in particular relies on a lack of request timeout to provide
// backpressure during ingestion.
func RequestTimeout(timeout time.Duration) Config {
	return func(client *net_http.Client, _ *net_http.Transport, _ *net.Dialer) {
		client.Timeout = timeout
	}
}

// NewClient returns a new net/http.Client.
func NewClient(userAgent string, options ...Config) *net_http.Client {
	var httpTransport *net_http.Transport

	if tr, ok := net_http.DefaultTransport.(*net_http.Transport); ok {
		// NOTE: non-racy copy of http transport
		// https://groups.google.com/forum/#!topic/golang-nuts/JmpHoAd76aU
		// https://github.com/golang/go/issues/26013
		// https://go-review.googlesource.com/c/go/+/174597/5/src/net/http/transport.go#295
		httpTransport = tr.Clone()
	} else {
		panic("http.DefaultTransport is not (*http.Transport). net/http changed in stdlib.")
	}

	client := &net_http.Client{}

	// Matches the default settings of DefaultTransport
	dial := &net.Dialer{
		Timeout:   DefaultNetHTTPDialerTimeout,
		KeepAlive: DefaultNetHTTPDialerKeepAlive,
		DualStack: true,
	}

	httpTransport.DialContext = dial.DialContext
	httpTransport.MaxIdleConns = 2048
	httpTransport.MaxIdleConnsPerHost = 512
	httpTransport.IdleConnTimeout = 120 * time.Second
	httpTransport.TLSClientConfig.MinVersion = tls.VersionTLS12

	for _, opt := range options {
		opt(client, httpTransport, dial)
	}
	client.Transport = &uaTransport{rt: httpTransport, userAgent: userAgent}

	return client
}

// Default returns an HTTP client with reasonable settings.
func Default(ua string) *net_http.Client {
	return NewClient(
		ua,
		TLSHandshakeTimeout(defaultTLSTimeout),
		ConnectTimeout(defaultConnectTimeout),
	)
}
