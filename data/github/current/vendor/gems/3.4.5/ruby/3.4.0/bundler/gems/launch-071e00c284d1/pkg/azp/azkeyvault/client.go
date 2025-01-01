package azkeyvault

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

const (
	urlTemplate   = "https://%s.vault.azure.net/secrets/%s?api-version=7.0"
	keyCacheTTL   = 5 * time.Minute           // Cache for 5 minutes
	vaultResource = "https://vault.azure.net" //nolint
)

type Options struct {
	breaker  *circuit.Breaker
	cache    launchcache.S2SCache
	tokenSrc launchhttp.TokenSource
	hooks    *httpclient.ClientHooks
}

type Option func(*Options)

func WithCache(cache launchcache.S2SCache) Option {
	return func(o *Options) {
		o.cache = cache
	}
}

func WithBreaker(breaker *circuit.Breaker) Option {
	return func(o *Options) {
		o.breaker = breaker
	}
}

func WithTokenSource(tokenSrc launchhttp.TokenSource) Option {
	return func(o *Options) {
		o.tokenSrc = tokenSrc
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

func NewClient(
	http *httpclient.Client,
	options ...Option,
) *Client {

	defaultOptions := &Options{
		breaker:  nil,
		cache:    nil,
		tokenSrc: nil,
	}

	for _, option := range options {
		option(defaultOptions)
	}

	if defaultOptions.hooks != nil {
		http = http.WithHooks(defaultOptions.hooks)
	}

	http = http.WithPkgName("azure")
	http = http.WithSvcName("key-vault")
	return &Client{
		http:    http,
		options: defaultOptions,
	}
}

// GetSecret gets secrets from azure key vault
//
// Uses https://docs.microsoft.com/en-us/rest/api/keyvault/getsecret/getsecret
func (c *Client) GetSecret(ctx context.Context, vaultName, secretName string) (*azp.KeyVaultSecret, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "key-vault-secret" // TODO: rename to GetSecret

	var secret *azp.KeyVaultSecret

	doOptions := c.defaultOptions()
	if c.options.cache != nil {
		cache := c.options.cache.KeyVaultCacheFor(vaultName, secretName)
		doOptions = append(doOptions, []httpclient.DoOption{
			httpclient.WithCache(
				cacheSetterBuilder(cache),
				cacheGetterBuilder(cache),
			),
		}...)
	}

	err := c.http.Do(
		ctx,
		opname,
		http.MethodGet,
		getURL(vaultName, secretName),

		nil,
		&secret,
		doOptions...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return secret, nil
}

func cacheGetterBuilder(cache launchcache.KeyVaultCache) func(context.Context, any) (time.Time, bool, error) {
	return func(ctx context.Context, v any) (time.Time, bool, error) {
		ctx, span := tracing.Start(ctx)
		defer span.End()

		rawsecret, ok, err := cache.Get(ctx)

		if err != nil {
			return time.Time{}, false, tracing.RecordError(span, err)
		}

		if !ok {
			return time.Time{}, false, nil
		}

		err = json.Unmarshal(rawsecret, &v)
		if err != nil {
			return time.Time{}, false, tracing.RecordError(span, err)
		}

		return time.Time{}, true, nil
	}
}

func cacheSetterBuilder(cache launchcache.KeyVaultCache) func(context.Context, any) (bool, error) {
	return func(ctx context.Context, v any) (bool, error) {
		ctx, span := tracing.Start(ctx)
		defer span.End()

		dptr, ok := v.(**azp.KeyVaultSecret)
		secret := &dptr
		if !ok {
			return false, tracing.RecordError(span, errors.New("could not assert expected type"))
		}
		secretJSON, err := json.Marshal(secret)
		if err != nil {
			return false, tracing.RecordError(span, errors.Wrap(err, "marshaling token to json for Set"))
		}
		cerr := cache.Set(ctx, secretJSON, keyCacheTTL)
		if cerr != nil {
			return false, tracing.RecordError(span, errors.Wrap(cerr, "failed to write in cache"))
		}
		return true, nil
	}
}

func getURL(vaultName, secretName string) string {
	return fmt.Sprintf(urlTemplate, vaultName, secretName)
}

func (c *Client) defaultOptions(options ...httpclient.DoOption) []httpclient.DoOption {
	doOptions := []httpclient.DoOption{
		httpclient.WithRetries(nil),
		responseValidator(),
	}

	if c.options.tokenSrc != nil {
		doOptions = append(doOptions, httpclient.WithTokenAuth(c.options.tokenSrc))
	}

	if c.options.breaker != nil {
		doOptions = append(doOptions, httpclient.WithBreaker(c.options.breaker))
	}

	return append(doOptions, options...)
}

func responseValidator() httpclient.DoOption {
	return func(do *httpclient.DoOptions) {
		do.ResponseValidator = func(r *http.Response) (bool, error) {
			err := handleError(r)

			if err == nil {
				return false, nil
			}

			if r.StatusCode >= http.StatusBadRequest && r.StatusCode < http.StatusInternalServerError {
				return false, err
			}

			return true, err
		}
	}
}

func handleError(r *http.Response) error {
	if r.StatusCode < http.StatusOK || r.StatusCode >= http.StatusMultipleChoices {
		if r.Body != nil {
			var bytes []byte
			bytes, err := io.ReadAll(r.Body)
			if err != nil {
				return errors.Errorf("received non-success status code %v unable to read body", r.StatusCode)
			}
			defer r.Body.Close()
			return azperrors.NewErrorFromAZPResponse(bytes, r.StatusCode)
		}
		return errors.Errorf("received non-success status code %v body is nil", r.StatusCode)
	}
	return nil
}
