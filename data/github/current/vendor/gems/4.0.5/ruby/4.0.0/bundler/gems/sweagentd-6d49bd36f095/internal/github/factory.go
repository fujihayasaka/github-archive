package github

import (
	"context"
	_ "embed"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/ratelimits"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/shurcooL/githubv4"
	"github.com/twitchtv/twirp"
	"golang.org/x/oauth2"
)

// graphqlClientTimeout is the client-side timeout for GraphQL HTTP requests.
// The server-side timeout in github/github is 10s, so 15s gives enough headroom
// for the server to respond while still bounding requests that hang indefinitely.
const graphqlClientTimeout = 15 * time.Second

// ClientFactoryInterface defines the interface for creating GitHub API clients.
type ClientFactoryInterface interface {
	NewClientForUser(token string, userID uint64, app sweagentd.AgenticApp) ClientInterface
	NewClientForRepo(ctx context.Context, app sweagentd.AgenticApp, repo sweagentd.Repository) (ClientInterface, error)
	NewClientFromRepo(ctx context.Context, app sweagentd.AgenticApp, repoId, repoOwnerId int64) (ClientInterface, error)
	NewClientFromRepoName(ctx context.Context, app sweagentd.AgenticApp, repoName, ownerName string, userID uint64) (ClientInterface, error)
	InvalidateTokenForRepo(app sweagentd.AgenticApp, repoID, repoOwnerID int64)
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
	twirpClient                githubtwirp.ClientInterface
	refreshCoordinator         *tokenRefreshCoordinator
}

type ClientFactoryOption func(*ClientFactory)

func WithTokenCache(cache tokens.Cache) ClientFactoryOption {
	return func(cf *ClientFactory) {
		cf.tokenCache = cache
	}
}

// WithTwirpClient sets the Twirp client used for server-to-server token minting.
func WithTwirpClient(client githubtwirp.ClientInterface) ClientFactoryOption {
	return func(cf *ClientFactory) {
		cf.twirpClient = client
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
		refreshCoordinator:         newTokenRefreshCoordinator(),
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

// NewClientForRepo creates a new [Client] authenticated as the installation
// associated with the given owner ID, scoped to the given repo ID.
//
// The token is cached during the lifetime of the request, and will be reused by
// other clients created using the same repoId/repoOwnerId. The repoOwnerId is also
// used to keep track of installation rate limits across requests and asynchronous
// jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientForRepo(ctx context.Context, app sweagentd.AgenticApp, repo sweagentd.Repository) (ClientInterface, error) {
	target := sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), repo.GetOwnerID())

	return cf.newClientForRepo(ctx, target, app, repo)
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

	return cf.newClientFromRepo(ctx, target, app, repoID, repoOwnerID)
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

	return cf.newClientFromRepoName(ctx, target, app, repoName, ownerName)
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

// InvalidateTokenForRepo evicts the cached server-to-server token for the
// given app and repository. Call this when a 401 indicates the installation
// token has been revoked (e.g. after the app is uninstalled and reinstalled).
func (cf *ClientFactory) InvalidateTokenForRepo(app sweagentd.AgenticApp, repoID, repoOwnerID int64) {
	target := sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), repoOwnerID)
	tokens.InvalidateServerToServerTokenForRepo(target, repoID, repoOwnerID, cf.tokenCache)
}

