package github

import (
	"context"
	_ "embed"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github/ratelimits"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
	"github.com/shurcooL/githubv4"
	"golang.org/x/oauth2"
)

type ClientFactoryInterface interface {
	CopilotUserChecker
	AppID() int64
	NewClient(token string) ClientInterface
	NewClientForUser(token string, userID uint64) ClientInterface
	NewClientForTarget(token string, target string) ClientInterface
	NewClientForRepo(ctx context.Context, repo sweagentd.Repository) (ClientInterface, error)
	NewClientFromRepo(ctx context.Context, repoId, repoOwnerId int64) (ClientInterface, error)
	NewClientFromRepoName(ctx context.Context, repoName, ownerName string) (ClientInterface, error)
}

// ClientFactory is a factory for creating GitHub clients, using
// the given base URL (ex: http://api.github.localhost, https://api.github.com).
type ClientFactory struct {
	baseUrl                    *url.URL
	baseInternalURL            *url.URL
	dynamicWorkflowsHmacSecret string
	ffClient                   featureflags.Client
	limiter                    limiter.RateLimiter
	githubApp                  *GitHubApp
	githubCommitLogin          string
	githubCommitEmail          string
	obsv                       observability.Exporters
	environment                config.Environment
}

// NewClientFactory returns a new ClientFactory.
func NewClientFactory(
	obsv observability.Exporters,
	ffClient featureflags.Client,
	limiter limiter.RateLimiter,
	baseUrl,
	baseInternalURL string,
	githubApp *GitHubApp,
	githubCommitLogin,
	githubCommitEmail string,
	dynamicWorkflowsHmacSecret string,
	environment config.Environment,
) (ClientFactoryInterface, error) {
	parsedUrl, err := url.Parse(baseUrl)
	if err != nil {
		return nil, err
	}
	if !strings.HasSuffix(parsedUrl.Path, "/") {
		parsedUrl.Path = parsedUrl.Path + "/"
	}

	parsedInternalUrl := parsedUrl
	if baseInternalURL != "" {
		parsedInternalUrl, err = url.Parse(baseInternalURL)
		if err != nil {
			return nil, err
		}
	}

	if !strings.HasSuffix(parsedInternalUrl.Path, "/") {
		parsedInternalUrl.Path = parsedInternalUrl.Path + "/"
	}

	return &ClientFactory{
		baseUrl:                    parsedUrl,
		baseInternalURL:            parsedInternalUrl,
		dynamicWorkflowsHmacSecret: dynamicWorkflowsHmacSecret,
		ffClient:                   ffClient,
		limiter:                    limiter,
		githubApp:                  githubApp,
		githubCommitLogin:          githubCommitLogin,
		githubCommitEmail:          githubCommitEmail,
		obsv:                       obsv,
		environment:                environment,
	}, nil
}

func NewClientFactoryFromConfig(
	obsv observability.Exporters,
	cfg *config.Config,
	ffClient featureflags.Client,
	limiter limiter.RateLimiter,
) (ClientFactoryInterface, error) {
	app, err := NewAppFromConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create GitHub app: %w", err)
	}

	return NewClientFactory(
		obsv,
		ffClient,
		limiter,
		cfg.GitHubAPIURL,
		cfg.GitHubInternalAPIURL,
		app,
		cfg.GitHubCommitLogin,
		cfg.GitHubCommitEmail,
		cfg.DynamicWorkflowsHMACKey,
		cfg.Environment)
}

func (cf *ClientFactory) AppID() int64 {
	return cf.githubApp.ID
}

// NewAppClient returns a new [gg.Client] authenticated with a JWT for the app
func (cf *ClientFactory) NewAppClient() *gg.Client {
	atr := ghinstallation.NewAppsTransportFromPrivateKey(http.DefaultTransport, cf.githubApp.ID, cf.githubApp.PrivateKey)
	atr.BaseURL = cf.baseUrl.String()

	transport := AppClientTransport(atr, cf.obsv, cf.limiter)
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseUrl

	return client
}

