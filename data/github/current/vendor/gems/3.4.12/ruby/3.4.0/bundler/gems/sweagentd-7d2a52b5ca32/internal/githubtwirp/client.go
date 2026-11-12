package githubtwirp

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	billingClient "github.com/github/billing-platform/clients/go/v1/go-client/client"
	coreTwirp "github.com/github/copilot-api/proto/twirp/core/v1"
	copilotLimiterTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/proxima"
	"github.com/github/sweagentd/internal/requestctx"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"

	"github.com/hashicorp/go-retryablehttp"
	"github.com/twitchtv/twirp"
)

type ClientInterface interface {
	UserDetailAPI() copilotUsersTwirp.CopilotUserDetailAPI
	SweagentdAPI() sweagentdTwirp.SweagentdAPI
	LimiterAPI() copilotLimiterTwirp.CopilotLimiterAPI
	AuthorizationAPI() coreTwirp.AuthorizationAPI
	RepositoriesAPI() repositoriesTwirp.RepositoriesAPI
	BillingClient() billingClient.ClientInterface

	GetRepoById(ctx context.Context, id int64) (*repositoriesTwirp.RepositoryListItem, error)
}

func NewClientFromConfig(obsv observability.Exporters, ffClient featureflags.Client, cfg *config.Config) (*Client, error) {
	twirp, err := NewClient(
		cfg.GitHubTwirpAPIURL,
		cfg.GitHubTwirpHMACKey,
		cfg.LimiterTwirpAPIURL,
		cfg.LimiterTwirpHMAC,
		cfg.LimiterTwirpRequestTimeoutMs,
		cfg.BillingClientURL,
		cfg.BillingClientHMACKey,
		obsv,
		ffClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create github twirp client: %w", err)
	}

	if cfg.IsDevelopment() {
		// This uses a mix of the real client and a noop limiter client.
		// We don't need the limiter service in development, so we use a noop limiter client.
		twirp.WithNoopLimiterAPI()
	}

	return twirp, nil
}

func NewClient(
	githubTwirpAPIURL,
	githubTwirpHMACKey,
	limiterTwirpAPIURL,
	limiterTwirpHMACKey string,
	limiterTimeoutMs int,
	billingClientURL,
	billingClientHMACKey string,
	obsv observability.Exporters,
	ffClient featureflags.Client,
) (*Client, error) {
	return NewClientWithTimeout(
		githubTwirpAPIURL,
		githubTwirpHMACKey,
		limiterTwirpAPIURL,
		limiterTwirpHMACKey,
		billingClientURL,
		billingClientHMACKey,
		obsv,
		ffClient,
		10*time.Second,
		limiterTimeoutMs)
}

func NewClientWithTimeout(
	githubTwirpAPIURL,
	githubTwirpHMACKey,
	limiterTwirpAPIURL,
	limiterTwirpHMACKey,
	billingClientURL,
	billingClientHMACKey string,
	obsv observability.Exporters,
	ffClient featureflags.Client,
	timeout time.Duration,
	limiterTimeoutMs int,
) (*Client, error) {
	c := retryablehttp.NewClient()
	c.HTTPClient = &http.Client{
		Timeout:   timeout,
		Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, "github-twirp"),
	}
	c.RetryMax = 3
	c.RetryWaitMax = timeout
	c.CheckRetry = isRetryableError

	githubTwirpClient, err := twirpAuth.NewRequestHMACSigner(githubTwirpHMACKey, c.StandardClient())
	if err != nil {
		return nil, fmt.Errorf("failed to create HMAC signer for github twirp client: %w", err)
	}

	ac := retryablehttp.NewClient()
	ac.HTTPClient = &http.Client{
		Timeout:   timeout,
		Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, "github-auth-twirp"),
	}
	ac.RetryMax = 3
	ac.RetryWaitMax = timeout
	ac.ErrorHandler = authErrorHandler
	ac.CheckRetry = isRetryableError
	githubAuthTwirpClient, err := twirpAuth.NewRequestHMACSigner(githubTwirpHMACKey, ac.StandardClient())
	if err != nil {
		return nil, fmt.Errorf("failed to create HMAC signer for github auth twirp client: %w", err)
	}

	cLimiter := retryablehttp.NewClient()
	cLimiter.HTTPClient = &http.Client{
		Timeout:   time.Duration(limiterTimeoutMs) * time.Millisecond,
		Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, obsv, "limiter-twirp"),
	}
	cLimiter.RetryMax = 3
	cLimiter.RetryWaitMax = time.Duration(limiterTimeoutMs) * time.Millisecond
	cLimiter.CheckRetry = isRetryableError

	limiterTwirpClient, err := twirpAuth.NewRequestHMACSigner(limiterTwirpHMACKey, cLimiter.StandardClient())
	if err != nil {
		return nil, fmt.Errorf("failed to create HMAC signer for limiter twirp client: %w", err)
	}

	clientHooks := &twirp.ClientHooks{
		RequestPrepared: func(ctx context.Context, req *http.Request) (context.Context, error) {
			slug := requestctx.TenantSlug(ctx)
			obsv.Logger.Info("tenant slug for twirp request", kvp.String("tenant_slug", slug))

			if slug != "" {
				req.Header.Set(requestctx.GitHubTenantHeader, slug)
				req.Header.Set(requestctx.GitHubTenantIDHeader, requestctx.TenantID(ctx))
			}

			req.Header.Set(headers.GLBVia, "true")
			requestid.Forward(req)

			// Replace <tenant> placeholder in URL with actual tenant ID from context
			if req.URL != nil {
				originalURL := req.URL.String()
				modifiedURL, err := proxima.ReplaceTenantPlaceholder(ctx, originalURL)
				if err != nil {
					return ctx, fmt.Errorf("failed to replace tenant placeholder in URL: %w", err)
				}

				if modifiedURL != originalURL {
					// Parse the modified URL and update the request
					if newURL, err := url.Parse(modifiedURL); err == nil {
						req.URL = newURL
						req.Host = newURL.Host // Update the Host header to match the new URL host to avoid HTTP/2 validation errors
					}
				}
			}

			return ctx, nil
		},
	}

	userDetailClient := copilotUsersTwirp.NewCopilotUserDetailAPIProtobufClient(githubTwirpAPIURL, githubTwirpClient, twirp.WithClientHooks(clientHooks))
	sweagentdClient := sweagentdTwirp.NewSweagentdAPIProtobufClient(githubTwirpAPIURL, githubTwirpClient, twirp.WithClientHooks(clientHooks))
	limiterClient := copilotLimiterTwirp.NewCopilotLimiterAPIProtobufClient(limiterTwirpAPIURL, limiterTwirpClient, twirp.WithClientHooks(clientHooks))

	billingClient, err := billingClient.NewClient(&billingClient.ClientConfig{
		URL:     billingClientURL,
		HMACKey: billingClientHMACKey,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create billing client: %w", err)
	}

	// Note: Request tweak in github/github here to allow calling
	// https://github.com/github/github/blob/f8b9ee7694a04a50cfe9dd719d4e3d2488041be5/app/api/internal/twirp/copilotapi/core/v1/authorization_api_handler.rb#L15
	authorizationClient := coreTwirp.NewAuthorizationAPIProtobufClient(githubTwirpAPIURL, githubAuthTwirpClient, twirp.WithClientHooks(clientHooks))
	repos := repositoriesTwirp.NewRepositoriesAPIProtobufClient(githubTwirpAPIURL, githubTwirpClient, twirp.WithClientHooks(clientHooks))

	return &Client{
		obsv:     obsv,
		ffClient: ffClient,

		userDetailAPI:    userDetailClient,
		sweagentdAPI:     sweagentdClient,
		limitersAPI:      limiterClient,
		authorizationAPI: authorizationClient,
		reposAPI:         repos,
		billingClient:    billingClient,
	}, nil
}

