package abreaker

import (
	"context"
	"errors"
	"time"

	backoff "github.com/cenkalti/backoff/v4"
	circuit "github.com/rubyist/circuitbreaker"

	clock "github.com/github/launch/utils/clock"

	"github.com/github/launch/observability"
)

func newRateBreaker(ctx context.Context, obs *observability.Observability, cfg *RateBreakerConfig) (*circuit.Breaker, error) {
	err := cfg.validate()
	if err != nil {
		return nil, err
	}

	breaker := circuit.NewBreakerWithOptions(&circuit.Options{
		BackOff:    BuildExponentialBackoff(cfg),
		ShouldTrip: circuit.RateTripFunc(cfg.Rate, cfg.Min),
		WindowTime: time.Duration(cfg.WindowSize) * time.Second,
	})
	observability.MonitorCircuitBreaker(ctx, obs, cfg.Name, breaker)
	return breaker, nil
}

type RateBreakerConfig struct {
	Min  int64
	Rate float64
	// WindowSize is the duration of the evaluation window in seconds
	WindowSize int
	// Name is the name of the breaker, it's used as a metric name for the breaker
	Name string
	// Initial backoff duration
	InitialBackoff time.Duration
}

func (cfg *RateBreakerConfig) validate() error {
	if cfg.Rate == 0 || cfg.Min == 0 || cfg.WindowSize == 0 {
		return errors.New("invalid breaker configuration, min, rate, and windowsize must not be zero values")
	}
	return nil
}

type RateBreakerBuilder = func(cfg Config) *RateBreakerConfig

func buildRateBreakerConfig(min int64, rate float64, windowSize int, name string, initialBackoff time.Duration) *RateBreakerConfig {
	return &RateBreakerConfig{
		Min:            min,
		Rate:           rate,
		WindowSize:     windowSize,
		Name:           name,
		InitialBackoff: initialBackoff,
	}
}

func BuildGitHubClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.GitHubClientBreakerMin,
		cfg.GitHubClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.GitHubClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildGitHubTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.GitHubTwirpClientBreakerMin,
		cfg.GitHubTwirpClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.GitHubTwirpClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildGitHubTwirpBillingClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.GitHubTwirpBillingClientBreakerMin,
		cfg.GitHubTwirpBillingClientBreakerRate,
		cfg.GitHubTwirpBillingClientWindowSize,
		cfg.GitHubTwirpBillingClientBreakerName,
		cfg.GitHubTwirpBillingClientInitialBackoff,
	)
}

func BuildAzpRepoClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.AzpRepoClientBreakerMin,
		cfg.AzpRepoClientBreakerRate,
		cfg.AzpDefaultBreakerWindowSize,
		cfg.AzpRepoClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildJobCLIAZPClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.AzpJobCLIClientBreakerMin,
		cfg.AzpJobCLIClientBreakerRate,
		cfg.AzpDefaultBreakerWindowSize,
		cfg.AzpJobCLIClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildAzpBearerTokenConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.AzpBearerTokenBreakerMin,
		cfg.AzpBearerTokenBreakerRate,
		cfg.AzpDefaultBreakerWindowSize,
		cfg.AzpBearerTokenBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildAzpKeyVaultConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.AzpKeyVaultBreakerMin,
		cfg.AzpKeyVaultBreakerRate,
		cfg.AzpDefaultBreakerWindowSize,
		cfg.AzpKeyVaultBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildRedisConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.RedisBreakerMin,
		cfg.RedisBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.RedisBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildRedisReceiverConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.RedisReceiverBreakerMin,
		cfg.RedisReceiverBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.RedisReceiverBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildAqueductDeployerClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.AqueductDeployerClientBreakerMin,
		cfg.AqueductDeployerClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.AqueductDeployerClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildAqueductWorkerClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.AqueductWorkerClientBreakerMin,
		cfg.AqueductWorkerClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.AqueductWorkerClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildSpokesdClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.SpokesdClientBreakerMin,
		cfg.SpokesdClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.SpokesdClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildDeployerTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.DeployerTwirpClientBreakerMin,
		cfg.DeployerTwirpClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.DeployerTwirpClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildFrenoClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.FrenoClientBreakerMin,
		cfg.FrenoClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.FrenoClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildKredzTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.KredzTwirpClientBreakerMin,
		cfg.KredzTwirpClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.KredzTwirpClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildVarzTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.VarzTwirpClientBreakerMin,
		cfg.VarzTwirpClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.VarzTwirpClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildResultsTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.ResultsTwirpClientBreakerMin,
		cfg.ResultsTwirpClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.ResultsTwirpClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildRunServiceTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.RunServiceTwirpClientBreakerMin,
		cfg.RunServiceTwirpClientBreakerRate,
		cfg.DefaultBreakerWindowSize,
		cfg.RunServiceTwirpClientBreakerName,
		cfg.DefaultInitialBackoff,
	)
}

func BuildBillingPlatformTwirpClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.BillingPlatformTwirpClientBreakerMin,
		cfg.BillingPlatformTwirpClientBreakerRate,
		cfg.BillingPlatformTwirpClientWindowSize,
		cfg.BillingPlatformTwirpClientBreakerName,
		cfg.BillingPlatformTwirpClientInitialBackoff,
	)
}

func BuildNetworkServiceClientConfig(cfg Config) *RateBreakerConfig {
	return buildRateBreakerConfig(
		cfg.NetworkServiceClientBreakerMin,
		cfg.NetworkServiceClientBreakerRate,
		cfg.NetworkServiceClientWindowSize,
		cfg.NetworkServiceClientBreakerName,
		cfg.NetworkServiceClientInitialBackoff,
	)
}

func BuildExponentialBackoff(cfg *RateBreakerConfig) *backoff.ExponentialBackOff {
	backoff := backoff.NewExponentialBackOff()
	backoff.InitialInterval = cfg.InitialBackoff
	backoff.MaxElapsedTime = 0 * time.Second
	backoff.Clock = clock.New()
	backoff.Reset()

	return backoff
}
