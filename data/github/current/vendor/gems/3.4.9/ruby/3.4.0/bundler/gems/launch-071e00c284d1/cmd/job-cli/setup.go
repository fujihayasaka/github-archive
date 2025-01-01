package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"time"

	"github.com/github/go-config/v2"
	"github.com/github/go-config/v2/env"
	throttler "github.com/github/go-freno-client"
	errs "github.com/pkg/errors"
	"github.com/redis/go-redis/v9"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/launchredis"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/keystore"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/azp/azpbearer"
	"github.com/github/launch/pkg/azp/azpbearer/tokensrc"
	"github.com/github/launch/pkg/azp/azpclient"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/dsn"
	"github.com/github/launch/utils/roundtrippers"
	azpConfig "github.com/github/launch/workflowbuild/azp/config"
)

type cfg struct {
	launchconfig.CommonConfig

	ReportingAddr                 string        `config:",env=FAILBOT_HAYSTACK_URL"`
	DeployerDBURL                 string        `config:",env=DEPLOYER_DATABASE_URL,required"`
	ReadOnlyDeployerDBURL         string        `config:",env=DEPLOYER_DATABASE_READ_ONLY_URL,required"`
	FrenoAddr                     string        `config:",env=FRENO_ADDR"`
	FrenoOverrideCluster          string        `config:",env=FRENO_OVERRIDE_CLUSTER"`
	AppID                         int64         `config:",env=GITHUB_APP_ID,required"`
	APIHost                       string        `config:",env=API_HOST,required"`
	V3APIEndpoint                 string        `config:",env=V3_API_PATH"`
	GraphQLEndpoint               string        `config:"graphql,env=GRAPHQL_API_PATH"`
	AppPrivateKey                 string        `config:",env=GITHUB_APP_PRIVATE_KEY,required"`
	GraphQLServiceToken           string        `config:",env=GITHUB_GRAPHQL_SERVICE_TOKEN"`
	MySQLBreakerConsecutiveErrors int           `config:"500,env=MYSQL_CIRCUIT_BREAKER_CONSECUTIVE_ERRORS"`
	MySQLMaxOpenConns             int           `config:"512,env=MYSQL_MAX_OPEN_CONNS"`
	MySQLMaxIdleConns             int           `config:"512,env=MYSQL_MAX_IDLE_CONNS"`
	MySQLMaxIdleTime              time.Duration `config:"25s,env=MYSQL_MAX_IDLE_TIME"`
	MySQLMaxLifetime              time.Duration `config:"5m,env=MYSQL_MAX_LIFETIME"`
	GitHubTwirpAddr               string        `config:",env=GITHUB_TWIRP_ADDR"`
	GitHubTwirpHMACSecret         string        `config:",env=GITHUB_TWIRP_HMAC_SECRET"`

	launchcache.CacheConfig
	launchredis.RedisConfig

	// Keystore diet earthsmoke key
	KeystoreAZPOrganizationKey string `config:",env=EARTHSMOKE_KEYSTORE_AZP_ORGANIZATION"`

	azpConfig.AzureProviderConfig
	BreakerConfig abreaker.Config
	roundtrippers.RoundTripperConfig
}

func loadConfig() (*cfg, error) {
	cfg := &cfg{}
	if err := config.Load(cfg, env.New()); err != nil {
		return nil, err
	}

	if err := cfg.AzureProviderConfig.Parse(); err != nil {
		return nil, err
	}

	return cfg, nil
}

func getLogger(cfg *cfg) logger.Logger {
	return logger.New(&logger.Config{
		Debug:     cfg.LogDebug,
		App:       "launch",
		ReportURL: cfg.ReportingAddr,
		Hostname:  getHostName(),
		// Report the following fields as tags to Sentry
		FieldTags: logger.DefaultFieldTags,
	})
}

func getHostName() string {
	if appHost, err := os.Hostname(); err == nil {
		return appHost
	}
	return "unknown"
}

func getStatter(cfg *cfg) statter.Statter {
	statter := statter.New(&statter.Config{
		Prefix: cfg.StatsPrefix,
		Addr:   cfg.StatsAddr,
		Period: cfg.StatsPeriod,
	})
	statter.Start()
	return statter
}

func getObservability(cfg *cfg) (*observability.Observability, func()) {
	log := getLogger(cfg)
	sttr := getStatter(cfg)
	defaultStatter := statter.DefaultStatter()
	return observability.New(log, sttr), func() {
		sttr.Stop()
		defaultStatter.Stop()
	}
}

