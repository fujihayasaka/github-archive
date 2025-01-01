package azpbearer

import (
	"context"
	"errors"
	"net/http"
	"time"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azpbearer/jwt"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type Options struct {
	breaker *circuit.Breaker
	cache   launchcache.AZPCache
	hooks   *httpclient.ClientHooks
}

type Option func(*Options)

func WithCache(cache launchcache.AZPCache) Option {
	return func(o *Options) {
		o.cache = cache
	}
}

func WithBreaker(breaker *circuit.Breaker) Option {
	return func(o *Options) {
		o.breaker = breaker
	}
}

func WithHooks(hooks *httpclient.ClientHooks) Option {
	return func(o *Options) {
		o.hooks = hooks
	}
}

type Client struct {
	http    *httpclient.Client
	options *Options
}

// New creates a client used to obtain bearer tokens.
func New(
	http *httpclient.Client,
	options ...Option,
) *Client {
	defaultOptions := &Options{
		breaker: nil,
		cache:   nil,
	}

	for _, option := range options {
		option(defaultOptions)
	}

	http = http.WithPkgName("azure")
	http = http.WithSvcName("bearer")

	if defaultOptions.hooks != nil {
		http = http.WithHooks(defaultOptions.hooks)
	}

	return &Client{
		http:    http,
		options: defaultOptions,
	}
}

type bearerTokenSource struct {
	jwtProvider jwt.Provider
	requestURL  string
	clientID    string
	resource    string
	getF        func(ctx context.Context, jwtProvider jwt.Provider, requestURL, clientID, resource string) (string, error)
}

func (bts *bearerTokenSource) Get(ctx context.Context) (string, error) {
	return bts.getF(ctx, bts.jwtProvider, bts.requestURL, bts.clientID, bts.resource)
}

func (c *Client) TokenSourceFor(jwtProvider jwt.Provider, requestURL, clientID, resource string) launchhttp.TokenSource {
	return &bearerTokenSource{
		jwtProvider: jwtProvider,
		requestURL:  requestURL,
		clientID:    clientID,
		resource:    resource,
		getF:        c.get,
	}
}

func (c *Client) get(ctx context.Context, jwtProvider jwt.Provider, requestURL, clientID, resource string) (string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	signed, err := jwtProvider.Provide(ctx, requestURL, clientID, resource)
	if err != nil {
		return "", tracing.RecordError(span, err)
	}

	body := []byte(signed)

	var token *azp.BearerToken
	doOptions := []httpclient.DoOption{
		httpclient.WithRequestErrorProcessor(azp.CleanRequestError),
		httpclient.WithRetries(azp.ResponseValidator()),
		httpclient.WithRequestOptions(
			launchhttp.WithContentType("application/x-www-form-urlencoded"),
			launchhttp.WithADNCorrelationHeaders(ctx),
		),
	}

	if c.options.cache != nil {
		doOptions = append(doOptions, []httpclient.DoOption{
			httpclient.WithCache(
				c.cacheSetterBuilder(requestURL, clientID, resource),
				c.cacheGetterBuilder(requestURL, clientID, resource)),
		}...)
	}

	if c.options.breaker != nil {
		doOptions = append(doOptions, httpclient.WithBreaker(c.options.breaker))
	}

	err = c.http.Do(
		ctx,
		"get",
		http.MethodPost,
		requestURL,
		body,
		&token,
		doOptions...,
	)
	if err != nil {
		return "", tracing.RecordError(span, err)
	}
	return token.AccessToken, nil
}

func (c *Client) cacheGetterBuilder(requestURL, clientID, resource string) func(context.Context, any) (time.Time, bool, error) {
	return func(ctx context.Context, v any) (time.Time, bool, error) {
		ctx, span := tracing.Start(ctx)
		defer span.End()

		cache := c.options.cache.BearerTokenCacheFor(requestURL, clientID, resource)

		t, exp, ok, err := cache.Get(ctx)

		if err != nil {
			return time.Time{}, false, tracing.RecordError(span, err)
		}

		if ok {
			dptr, ok := v.(**azp.BearerToken)
			if !ok {
				return time.Time{}, false, tracing.RecordError(span, errors.New("could not assert expected type"))
			}
			*dptr = &azp.BearerToken{AccessToken: string(t)}
			return exp, true, nil
		}

		return time.Time{}, false, nil
	}
}

func (c *Client) cacheSetterBuilder(requestURL, clientID, resource string) func(context.Context, any) (bool, error) {
	return func(ctx context.Context, v any) (bool, error) {
		ctx, span := tracing.Start(ctx)
		defer span.End()

		dptr, ok := v.(**azp.BearerToken)
		token := *dptr
		if !ok {
			return false, tracing.RecordError(span, errors.New("could not assert expected type"))
		}
		expiresIn, err := token.Expires()

		if err != nil {
			return false, tracing.RecordError(span, err)
		}

		if expiresIn > time.Minute {
			expiresIn -= time.Minute
		}

		cache := c.options.cache.BearerTokenCacheFor(requestURL, clientID, resource)

		err = cache.Set(ctx, []byte(token.AccessToken), expiresIn)

		if err != nil {
			return false, tracing.RecordError(span, err)
		}

		return true, nil
	}
}
