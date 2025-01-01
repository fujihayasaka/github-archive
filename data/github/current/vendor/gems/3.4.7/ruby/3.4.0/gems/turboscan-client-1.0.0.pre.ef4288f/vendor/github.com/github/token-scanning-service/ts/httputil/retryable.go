package httputil

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/v2/middleware/headers"
	go_retry "github.com/hashicorp/go-retryablehttp"
)

// RetryableHttpClient is an interface for httputil.Client
//
//counterfeiter:generate -o ./fakes/fake_retryable_http_client.go . RetryableHttpClient
type RetryableHttpClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// BackoffStrategy specifys which high-level backoff implementation to bind to this retry client.
type BackoffStrategy string

const (
	// Exponential backoff strategy uses exponential backoff for retries. It is the default.
	Exponential BackoffStrategy = "exponential"
	// LinearJitter backoff strategy uses linear backoff with random jitter.
	LinearJitter BackoffStrategy = "linear_jitter"
)

// ErrorHandler provides a hook to customize error handling on HTTP response,
// for successful and failed attempts.
type ErrorHandler func(resp *http.Response, err error, attempt int) (*http.Response, error)

// Policy provides a hook to customize retriability decision based on HTTP
// response and attempt error. It returns bool for the decision, and an error if the
// decision can't be completed due to an error in the checks the function
// performs.
type Policy func(ctx context.Context, resp *http.Response, err error) (bool, error)

// RequestLogger provides a hook to customize logging per HTTP request attempt.
type RequestLogger func(logger log.Logger, req *http.Request, attempt int)

// ResponseLogger provides a hook to customize logging per HTTP response (successful and failed).
type ResponseLogger func(logger log.Logger, req *http.Response)

type shimLogger struct {
	Logger log.Logger
}

// Option setter
type Option func(*options) error

// opaque container for abstracted retry client parameters
type options struct {
	retryAttempts  *int
	minWait        time.Duration
	maxWait        time.Duration
	backoff        BackoffStrategy
	errorHandler   ErrorHandler
	retryPolicy    Policy
	requestLogger  RequestLogger
	responseLogger ResponseLogger
	logger         log.Logger
	httpClient     *http.Client
	hmacKey        *string
	userAgent      *string
}

// Client with Transparent retry wrapper for Twirp HTTPClient
type Client struct {
	client    *go_retry.Client
	secret    *string
	userAgent *string
}

// WithUserAgent returns an Option that sets the user agent for the http client
func WithUserAgent(userAgent string) Option {
	return func(opts *options) error {
		opts.userAgent = &userAgent
		return nil
	}
}

// WithAttempts returns an Option that sets the number of attempts, which must
// be > 0 and doesn't include the initial attempt.
func WithAttempts(retryAttempts int) Option {
	return func(opts *options) error {
		opts.retryAttempts = &retryAttempts
		return nil
	}
}

// WithInitialBackoff returns an Option that sets the backoff duration for initial the retry.
func WithInitialBackoff(minWait time.Duration) Option {
	return func(opts *options) error {
		opts.minWait = minWait
		return nil
	}
}

// WithMaxBackoff returns an Option that sets the maximum backoff cap for any retry.
func WithMaxBackoff(maxWait time.Duration) Option {
	return func(opts *options) error {
		opts.maxWait = maxWait
		return nil
	}
}

// WithBackoffStrategy returns an Option that sets the client's backoff strategy.
func WithBackoffStrategy(backoffStrategy BackoffStrategy) Option {
	return func(opts *options) error {
		opts.backoff = backoffStrategy
		return nil
	}
}

// WithErrorHandler returns an Option that sets the client's error handler.
func WithErrorHandler(errorHandler ErrorHandler) Option {
	return func(opts *options) error {
		opts.errorHandler = errorHandler
		return nil
	}
}

// WithRetryPolicy returns an option that sets the
func WithRetryPolicy(retryPolicy Policy) Option {
	return func(opts *options) error {
		opts.retryPolicy = retryPolicy
		return nil
	}
}

// WithLogger returns an Option that sets the logger.
func WithLogger(logger log.Logger) Option {
	return func(opts *options) error {
		opts.logger = logger
		return nil
	}
}

// WithRequestLogging returns an Option that sets the RequestLogger.
func WithRequestLogging(fn RequestLogger) Option {
	return func(opts *options) error {
		opts.requestLogger = fn
		return nil
	}
}

// WithResponseLogging returns an Option that sets the ResponseLogger.
func WithResponseLogging(fn ResponseLogger) Option {
	return func(opts *options) error {
		opts.responseLogger = fn
		return nil
	}
}

// WithHTTPClient returns an Option that sets the http.Client to use for the retrier.
func WithHTTPClient(httpClient *http.Client) Option {
	return func(opts *options) error {
		opts.httpClient = httpClient
		return nil
	}
}

// WithHMACKey returns an Option that sets a key to be used for adding request HMAC headers.
func WithHMACKey(secret *string) Option {
	return func(opts *options) error {
		opts.hmacKey = secret
		return nil
	}
}

