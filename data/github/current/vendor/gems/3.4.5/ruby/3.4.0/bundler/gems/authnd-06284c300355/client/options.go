package client

import (
	"net/http"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
)

// Option is a functional option type to control construction of the Authenticator client.
type Option func(*options) error

// options contains all the options we need to construct the Authenticator client.
type options struct {
	Statter           stats.Client
	HTTPClientOptions *httpClientOptions
	CustomHTTPClient  pb.HTTPClient
}

// defaultClientOptions represents the settings that will be used by default
// if no Options functions are supplied to the Authenticator client constructor.
func defaultClientOptions() *options {
	return &options{
		Statter:           stats.NullStatter,
		HTTPClientOptions: defaultHTTPClientOptions(),
		CustomHTTPClient:  nil,
	}
}

// applyOptions is a helper that updates the options reference
// in-place given an array of Option functions.
func applyOptions(options *options, opts ...Option) error {
	for _, opt := range opts {
		err := opt(options)
		if err != nil {
			return err
		}
	}
	return nil
}

// WithStatter adds a statter to report client stats to authnd (recommended).
// Note - if the statter was created with a prefix, the stats emitted from this middleware will contain that prefix.
// If at all possible, please try to avoid using a statter that contains a prefix.
func WithStatter(statter stats.Client) Option {
	return func(c *options) error {
		c.Statter = statter
		return nil
	}
}

// WithHMACKey appends the HMAC auth header to requests on the client.
// Each request generates a new HMAC using the provided HMAC Key.
// This option will not be applied if a custom HTTP client is used.
// HMACKey - HMAC secret key
func WithHMACKey(HMACKey string) Option {
	return func(c *options) error {
		c.HTTPClientOptions.HMACOptions = &hmacOptions{
			HMAC: HMACKey,
		}
		return nil
	}
}

// WithHMAC appends the HMAC auth header to requests on the client
// This option will not be applied if a custom HTTP client is used.
// HMAC - a HMAC that has already been generated from an HMAC key
func WithHMAC(HMAC string) Option {
	return func(c *options) error {
		c.HTTPClientOptions.HMACOptions = &hmacOptions{
			HMAC:  HMAC,
			IsRaw: true,
		}
		return nil
	}
}

// WithRetryMaxAttempts sets the max retry attempts that
// will be used in the default HTTP client.
// This option will not be applied if a custom HTTP client is used.
func WithRetryAttempts(retryAttempts int) Option {
	return func(c *options) error {
		if c.HTTPClientOptions.RetryOptions == nil {
			c.HTTPClientOptions.RetryOptions = new(retryOptions)
		}
		c.HTTPClientOptions.RetryOptions.Enabled = true
		c.HTTPClientOptions.RetryOptions.Attempts = retryAttempts
		return nil
	}
}

// WithoutRetries disables HTTP client retries on the default HTTP client.
// If using a custom HTTP client, this option is a no-op since
// retry logic is not applied on custom HTTP clients.
func WithoutRetries() Option {
	return func(c *options) error {
		if c.HTTPClientOptions.RetryOptions == nil {
			c.HTTPClientOptions.RetryOptions = new(retryOptions)
		}
		c.HTTPClientOptions.RetryOptions.Enabled = false
		return nil
	}
}

// WithoutRequestIDForwarder disables the forwarding of GitHub's request_id used for tracing a user request to
// github.com through each of the different services in the request lifecycle.
// If using a custom HTTP client, this option is a no-op since
// request ID forwarding is not applied on custom HTTP clients.
func WithoutRequestIDForwarder() Option {
	return func(c *options) error {
		c.HTTPClientOptions.DisableRequestIDForwarding = true
		return nil
	}
}

// WithCustomHTTPClient allows callers to override the default HTTP client.
// If provided, helpful HTTP client middleware (like HMAC Auth, retries, request ID forwarding, etc.) will not be applied.
// This includes middleware that sets the _required_ `Catalog-Service` HTTP header.
// If you use a custom HTTP client, you must ensure you set the `Catalog-Service` HTTP header yourself.
func WithCustomHTTPClient(client pb.HTTPClient) Option {
	return func(c *options) error {
		c.CustomHTTPClient = client
		return nil
	}
}

// WithRoundTripper is helpful if you'd like to pass a custom
// http.Transport such as the one that comes from OpenTelemetry
// using otelhttp.NewTransport and others. Note that the client
// containing such transport will still be wrapped by retries
// and header forwarders. See WithCustomHTTPClient if you'd like
// to override those defaults.
func WithRoundTripper(rt http.RoundTripper) Option {
	return func(c *options) error {
		c.HTTPClientOptions.RoundTripper = rt
		return nil
	}
}

// WithVerbose enables logging of HTTP responses. Should only be used for debugging and local
// testing. Should NEVER be used in production.
func WithVerboseRequestLogging() Option {
	return func(c *options) error {
		c.HTTPClientOptions.VerboseRequestLogging = true
		return nil
	}
}