// NewClientForRepo creates a new [Client] authenticated as the installation
// associated with the given owner ID, scoped to the given repo ID.
//
// The token is cached during the lifetime of the request, and will be reused by
// other clients created using the same repoId/repoOwnerId. The repoOwnerId is also
// used to keep track of installation rate limits across requests and asynchronous
// jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientForRepo(ctx context.Context, repo sweagentd.Repository) (ClientInterface, error) {
	target := limiter.TargetForOwnerID(repo.GetOwnerID())
	resp, token, err := tokens.GetGlobalTokenByRepo(ctx, cf, repo)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo ID")
	}
	return cf.NewClientForTarget(token, target), nil
}

// NewClientFromRepo creates a new [Client] authenticated as the installation
// associated with the given owner ID, scoped to the given repo ID.
//
// The token is cached during the lifetime of the request, and will be reused by
// other clients created using the same repoId/repoOwnerId. The repoOwnerId is also
// used to keep track of installation rate limits across requests and asynchronous
// jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientFromRepo(ctx context.Context, repoId, repoOwnerId int64) (ClientInterface, error) {
	target := limiter.TargetForOwnerID(repoOwnerId)
	resp, token, err := tokens.GetGlobalTokenByRepoID(ctx, cf, repoId, repoOwnerId)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo ID")
	}
	return cf.NewClientForTarget(token, target), nil
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
func (cf *ClientFactory) NewClientFromRepoName(ctx context.Context, repoName, ownerName string) (ClientInterface, error) {
	target := limiter.TargetForOwnerName(ownerName)
	resp, token, err := tokens.GetGlobalTokenByRepoName(ctx, cf, repoName, ownerName)
	if err != nil {
		return nil, cf.checkError(ctx, target, resp, err, "failed to get global token by org and repo name")
	}
	return cf.NewClientForTarget(token, target), nil
}

// NewClientForUser creates a new [Client] authenticated with the given token.
// The token should be a user token.
//
// The userID is used to keep track of the user's rate limits across requests and
// asynchronous jobs to prevent hitting rate limit errors.
func (cf *ClientFactory) NewClientForUser(token string, userID uint64) ClientInterface {
	target := limiter.TargetForUserID(int64(userID))
	return cf.newClient(token, target)
}

// TODO (colbylwilliams): Temporary
func (cf *ClientFactory) NewClientForTarget(token string, target string) ClientInterface {
	return cf.newClient(token, target)
}

// NewClient creates a new [Client] authenticated with the given token.
//
// NOTE: Prefer using one of the following methods which set track rate limits
// across requests and asynchronous jobs:
//
//   - [ClientFactory.NewClientForRepo]
//   - [ClientFactory.NewClientFromRepo]
//   - [ClientFactory.NewClientFromRepoName]
//   - [ClientFactory.NewClientForUser]
func (cf *ClientFactory) NewClient(token string) ClientInterface {
	return cf.newClient(token, "")
}

func (cf *ClientFactory) newClient(token, target string) ClientInterface {
	transport := ClientTransport(http.DefaultTransport, cf.obsv, cf.limiter, target, "githubrest")
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseUrl
	client = client.WithAuthToken(token)

	internalClient := gg.NewClient(&http.Client{Transport: transport})
	internalClient.BaseURL = cf.baseInternalURL
	internalClient = internalClient.WithAuthToken(token)

	src := oauth2.StaticTokenSource(
		&oauth2.Token{AccessToken: token},
	)
	httpClient := oauth2.NewClient(context.Background(), src)
	// Apply the same round tripper to the GraphQL client
	transport2 := ClientTransport(httpClient.Transport, cf.obsv, cf.limiter, target, "graphql")
	httpClient.Transport = transport2

	gqlclient := githubv4.NewEnterpriseClient(cf.graphqlUrl(), httpClient)

	return &Client{
		target:                     target,
		client:                     client,
		internalClient:             internalClient,
		ffClient:                   cf.ffClient,
		limiter:                    cf.limiter,
		gqlclient:                  gqlclient,
		token:                      token,
		githubApp:                  cf.githubApp,
		githubCommitLogin:          cf.githubCommitLogin,
		githubCommitEmail:          cf.githubCommitEmail,
		obsv:                       cf.obsv,
		dynamicWorkflowsHmacSecret: cf.dynamicWorkflowsHmacSecret,
		environment:                cf.environment,
	}
}

