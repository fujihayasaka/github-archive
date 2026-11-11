package github

import (
	"context"
	_ "embed"
	"net/http"
	"net/url"
	"strings"

	"github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/ratelimits"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/shurcooL/githubv4"
	"golang.org/x/oauth2"
)

// ClientFactoryInterface defines the interface for creating GitHub API clients.
type ClientFactoryInterface interface {
	NewClientForUser(token string, userID uint64, app sweagentd.AgenticApp) ClientInterface
	NewClientForRepo(ctx context.Context, app sweagentd.AgenticApp, repo sweagentd.Repository) (ClientInterface, error)
	NewClientFromRepo(ctx context.Context, app sweagentd.AgenticApp, repoId, repoOwnerId int64) (ClientInterface, error)
	NewClientFromRepoName(ctx context.Context, app sweagentd.AgenticApp, repoName, ownerName string, userID uint64) (ClientInterface, error)
}

// ClientFactory is a factory for creating GitHub clients, using
// the given base URL (ex: http://api.github.localhost, https://api.github.com).
type ClientFactory struct {
	baseURL                    *url.URL
	baseInternalURL            *url.URL
	dynamicWorkflowsHmacSecret string
	ffClient                   featureflags.Client
	limiter                    limiter.RateLimiter
	obsv                       observability.Exporters
	environment                config.Environment
	appProvider                *agenticapp.Provider
	tokenCache                 tokens.Cache
}

type ClientFactoryOption func(*ClientFactory)

func WithTokenCache(cache tokens.Cache) ClientFactoryOption {
	return func(cf *ClientFactory) {
		cf.tokenCache = cache
	}
}

// NewClientFactory returns a new ClientFactory.
func NewClientFactory(
	obsv observability.Exporters,
	ffClient featureflags.Client,
	limiter limiter.RateLimiter,
	baseURL,
	baseInternalURL string,
	dynamicWorkflowsHmacSecret string,
	environment config.Environment,
	appProvider *agenticapp.Provider,
	opts ...ClientFactoryOption,
) (*ClientFactory, error) {
	parsedURL, err := url.Parse(baseURL)
	if err != nil {
		return nil, err
	}
	if !strings.HasSuffix(parsedURL.Path, "/") {
		parsedURL.Path += "/"
	}

	parsedInternalURL := parsedURL
	if baseInternalURL != "" {
		parsedInternalURL, err = url.Parse(baseInternalURL)
		if err != nil {
			return nil, err
		}
	}

	if !strings.HasSuffix(parsedInternalURL.Path, "/") {
		parsedInternalURL.Path += "/"
	}

	s := &ClientFactory{
		baseURL:                    parsedURL,
		baseInternalURL:            parsedInternalURL,
		dynamicWorkflowsHmacSecret: dynamicWorkflowsHmacSecret,
		ffClient:                   ffClient,
		limiter:                    limiter,
		obsv:                       obsv,
		environment:                environment,
		appProvider:                appProvider,
		tokenCache:                 &tokens.NoopCache{},
	}

	for _, opt := range opts {
		opt(s)
	}

	return s, nil
}

// NewClientFactoryFromConfig creates a new ClientFactory from the provided configuration.
func NewClientFactoryFromConfig(
	obsv observability.Exporters,
	cfg *config.Config,
	ffClient featureflags.Client,
	limiter limiter.RateLimiter,
	appProvider *agenticapp.Provider,
	opts ...ClientFactoryOption,
) (*ClientFactory, error) {
	return NewClientFactory(
		obsv,
		ffClient,
		limiter,
		cfg.GitHubAPIURL,
		cfg.GitHubInternalAPIURL,
		cfg.DynamicWorkflowsHMACKey,
		cfg.Environment,
		appProvider,
		opts...,
	)
}

// NewAppClient returns a new [gg.Client] authenticated with a JWT for the app
func (cf *ClientFactory) NewAppClient(app sweagentd.AgenticApp) *gg.Client {
	atr := ghinstallation.NewAppsTransportFromPrivateKey(http.DefaultTransport, app.AppID(), app.PrivateKey())
	atr.BaseURL = cf.baseURL.String()

	target := sweagentd.ClientTargetForApp(app.AppID())

	transport := ClientTransport(atr, cf.obsv, cf.limiter, target, "github-app")
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseURL

	return client
}

// NewClientForRepo creates a new [Client] authenticated as the installation
// associated with the given owner ID, scoped to the given repo ID.
//
// The token is cached during the lifetime of the request, and will be reused by
// other clients created using the same repoId/repoOwnerId. The repoOwnerId is also
// used to keep track of installation rate limits across requests and asynchronous
// jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientForRepo(ctx context.Context, app sweagentd.AgenticApp, repo sweagentd.Repository) (ClientInterface, error) {
	target := sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), repo.GetOwnerID())
	useCache := cf.ffClient.IsEnabledForRepoOrOwner(ctx, featureflags.CopilotSWEAgentCacheMintedTokens, repo)
	resp, token, err := tokens.GetGlobalTokenByRepo(ctx, target, cf, app, repo, cf.tokenCache, useCache)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo ID")
	}

	return cf.newClient(ctx, token, target, app), nil
}