func getDbConn(cfg *cfg, stats statter.Statter) (*sql.DB, error) {
	dbURL, err := dsn.WithInterpolateParams(cfg.DeployerDBURL, "true")
	if err != nil {
		return nil, errs.Wrap(err, "unable to set interpolate params attribute")
	}

	conn, err := mysqldb.NewDB(stats, dbURL)
	if err != nil {
		return nil, err
	}

	conn.SetMaxIdleConns(cfg.MySQLMaxIdleConns)
	conn.SetMaxOpenConns(cfg.MySQLMaxOpenConns)

	// Set max idle time before max lifetime to avoid https://github.com/golang/go/pull/58490
	conn.SetConnMaxIdleTime(cfg.MySQLMaxIdleTime)
	conn.SetConnMaxLifetime(cfg.MySQLMaxLifetime)

	return conn, nil
}

func getRODbConn(cfg *cfg, stats statter.Statter) (*sql.DB, error) {
	dbURL, err := dsn.WithInterpolateParams(cfg.ReadOnlyDeployerDBURL, "true")
	if err != nil {
		return nil, errs.Wrap(err, "unable to set interpolate params attribute")
	}

	conn, err := mysqldb.NewDB(stats, dbURL)
	if err != nil {
		return nil, err
	}

	conn.SetMaxIdleConns(cfg.MySQLMaxIdleConns)
	conn.SetMaxOpenConns(cfg.MySQLMaxOpenConns)

	// Set max idle time before max lifetime to avoid https://github.com/golang/go/pull/58490
	conn.SetConnMaxIdleTime(cfg.MySQLMaxIdleTime)
	conn.SetConnMaxLifetime(cfg.MySQLMaxLifetime)

	return conn, nil
}

func getCache(ctx context.Context, cfg *cfg, obs *observability.Observability, breaker *circuit.Breaker) (cache launchcache.Cache, done func(), err error) {
	done = func() {}
	var redisClient redis.UniversalClient
	if cfg.RedisConfig.RedisURL != "" {
		redisClient, err = launchredis.New(ctx, cfg.RedisConfig, obs)
		if err != nil {
			return nil, done, err
		}
		done = func() { redisClient.Close() }
	}
	cache = launchcache.NewSharedCache(redisClient, breaker, cfg.CacheConfig, obs)
	return cache, done, nil
}

func getThrottlerFunc(cfg *cfg) throttlerFunc {
	return func(disableFreno bool) (throttler.Throttler, error) {
		if disableFreno {
			return throttler.DefaultThrottler, nil
		}

		if cfg.FrenoAddr == "" {
			return nil, errors.New("you must set FRENO_ADDR to use it as a throttler, or pass --disable-freno")
		}

		cluster := freno.LaunchDBCluster
		if cfg.FrenoOverrideCluster != "" {
			cluster = cfg.FrenoOverrideCluster
		}

		return throttler.NewFrenoThrottler(cfg.FrenoAddr, freno.AppName, cluster), nil
	}
}

func getTokenService(ctx context.Context, cfg *cfg, httpClient *http.Client, obs *observability.Observability, a appcontext.ApplicationMetadata, ghCache launchcache.GitHubCache, ghTwirpClient ghtwirp.Client) (tokens.Service, error) {
	tokenServiceBreaker, err := abreaker.NewJobCLITokenServiceBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}

	apiBase, err := url.Parse(cfg.APIHost)
	if err != nil {
		return nil, err
	}
	apiBase.Path = cfg.V3APIEndpoint

	tokenService, err := tokens.NewService(
		a.Environment,
		obs,
		apiBase,
		cfg.AppID,
		[]byte(cfg.AppPrivateKey),
		tokenServiceBreaker,
		httpclient.New(httpClient, httpclient.WithRetryDelay(25*time.Millisecond)),
		ghCache,
		ghTwirpClient.IsFeatureEnabledForActor,
		ghTwirpClient.IsFeatureEnabledGlobally,
		ghTwirpClient.GetRepositoryOwnerID,
		reqobs.NewHTTPClientHooks(obs),
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return nil, err
	}
	return tokenService, nil
}

func getGitHubTwirpClient(ctx context.Context, cfg *cfg, httpClient *http.Client, obs *observability.Observability, a appcontext.ApplicationMetadata, twirpCache launchcache.GitHubTwirpCache) (ghtwirp.Client, error) {
	githubTwirpBreaker, err := abreaker.NewGithubTwirpClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, errs.Wrap(err, "error creating breaker for GitHub Twirp client")
	}
	twirpTelemetry := reqobs.NewTwirpMetricsHooks(obs.Statter)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	ghTwirpClient, err := ghtwirp.NewClient(
		cfg.GitHubTwirpAddr,
		cfg.GitHubTwirpHMACSecret,
		obs,
		a.Environment.String(),
		twirpCache,
		ahttp.NewRetryClient(githubTwirpBreaker, obs.Statter, httpClient, "ghtwirp"),
		twirpOpts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return nil, errs.Wrap(err, "error creating GitHub Twirp client")
	}

	if cfg.IsEnterprise() {
		return ghtwirp.NewEnterpriseClient(ghTwirpClient), nil
	}

	return ghTwirpClient, nil
}

