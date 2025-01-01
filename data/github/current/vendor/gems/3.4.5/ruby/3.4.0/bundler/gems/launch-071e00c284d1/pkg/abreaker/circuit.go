// This package takes care of a lot of boilerplate code for creating circuit breakers. The intent
// is to make sure that all circuit breakers are created with the intended configuration and are monitored
// in a standard way.
//
// If you find yourself needing to create a new configuration, there's a few things to do.
//
// 1. Add fields to BreakerConfig. See existing configurations for examples.
//
// 2. Depending on what kind of breaker is desired (currently rate and consecutive) create a new rateBreakerBuilder
// or consecutiveBreakerBuilder function in either rate.go or consecutive.go, respectively. Add the new function to
// rateBreakerBuilders or consecutiveBreakerBuilders in `cmd/grapher/dashboard.go`. This step is important, because
// it's how a auditing dashboard is automatically generated from our configuration.
//
// 2. Create a function in circuit.go that returns a circuit.Breaker with this new configuration. Example:
//
//	func NewSomeNewThingThatNeedsAUniqueBreakerConfigBreaker(ctx context.Context, obs *observability.Observability, cfg BreakerConfig) (*circuit.Breaker, error) {
//		return newRateBreaker(ctx, obs, BuildSomeNewThingThatNeedsAUniqueBreakerConfigConfig(cfg))
//	}
package abreaker

import (
	"context"
	"fmt"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
)

func NewGithubClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildGitHubClientConfig(cfg))
}

func NewGithubTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildGitHubTwirpClientConfig(cfg))
}

func NewGithubTwirpBillingClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildGitHubTwirpBillingClientConfig(cfg))
}

func NewAzpRepoClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildAzpRepoClientConfig(cfg))
}

func NewJobCLIAZPClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildJobCLIAZPClientConfig(cfg))
}

func NewAzpBearerTokenBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildAzpBearerTokenConfig(cfg))
}

func NewAzpKeyVaultBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildAzpKeyVaultConfig(cfg))
}

func NewAzpS2SBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newConsecutiveBreaker(ctx, obs, BuildAzpS2SConfig(cfg))
}

func NewRedisBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildRedisConfig(cfg))
}

func NewRedisReceiverBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildRedisReceiverConfig(cfg))
}

func NewAqueductDeployerClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildAqueductDeployerClientConfig(cfg))
}

func NewAqueductWorkerClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildAqueductWorkerClientConfig(cfg))
}

func NewSpokesdClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildSpokesdClientConfig(cfg))
}

func NewAuthzdClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newConsecutiveBreaker(ctx, obs, BuildAuthzdClientConfig(cfg))
}

func NewDeployerTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildDeployerTwirpClientConfig(cfg))
}

func NewJobCLITokenServiceBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newConsecutiveBreaker(ctx, obs, BuildJobCLITokenServiceConfig(cfg))
}

func NewFrenoClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildFrenoClientConfig(cfg))
}

func NewLaunchDBClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newConsecutiveBreaker(ctx, obs, BuildLaunchDBClientConfig(cfg))
}

func NewLaunchRODBClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newConsecutiveBreaker(ctx, obs, BuildLaunchRODBClientConfig(cfg))
}

func NewPayloadsClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newConsecutiveBreaker(ctx, obs, BuildPayloadsClientConfig(cfg))
}

func NewKredzTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildKredzTwirpClientConfig(cfg))
}

func NewVarzTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildVarzTwirpClientConfig(cfg))
}

func NewResultsTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildResultsTwirpClientConfig(cfg))
}

func NewRunServiceTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildRunServiceTwirpClientConfig(cfg))
}

func NewBillingPlatformTwirpClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildBillingPlatformTwirpClientConfig(cfg))
}

func NewNetworkServiceClientBreaker(ctx context.Context, obs *observability.Observability, cfg Config) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, BuildNetworkServiceClientConfig(cfg))
}

// NewNamedRateBreaker returns a rate breaker with a customized name, used so multiple transitions in GHES
// do not have a name conflict on the breaker monitor when using the same type of breaker
func NewNamedRateBreaker(ctx context.Context, obs *observability.Observability, cfg *RateBreakerConfig, name string) (*circuit.Breaker, error) {
	return newRateBreaker(ctx, obs, &RateBreakerConfig{
		Min:            cfg.Min,
		Rate:           cfg.Rate,
		WindowSize:     cfg.WindowSize,
		InitialBackoff: cfg.InitialBackoff,
		Name:           fmt.Sprintf("%s_%s", cfg.Name, name),
	})
}
