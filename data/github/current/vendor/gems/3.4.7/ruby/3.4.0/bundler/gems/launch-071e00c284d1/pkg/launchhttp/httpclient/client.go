package httpclient

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchhttp"
)

// ClientOptions are the options that relate to request execution. They do not modify the request itself.
type ClientOptions struct {
	ReqRetryDelay      time.Duration
	ReqRetryMultiplier float64
	ReqRetryRandFactor float64
	ReqMaxRetries      int
	Hooks              *ClientHooks
	DefaultDoOptions   []DoOption
}

// Client is an modular wrapper around the underlying HTTP client.
type Client struct {
	backend launchhttp.Client
	svcname string
	pkgname string
	options *ClientOptions
}

// ClientOption is an option that relates to request execution. It does not modify the request itself.
type ClientOption func(*ClientOptions)

// WithDefaultDoOptions takes a slice of DoOptions and applies them to all requests serviced by the Client.
func WithDefaultDoOptions(options []DoOption) ClientOption {
	return func(o *ClientOptions) {
		o.DefaultDoOptions = options
	}
}

// WithRetryDelay sets the delay between retries.
func WithRetryDelay(duration time.Duration) ClientOption {
	return func(o *ClientOptions) {
		o.ReqRetryDelay = duration
	}
}

// New wraps the provided HTTP backend with the provided options.
func New(
	backend launchhttp.Client,
	options ...ClientOption,
) *Client {

	defaultOptions := &ClientOptions{
		ReqRetryDelay:      1500 * time.Millisecond,
		ReqRetryMultiplier: 2.0,
		ReqRetryRandFactor: 0.5,
		ReqMaxRetries:      3,
		Hooks:              NewClientHooks(),
		DefaultDoOptions:   nil,
	}

	for _, opt := range options {
		opt(defaultOptions)
	}

	return &Client{
		backend: backend,
		svcname: "",
		pkgname: "",
		options: defaultOptions,
	}
}

// WithSvcName sets the service name for the client.
func (c *Client) WithSvcName(name string) *Client {
	return &Client{
		// changes
		svcname: name,
		// same
		backend: c.backend,
		pkgname: c.pkgname,
		options: c.options,
	}
}

// WithPkgName sets the package name for the client.
func (c *Client) WithPkgName(name string) *Client {
	return &Client{
		// changes
		pkgname: name,
		// same
		backend: c.backend,
		svcname: c.svcname,
		options: c.options,
	}
}

// WithHooks sets the hooks for the client.
func (c *Client) WithHooks(hooks *ClientHooks) *Client {
	newOptions := c.options
	// changes
	newOptions.Hooks = hooks
	return &Client{
		// same
		backend: c.backend,
		svcname: c.svcname,
		pkgname: c.pkgname,
		options: newOptions,
	}
}

// Do executes an http request returning an error on failure.
//
// opname is the friendly name of the operation.
//
// method is the HTTP method to use.
//
// url is the URL to use.
//
// body is the body to use. The client can handle json, []byte, io.Reader, *bytes.Buffer, or a BodyBuilder.
//
// dst is a pointer to some struct that conforms to the response body. If nil the body is not evaluated.
//
// opts are used to augment the request execution behavior. E.g. retries, breakers, polling, and response validation.
func (c *Client) Do(ctx context.Context, opname string, method string, url string, body any, dst any, opts ...DoOption) (err error) {
	urlBuilder := func() (string, error) {
		return url, nil
	}
	return c.DoWithURLBuilder(ctx, opname, method, urlBuilder, body, dst, opts...)
}

