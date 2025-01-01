package featureflags

import (
	"context"
	"fmt"

	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
)

const (
	// Working through an issue with Vexi - disabling until it's resolved
	VexiEnabled = true
)

type IFeatureFlagsClient interface {
	IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool
	IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, actor vexi.Actor) bool
}

func NewFeatureFlagsClient(ctx context.Context, cfg *Config, stamp string) (IFeatureFlagsClient, error) {
	// For now we're only using Vexi for the dotcom stamp, flags related to other proxima stamps
	// need to go via the twirp features api still.
	if stamp == "dotcom" && VexiEnabled {
		logger.Info(ctx, "initializing vexi client")
		client, err := newVexiClient(ctx, cfg, stamp)
		if err != nil {
			// TODO: Do we want to continue here? Probably best up with no flags
			//       instead of hard down
			return nil, fmt.Errorf("failed to initialize vexi client")
		}

		return client, nil
	}

	if cfg.DotcomTwirpApiUrl != "" {
		resolvedTwirpUrl := cfg.GetTwirpApiUrlForStamp(stamp)
		apiClient, err := newApiClient(ctx, resolvedTwirpUrl, cfg.DotcomTwirpApiHmac, stamp)
		if err != nil {
			return nil, fmt.Errorf("failed to initialize api client: %w", err)
		}

		if !cfg.AllowFallbackToLocal || apiClient.IsApiAvailable(ctx) {
			logger.Info(ctx, "initialized feature flags api client",
				kvp.String("stamp", stamp),
				kvp.String("url", resolvedTwirpUrl),
			)
			return apiClient, nil
		}

		logger.Info(ctx, "features API is not available. Falling back to local feature flags")
		return newLocalClientFromConfig(ctx), nil
	}

	if !cfg.AllowFallbackToLocal {
		return nil, fmt.Errorf("failed to initialize feature flag client because features API is not configured")
	}

	logger.Info(ctx, "features API is not configured. Falling back to local feature flags")
	return newLocalClientFromConfig(ctx), nil
}
