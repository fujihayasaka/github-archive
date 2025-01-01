package launchchaos

import (
	"net/http"

	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/apphttp"
)

type GitHubFeatureFlagTwirpConfig struct {
	Addr, HMACSecret, Env string
	Cache                 launchcache.GitHubTwirpCache
	Opts                  []twirp.ClientOption
}

func SetupChaosMode(obs *observability.Observability, ffConfig GitHubFeatureFlagTwirpConfig, scenario string) (func(http.RoundTripper) http.RoundTripper, error) {
	githubTwirpClient, err := ghtwirp.NewClient(
		ffConfig.Addr,
		ffConfig.HMACSecret,
		obs,
		ffConfig.Env,
		ffConfig.Cache,
		apphttp.NewClient(), // Don't subject the FF checker to chaos
		ffConfig.Opts,
		launchconfig.IsMultiTenant(),
	)
	if err != nil {
		return nil, err
	}

	participator, err := NewFeatureFlagParticipator(DefaultFeatureFlag, githubTwirpClient.IsFeatureEnabledGlobally, DefaultParticipation)
	if err != nil {
		return nil, err
	}

	switch scenario {
	case GraphQLSlowError:
		return func(next http.RoundTripper) http.RoundTripper {
			return NewGraphQLSlowError(next, obs.Logger, participator)
		}, nil
	default:
		return nil, NewUnknownScenarioError(scenario)
	}
}
