package featureflags

import (
	"context"
	"fmt"
	"time"

	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	twirpAuth "github.com/github/go-twirp/v2/client/auth"
	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
	"github.com/github/hosted-compute-ims/internal/utils"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	gocache "github.com/patrickmn/go-cache"
)

// The current implementation of the feature flags client uses Twirp Features API provided by dotcom
// https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp/
// This API has a couple of limitations that we need to be aware of:
// - Don't support enabling FF by billing owner (if FF is enabled for Enteprise, it won't apply for all organization. Every organization in the enterprise needs to enable it separately)
//
// These limitations are not critical for now, but we will probably want to revisit the current approach in future.
// Potentially, we can add own dotcom twirp method to validate FF for billing owner and environment.

var _ IFeatureFlagsClient = (*apiClient)(nil)

const (
	cacheExpiry          = 10 * time.Minute
	cacheCleanupInterval = 10 * time.Minute
)

//go:generate mockgen -destination ../../gen/mocks/mocks_featureflags/mock_dotcom_features_api.go -package mocks_featureflags github.com/github/monolith-twirp-features/core/v1 FeaturesAPI

type apiClient struct {
	cache       *gocache.Cache
	featuresAPI twirpFeatures.FeaturesAPI
	stamp       string
}

func newApiClient(ctx context.Context, dotcomTwirpApiUrl, dotcomTwirpApiHmac, stamp string) (*apiClient, error) {
	httpClient := utils.NewRetryableHttpClientWithLogging("feature_flags")
	httpClientWithAuth, err := twirpAuth.NewRequestHMACSigner(dotcomTwirpApiHmac, httpClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create http client with auth: %w", err)
	}

	logger.Info(ctx, "initializing feature flag api client",
		kvp.String("stamp", stamp),
		kvp.String("url", dotcomTwirpApiUrl),
	)

	return &apiClient{
		cache:       gocache.New(cacheExpiry, cacheCleanupInterval),
		featuresAPI: twirpFeatures.NewFeaturesAPIProtobufClient(dotcomTwirpApiUrl, httpClientWithAuth),
		stamp:       stamp,
	}, nil
}

func (c *apiClient) IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	cacheKey := getCacheKeyGlobal(feature)

	cacheValue, found := c.cache.Get(cacheKey)
	statter.Increment(ctx, "feature_flags.cache",
		kvp.String("stamp", c.stamp),
		kvp.String("feature", string(feature)),
		kvp.String("level", "global"),
		kvp.Bool("cache_hit", found),
	)

	if found {
		return cacheValue.(bool)
	} else {
		featureEnabled, err := c.apiGetFeatureFlagGlobal(ctx, feature)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to check global feature flag", err,
				kvp.String("stamp", c.stamp),
				kvp.String("feature", string(feature)),
			)
			return false
		}

		c.cache.Set(cacheKey, featureEnabled, gocache.DefaultExpiration)
		return featureEnabled
	}
}

func (c *apiClient) IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, vexiActor vexi.Actor) bool {
	if vexiActor == nil {
		logger.Error(ctx, "actor is nil, cannot check feature flag, defaulting false")
		return false
	}

	actor, castOk := vexiActor.(models.Actor)
	if !castOk {
		// only owner actor is supported in FeaturesAPI
		return false
	}

	if enabled := c.IsFeatureFlagEnabledGlobally(ctx, feature); enabled {
		return true
	}

	cacheKey := getCacheKeyActor(feature, actor.GlobalId())

	cacheValue, found := c.cache.Get(cacheKey)
	statter.Increment(ctx, "feature_flags.cache",
		kvp.String("stamp", c.stamp),
		kvp.String("feature", string(feature)),
		kvp.String("level", "actor"),
		kvp.Bool("cache_hit", found),
	)

	if found {
		return cacheValue.(bool)
	} else {
		featureEnabled, err := c.apiGetFeatureFlagForOwnerId(ctx, feature, actor.DotcomActor().String())
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to check global feature flag", err,
				kvp.String("stamp", c.stamp),
				kvp.String("feature", string(feature)),
				kvp.String("actor_global_id", actor.GlobalId()),
				kvp.String("actor_decoded", actor.DotcomActor().String()),
			)
			return false
		}

		c.cache.Set(cacheKey, featureEnabled, gocache.DefaultExpiration)
		return featureEnabled
	}
}

func (c *apiClient) IsApiAvailable(ctx context.Context) bool {
	_, err := c.featuresAPI.CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{
		Feature: "some_unknown_and_invalid_feature_flag",
	})

	// Features API returns "false" if feature flag doesn't exist
	// So, passing some random FF to check if API is available
	return err == nil
}

func getCacheKeyGlobal(feature FeatureFlag) string {
	return string(feature)
}

func getCacheKeyActor(feature FeatureFlag, actorGlobalId string) string {
	return fmt.Sprintf("%s:%s", string(feature), actorGlobalId)
}

func (c *apiClient) apiGetFeatureFlagGlobal(ctx context.Context, feature FeatureFlag) (bool, error) {
	resp, err := c.featuresAPI.CheckGlobalFeature(ctx, &twirpFeatures.CheckGlobalFeatureRequest{
		Feature: string(feature),
	})
	if err != nil {
		return false, fmt.Errorf("failed to get global feature flag state via featuresApi: %w", err)
	}

	return resp.IsEnabled, nil
}

func (c *apiClient) apiGetFeatureFlagForOwnerId(ctx context.Context, feature FeatureFlag, actorId string) (bool, error) {
	resp, err := c.featuresAPI.CheckActorFeature(ctx, &twirpFeatures.CheckActorFeatureRequest{
		ActorId: actorId,
		Feature: string(feature),
	})
	if err != nil {
		return false, fmt.Errorf("failed to get feature flag state for owner via featuresApi: %w", err)
	}

	return resp.IsEnabled, nil
}
