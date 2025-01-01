package httpclient

import (
	"context"
	"io"
	"net/http"
	"time"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/pkg/launchhttp"
)

// DoOption provides a DoOptions instance that can be mutated in whatever way
// the called finds reasonable and helpful in getting their task done.
type DoOption func(*DoOptions)

// ResponseValidator receives the response if no error was returned by the http backend.
type ResponseValidator func(*http.Response) (retryable bool, err error)

// BodyBuilder is used to build the body of the request in situations where the body
// cannot be reused in between attempts.
type BodyBuilder func() (io.Reader, error)

// URLBuilder is used to build the url of the request in situations where the url
// cannot be reused in between attempts.
type URLBuilder func() (string, error)

// DoOptions are options provided to Client.Do and give us a way to keep the base client generalized while
// simulatenously allowing for variance when needed.
type DoOptions struct {
	WithRetries bool
	Breaker     *circuit.Breaker
	Hooks       *ClientHooks

	RetriesMax                              int
	RetriesRand, RetryMultiplier            float64
	RetryDelay, RetryTimeout, RetryMaxDelay time.Duration

	// ResponseValidator validates non-body related response metadata, such as http code
	ResponseValidator ResponseValidator

	// ResponseInspector evaluates is given the response and the dst. It may validate the dst for problems.
	ResponseInspector func(v any) (bool, error)

	// TokenSource provides a request with an authentication token
	TokenSource launchhttp.TokenSource

	CacheSetter func(context.Context, any) (bool, error)
	CacheGetter func(context.Context, any) (time.Time, bool, error)

	RequestOptions []launchhttp.RequestOption

	ReqErrorProcessor func(error) error
}

// WithRetries indicates that the request should be retried. There are more tunables besides the permanent error
// range that can be exposed if needed. Otherwise, this method relies on the defaults provided to the Client at
// creation time. These defaults should cover most cases since each Client endpoint likely communicates with the
// same service.
func WithRetries(validator ResponseValidator) DoOption {
	return func(do *DoOptions) {
		do.WithRetries = true
		do.ResponseValidator = validator
	}
}

func WithBackoff(retriesMax int, retryDelay time.Duration, retryMultiplier float64, retriesRand float64) DoOption {
	return func(do *DoOptions) {
		do.WithRetries = true
		do.RetriesMax = retriesMax
		do.RetryDelay = retryDelay
		do.RetryMultiplier = retryMultiplier
		do.RetriesRand = retriesRand
	}
}

// WithPollOutcome polls for some state in the response body. This is somewhat niche and only used by the tenant creation code so far.
func WithPollOutcome(startingDelay, maxDelay, timeout time.Duration, multiplier float64, inspector func(any) (bool, error)) DoOption {
	return func(do *DoOptions) {
		do.WithRetries = true
		do.RetryDelay = startingDelay
		do.RetryMaxDelay = maxDelay
		do.RetryTimeout = timeout
		do.RetryMultiplier = multiplier
		do.ResponseInspector = inspector
	}
}

// WithBreaker specifies that the request should add a breaker middleware to its middleware chain.
func WithBreaker(breaker *circuit.Breaker) DoOption {
	return func(do *DoOptions) {
		do.Breaker = breaker
	}
}

// WithValidator analyzes the response for errors
func WithValidator(rmv ResponseValidator) DoOption {
	return func(do *DoOptions) {
		do.ResponseValidator = rmv
	}
}

// WithCache adds a cache setter and getter function to the request lifecycle
func WithCache(setter func(context.Context, any) (bool, error), getter func(context.Context, any) (time.Time, bool, error)) DoOption {
	return func(do *DoOptions) {
		do.CacheSetter = setter
		do.CacheGetter = getter
	}
}

// WithTokenAuth handles requesting a token from some source to the request
func WithTokenAuth(tokensrc launchhttp.TokenSource) DoOption {
	return func(do *DoOptions) {
		do.TokenSource = tokensrc
	}
}

// WithRequestOptions adds a series of options that are called when building the http.Request
func WithRequestOptions(options ...launchhttp.RequestOption) DoOption {
	return func(do *DoOptions) {
		do.RequestOptions = append(do.RequestOptions, options...)
	}
}

// WithRequestErrorProcessor modifies an error returned by the http backend before response validation.
func WithRequestErrorProcessor(processor func(error) error) DoOption {
	return func(do *DoOptions) {
		do.ReqErrorProcessor = processor
	}
}