// NewClientFromRepo creates a new [Client] authenticated as the installation
// associated with the given owner ID, scoped to the given repo ID.
//
// The token is cached during the lifetime of the request, and will be reused by
// other clients created using the same repoID/repoOwnerID. The repoOwnerID is also
// used to keep track of installation rate limits across requests and asynchronous
// jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientFromRepo(ctx context.Context, app sweagentd.AgenticApp, repoID, repoOwnerID int64) (ClientInterface, error) {
	target := sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), repoOwnerID)
	useCache := cf.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentCacheMintedTokens, repoID)
	resp, token, err := tokens.GetGlobalTokenByRepoID(ctx, target, cf, app, repoID, repoOwnerID, cf.tokenCache, useCache)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo ID")
	}

	return cf.newClient(ctx, token, target, app), nil
}

// NewClientFromRepoName creates a new [Client] authenticated as the installation
// associated with the given owner, scoped to the givin repo.
//
// The token is cached during the lifetime of the request, and will be reused by
// other clients created using the same repoName/ownerName. The ownerName is also
// used to keep track of installation rate limits across requests and asynchronous
// jobs to prevent hitting rate limit errors.
//
// This method should be used when the owner and repo ID are not available. If
// the IDs are available, prefer using [NewClientFromRepo] to create the client.
func (cf *ClientFactory) NewClientFromRepoName(ctx context.Context, app sweagentd.AgenticApp, repoName, ownerName string, userID uint64) (ClientInterface, error) {
	target := sweagentd.ClientTargetForInstallationByOwnerName(app.AppID(), ownerName)
	useCache := cf.ffClient.IsEnabledForUser(ctx, featureflags.CopilotSWEAgentCacheMintedTokens, int64(userID))
	resp, token, err := tokens.GetGlobalTokenByRepoName(ctx, target, cf, app, repoName, ownerName, cf.tokenCache, useCache)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo name")
	}
	return cf.newClient(ctx, token, target, app), nil
}

// NewClientForUser creates a new [Client] authenticated with the given token.
// The token should be a user token.
//
// The userID is used to keep track of the user's rate limits across requests and
// asynchronous jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientForUser(token string, userID uint64, app sweagentd.AgenticApp) ClientInterface {
	// TODO(josebalius): This needs to be removed.
	if app == nil {
		app = cf.appProvider.CopilotApp()
	}
	target := sweagentd.ClientTargetForUser(app.AppID(), int64(userID))

	return cf.newClient(context.Background(), token, target, app)
}

//nolint:funcorder // Helper method is placed near callers for readability
func (cf *ClientFactory) newClient(ctx context.Context, token string, target sweagentd.ClientTarget, app sweagentd.AgenticApp) ClientInterface {
	transport := ClientTransport(http.DefaultTransport, cf.obsv, cf.limiter, target, "githubrest")
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseURL
	client = client.WithAuthToken(token)

	internalClient := gg.NewClient(&http.Client{Transport: transport})
	internalClient.BaseURL = cf.baseInternalURL
	internalClient = internalClient.WithAuthToken(token)

	src := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: token},
	)
	httpClient := oauth2.NewClient(ctx, src)
	// Apply the same round tripper to the GraphQL client
	transport2 := ClientTransport(httpClient.Transport, cf.obsv, cf.limiter, target, "graphql")
	httpClient.Transport = transport2

	gqlclient := githubv4.NewEnterpriseClient(cf.graphqlURL(), httpClient)

	// Create internal GraphQL client with same transport but internal URL
	internalHttpClient := oauth2.NewClient(ctx, src)
	internalHttpClient.Transport = ClientTransport(internalHttpClient.Transport, cf.obsv, cf.limiter, target, "graphql")
	internalGqlClient := githubv4.NewEnterpriseClient(cf.internalGraphqlURL(), internalHttpClient)

	return &Client{
		target:                     target,
		client:                     client,
		internalClient:             internalClient,
		ffClient:                   cf.ffClient,
		limiter:                    cf.limiter,
		gqlclient:                  gqlclient,
		internalGqlClient:          internalGqlClient,
		token:                      token,
		obsv:                       cf.obsv,
		dynamicWorkflowsHmacSecret: cf.dynamicWorkflowsHmacSecret,
		environment:                cf.environment,
		app:                        app,
	}
}

