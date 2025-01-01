package httputil

import (
	"crypto/tls"
	"crypto/x509"
	"net"
	"net/http"
	"time"

	"github.com/pkg/errors"
)

// NewClient - compose a well-formed HTTP(S) client including
// specific config overrides provided by Options
func NewClient(defaultHeaders http.Header, opts ...Option) (*http.Client, error) {
	var transport *http.Transport
	if tr, ok := http.DefaultTransport.(*http.Transport); ok {
		// obtain non-racy copy of *http.Transport
		// https://groups.google.com/forum/#!topic/golang-nuts/JmpHoAd76aU
		// https://github.com/golang/go/issues/26013
		// https://go-review.googlesource.com/c/go/+/174597/5/src/net/http/transport.go#295
		transport = tr.Clone()
	} else {
		return nil, errors.Errorf("http.DefaultTransport is not of expected type: *http.Transport")
	}

	client := &http.Client{}
	dialer := &net.Dialer{}

	// apply caller's configuration overrides
	for _, opt := range opts {
		if err := opt(client, transport, dialer); err != nil {
			return nil, errors.Wrapf(err, "while configuring HTTP client")
		}
	}

	// assemble the *http.Client components for caller
	transport.DialContext = dialer.DialContext
	if len(defaultHeaders) > 0 {
		client.Transport = &roundTripperWithHeaders{defaultHeaders, transport}
	} else {
		client.Transport = transport
	}

	return client, nil
}

// Option - configuration function template. see also:
// https://dave.cheney.net/2014/10/17/functional-options-for-friendly-apis
// https://blog.cloudflare.com/the-complete-guide-to-golang-net-http-timeouts/
type Option = func(*http.Client, *http.Transport, *net.Dialer) error

// WithTLSFromEnv - configure TLS using PEM-encoded private key, certificate, and (optional) CA bundle.
// This method expects string arguments extracted from Moda (Vault) injected env vars.
//
// TODO: add variant as needed for configuring backing clients for services that expect to load the
// same from file paths, there isn't consensus on this pattern yet at for Moda services we might need
// to talk to.
func WithTLSFromEnv(keyPEM, certPEM, caBundlePEM string) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		if len(keyPEM) > 0 && len(certPEM) > 0 {
			cert, err := tls.X509KeyPair([]byte(certPEM), []byte(keyPEM))
			if err != nil {
				return errors.Wrapf(err, "failed to load x509 key and/or cert from PEM data")
			}
			transport.TLSClientConfig = &tls.Config{
				Certificates: []tls.Certificate{cert},
				MinVersion:   tls.VersionTLS12,
			}

			if len(caBundlePEM) > 0 {
				caCertPool, err := x509.SystemCertPool()
				if err != nil {
					return errors.Wrapf(err, "failed to obtain ref to CA cert pool")
				}

				caCertPool.AppendCertsFromPEM([]byte(caBundlePEM))
				transport.TLSClientConfig.RootCAs = caCertPool
			}

			return nil
		}

		return errors.New("required for TLS config: private key, certificate, (optional) CA bundle")
	}
}

// WithRequestTimeout - override client overall timeout
func WithRequestTimeout(timeout time.Duration) Option {
	return func(client *http.Client, _ *http.Transport, _ *net.Dialer) error {
		client.Timeout = timeout
		return nil
	}
}

// WithConnectTimeout - override dialer connection timeout
func WithConnectTimeout(timeout time.Duration) Option {
	return func(_ *http.Client, _ *http.Transport, dialer *net.Dialer) error {
		dialer.Timeout = timeout
		return nil
	}
}

// WithTLSHandshakeTimeout - like it says on the tin
func WithTLSHandshakeTimeout(timeout time.Duration) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.TLSHandshakeTimeout = timeout
		return nil
	}
}

// WithResponseHeaderTimeout - override timeout for reading response headers
func WithResponseHeaderTimeout(timeout time.Duration) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.ResponseHeaderTimeout = timeout
		return nil
	}
}

// WithCompression - override compression defaults on transport
func WithCompression(enabled bool) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.DisableCompression = !enabled
		return nil
	}
}

// WithKeepAlive - override dialer connection keep-alive
func WithKeepAlive(keepAlive time.Duration) Option {
	return func(_ *http.Client, _ *http.Transport, dialer *net.Dialer) error {
		dialer.KeepAlive = keepAlive
		return nil
	}
}

// WithIdleConnTimeout - override transport idle conns timeout
func WithIdleConnTimeout(timeout time.Duration) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.IdleConnTimeout = timeout
		return nil
	}
}

// WithMaxIdleConns - override transport idle conns cap
func WithMaxIdleConns(maxIdleConns int) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.MaxIdleConns = maxIdleConns
		return nil
	}
}

// WithMaxIdleConnsPerHost - override transport idle conns per-host cap
func WithMaxIdleConnsPerHost(maxIdleConnsPerHost int) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.MaxIdleConnsPerHost = maxIdleConnsPerHost
		return nil
	}
}

// WithMaxConnsPerHost - override transport conns per-host cap
func WithMaxConnsPerHost(maxConnsPerHost int) Option {
	return func(_ *http.Client, transport *http.Transport, _ *net.Dialer) error {
		transport.MaxConnsPerHost = maxConnsPerHost
		return nil
	}
}

// internal: roundTripperWithHeaders applies default headers to all outgoing HTTP requests.
// Meets the http.RoundTripper contract via delegation.
type roundTripperWithHeaders struct {
	headers http.Header
	http.RoundTripper
}

// RoundTrip adds the default headers to every outgoing request.
func (rtwh *roundTripperWithHeaders) RoundTrip(req *http.Request) (*http.Response, error) {
	if len(rtwh.headers) > 0 {
		for k, vs := range rtwh.headers {
			for _, v := range vs {
				req.Header.Add(k, v)
			}
		}
	}

	return rtwh.RoundTripper.RoundTrip(req)
}
