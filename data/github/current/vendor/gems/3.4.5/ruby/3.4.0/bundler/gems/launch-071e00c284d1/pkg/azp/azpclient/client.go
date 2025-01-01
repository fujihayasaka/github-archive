package azpclient

import (
	"context"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

type Options struct {
	breaker  *circuit.Breaker
	tokenSrc launchhttp.TokenSource
	hooks    *httpclient.ClientHooks
}

type Option func(*Options)

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

func WithClientHooks(hooks *httpclient.ClientHooks) Option {
	return func(o *Options) {
		o.hooks = hooks
	}
}

type Client struct {
	obs           *observability.Observability
	ghTwirpClient ghtwirp.Client
	url           *urlBuilder
	options       *Options

	// Embedding to satisfy azp.RepositoryClient interface.
	*BuildsService
	*URLExchangeService
	*RunnersService
	*RunnerGroupsService
	*RunnerScaleSetsService
	*ArtifactsService
	*LabelsService
	*GatesService
	*LargerRunnersService
	*ChecksService
	*ArtifactCacheService
}

// New returns a new repo client. Assumes the provided http authenticates requests.
func New(
	ctx context.Context,
	http *httpclient.Client,
	ghTwirpClient ghtwirp.Client,
	obs *observability.Observability,
	cfg config.AzureProviderConfig,
	r *azptypes.BackingResources,
	options ...Option,
) *Client {
	defaultOptions := &Options{
		breaker:  nil,
		tokenSrc: nil,
	}

	for _, option := range options {
		option(defaultOptions)
	}

	repoBaseURL := cfg.RepoAPIsBaseURL
	runnerServiceBaseURL := cfg.RunnerServiceBaseURL
	runnerServiceIsDirectScaleUnitURL := false
	acServiceBaseURL := cfg.ACServiceBaseURL

	if ghTwirpClient.IsFeatureEnabledForActor(ctx, github.ConstructScaleUnitURL, r.EntityID) {
		if url, ok := scaleUnitMap[r.PipelinesScaleUnitID]; ok {
			repoBaseURL = url
		} else {
			obs.Log(ctx, "Pipelines Scale Unit ID not found in scale unit map", kvp.String("gh.launch.scale_unit.identifier", r.PipelinesScaleUnitID), kvp.String("gh.repo.global_id", r.EntityID.String()))
		}
		if url, ok := scaleUnitMap[r.ArtifactCacheScaleUnitID]; ok {
			acServiceBaseURL = url
		} else {
			obs.Log(ctx, "Artifact Cache Scale Unit ID not found in scale unit map", kvp.String("gh.launch.scale_unit.identifier", r.ArtifactCacheScaleUnitID), kvp.String("gh.repo.global_id", r.EntityID.String()))
		}
		if url, ok := scaleUnitMap[r.RunnerScaleUnitID]; ok {
			runnerServiceBaseURL = url
			runnerServiceIsDirectScaleUnitURL = true
		} // TODO: Add logging here when runner_scale_unit_id is backfilled
	}

	c := &Client{
		obs:           obs,
		ghTwirpClient: ghTwirpClient,
		url: &urlBuilder{
			repoBaseURL:                        repoBaseURL,
			acServiceBaseURL:                   acServiceBaseURL,
			runnersServiceBaseURL:              runnerServiceBaseURL,
			runnersServiceIsDirectScaleUnitURL: runnerServiceIsDirectScaleUnitURL,
			repoExternalBaseURL:                cfg.ExternalRepoAPIsBaseURL,
			tenantName:                         r.TenantName,
			tenantID:                           r.TenantID,
			projectName:                        r.ProjectName,
			pipelineID:                         r.PipelineID,
		},
		options: defaultOptions,
	}

	if defaultOptions.hooks != nil {
		http = http.WithHooks(defaultOptions.hooks)
	}

	useDefaultGateAuth := func(ctx context.Context) bool {
		return ghTwirpClient.IsFeatureEnabledForActor(ctx, github.GatesUseDefaultAuth, r.EntityID)
	}

	http = http.WithPkgName("azp")

	c.BuildsService = &BuildsService{client: c, http: http.WithSvcName("azp.builds")}
	c.URLExchangeService = &URLExchangeService{client: c, http: http.WithSvcName("azp.urlexchange")}
	c.RunnersService = &RunnersService{client: c, http: http.WithSvcName("azp.runners")}
	c.RunnerGroupsService = &RunnerGroupsService{client: c, http: http.WithSvcName("azp.runnergroups")}
	c.RunnerScaleSetsService = &RunnerScaleSetsService{client: c, http: http.WithSvcName("azp.runnerscalesets")}
	c.ArtifactsService = &ArtifactsService{client: c, http: http.WithSvcName("azp.artifacts")}
	c.LabelsService = &LabelsService{client: c, http: http.WithSvcName("azp.labels")}
	c.GatesService = &GatesService{client: c, http: http.WithSvcName("azp.gates"), useDefaultAuth: useDefaultGateAuth}
	c.LargerRunnersService = &LargerRunnersService{client: c, http: http.WithSvcName("azp.largerrunners")}
	c.ChecksService = &ChecksService{client: c, http: http.WithSvcName("azp.checks")}
	c.ArtifactCacheService = &ArtifactCacheService{client: c, http: http.WithSvcName("azp.artifactcache")}
	return c
}

func (c *Client) withDefaultOpts(ctx context.Context, options ...httpclient.DoOption) []httpclient.DoOption {
	var doOptions []httpclient.DoOption

	if c.options.tokenSrc != nil {
		doOptions = append(doOptions, httpclient.WithTokenAuth(c.options.tokenSrc))
	}

	if c.options.breaker != nil {
		doOptions = append(doOptions, httpclient.WithBreaker(c.options.breaker))
	}

	doOptions = append(doOptions, httpclient.WithRequestOptions(launchhttp.WithADNCorrelationHeaders(ctx)))
	doOptions = append(doOptions, httpclient.WithRetries(azp.ResponseValidator()))
	doOptions = append(doOptions, httpclient.WithRequestErrorProcessor(azp.CleanRequestError))

	return append(doOptions, options...)
}

func WithMultipartPayload(mp *azp.MultipartPayload) []httpclient.DoOption {
	return []httpclient.DoOption{
		httpclient.WithRequestOptions(launchhttp.WithContentType(mp.ContentType())),
	}
}
