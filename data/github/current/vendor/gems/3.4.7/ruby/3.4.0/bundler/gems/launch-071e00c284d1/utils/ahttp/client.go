// ahttp was vendored from mu at v2.1.0
package ahttp

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/go-kvp"
	circuit "github.com/rubyist/circuitbreaker"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"

	"github.com/github/launch/observability/callcounter"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/mathutils"
	"github.com/github/launch/utils/timeutils"
)

// Client is a thin wrapper around an http.Client that includes a
// circuitbreaker. The provided client should be configured with the necessary
// timeouts and transport settings. Errors returned by the client requests count as
// a Fail for the breaker, as do 5xx responses.
type Client struct {
	Breaker         *circuit.Breaker
	Statter         statter.Statter
	BackoffStrategy BackoffStrategy
	RetryInterval   time.Duration
	Attempts        uint

	client      *http.Client
	serviceName string
}

// Allows the caller to provide a backoff strategy and http client.
// The http.Client instance should be created once and reused.
func NewClient(breaker *circuit.Breaker, statter statter.Statter, strategy BackoffStrategy, httpClient *http.Client, serviceName string) *Client {
	return &Client{
		Breaker:         breaker,
		Statter:         statter,
		BackoffStrategy: strategy,
		RetryInterval:   defaultRetryInterval,
		Attempts:        defaultAttempts,
		client:          httpClient,
		serviceName:     serviceName,
	}
}

var (
	// using unix-nano as seed because it doesn't need to be unpredictable, but also
	// we don't want all retries to synchronize because each process starts with the
	// same seed for the pseudo-random generator
	retryRand            = mathutils.NewSynchronizedRandProviderFromClock()
	defaultRetryInterval = time.Millisecond * 50
	defaultAttempts      = uint(3)
)

// DefaultBackoffStrategy uses a _randomized_ exponential backoff to mitigate thundering herd problems.
// - https://en.wikipedia.org/wiki/Thundering_herd_problem#Mitigation
// The jitter is set to 100% per:
// - https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
// REVIEW:  Consider migrating to github.com/cenkalti/backoff (or similar)
var DefaultBackoffStrategy = RandomizedExponentialBackoff(retryRand, 1)

// HandlerFunc allows a request to be processed pre-flight using Use(), Host(),
// or the verb + route based methods.
type HandlerFunc func(*http.Request)

// BackoffStrategy is used to determine how long a retry attempt should wait.
// The zeroBasedAttemptNumber is the number of attempts that have been made so far.
// (Pass 0 for the initial attempt.  Pass 1 for the first retry, etc.)
type BackoffStrategy func(zeroBasedAttemptNumber uint, baseDuration time.Duration) time.Duration

// RandomizedExponentialBackoff models a backoff that approximates the curve:
//
//	0 for n==0, otherwise [2^(n-1)]*d
//
// where d represents the baseDuration
//
//	n represents the zero-based attempt number
//	(Attempt 0 is the initial attempt.  Attempt 1 is the first retry, etc.)
//
// maxJitterScale is a mechanism for adding jitter to the otherwise natural exponential progression.
// It is expressed as value between [0.0, 1.0].
// Note that when you pass a value of 1.0 for maxJitterScale, you are implicitly
// accepting some small chance (for any given retry attempt) that the randomly computed jitter
// might either (a) double or (b) completely negate the natural exponential backoff.
//
// This phenomenon is illustrated in the right-most column of the table below.
//
//	Natural Exponential |                           maxJitterScale
//	Progression:        |   0.0 |       0.2      |       0.5       |     0.75        |     1.0
//	--------------------+-------+----------------+-----------------+-----------------+--------------
//	100ms               | 100ms | [ 80ms, 120ms) | [ 50ms,  150ms) | [ 25ms,  175ms) | [0ms,  200ms)
//	200ms               | 200ms | [160ms, 240ms) | [100ms,  300ms) | [ 50ms,  350ms) | [0ms,  400ms)
//	400ms               | 400ms | [320ms, 480ms) | [200ms,  600ms) | [100ms,  700ms) | [0ms,  800ms)
//	800ms               | 800ms | [640ms, 960ms) | [400ms, 1200ms) | [200ms, 1400ms) | [0ms, 1600ms)
//	                    |
func RandomizedExponentialBackoff(r *mathutils.SynchronizedRandProvider, maxJitterScale float64) BackoffStrategy {
	if maxJitterScale < 0 || maxJitterScale > 1 {
		panic("jitterRange not between 0 and 1")
	}

	// Note that attemptNumber is zero-based
	return func(attemptNumber uint, baseDuration time.Duration) time.Duration {
		if attemptNumber == 0 {
			// for the initial attempt (technically, not a retry), don't delay.
			return 0
		}

		// The basic formula for backoff with jitter is:
		// effectiveBackoff = naturalBackoff ± jitter

		// In this implementation, jitter is expressed as a ratio relative to the natural backoff.
		// The formula is as follows:
		//
		//  |                  | n == 0 | n > 0                                 |
		//  |------------------+--------+---------------------------------------|
		//  | naturalBackoff   |      0 | [2^(n-1)]*d                           |
		//  | effectiveBackoff |      0 | naturalBackoff + (j * naturalBackoff) |
		//
		// where d representes the base duration
		//       n represents the zero-based attempt number
		//       j is a randomly generated number in the range [-maxJitterScale, maxJitterScale)
		// and where maxJitterScale cannot exceed 1.0.

		// compute naturalBackoff as described above.
		// Recall that 1<<p is the bitwise expression of 2^p.
		// Note that attemptNumber >= 1 is guaranteed at this point.
		// [Reminder: (2^0) == (1 << 0) == 1]
		naturalBackoff := timeutils.ScaleDuration(1<<(attemptNumber-1), baseDuration)

		// compute the jitter scale factor, j, as described above.
		j := mathutils.RandomFloat64(r, -maxJitterScale, maxJitterScale)
		effectiveBackoff := naturalBackoff + timeutils.ScaleDuration(j, naturalBackoff)
		return effectiveBackoff
	}
}