// Meets go_retry.LeveledLogger contracts
func shimLeveledLogger(in log.Logger) go_retry.LeveledLogger {
	return &shimLogger{in}
}

func (sl *shimLogger) Fields(keysAndValues []interface{}) []kvp.Field {
	fields := []kvp.Field{}

	for i := 0; i < len(keysAndValues); i += 2 {
		fields = append(fields, kvp.Any(keysAndValues[i].(string), keysAndValues[i+1]))
	}

	return fields
}

func (sl *shimLogger) Info(msg string, keysAndValues ...interface{}) {
	sl.Logger.Info(msg, sl.Fields(keysAndValues)...)
}

func (sl *shimLogger) Debug(msg string, keysAndValues ...interface{}) {
	sl.Logger.Debug(msg, sl.Fields(keysAndValues)...)
}

func (sl *shimLogger) Warn(msg string, keysAndValues ...interface{}) {
	sl.Logger.Error(msg, sl.Fields(keysAndValues)...)
}

func (sl *shimLogger) Error(msg string, keysAndValues ...interface{}) {
	sl.Logger.Error(msg, sl.Fields(keysAndValues)...)
}

// NewHttpClient creates Twirp-compatible HTTPClient automating retries
//
// Usage:
//
// httpClient, err := retry.New(
//
//	WithAttempts(3),
//	WithBackoff(Exponential),
//	...more configs...
//
// )
// if err != nil { ... }
//
// client, err := awesome.MyTwirpProtobufClient(config.URL, httpClient)
func NewHTTPClient(opts ...Option) (*Client, error) {
	builder := options{}

	for _, opt := range opts {
		if err := opt(&builder); err != nil {
			return nil, err
		}
	}

	client, err := applyOptions(go_retry.NewClient(), &builder)

	return &Client{client, builder.hmacKey, builder.userAgent}, err
}

// ExponentialWithJitter HTTP retry strategy. Make exponential attempts, but with a maximum backoff of 30 seconds.
// Apply some initial jitter to prevent thunderring herd.
func ExponentialWithJitter(attempts int) (*Client, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(2*1000))
	if err != nil {
		fmt.Println("error:", err)
		return nil, err
	}
	jitter := time.Duration(n.Int64())

	return NewHTTPClient(
		WithAttempts(attempts),
		WithBackoffStrategy(Exponential),
		WithInitialBackoff(jitter*time.Millisecond),
		WithMaxBackoff(30*time.Second),
	)
}

// Default default HTTP retry strategy. Tries hard before giving up.
func Default() (*Client, error) {
	return ExponentialWithJitter(10)
}

// Implements Twirp's HTTPClient contract

func (c *Client) Do(req *http.Request) (*http.Response, error) {
	// requests passed to client.Do(req) must be wrapped for retry handling
	wrapped, err := go_retry.FromRequest(req)
	if err != nil {
		return nil, fmt.Errorf("failed to wrap *http.Request in retry handler: %s", err)
	}

	if c.secret != nil {
		wrapped.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(*c.secret).String())
	}

	if c.userAgent != nil {
		wrapped.Header.Add("User-Agent", *c.userAgent)
	}

	return c.client.Do(wrapped)
}

// apply configuration from abstracted attributes
func applyOptions(client *go_retry.Client, opts *options) (*go_retry.Client, error) {
	if opts.retryAttempts != nil {
		client.RetryMax = *opts.retryAttempts
	}

	if opts.minWait != time.Duration(0) {
		client.RetryWaitMin = opts.minWait
	}

	if opts.maxWait != time.Duration(0) {
		client.RetryWaitMax = opts.maxWait
	}

	if len(opts.backoff) > 0 {
		switch opts.backoff {
		case LinearJitter:
			client.Backoff = go_retry.LinearJitterBackoff

		case Exponential:
			client.Backoff = go_retry.DefaultBackoff

		default:
			return nil, fmt.Errorf("specified backoff is not valid: %s", opts.backoff)
		}
	}

	if opts.logger != nil {
		client.Logger = shimLeveledLogger(opts.logger)
	}

	if opts.requestLogger != nil {
		client.RequestLogHook =
			func(leveledLogger go_retry.Logger, req *http.Request, attempts int) {
				opts.requestLogger(opts.logger, req, attempts)
			}
	}

	if opts.responseLogger != nil {
		client.ResponseLogHook = func(leveledLogger go_retry.Logger, resp *http.Response) {
			opts.responseLogger(opts.logger, resp)
		}
	}

	if opts.errorHandler != nil {
		client.ErrorHandler = go_retry.ErrorHandler(opts.errorHandler)
	}

	if opts.retryPolicy != nil {
		client.CheckRetry = go_retry.CheckRetry(opts.retryPolicy)
	}

	if opts.httpClient != nil {
		client.HTTPClient = opts.httpClient
	}

	return client, nil
}