//nolint:funcorder // Helper method is placed near callers for readability
func (cf *ClientFactory) graphqlURL() string {
	return cf.baseURL.JoinPath("graphql").String()
}

//nolint:funcorder // Helper method is placed near callers for readability
func (cf *ClientFactory) internalGraphqlURL() string {
	return cf.baseInternalURL.JoinPath("graphql").String()
}

// AltClientFactory is a client factory for creating GitHub App [gg.Client]s using
// the only the [GitHubApp] information. It is used in rare cases where we need to
// create a one-off [Client] with a unique configuration, or to make a single request
// to the GitHub API (e.g. [AltClientFactory.RateLimitsForRepo]).
//
// Unless you have a very specific reason to use this factory, use [ClientFactory]
type AltClientFactory struct {
	appProvider *agenticapp.Provider
	obsv        observability.Exporters
	baseURL     *url.URL
	ffClient    featureflags.Client
	tokenCache  tokens.Cache
}

type AltClientFactoryOption func(*AltClientFactory)

func WithTokenCacheAlt(cache tokens.Cache) AltClientFactoryOption {
	return func(cf *AltClientFactory) {
		cf.tokenCache = cache
	}
}

// NewAltClientFactoryFromConfig creates a new [AltClientFactory] from the given
// [config.Config] object.
//
// Unless you have a very specific reason to use the [AltClientFactory], use
// [NewClientFactoryFromConfig] instead to create a [ClientFactory].
func NewAltClientFactoryFromConfig(obsv observability.Exporters, cfg *config.Config, ffClient featureflags.Client, opts ...AltClientFactoryOption) (*AltClientFactory, error) {
	parsedURL, err := url.Parse(cfg.GitHubAPIURL)
	if err != nil {
		return nil, err
	}
	if !strings.HasSuffix(parsedURL.Path, "/") {
		parsedURL.Path += "/"
	}

	s := &AltClientFactory{
		obsv:       obsv,
		baseURL:    parsedURL,
		ffClient:   ffClient,
		tokenCache: &tokens.NoopCache{},
	}

	for _, opt := range opts {
		opt(s)
	}

	return s, nil
}

// NewAppClient creates a new [gg.Client] using the GitHub App's private key.
// This client is used for making requests to the GitHub API as the app itself.
//
// The main difference between the client returned by this method and the client
// returned by [ClientFactory.NewAppClient] is that this one does not include
// the [ratelimits.RoundTripper].
func (cf *AltClientFactory) NewAppClient(app sweagentd.AgenticApp) *gg.Client {
	atr := ghinstallation.NewAppsTransportFromPrivateKey(http.DefaultTransport, app.AppID(), app.PrivateKey())
	atr.BaseURL = cf.baseURL.String()

	transport := TelemetryClientTransport(atr, cf.obsv)
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseURL

	return client
}

// RateLimitsForRepo retrieves the rate limits for a specific installation
// associated with the repo owner/org.
//
// This request is intended to be one-shot, so this method creates a single-use
// GitHub client to make the request. A couple of things to note:
//
//  1. The created client does not use the [ratelimits.RoundTripper]. This is
//     critical because [limiter.RateLimiter] calls this method to populate
//     its rate limit cache. [ratelimits.RoundTripper] will attempt to update
//     updates the same (locked) cache while processing the response, so using
//     the round tripper with this client would cause a deadlock.
//  2. This method uses [tokens.GetGlobalTokenByRepoID] which ensures the token
//     minted for the client is cached and reused by other clients created during
//     the request - including those created by [ClientFactory].
func (cf *AltClientFactory) RateLimitsForRepo(ctx context.Context, app sweagentd.AgenticApp, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	ctx, span := cf.obsv.Tracer.Start(ctx, "github.AltClientFactory.RateLimitsForRepo")
	defer span.End()

	target := sweagentd.ClientTargetForApp(app.AppID())
	useCache := cf.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentCacheMintedTokens, repoID)
	resp, token, err := tokens.GetGlobalTokenByRepoID(ctx, target, cf, app, repoID, ownerID, cf.tokenCache, useCache)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo ID")
	}

	transport := TelemetryClientTransport(http.DefaultTransport, cf.obsv)
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseURL
	client = client.WithAuthToken(token)

	rates, _, err := client.RateLimit.Get(ctx)
	if err != nil {
		return nil, goerrors.Errorf("failed to get rate limits: %w", err)
	}

	return ratelimits.ToLimiterRates(rates), nil
}

// BaseURL returns the base URL used by this factory to create clients.
// Implements [sweagentd.GitHubAPI].
func (cf *ClientFactory) BaseURL() *url.URL {
	return cf.baseURL
}

// BaseURL returns the base URL used by this factory to create clients.
// Implements [sweagentd.GitHubAPI].
func (cf *AltClientFactory) BaseURL() *url.URL {
	return cf.baseURL
}