// Do performs the http request, Failing the breaker when an error is returned
func (c *Client) Do(req *http.Request) (*http.Response, error) {
	if !c.breakerReady() {
		return nil, circuit.ErrBreakerOpen
	}

	ctx := req.Context()

	setSpanRequestID(ctx, req)

	// REVIEW:  if Client.Timeout is set, consider setting the request's Request-Timeout header
	// such that it does not exceed Client.Timeout.
	callcounter.ExternalCall(ctx, fmt.Sprintf("ahttp.%s", c.serviceName))

	res, err := c.client.Do(req)
	if err != nil || res.StatusCode >= 500 {
		c.breakerFail()
	} else {
		c.breakerSuccess()
	}

	c.logOutboundStats(ctx, 0)

	return res, err
}

// DoWithRetries performs the http request, retrying on errors
func (c *Client) DoWithRetries(req *http.Request) (*http.Response, error) {
	if !c.breakerReady() {
		return nil, circuit.ErrBreakerOpen
	}
	if c.BackoffStrategy == nil {
		c.BackoffStrategy = DefaultBackoffStrategy
	}
	if c.RetryInterval == 0 {
		c.RetryInterval = defaultRetryInterval
	}
	if c.Attempts == 0 {
		c.Attempts = defaultAttempts
	}

	ctx := req.Context()

	setSpanRequestID(ctx, req)

	// REVIEW:  if Client.Timeout is set, consider setting the request's Request-Timeout header
	// such that it does not exceed Client.Timeout.
	var res *http.Response
	var err error
	var buf *bytes.Reader

	if req.Body != nil {
		body, err := io.ReadAll(req.Body)
		if err != nil {
			return nil, err
		}

		buf = bytes.NewReader(body)
		req.Body = io.NopCloser(buf)
	}

	start := time.Now()
	for i := uint(0); i < c.Attempts; i++ {
		// We're retrying, so close it here
		if res != nil {
			res.Body.Close()
		}

		oteltrace.SpanFromContext(ctx).SetAttributes(
			// Note that it's correct to report ZERO retries during the initial attempt.
			attribute.Int64("http.request.resend_count", int64(i)),
		)

		callcounter.ExternalCall(ctx, fmt.Sprintf("ahttp-retries.%s", c.serviceName))

		res, err = c.client.Do(req)

		// If we're cancelled, don't retry any more
		select {
		case <-ctx.Done():
			c.breakerFail()
			return nil, context.Canceled
		default:
		}

		if err != nil || res.StatusCode >= 500 {
			c.breakerFail()

			if req.Body != nil {
				if _, err := buf.Seek(0, 0); err != nil {
					return res, err
				}
				req.Body = io.NopCloser(buf)
			}

			// Do we have room for another attempt?
			nextI := i + 1
			if nextI < c.Attempts {
				// The current attempt is complete.  Compute the backoff duration for the *next* attempt.
				time.Sleep(c.BackoffStrategy(nextI, c.RetryInterval))
			}
			continue
		}

		// Note that it's correct to report ZERO retries during the initial attempt.
		c.logOutboundStats(ctx, i)
		c.breakerSuccess()
		return res, err
	}

	// The above loop has several early returns (including early return on SUCCESS and early return on CANCELLED).
	// As a result, we can only reach this point if we've exhausted the maximum number of attempts permitted (c.Attempts).
	// Therefore, we can safely conclude that the number of *retries* is always one less than the number of attempts.
	retryCount := c.Attempts - 1
	c.logOutboundStats(ctx, retryCount)

	f := time.Since(start)

	if err != nil {
		return res, kvperrors.WrapWith(err, kvp.Uint("http.request.resend_count", retryCount), kvp.Duration("http.client.request.duration", f))
	}

	if res.StatusCode >= 500 {
		err = kvperrors.WrapWith(errMaxRetries, kvp.Uint("http.request.resend_count", retryCount), kvp.Duration("http.client.request.duration", f))
	}

	return res, err
}

func (c *Client) logOutboundStats(ctx context.Context, retryCount uint) { //nolint:staticcheck
	if c.Statter == nil {
		return
	}

	c.Statter.Counter(ctx, "outbound_http.retries", nil, int64(retryCount))
}

func (c *Client) breakerFail() {
	if c.Breaker != nil {
		c.Breaker.Fail()
	}
}

func (c *Client) breakerSuccess() {
	if c.Breaker != nil {
		c.Breaker.Success()
	}
}

func (c *Client) breakerReady() bool {
	if c.Breaker == nil {
		return true
	}
	return c.Breaker.Ready()
}

func setSpanRequestID(ctx context.Context, req *http.Request) {
	reqID := req.Header.Get("X-GitHub-Request-Id")
	if reqID == "" {
		return
	}

	oteltrace.SpanFromContext(ctx).SetAttributes(
		attribute.String("gh.request_id", reqID),
	)
}

var errMaxRetries = errors.New("maximum retries exceeded")
