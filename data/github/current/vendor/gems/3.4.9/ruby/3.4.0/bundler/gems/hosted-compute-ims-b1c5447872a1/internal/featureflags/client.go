package featureflags

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-core/telemetry"
)

type IFeatureFlagsClient interface {
	IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool
	IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, actorGlobalId string) bool
}

func NewFeatureFlagsClient(ctx context.Context, cfg *Config, logger *telemetry.ReportingLogger, stamp string) (IFeatureFlagsClient, error) {
	if cfg.DotcomTwirpApiUrl != "" {
		resolvedTwirpUrl := cfg.GetTwirpApiUrlForStamp(stamp)
		apiClient, err := newApiClient(resolvedTwirpUrl, cfg.DotcomTwirpApiHmac, stamp, logger)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize api client: %w", err)
		}

		if !cfg.AllowFallbackToLocal || apiClient.IsApiAvailable(ctx) {
			logger.Info("initialized feature flags api client", kvp.String("stamp", stamp), kvp.String("url", resolvedTwirpUrl))
			return apiClient, nil
		}

		logger.Info("features API is not available. Falling back to local feature flags")
		return newLocalClientFromConfig(logger), nil
	}

	if !cfg.AllowFallbackToLocal {
		return nil, fmt.Errorf("failed to initialize feature flag client because features API is not configured")
	}

	logger.Info("features API is not configured. Falling back to local feature flags")
	return newLocalClientFromConfig(logger), nil
}