// TODO (chuxel): Remove newClient once ff is rolled out to switch everything to newClientWithTokenRefresh
//
//nolint:funcorder // Helper method is placed near callers for readability
func (cf *ClientFactory) newClient(ctx context.Context, token string, target sweagentd.ClientTarget, app sweagentd.AgenticApp) ClientInterface {
	client := gg.NewClient(&http.Client{
		Transport: ClientTransport(
			http.DefaultTransport,
			cf.obsv,
			cf.limiter,
			target,
			"githubrest",
			githubAPIMetricTagsFn(cf.ffClient, target, apiTargetPublicREST),
		),
	})
	client.BaseURL = cf.baseURL
	client = client.WithAuthToken(token)

	internalClient := gg.NewClient(&http.Client{
		Transport: ClientTransport(
			http.DefaultTransport,
			cf.obsv,
			cf.limiter,
			target,
			"githubrest",
			githubAPIMetricTagsFn(cf.ffClient, target, apiTargetInternalREST),
		),
	})
	internalClient.BaseURL = cf.baseInternalURL
	internalClient = internalClient.WithAuthToken(token)

	src := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: token},
	)
	httpClient := oauth2.NewClient(ctx, src)
	httpClient.Timeout = graphqlClientTimeout
	// Apply the same round tripper to the GraphQL client
	transport2 := ClientTransport(
		httpClient.Transport,
		cf.obsv,
		cf.limiter,
		target,
		"graphql",
		githubAPIMetricTagsFn(cf.ffClient, target, apiTargetPublicGraphQL),
	)
	httpClient.Transport = transport2

	gqlclient := githubv4.NewEnterpriseClient(cf.graphqlURL(), httpClient)

	// Create internal GraphQL client with same transport but internal URL
	internalHttpClient := oauth2.NewClient(ctx, src)
	internalHttpClient.Timeout = graphqlClientTimeout
	internalHttpClient.Transport = ClientTransport(
		internalHttpClient.Transport,
		cf.obsv,
		cf.limiter,
		target,
		"graphql",
		githubAPIMetricTagsFn(cf.ffClient, target, apiTargetInternalGraphQL),
	)
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

// makeServerToServerTokenRefreshFunc returns a tokenRefreshFunc that invalidates the
// cached S2S token, re-mints a fresh one, and updates tokenSrc with the new
// value. It uses the factory's tokenRefreshCoordinator so that concurrent
// refreshes for the same cache key are deduplicated across all clients and
// transports.
//
//nolint:funcorder // Helper method is placed near callers for readability
func (cf *ClientFactory) makeServerToServerTokenRefreshFunc(target sweagentd.ClientTarget, app sweagentd.AgenticApp, repoID, repoOwnerID int64, tokenSrc *refreshableTokenSource) (tokenRefreshFunc, error) {
	if repoOwnerID == 0 {
		return nil, goerrors.Errorf("cannot create token refresh: zero repoOwnerID for repo %d", repoID)
	}
	cacheKey := tokens.GlobalCacheKeyForRepo(target, repoID, repoOwnerID)

	doRefresh := func(ctx context.Context) (string, error) {
		tokens.InvalidateServerToServerTokenForRepo(target, repoID, repoOwnerID, cf.tokenCache)
		return tokens.GetServerToServerTokenByRepoID(ctx, target, cf.twirpClient.SweagentdAPI(), app, repoID, repoOwnerID, cf.tokenCache)
	}

	return func(ctx context.Context) (string, error) {
		newToken, err := cf.refreshCoordinator.Refresh(ctx, cacheKey, doRefresh)
		if err != nil {
			return "", err
		}
		tokenSrc.Update(newToken)
		return newToken, nil
	}, nil
}

