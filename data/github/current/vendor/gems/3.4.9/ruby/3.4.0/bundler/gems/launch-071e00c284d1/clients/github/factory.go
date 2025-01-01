package github

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/shurcooL/githubv4"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ahttp"
)

type ClientTokenOptions struct {
	UseTokenCache       bool
	TokenPermissions    *tokens.InstallationPermissions
	ExtendedPermissions *tokens.ExtendedPermissions
}

// Factory defines the Interface a Client Factory must adhere to
type Factory interface {
	// NewClientForRepositoryOwnerDatabaseID creates a global app (site scoped) token for a repository owner database ID.
	// Note: this will cache and reuse tokens
	NewClientForRepositoryOwnerDatabaseID(ctx context.Context, repositoryID types.GlobalID, ownerID int64) (Client, error)
	// NewClientForRepository creates a global app (site scoped) token for an owner and a single repo.
	NewClientForRepository(ctx context.Context, repositoryID, ownerID types.GlobalID, opts *ClientTokenOptions) (Client, error)
	// NewClientForRepositoryOwner creates a global app (site scoped) token for a repository owner Global ID.
	// Note: this will cache and reuse tokens
	NewClientForRepositoryOwner(ctx context.Context, repositoryID, ownerID types.GlobalID) (Client, error)
}

// NewFactory creates an instance of the Factory
func NewFactory(env launchconfig.AppEnv, apiURLs cu.GraphQLURLProvider, serviceToken tokens.ServiceToken, tokenService tokens.Service, obs *observability.Observability, breaker *circuit.Breaker, hooks *ClientHooks, httpClient *http.Client, ghTwirpClient ghtwirp.Client, isMultiTenant bool) Factory {
	return &clientFactory{
		env:           env,
		apiURLs:       apiURLs,
		serviceToken:  serviceToken,
		tokenService:  tokenService,
		obs:           obs,
		hooks:         hooks,
		breaker:       breaker,
		gqlClient:     githubv4.NewEnterpriseClient(apiURLs.GraphQLApiURL(), httpClient),
		httpClient:    httpClient,
		ghTwirpClient: ghTwirpClient,
		isMultiTenant: isMultiTenant,
	}
}

// clientFactory holds configured API URL so we can just set this once
type clientFactory struct {
	env           launchconfig.AppEnv
	apiURLs       cu.GraphQLURLProvider
	serviceToken  tokens.ServiceToken
	tokenService  tokens.Service
	obs           *observability.Observability
	hooks         *ClientHooks
	breaker       *circuit.Breaker
	gqlClient     *githubv4.Client
	httpClient    *http.Client
	ghTwirpClient ghtwirp.Client
	isMultiTenant bool
}

// All clients are created here.
func (f *clientFactory) newClient(token *tokens.AccessToken, options ...Option) Client {
	options = append(options, WithNextGlobalIDHeader())

	return newClient(
		f.env,
		f.apiURLs,
		f.gqlClient,
		f.serviceToken,
		token,
		ahttp.NewClient(f.breaker, f.obs.Statter, ahttp.DefaultBackoffStrategy, f.httpClient, "github"),
		f.obs,
		time.Now,
		f.hooks,
		f.isMultiTenant,
		f.ghTwirpClient,
		options...,
	)
}

func (f *clientFactory) NewClientForRepositoryOwnerDatabaseID(ctx context.Context, repositoryID types.GlobalID, ownerDatabaseID int64) (Client, error) {
	// If this function is passed an ownerDatabaseID of 0, reach out to the GitHub API to get the owner ID
	var (
		ownerID int64
		err     error
	)

	if ownerDatabaseID == 0 {
		ownerID, err = f.getOwnerDatabaseIDFromTwirp(ctx, repositoryID)
		if err != nil {
			return nil, err
		}
	} else {
		ownerID = ownerDatabaseID
	}

	return f.newSiteScopedClient(ctx, repositoryID, ownerID, &ClientTokenOptions{
		UseTokenCache: true,
	}, false)
}

func (f *clientFactory) NewClientForRepositoryOwner(ctx context.Context, repositoryID, ownerID types.GlobalID) (Client, error) {
	var (
		typeName        string
		ownerDatabaseID int64
		err             error
	)

	if !ownerID.IsZeroValue() {
		typeName, ownerDatabaseID, err = ownerID.Decode()
		if err != nil {
			return nil, err
		}

		if (typeName != types.GlobalIDUserType) && (typeName != types.GlobalIDOrganizationType) {
			return nil, fmt.Errorf("got non-owner type for repository owner: %q", typeName)
		}
	} else {
		ownerDatabaseID, err = f.getOwnerDatabaseIDFromTwirp(ctx, repositoryID)
		if err != nil {
			return nil, err
		}
	}

	return f.newSiteScopedClient(ctx, repositoryID, ownerDatabaseID, &ClientTokenOptions{
		UseTokenCache: true,
	}, false)
}

func (f *clientFactory) NewClientForRepository(ctx context.Context, repositoryID, ownerID types.GlobalID, opts *ClientTokenOptions) (Client, error) {
	var (
		typeName        string
		ownerDatabaseID int64
		err             error
	)

	if !ownerID.IsZeroValue() {
		typeName, ownerDatabaseID, err = ownerID.Decode()
		if err != nil {
			return nil, err
		}

		if (typeName != types.GlobalIDUserType) && (typeName != types.GlobalIDOrganizationType) {
			return nil, fmt.Errorf("got non-owner type for repository owner: %q", typeName)
		}
	} else {
		ownerDatabaseID, err = f.getOwnerDatabaseIDFromTwirp(ctx, repositoryID)
		if err != nil {
			return nil, err
		}
	}

	return f.newSiteScopedClient(ctx, repositoryID, ownerDatabaseID, opts, true)
}

func (f *clientFactory) newSiteScopedClient(ctx context.Context, repositoryID types.GlobalID, ownerDatabaseID int64, opts *ClientTokenOptions, isRepoScoped bool) (Client, error) {
	if f.tokenService == nil {
		return nil, errors.New("token service not configured")
	}

	if opts == nil {
		opts = &ClientTokenOptions{}
	}

	permissions := opts.TokenPermissions
	if permissions == nil {
		// this will use default permissions
		permissions = &tokens.InstallationPermissions{}
	}

	var token *tokens.AccessToken
	var err error

	if isRepoScoped {
		token, err = f.tokenService.SiteScopedTokenForRepository(ctx, repositoryID, ownerDatabaseID, opts.UseTokenCache, permissions, opts.ExtendedPermissions)
	} else {
		token, err = f.tokenService.SiteScopedTokenForRepositoryOwner(ctx, repositoryID, ownerDatabaseID, opts.UseTokenCache, permissions, opts.ExtendedPermissions)
	}

	if err != nil {
		return nil, err
	}

	return f.newClient(token), nil
}

func (f *clientFactory) getOwnerDatabaseIDFromTwirp(ctx context.Context, repositoryID types.GlobalID) (int64, error) {
	typeName, repoDatabaseID, err := repositoryID.Decode()
	if err != nil {
		return 0, err
	}

	if typeName != types.GlobalIDRepositoryType {
		return 0, fmt.Errorf("got non-repo type for repository: %q", typeName)
	}

	ownerDatabaseID, err := f.ghTwirpClient.GetRepositoryOwnerID(ctx, repoDatabaseID, true)
	if err != nil {
		return 0, fmt.Errorf("could not find owner id by repo id")
	}
	return ownerDatabaseID, nil
}