func (cf *ClientFactory) graphqlUrl() string {
	return cf.baseUrl.JoinPath("graphql").String()
}

// AltClientFactory is a client factory for creating GitHub App [gg.Client]s using
// the only the [GitHubApp] information. It is used in rare cases where we need to
// create a one-off [Client] with a unique configuration, or to make a single request
// to the GitHub API (e.g. [AltClientFactory.RateLimitsForRepo]).
//
// Unless you have a very specific reason to use this factory, use [ClientFactory]
type AltClientFactory struct {
	app     *GitHubApp
	obsv    observability.Exporters
	baseUrl *url.URL
}

// NewAltClientFactoryFromConfig creates a new [AltClientFactory] from the given
// [config.Config] object.
//
// Unless you have a very specific reason to use the [AltClientFactory], use
// [NewClientFactoryFromConfig] instead to create a [ClientFactory].
func NewAltClientFactoryFromConfig(obsv observability.Exporters, cfg *config.Config) (*AltClientFactory, error) {
	app, err := NewAppFromConfig(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create GitHub app: %w", err)
	}

	return app.newAltClientFactory(obsv, cfg.GitHubAPIURL)
}

func (a *GitHubApp) newAltClientFactory(obsv observability.Exporters, baseUrl string) (*AltClientFactory, error) {
	parsedUrl, err := url.Parse(baseUrl)
	if err != nil {
		return nil, err
	}
	if !strings.HasSuffix(parsedUrl.Path, "/") {
		parsedUrl.Path = parsedUrl.Path + "/"
	}

	return &AltClientFactory{
		app:     a,
		obsv:    obsv,
		baseUrl: parsedUrl,
	}, nil
}

// NewAppClient creates a new [gg.Client] using the GitHub App's private key.
// This client is used for making requests to the GitHub API as the app itself.
//
// The main difference between the client returned by this method and the client
// returned by [ClientFactory.NewAppClient] is that this one does not include
// the [ratelimits.RoundTripper].
func (cf *AltClientFactory) NewAppClient() *gg.Client {
	atr := ghinstallation.NewAppsTransportFromPrivateKey(http.DefaultTransport, cf.app.ID, cf.app.PrivateKey)
	atr.BaseURL = cf.baseUrl.String()

	transport := TelemetryClientTransport(atr, cf.obsv)
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseUrl

	return client
}

// RateLimitsForRepo retrieves the rate limits for a a specific installation
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
func (cf *AltClientFactory) RateLimitsForRepo(ctx context.Context, ownerID, repoID int64) (map[uint8]limiter.Rate, error) {
	ctx, span := cf.obsv.Tracer.Start(ctx, "github.AltClientFactory.RateLimitsForRepo")
	defer span.End()

	resp, token, err := tokens.GetGlobalTokenByRepoID(ctx, cf, repoID, ownerID)
	if err != nil {
		return nil, cf.checkError(ctx, resp, err, "failed to get global token by org and repo ID")
	}

	transport := TelemetryClientTransport(http.DefaultTransport, cf.obsv)
	client := gg.NewClient(&http.Client{Transport: transport})
	client.BaseURL = cf.baseUrl
	client = client.WithAuthToken(token)

	rates, _, err := client.RateLimit.Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get rate limits: %w", err)
	}

	return ratelimits.ToLimiterRates(rates), nil
}
