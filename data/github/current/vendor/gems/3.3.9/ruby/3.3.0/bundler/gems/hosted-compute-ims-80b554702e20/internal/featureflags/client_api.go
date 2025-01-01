package featureflags

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	twirpAuth "github.com/github/go-twirp/client/auth"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/models"
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

const (
	cacheExpiry          = 10 * time.Minute
	cacheCleanupInterval = 10 * time.Minute
)

//go:generate mockgen -destination ../../gen/mocks/mocks_featureflags/mock_dotcom_features_api.go -package mocks_featureflags github.com/github/monolith-twirp-features/core/v1 FeaturesAPI

type apiClient struct {
	cache       *gocache.Cache
	featuresAPI twirpFeatures.FeaturesAPI
	logger      *telemetry.ReportingLogger
}

func newApiClient(dotcomTwirpApiUrl, dotcomTwirpApiHmac string, logger *telemetry.ReportingLogger) (*apiClient, error) {
	httpClient := utils.NewRetryableHttpClientWithLogging("feature_flags", logger)
	httpClientWithAuth, err := twirpAuth.NewRequestHMACSigner(dotcomTwirpApiHmac, httpClient)
	if err != nil {
		return nil, fmt.Errorf("failed to create http client with auth: %w", err)
	}

	return &apiClient{
		cache:       gocache.New(cacheExpiry, cacheCleanupInterval),
		featuresAPI: twirpFeatures.NewFeaturesAPIProtobufClient(dotcomTwirpApiUrl, httpClientWithAuth),
		logger:      logger,
	}, nil
}

func (c *apiClient) IsFeatureFlagEnabledGlobally(ctx context.Context, feature FeatureFlag) bool {
	cacheKey := getCacheKeyGlobal(feature)

	cacheValue, found := c.cache.Get(cacheKey)
	c.logger.Statter.Counter("feature_flags.cache", stats.Tags{
		"feature":   string(feature),
		"level":     "stamp",
		"cache_hit": fmt.Sprintf("%t", found),
	}, 1)

	if found {
		return cacheValue.(bool)
	} else {
		featureEnabled, err := c.apiGetFeatureFlagGlobal(ctx, feature)
		if err != nil {
			c.logger.ErrorWithReport("failed to check global feature flag", err, kvp.String("feature", string(feature)))
			return false
		}

		c.cache.Set(cacheKey, featureEnabled, gocache.DefaultExpiration)
		return featureEnabled
	}
}

func (c *apiClient) IsFeatureFlagEnabledForActor(ctx context.Context, feature FeatureFlag, ownerId string) bool {
	if enabled := c.IsFeatureFlagEnabledGlobally(ctx, feature); enabled {
		return true
	}

	cacheKey := getCacheKeyOwnerId(feature, ownerId)

	cacheValue, found := c.cache.Get(cacheKey)
	c.logger.Statter.Counter("feature_flags.cache", stats.Tags{
		"feature":   string(feature),
		"level":     "owner",
		"cache_hit": fmt.Sprintf("%t", found),
	}, 1)

	if found {
		return cacheValue.(bool)
	} else {
		// Twirp Features API doesn't support using GlobalId and requires "actorType:actorId" format
		actor, err := models.DotcomActorFromGlobalID(ownerId)
		if err != nil {
			c.logger.ErrorWithReport("failed to decode ownerId", err, kvp.String("owner_id", ownerId))
			return false
		}

		featureEnabled, err := c.apiGetFeatureFlagForOwnerId(ctx, feature, actor.String())
		if err != nil {
			c.logger.ErrorWithReport("failed to check global feature flag", err,
				kvp.String("feature", string(feature)),
				kvp.String("owner_id", ownerId),
				kvp.String("actor", actor.String()),
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

func getCacheKeyOwnerId(feature FeatureFlag, ownerID string) string {
	return fmt.Sprintf("%s:%s", string(feature), ownerID)
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
