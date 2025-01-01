package shared

import (
	"context"
	"os"
	"time"

	backoff "github.com/cenkalti/backoff/v4"
	throttler "github.com/github/go-freno-client"
	"github.com/github/go-kvp"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/reqobs"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/roundtrippers"
)

type Dependencies struct {
	Obs           *observability.Observability
	StopObs       func()
	GhTwirpClient ghtwirp.Client
	LaunchCache   launchcache.Cache
	DBThrottler   throttler.Throttler
	Backoff       backoff.BackOff
}
type DependencyFunc func(context.Context) (*Dependencies, error)

type TransitionCfg struct {
	launchconfig.CommonConfig

	LaunchCI      string `config:",env=LAUNCH_CI"`
	IsCodespaces  bool   `config:"false,env=CODESPACES"`
	ReportingAddr string `config:",env=FAILBOT_HAYSTACK_URL"`

	CacheConfig   launchcache.CacheConfig
	RedisConfig   launchredis.RedisConfig
	BreakerConfig abreaker.Config
	roundtrippers.RoundTripperConfig

	GitHubTwirpHMACSecret string `config:",env=GITHUB_TWIRP_HMAC_SECRET"`
	GitHubTwirpAddr       string `config:",env=GITHUB_TWIRP_ADDR"`

	FrenoAddr            string `config:",env=FRENO_ADDR"`
	FrenoOverrideCluster string `config:",env=FRENO_OVERRIDE_CLUSTER"`
	DisableFreno         bool   `config:"false,env=DISABLE_FRENO"`
}

func (cfg TransitionCfg) getLogger() logger.Logger {
	return logger.New(&logger.Config{
		Debug:     cfg.LogDebug,
		App:       "launch",
		ReportURL: cfg.ReportingAddr,
		Hostname:  getHostName(),
		// Report the following fields as tags to Sentry
		FieldTags: map[string]bool{
			"gh.request_id": true,
		},
	})
}

func getHostName() string {
	if appHost, err := os.Hostname(); err == nil {
		return appHost
	}
	return "unknown"
}

func (cfg TransitionCfg) getStatter() statter.Statter {
	if cfg.StatsAddr != "" {
		statter := statter.New(&statter.Config{
			Prefix: cfg.StatsPrefix,
			Addr:   cfg.StatsAddr,
			Period: cfg.StatsPeriod,
			Tags: statter.Tags{
				"launch_service": "migratorctl",
			},
		})
		statter.Start()
		return statter
	}
	return statter.NullStatter()
}

func (cfg TransitionCfg) GetObservability() (*observability.Observability, func()) {
	log := cfg.getLogger()
	sttr := cfg.getStatter()
	defaultStatter := statter.DefaultStatter()
	return observability.New(log, sttr), func() {
		sttr.Stop()
		defaultStatter.Stop()
	}
}

func (cfg TransitionCfg) GetThrottler(cluster string) throttler.Throttler {
	if cfg.DisableFreno {
		return throttler.DefaultThrottler
	}

	if cfg.FrenoOverrideCluster != "" {
		cluster = cfg.FrenoOverrideCluster
	}

	if cfg.FrenoAddr != "" {
		return throttler.NewFrenoThrottler(cfg.FrenoAddr, freno.AppName, cluster)
	}
	return throttler.DefaultThrottler
}

func (cfg TransitionCfg) SetupGitHubTwirpClient(ctx context.Context, obs *observability.Observability, twirpCache launchcache.GitHubTwirpCache, name string) (ghtwirp.Client, error) {
	breaker, err := abreaker.NewNamedRateBreaker(ctx, obs, abreaker.BuildGitHubTwirpClientConfig(cfg.BreakerConfig), name)
	if err != nil {
		obs.Error(ctx, "unable to build twirp breaker", kvp.Err(err))
		return nil, err
	}

	twirpTelemetry := reqobs.NewTwirpMetricsHooks(obs.Statter)
	twirpOpts := reqobs.AdaptTwirpHooksToClientOptions(twirpTelemetry, time.Now)

	var githubTwirpClient ghtwirp.Client
	githubTwirpClient, err = ghtwirp.NewClient(
		cfg.GitHubTwirpAddr,
		cfg.GitHubTwirpHMACSecret,
		obs,
		cfg.LaunchEnv,
		twirpCache,
		ahttp.NewRetryClient(
			breaker,
			obs.Statter,
			apphttp.NewClient(apphttp.WithObservability(obs, cfg.RoundTripperConfig)),
			"ghtwirp",
		),
		twirpOpts,
		launchconfig.IsMultiTenant())
	if err != nil {
		obs.Error(ctx, "error creating GitHub Twirp client", kvp.Err(err))
		return nil, err
	}

	if cfg.IsEnterprise() {
		return ghtwirp.NewEnterpriseClient(githubTwirpClient), nil
	}

	return githubTwirpClient, nil
}

func (cfg TransitionCfg) GetCache(ctx context.Context, obs *observability.Observability, breaker *circuit.Breaker) (cache launchcache.Cache, done func(), err error) {
	done = func() {}
	redisClient, err := launchredis.New(ctx, cfg.RedisConfig, obs)
	if err != nil {
		return nil, done, err
	}
	done = func() { redisClient.Close() }
	cache = launchcache.NewSharedCache(redisClient, breaker, cfg.CacheConfig, obs)
	return cache, done, nil
}