// newClientWithTokenRefresh creates a Client whose HTTP transports automatically
// retry once on HTTP 401 by calling refreshFn to mint a fresh token. This handles
// stale cached installation tokens (e.g., after a GitHub App reinstall) by cache key.
//
//nolint:funcorder // Helper method is placed near callers for readability
func (cf *ClientFactory) newClientWithTokenRefresh(ctx context.Context, token string, target sweagentd.ClientTarget, app sweagentd.AgenticApp, tokenSrc *refreshableTokenSource, refreshFn tokenRefreshFunc) ClientInterface {
	// REST (public)
	restTransport := &tokenRefreshTransport{
		base: ClientTransport(
			http.DefaultTransport, cf.obsv, cf.limiter, target,
			"githubrest", githubAPIMetricTagsFn(cf.ffClient, target, apiTargetPublicREST),
		),
		refreshToken: refreshFn,
		currentToken: tokenSrc.Current,
	}
	client := gg.NewClient(&http.Client{Transport: restTransport})
	client.BaseURL = cf.baseURL
	client = client.WithAuthToken(token)

	// REST (internal)
	internalRESTTransport := &tokenRefreshTransport{
		base: ClientTransport(
			http.DefaultTransport, cf.obsv, cf.limiter, target,
			"githubrest", githubAPIMetricTagsFn(cf.ffClient, target, apiTargetInternalREST),
		),
		refreshToken: refreshFn,
		currentToken: tokenSrc.Current,
	}
	internalClient := gg.NewClient(&http.Client{Transport: internalRESTTransport})
	internalClient.BaseURL = cf.baseInternalURL
	internalClient = internalClient.WithAuthToken(token)

	// GraphQL (public) - oauth2.Transport injects the token; on retry after
	// refresh, it reads the updated value from tokenSrc.
	gqlOAuthTransport := &oauth2.Transport{Source: tokenSrc, Base: http.DefaultTransport}
	httpClient := &http.Client{
		Transport: &tokenRefreshTransport{
			base: ClientTransport(
				gqlOAuthTransport, cf.obsv, cf.limiter, target,
				"graphql", githubAPIMetricTagsFn(cf.ffClient, target, apiTargetPublicGraphQL),
			),
			refreshToken: refreshFn,
		},
		Timeout: graphqlClientTimeout,
	}
	gqlclient := githubv4.NewEnterpriseClient(cf.graphqlURL(), httpClient)

	// GraphQL (internal)
	internalGqlOAuthTransport := &oauth2.Transport{Source: tokenSrc, Base: http.DefaultTransport}
	internalHTTPClient := &http.Client{
		Transport: &tokenRefreshTransport{
			base: ClientTransport(
				internalGqlOAuthTransport, cf.obsv, cf.limiter, target,
				"graphql", githubAPIMetricTagsFn(cf.ffClient, target, apiTargetInternalGraphQL),
			),
			refreshToken: refreshFn,
		},
		Timeout: graphqlClientTimeout,
	}
	internalGqlClient := githubv4.NewEnterpriseClient(cf.internalGraphqlURL(), internalHTTPClient)

	return &Client{
		target:                     target,
		client:                     client,
		internalClient:             internalClient,
		ffClient:                   cf.ffClient,
		limiter:                    cf.limiter,
		gqlclient:                  gqlclient,
		internalGqlClient:          internalGqlClient,
		token:                      token,
		tokenSource:                tokenSrc,
		obsv:                       cf.obsv,
		dynamicWorkflowsHmacSecret: cf.dynamicWorkflowsHmacSecret,
		environment:                cf.environment,
		app:                        app,
	}
}

//nolint:funcorder // Server-to-server helpers are grouped together for readability
func (cf *ClientFactory) newClientForRepo(ctx context.Context, target sweagentd.ClientTarget, app sweagentd.AgenticApp, repo sweagentd.Repository) (ClientInterface, error) {
	token, err := tokens.GetServerToServerTokenByRepo(ctx, target, cf.twirpClient.SweagentdAPI(), app, repo, cf.tokenCache)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) && twerr.Code() == twirp.NotFound {
			return nil, twirp.NotFoundError("repository not found")
		}
		return nil, goerrors.Errorf("failed to get server-to-server token by repo: %w", err)
	}
	if cf.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentClientTokenRefreshOn401, repo.GetRepositoryID()) {
		tokenSrc := newRefreshableTokenSource(token)
		refreshFn, err := cf.makeServerToServerTokenRefreshFunc(target, app, repo.GetRepositoryID(), repo.GetOwnerID(), tokenSrc)
		if err != nil {
			return nil, err
		}
		return cf.newClientWithTokenRefresh(ctx, token, target, app, tokenSrc, refreshFn), nil
	}
	return cf.newClient(ctx, token, target, app), nil
}

