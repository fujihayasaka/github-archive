// Package flipper is used to manage feature flags
//
// Flags are defined in flags.go or long_lived.go.
package flipper

import (
	"context"
	"fmt"
	"net/http"
	"sync"
	"time"

	twirpAuth "github.com/github/go-twirp/v2/client/auth"
	twirpRequestID "github.com/github/go-twirp/v2/client/requestid"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/o11y"
)

var ffs = initFeatureFlagService()

const cacheDuration = time.Minute * 1

// initFeatureFlagService is used to initialize the global singleton feature flag service.
// It loads values from the config for the twirp API URL and the HMAC secret to use
// when signing requests - these values will be different in development or in production.
// If something goes wrong loading the config, this method will panic.
// TODO maybe we should consider having a recovery feature flag service that just returns
// false for every ff check instead of panicking.
func initFeatureFlagService() *featureFlagService {
	noopFeatureFlagService := newNoopFeatureFlagService()

	cfg, err := config.Load()
	if err != nil {
		return noopFeatureFlagService
	}

	hmacSecret := cfg.GitHubTwirpHMACKey
	logger, loggerErr := cfg.NewLogger()

	featureFlagApiUrl := cfg.FeatureFlagServiceTwirpAddr
	if featureFlagApiUrl == "" {
		if loggerErr == nil {
			logger.Debug("Missing Feature Flag Twirp URL")
		}
		return noopFeatureFlagService
	}

	service, err := newFeatureFlagService(featureFlagApiUrl, hmacSecret, cfg.UserAgent())
	if err != nil {
		if loggerErr == nil {
			logger.Debug("Error initialising Feature Flag service: " + err.Error())
		}
		return noopFeatureFlagService
	}
	return service
}

func newNoopFeatureFlagService() *featureFlagService {
	return &featureFlagService{
		client: noopClient{},
	}
}

func newFeatureFlagService(twirpApiUrl string, hmacSecret string, userAgent *twirp.ClientHooks) (*featureFlagService, error) {
	hmac, err := twirpAuth.NewRequestHMACSigner(hmacSecret, http.DefaultClient)
	if err != nil {
		return nil, err
	}

	requestID := twirpRequestID.NewForwarder(hmac)

	client := twirpFeatures.NewFeaturesAPIProtobufClient(twirpApiUrl, requestID, twirp.WithClientHooks(userAgent))
	return &featureFlagService{
		client: client,
	}, nil
}

type featureFlagService struct {
	client twirpFeatures.FeaturesAPI
	cache  sync.Map
}

type boolWithTTL struct {
	value bool
	ttl   time.Time
}

// isOrgOrRepoEnabled returns whether the given feature flag is enabled for the org or repo
func (ffs *featureFlagService) isOrgOrRepoEnabled(ctx context.Context, orgID ts.OwnerEID, repoID ts.RepositoryEID, feature string) (bool, error) {
	res, err := ffs.isOrgEnabled(ctx, orgID, feature)
	if err == nil && res {
		return true, nil
	}
	return ffs.isRepoEnabled(ctx, repoID, feature)
}

// isRepoEnabled returns whether the given feature flag is enabled for the repo
func (ffs *featureFlagService) isRepoEnabled(ctx context.Context, repoID ts.RepositoryEID, feature string) (bool, error) {
	return ffs.checkActorFeature(ctx, fmt.Sprintf("Repository:%d", repoID), feature)
}

// isOrgEnabled returns whether the given feature flag is enabled for the org
func (ffs *featureFlagService) isOrgEnabled(ctx context.Context, orgID ts.OwnerEID, feature string) (bool, error) {
	return ffs.checkActorFeature(ctx, fmt.Sprintf("Organization:%d", orgID), feature)
}

// checkActorFeature checks whether the feature is enabled for the actor.
// We consider in order: Global overrides, Actor specific overrides, the Cache, and finally reach out to gh/gh.
func (ffs *featureFlagService) checkActorFeature(ctx context.Context, actor string, feature string) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if overrideValue, ok := getOverride(ctx, actor, feature); ok {
		return overrideValue, nil
	}

	key := fmt.Sprintf("%s:%s", actor, feature)
	return ffs.withCache(ctx, key, func(ctx context.Context) (bool, error) {
		// Check for global enablement
		globalReq := twirpFeatures.CheckGlobalFeatureRequest{
			Feature: feature,
		}
		globalResp, err := ffs.client.CheckGlobalFeature(ctx, &globalReq)
		if err != nil {
			return false, err
		}
		if globalResp.IsEnabled {
			return true, nil
		}

		// Check for actor specific enablement
		actorReq := twirpFeatures.CheckActorFeatureRequest{
			ActorId: actor,
			Feature: feature,
		}
		actorResp, err := ffs.client.CheckActorFeature(ctx, &actorReq)
		if err != nil {
			return false, err
		}
		return actorResp.IsEnabled, nil
	})
}

// withCache checks if the given key has a result in the cache, and if not, it calls the given function and caches the result.
func (ffs *featureFlagService) withCache(ctx context.Context, key string, fn func(context.Context) (bool, error)) (bool, error) {
	// Check if the key is in the cache, if so and it is not expired, then return the value.
	if cachedValue, ok := ffs.cache.Load(key); ok {
		if cachedValue, ok := cachedValue.(boolWithTTL); ok {
			if cachedValue.ttl.After(time.Now()) {
				return cachedValue.value, nil
			}
		}
	}

	// Actually call the function
	value, err := fn(ctx)
	if err != nil {
		return false, err
	}

	// Cache for future use
	ffs.cache.Store(key, boolWithTTL{value, time.Now().Add(cacheDuration)})
	return value, nil
}

type noopClient struct{}

func (n noopClient) CheckActorFeature(ctx context.Context, req *twirpFeatures.CheckActorFeatureRequest) (*twirpFeatures.CheckActorFeatureResponse, error) {
	return &twirpFeatures.CheckActorFeatureResponse{IsEnabled: noopOverride(ctx, req.ActorId, req.Feature)}, nil
}

func (n noopClient) CheckActorsFeature(context.Context, *twirpFeatures.CheckActorsFeatureRequest) (*twirpFeatures.CheckActorsFeatureResponse, error) {
	return &twirpFeatures.CheckActorsFeatureResponse{}, nil
}

func (n noopClient) CheckActorFeatures(context.Context, *twirpFeatures.CheckActorFeaturesRequest) (*twirpFeatures.CheckActorFeaturesResponse, error) {
	return &twirpFeatures.CheckActorFeaturesResponse{}, nil
}

func (n noopClient) CheckGlobalFeature(context.Context, *twirpFeatures.CheckGlobalFeatureRequest) (*twirpFeatures.CheckGlobalFeatureResponse, error) {
	return &twirpFeatures.CheckGlobalFeatureResponse{}, nil
}