func (c *Client) DoWithURLBuilder(ctx context.Context, opname string, method string, ub URLBuilder, body, dst any, opts ...DoOption) (err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	hc := c.options.Hooks.OnBeginRPC(ctx, c.svcname, c.pkgname, opname)
	defer c.options.Hooks.OnEndRPC(ctx, hc)

	options := &DoOptions{
		WithRetries:       false,
		RetriesMax:        c.options.ReqMaxRetries,
		RetriesRand:       c.options.ReqRetryRandFactor,
		RetryMultiplier:   c.options.ReqRetryMultiplier,
		RetryDelay:        c.options.ReqRetryDelay,
		ResponseInspector: defaultInspector,
		ReqErrorProcessor: defaultReqErrorProcessor,
		Hooks:             NewClientHooks(),
		TokenSource:       nil,
	}
	options.ResponseValidator = DefaultValidator()

	for _, opt := range c.options.DefaultDoOptions {
		opt(options)
	}

	for _, opt := range opts {
		opt(options)
	}

	if options.CacheGetter != nil {
		options.Hooks.OnBeginCacheGet(ctx, hc)
		_, hc.CacheGetHit, hc.CacheGetErr = options.CacheGetter(ctx, dst)
		options.Hooks.OnEndCacheGet(ctx, hc)
		if hc.CacheGetHit {
			return nil
		}
	}

	if options.TokenSource != nil {
		token, err := options.TokenSource.Get(ctx)
		if err != nil {
			return tracing.RecordError(span, err)
		}
		options.RequestOptions = append(options.RequestOptions, launchhttp.WithBearerToken(token))
	}

	err = c.doAttempt(ctx, options, ub, method, body, dst, hc)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	if options.CacheSetter != nil {
		options.Hooks.OnBeginCacheSet(ctx, hc)
		hc.CacheSetHit, hc.CacheSetErr = options.CacheSetter(ctx, dst)
		options.Hooks.OnEndCacheSet(ctx, hc)
	}

	return nil
}

// operation represents a single request attempt.
type operation func(context.Context, *http.Request, any, int, *HookContext) (*http.Response, error)

// preaperOperation is used to create the operation with the provided options.
func (c *Client) prepareOperation(options *DoOptions) operation {
	return func(ctx context.Context, req *http.Request, dst any, attempt int, hc *HookContext) (*http.Response, error) {
		ctx, span := tracing.StartWithOpFuncName(ctx, fmt.Sprintf("operation-attempt-%d", attempt))
		defer span.End()

		select {
		case <-ctx.Done():
			return nil, tracing.RecordError(span, backoff.Permanent(ctx.Err()))
		default:
		}
		hc.Error = nil // clear previous error

		// Request Phase
		c.options.Hooks.OnStartPerformRequest(ctx, attempt, req, hc)
		resp, reqErr := c.backend.Do(req)
		c.options.Hooks.OnDonePerformRequest(ctx, reqErr, hc)
		if reqErr != nil {
			reqErr = options.ReqErrorProcessor(reqErr)
			hc.Error = reqErr
			return nil, tracing.RecordError(span, reqErr)
		}

		// Response Phase
		var (
			retryable bool
			respErr   error
		)
		c.options.Hooks.OnStartHandleResponse(ctx, resp, hc)
		defer c.options.Hooks.OnDoneHandleResponse(ctx, hc)
		retryable, respErr = options.ResponseValidator(resp) // used to determine if the response is an error response
		if respErr != nil {
			hc.Error = respErr
			if !retryable {
				respErr = backoff.Permanent(respErr)
			}
			return nil, tracing.RecordError(span, respErr)
		}

		if dst != nil {
			if resp.Body == nil {
				hc.Error = fmt.Errorf("found nil body when unmarshaling response")
				return nil, tracing.RecordError(span, hc.Error)
			}
			body, readErr := io.ReadAll(resp.Body)
			if readErr != nil {
				hc.Error = readErr
				return nil, tracing.RecordError(span, readErr)
			}
			respErr = json.Unmarshal(body, &dst)
			if respErr != nil {
				return nil, tracing.RecordError(span, respErr)
			}
		}
		ok, respErr := options.ResponseInspector(dst) // used for polling operations
		if respErr != nil || !ok {
			return nil, tracing.RecordError(span, respErr)
		}

		return resp, nil
	}
}