func getGithubClientFactory(ctx context.Context, cfg *cfg, httpClient *http.Client, obs *observability.Observability, tok tokens.Service, a appcontext.ApplicationMetadata, ghTwirpClient ghtwirp.Client) (github.Factory, error) {
	urlProvider, err := cu.NewGraphQLURLProvider(cfg.APIHost, cfg.GraphQLEndpoint)
	if err != nil {
		return nil, fmt.Errorf("error creating URLProvider for graphql client: %w", err)
	}

	breaker, err := abreaker.NewGithubClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}

	hooks := reqobs.GitHubGraphQLHooks(obs)

	clientFactory := github.NewFactory(
		a.Environment,
		urlProvider,
		tokens.ServiceToken(cfg.GraphQLServiceToken),
		tok,
		obs,
		breaker,
		hooks,
		httpClient,
		ghTwirpClient,
		launchconfig.IsMultiTenant(),
	)
	return clientFactory, nil
}

func getServiceClientFactories(ctx context.Context, cfg *cfg, obs *observability.Observability, conn *sql.DB, cache launchcache.Cache, a appcontext.ApplicationMetadata, dbBreaker *circuit.Breaker, ghTwirpClient ghtwirp.Client) (
	azp.RepositoryClientFactory,
	error,
) {
	err := cfg.AzureProviderConfig.Parse()
	if err != nil {
		return nil, err
	}

	breaker, err := abreaker.NewJobCLIAZPClientBreaker(ctx, obs, cfg.BreakerConfig)
	if err != nil {
		return nil, err
	}

	// Setup the keystore
	var ks keystore.Store

	if cfg.IsEnterprise() {
		ks = keystore.NewNullStore(keystore.NewEncoder())
	} else {
		if cfg.KeystoreAZPOrganizationKey == "" {
			return nil, errors.New("keystore:azp:organization key not found")
		}
		ks = keystore.NewStore(cfg.KeystoreAZPOrganizationKey, obs.Logger, obs.Statter)
	}

	aconn := asql.New(conn, obs.Logger, obs.Statter, dbBreaker, asql.LaunchCluster)

	repoDB := deployer.NewAZPResourcesRepo(
		aconn,
		a.Environment,
		obs,
		cfg.AzureProviderConfig.ResourcesLockPollFreq,
		cfg.AzureProviderConfig.ResourcesLockTimeout,
		deployer.NewGlobalIDMigrator(ghTwirpClient),
		ghTwirpClient,
	)

	httpClient := apphttp.NewClient(apphttp.WithIgnoreRedirects(), apphttp.WithAzureFrontDoorMaxTimeout(), apphttp.WithObservability(obs, cfg.RoundTripperConfig))

	scf := setupAZPClientFactory(
		httpClient,
		ghTwirpClient,
		cfg.AzureProviderConfig,
		obs,
		ks,
		repoDB,
		cache,
		a.Environment,
		breaker,
		breaker,
	)

	return scf, nil
}

func getFrenoClient(cfg *cfg, obs *observability.Observability, httpClient *http.Client, breaker *circuit.Breaker) (freno.Client, error) {
	// Freno is not currently deployed in Proxima, this IsMultiTenant check should be removed once it is.
	// See: https://github.com/github/actions-core-enterprise/issues/546
	if cfg.IsEnterprise() || cfg.IsMultiTenant {
		return freno.NopClient{}, nil
	}

	return freno.NewClient(cfg.FrenoAddr, cfg.FrenoOverrideCluster, reqobs.FrenoHooks(obs), httpClient, breaker)
}

func setupAZPClientFactory(
	hcl *http.Client,
	ghTwirpClient ghtwirp.Client,
	azcfg azpConfig.AzureProviderConfig,
	obs *observability.Observability,
	ks keystore.Store,
	azprepo deployer.AzpResourcesRepository,
	cache launchcache.Cache,
	env launchconfig.AppEnv,

	// Currently the same  breaker is provided for the token
	// and repo endpoints.
	tokenBreaker *circuit.Breaker,
	repoBreaker *circuit.Breaker,
) azp.RepositoryClientFactory {
	hooks := reqobs.NewHTTPClientHooks(obs)
	btc := azpbearer.New(
		httpclient.New(hcl),
		azpbearer.WithBreaker(tokenBreaker),
		azpbearer.WithCache(cache.AzureProvider()),
		azpbearer.WithHooks(hooks),
	)
	tsf := tokensrc.NewRepoClientTokenSourceFactory(azcfg, ks, btc, env.String())
	return azpclient.NewFactory(
		httpclient.New(hcl),
		ghTwirpClient,
		repoBreaker,
		obs,
		azcfg,
		azprepo,
		tsf,
		hooks,
	)
}
