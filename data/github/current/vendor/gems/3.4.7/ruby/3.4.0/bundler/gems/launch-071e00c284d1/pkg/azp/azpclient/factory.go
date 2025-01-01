package azpclient

import (
	"context"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azpbearer/tokensrc"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

type Factory struct {
	http          *httpclient.Client
	ghTwirpClient ghtwirp.Client

	tp      *tokensrc.RepoClientTokenSourceFactory
	repo    deployer.AzpResourcesRepository
	breaker *circuit.Breaker
	obs     *observability.Observability
	hooks   *httpclient.ClientHooks

	cfg config.AzureProviderConfig
}

func NewFactory(
	http *httpclient.Client,
	ghTwirpClient ghtwirp.Client,
	breaker *circuit.Breaker,
	obs *observability.Observability,
	cfg config.AzureProviderConfig,
	repo deployer.AzpResourcesRepository,
	tp *tokensrc.RepoClientTokenSourceFactory,
	hooks *httpclient.ClientHooks,
) *Factory {
	return &Factory{
		http:          http,
		ghTwirpClient: ghTwirpClient,
		cfg:           cfg,
		repo:          repo,
		tp:            tp,
		hooks:         hooks,
		breaker:       breaker,
		obs:           obs,
	}
}

func (f *Factory) ClientFromResources(ctx context.Context, resources *azptypes.BackingResources) azp.RepositoryClient {
	return f.newClient(ctx, resources)
}

func (f *Factory) ClientFromRepoGID(ctx context.Context, repoID types.GlobalID) (azp.RepositoryClient, error) {
	resources, err := f.repo.TryGet(ctx, repoID)
	if err != nil {
		return nil, err
	}
	return f.newClient(ctx, resources), nil
}

func (f *Factory) GetPipelineServiceURL(ctx context.Context, resources *azptypes.BackingResources) string {
	repoBaseURL := f.cfg.RepoAPIsBaseURL
	if f.ghTwirpClient.IsFeatureEnabledForActor(ctx, github.ConstructScaleUnitURL, resources.EntityID) {
		if url, ok := scaleUnitMap[resources.PipelinesScaleUnitID]; ok {
			repoBaseURL = url
		} else {
			f.obs.Log(ctx, "Pipelines Scale Unit ID not found in scale unit map", kvp.String("gh.launch.scale_unit.identifier", resources.PipelinesScaleUnitID), kvp.String("gh.repo.global_id", resources.EntityID.String()))
		}
	}

	url := &urlBuilder{
		repoBaseURL: repoBaseURL,
		tenantName:  resources.TenantName,
	}

	return url.getPipelineServiceURL()
}

// newClient mainly specializes the signer and token provider now that we have the relevant backing resources
func (f *Factory) newClient(ctx context.Context, r *azptypes.BackingResources) *Client {

	var options []Option
	if f.hooks != nil {
		options = append(options, WithClientHooks(f.hooks))
	}

	if f.tp != nil {
		options = append(options, WithTokenSource(f.tp.For(r)))
	}

	if f.breaker != nil {
		options = append(options, WithBreaker(f.breaker))
	}

	return New(
		ctx,
		f.http,
		f.ghTwirpClient,
		f.obs,
		f.cfg,
		r,
		options...,
	)
}
