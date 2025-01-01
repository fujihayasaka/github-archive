// ghinternal provides access to our v3/internal APIs, via a interface composable with (*http.Client).Do,
// with:
// - stats - via the observability.* APIs
// - tracing - via mu
// - circuit breaking - via mu
//
// If you're using a http.Request object not created via on of the client's New...Request() methods,
// use RequestWithOpName on the request:
//
//	c := New(...)
//	req, _ := http.NewRequest("PATCH", fmt.Sprintf("%s/patch", url), strings.NewReader("hello"))
//	c.Do(RequestWithOpName(req, "some-name"))
package ghinternal

import (
	"context"
	"net/http"
	"net/url"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
)

type Client interface {
	GetAbuseDataForHydro(ctx context.Context, entityIDs []types.GlobalID) (*AbuseDataForHydro, error)
	ResolveAction(ctx context.Context, nwo string, version types.GitRef, workflowRunID int64, jobID string, repoID uint64) (*ResolvedAction, error)
	GetConnectToken(ctx context.Context) (*tokens.AccessToken, error)
}

type Options struct {
	hooks       *httpclient.ClientHooks
	requestOpts []launchhttp.RequestOption
	breaker     *circuit.Breaker
}

type Option func(*Options)

type ghclient struct {
	base       *url.URL
	httpClient *httpclient.Client
	obs        *observability.Observability

	requestOpts []launchhttp.RequestOption
	breaker     *circuit.Breaker
}

// WithRequestOptions will be run in ConfigureRequest
func WithRequestOptions(options ...launchhttp.RequestOption) Option {
	return func(o *Options) {
		o.requestOpts = append(o.requestOpts, options...)
	}
}

// WithClientHooks adds hooks that are called throughout the request lifecycle
func WithClientHooks(hooks *httpclient.ClientHooks) Option {
	return func(o *Options) {
		o.hooks = hooks
	}
}

// WithBreaker adds circuit breaking capabilities to the client
func WithBreaker(breaker *circuit.Breaker) Option {
	return func(o *Options) {
		o.breaker = breaker
	}
}

// New returns a configured client - see ClientOption and WithRequestOptions
func New(
	base *url.URL,
	httpClient *http.Client,
	obs *observability.Observability,
	options ...Option,
) *ghclient {

	defaults := &Options{}

	for _, opt := range options {
		opt(defaults)
	}

	h := httpclient.New(httpClient).WithPkgName("ghclient").WithSvcName("ghclient")

	if defaults.hooks != nil {
		h = h.WithHooks(defaults.hooks)
	}

	c := &ghclient{
		base:        base,
		obs:         obs,
		httpClient:  h,
		requestOpts: defaults.requestOpts,
		breaker:     defaults.breaker,
	}

	return c
}

type errChecker func(*http.Response) (bool, error)

// do attempts an operation once, and returns the *resp, error pair as per (*http.Client).do
func (c *ghclient) do(ctx context.Context, opName, method, relativePath string, payload, resp any, errCheck errChecker) error {
	ctx, span := tracing.StartWithOpFuncName(ctx, opName)
	defer span.End()

	reqURL, err := c.base.Parse(relativePath)
	if err != nil {
		return tracing.RecordError(span, err)
	}

	hdrs := map[string]string{
		"User-Agent": "launch-ghclient",
	}
	if payload != nil {
		hdrs["Content-Type"] = "application/json"
	}

	isMultiTenant := launchconfig.IsMultiTenant()

	reqOpts := []launchhttp.RequestOption{
		launchhttp.WithHeaders(hdrs),
		func(req *http.Request) error {
			err := ghtenant.ForwardGitHubTenant(req, isMultiTenant, c.obs.Logger)
			if err != nil {
				return tracing.RecordError(span, err)
			}
			return nil
		},
		func(req *http.Request) error {
			mu.ForwardRequestID(req)
			for _, opt := range c.requestOpts {
				if err := opt(req); err != nil {
					return tracing.RecordError(span, err)
				}
			}
			return nil
		},
	}
	rmv := func(res *http.Response) (retryable bool, err error) {
		if errCheck != nil {
			retryable, err = errCheck(res)
		}
		return retryable, err
	}

	doOpts := []httpclient.DoOption{
		httpclient.WithRequestOptions(reqOpts...),
		httpclient.WithRetries(rmv),
	}

	if c.breaker != nil {
		doOpts = append(doOpts, httpclient.WithBreaker(c.breaker))
	}

	err = c.httpClient.Do(
		ctx,
		opName,
		method,
		reqURL.String(),
		payload,
		resp,
		doOpts...,
	)
	if err != nil {
		return tracing.RecordError(span, err)
	}
	return err
}