type Client struct {
	obsv     observability.Exporters
	ffClient featureflags.Client

	userDetailAPI    copilotUsersTwirp.CopilotUserDetailAPI
	sweagentdAPI     sweagentdTwirp.SweagentdAPI
	limitersAPI      copilotLimiterTwirp.CopilotLimiterAPI
	authorizationAPI coreTwirp.AuthorizationAPI
	reposAPI         repositoriesTwirp.RepositoriesAPI
	billingClient    billingClient.ClientInterface
}

func isRetryableError(ctx context.Context, resp *http.Response, err error) (bool, error) {
	retry, checkErr := retryablehttp.DefaultRetryPolicy(ctx, resp, err)
	if checkErr != nil {
		return false, checkErr
	}

	return retry, nil
}

func authErrorHandler(resp *http.Response, err error, numTries int) (*http.Response, error) {
	if resp != nil && resp.Body != nil {
		// Parse the twirp error that comes back to provide more context on auth related failures
		//  when they happen. But if this can't be parsed, return the checkErr as is instead.
		body, readErr := io.ReadAll(resp.Body)
		_ = resp.Body.Close() // Make sure the stream gets closed per https://pkg.go.dev/github.com/hashicorp/go-retryablehttp@v0.7.8#ErrorHanler
		if readErr == nil && len(body) > 0 {
			twirpErr := struct {
				Code    string `json:"code"`
				Message string `json:"msg"`
			}{}
			jsonErr := json.Unmarshal(body, &twirpErr)
			if jsonErr == nil {
				return resp, twirp.NewError(twirp.ErrorCode(twirpErr.Code), twirpErr.Message)
			}
		}
	}
	return resp, twirp.InternalError(fmt.Sprintf("authorization API failed after %d retries: %v", numTries, err))
}

// Ensure Client implements ClientInterface
var _ ClientInterface = &Client{}

func (c *Client) UserDetailAPI() copilotUsersTwirp.CopilotUserDetailAPI {
	return c.userDetailAPI
}

func (c *Client) SweagentdAPI() sweagentdTwirp.SweagentdAPI {
	return c.sweagentdAPI
}

func (c *Client) LimiterAPI() copilotLimiterTwirp.CopilotLimiterAPI {
	return c.limitersAPI
}

func (c *Client) RepositoriesAPI() repositoriesTwirp.RepositoriesAPI {
	return c.reposAPI
}

func (c *Client) BillingClient() billingClient.ClientInterface {
	return c.billingClient
}

func (c *Client) WithNoopLimiterAPI() {
	c.limitersAPI = &NoopLimiterAPI{}
}

func (c *Client) AuthorizationAPI() coreTwirp.AuthorizationAPI {
	return c.authorizationAPI
}