//nolint:funcorder // Server-to-server helpers are grouped together for readability
func (cf *ClientFactory) newClientFromRepo(ctx context.Context, target sweagentd.ClientTarget, app sweagentd.AgenticApp, repoID, repoOwnerID int64) (ClientInterface, error) {
	token, err := tokens.GetServerToServerTokenByRepoID(ctx, target, cf.twirpClient.SweagentdAPI(), app, repoID, repoOwnerID, cf.tokenCache)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) && twerr.Code() == twirp.NotFound {
			return nil, twirp.NotFoundError("repository not found")
		}
		return nil, goerrors.Errorf("failed to get server-to-server token by repo ID: %w", err)
	}
	if cf.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentClientTokenRefreshOn401, repoID) {
		tokenSrc := newRefreshableTokenSource(token)
		refreshFn, err := cf.makeServerToServerTokenRefreshFunc(target, app, repoID, repoOwnerID, tokenSrc)
		if err != nil {
			return nil, err
		}
		return cf.newClientWithTokenRefresh(ctx, token, target, app, tokenSrc, refreshFn), nil
	}
	return cf.newClient(ctx, token, target, app), nil
}

//nolint:funcorder // Server-to-server helpers are grouped together for readability
func (cf *ClientFactory) newClientFromRepoName(ctx context.Context, target sweagentd.ClientTarget, app sweagentd.AgenticApp, repoName, ownerName string) (ClientInterface, error) {
	// Resolve repo name to ID
	resolver := &repoResolver{client: cf.twirpClient}
	repo, err := resolver.GetRepoByName(ctx, ownerName, repoName)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) && twerr.Code() == twirp.NotFound {
			return nil, twirp.NotFoundError("repository not found")
		}
		return nil, goerrors.Errorf("failed to resolve repository %s/%s: %w", ownerName, repoName, err)
	}
	token, err := tokens.GetServerToServerTokenByRepoID(ctx, target, cf.twirpClient.SweagentdAPI(), app, repo.GetId(), repo.GetOwnerId(), cf.tokenCache)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) && twerr.Code() == twirp.NotFound {
			return nil, twirp.NotFoundError("repository not found")
		}
		return nil, goerrors.Errorf("failed to get server-to-server token by repo name: %w", err)
	}
	if cf.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentClientTokenRefreshOn401, repo.GetId()) {
		tokenSrc := newRefreshableTokenSource(token)
		refreshFn, err := cf.makeServerToServerTokenRefreshFunc(target, app, repo.GetId(), repo.GetOwnerId(), tokenSrc)
		if err != nil {
			return nil, err
		}
		return cf.newClientWithTokenRefresh(ctx, token, target, app, tokenSrc, refreshFn), nil
	}
	return cf.newClient(ctx, token, target, app), nil
}

// repoResolver adapts githubtwirp.ClientInterface to the tokens.repoResolver interface.
type repoResolver struct {
	client githubtwirp.ClientInterface
}

func (r *repoResolver) GetRepoByName(ctx context.Context, owner, name string) (*repositoriesTwirp.RepositoryListItem, error) {
	repo, err := r.client.GetRepoByName(ctx, owner, name)
	if err != nil {
		return nil, err
	}
	return repo, nil
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
	twirpClient githubtwirp.ClientInterface
}

type AltClientFactoryOption func(*AltClientFactory)

func WithTokenCacheAlt(cache tokens.Cache) AltClientFactoryOption {
	return func(cf *AltClientFactory) {
		cf.tokenCache = cache
	}
}

// WithTwirpClientAlt sets the Twirp client used for server-to-server token minting on AltClientFactory.
func WithTwirpClientAlt(client githubtwirp.ClientInterface) AltClientFactoryOption {
	return func(cf *AltClientFactory) {
		cf.twirpClient = client
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

	var target sweagentd.ClientTarget
	if ownerID != 0 && cf.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentCacheMintedTokensUsingOwnerID, repoID) {
		target = sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), ownerID)
	} else {
		target = sweagentd.ClientTargetForApp(app.AppID())
	}

	var token string
	var err error

	token, err = tokens.GetServerToServerTokenByRepoID(ctx, target, cf.twirpClient.SweagentdAPI(), app, repoID, ownerID, cf.tokenCache)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) && twerr.Code() == twirp.NotFound {
			return nil, twirp.NotFoundError("repository not found")
		}
		return nil, goerrors.Errorf("failed to get server-to-server token by repo ID: %w", err)
	}

	transport := TelemetryClientTransport(
		http.DefaultTransport,
		cf.obsv,
		githubAPIMetricTagsFn(cf.ffClient, target, apiTargetPublicREST),
	)
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