// doAttempt builds the attempter which attempt once or more depending on the provided DoOptions.
func (c *Client) doAttempt(ctx context.Context, options *DoOptions, ub URLBuilder, method string, body, dst any, hc *HookContext) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	attempt := 0

	var b backoff.BackOff
	if options.WithRetries {
		// build our backoff provider
		delay := backoff.NewExponentialBackOff()
		delay.InitialInterval = options.RetryDelay
		delay.Multiplier = options.RetryMultiplier
		delay.RandomizationFactor = options.RetriesRand
		b = backoff.WithMaxRetries(delay, uint64(options.RetriesMax))
	} else {
		b = &backoff.StopBackOff{}
	}
	b = backoff.WithContext(b, ctx)

	// If body is not a BodyBuilder, we need to wrap it up like one!
	var bodyBuilder BodyBuilder
	switch b := body.(type) {
	case []byte:
		bodyBuilder = func() (io.Reader, error) {
			r := bytes.NewReader(b)
			return r, nil
		}
	case *bytes.Buffer:
		bb := b.Bytes()
		bodyBuilder = func() (io.Reader, error) {
			r := bytes.NewReader(bb)
			return r, nil
		}
	case io.Reader:
		bb, err := io.ReadAll(b)
		if err != nil {
			return tracing.RecordError(span, errors.Wrap(err, "reading io.Reader body"))
		}
		bodyBuilder = func() (io.Reader, error) {
			r := bytes.NewReader(bb)
			return r, nil
		}
	case BodyBuilder:
		bodyBuilder = b
	default:
		if b != nil {
			bb, err := json.Marshal(b)
			if err != nil {
				return tracing.RecordError(span, errors.Wrap(err, "marshaling body"))
			}
			bodyBuilder = func() (io.Reader, error) {
				r := bytes.NewReader(bb)
				return r, nil
			}
		} else {
			bodyBuilder = func() (io.Reader, error) {
				return nil, nil
			}
		}
	}

	var reqOpts []launchhttp.RequestOption
	if options.RequestOptions != nil {
		reqOpts = append(reqOpts, options.RequestOptions...)
	}

	// build our with retries attempter
	// wrap our logic per-attempt logic in the correct function type
	operation := func() error {
		ctx, span := tracing.StartWithOpFuncName(ctx, "attempter")
		defer span.End()

		mwchain := applyMiddleware(ctx, dst, attempt, c.prepareOperation(options), options, hc)
		req, err := buildRequest(ctx, method, ub, bodyBuilder, reqOpts...)
		if err != nil {
			return tracing.RecordError(span, errors.Wrap(err, "building request"))
		}
		_, err = mwchain.Do(req)
		return tracing.RecordError(span, err)
	}

	// Start doing the thing
	err := backoff.RetryNotify(operation, b, func(_ error, _ time.Duration) {
		attempt++
	})
	if perr, ok := err.(*backoff.PermanentError); ok {
		err = perr.Unwrap() // unwrap it
	}
	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

// DefaultValidator is the default response validator and can be overridden if needed.
func DefaultValidator() ResponseValidator {
	return func(resp *http.Response) (retryable bool, err error) {
		switch resp.StatusCode / 100 {
		case 1, 2, 3:
			return false, nil
		case 4:
			return false, fmt.Errorf("response code error %d", resp.StatusCode)
		case 5:
			return true, fmt.Errorf("response code error %d", resp.StatusCode)
		default:
			return false, fmt.Errorf("unknown response code error %d", resp.StatusCode)
		}
	}
}

// defaultInspector is the default request inspector, needed to enable success polling operations.
// By default it does nothing.
func defaultInspector(_ any) (bool, error) { return true, nil }

// defaultReqErrorProcessor is the default request error processor. It does nothing.
func defaultReqErrorProcessor(err error) error {
	return err
}

// buildRequest builds an http.Request from the provided method, url, body and request options.
func buildRequest(ctx context.Context, method string, ub URLBuilder, bb BodyBuilder, options ...launchhttp.RequestOption) (*http.Request, error) {
	url, err := ub()
	if err != nil {
		return nil, errors.Wrap(err, "building url")
	}

	body, err := bb()
	if err != nil {
		return nil, errors.Wrap(err, "building body")
	}

	req, err := http.NewRequestWithContext(ctx, method, url, body)
	if err != nil {
		return nil, errors.Wrap(err, "building request with context")
	}

	for _, option := range options {
		err = option(req)
		if err != nil {
			return nil, errors.Wrap(err, "applying request options")
		}
	}

	return req, err
}
