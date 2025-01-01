package featureflag

import (
	"context"
	"fmt"
	"sync"
	"time"

	featurescore "github.com/github/monolith-twirp-features/core/v1"
)

const DefaultCacheDuration = time.Minute * 1

type FlagChecker interface {
	CheckGlobalFeature(ctx context.Context, feature string) (bool, error)
	CheckActorFeature(ctx context.Context, feature string, actorId string) (bool, error)
}

type FeatureFlagClient struct {
	FeaturesAPI   featurescore.FeaturesAPI
	cacheClock    CacheClock
	cacheDuration time.Duration
	cache         sync.Map
}

// CacheClock is a mockable interface for manipulating time for the cache
type CacheClock interface {
	Now() time.Time
	Later(d time.Duration) time.Time
}

// NewFeatureFlagClient creates a new FeatureFlagClient with a real clock
func NewFeatureFlagClient(featuresAPI featurescore.FeaturesAPI) *FeatureFlagClient {
	return NewFeatureFlagClientWithClock(featuresAPI, realClock{})
}

// NewFeatureFlagClientWithClock creates a new FeatureFlagClient with a
// custom clock (i.e. for testing)
func NewFeatureFlagClientWithClock(
	featuresAPI featurescore.FeaturesAPI,
	cacheClock CacheClock,
) *FeatureFlagClient {
	return &FeatureFlagClient{
		FeaturesAPI:   featuresAPI,
		cacheClock:    cacheClock,
		cacheDuration: DefaultCacheDuration,
	}
}

// CheckGlobalFeature checks if a global (boolean) feature is enabled
func (c *FeatureFlagClient) CheckGlobalFeature(ctx context.Context, feature string) (bool, error) {
	req := &featurescore.CheckGlobalFeatureRequest{Feature: feature}
	resp, err := c.FeaturesAPI.CheckGlobalFeature(ctx, req)

	if err != nil {
		return false, fmt.Errorf("checking global feature %q: %v", feature, err)
	}

	return resp.IsEnabled, nil
}

// CheckActorFeature checks if a feature is enabled globally or for a given actor
// An actorId is a string that consists of the actor's type and MySQL database
// id (primary key), separated by a colon. Example: "User:1234" so
// `fmt.Sprintf("Repository:%d", uint(repoID))` would be a way one could
// construct that.
//
// The mapping for actor types can be found at:
// https://github.com/github/github/blob/bc0726a89d8e70b4258e6692f2c5fa49f1d73b4e/lib/github/flipper_actor.rb#L90
func (c *FeatureFlagClient) CheckActorFeature(
	ctx context.Context,
	feature string,
	actorId string,
) (bool, error) {
	key := fmt.Sprintf("%s:%s", actorId, feature)
	return c.withCache(ctx, key, func(ctx context.Context) (bool, error) {
		// If the feature flag is enabled globally, then return true and skip actor-specific check
		globalReq := &featurescore.CheckGlobalFeatureRequest{Feature: feature}
		globalRes, err := c.FeaturesAPI.CheckGlobalFeature(ctx, globalReq)
		if err != nil {
			return false, fmt.Errorf("checking global feature %q: %v", feature, err)
		} else if globalRes.IsEnabled {
			return true, nil
		}

		// Check if the feature is enabled for the actor
		actorReq := &featurescore.CheckActorFeatureRequest{Feature: feature, ActorId: actorId}
		actorRes, err := c.FeaturesAPI.CheckActorFeature(ctx, actorReq)
		if err != nil {
			return false, fmt.Errorf("checking actor feature %q: %v", feature, err)
		}
		return actorRes.IsEnabled, nil
	})
}

type cachedBool struct {
	value   bool
	expires time.Time
}

type realClock struct{}

func (realClock) Now() time.Time {
	return time.Now().UTC()
}
func (realClock) Later(d time.Duration) time.Time {
	return time.Now().UTC().Add(d)
}

func (c *FeatureFlagClient) withCache(
	ctx context.Context,
	key string,
	fn func(context.Context) (bool, error),
) (bool, error) {
	// Check if the key is in the cache, if so and it is not expired, then return the value.
	if cachedValue, ok := c.cache.Load(key); ok {
		if cachedValue, ok := cachedValue.(cachedBool); ok {
			if cachedValue.expires.After(c.cacheClock.Now().UTC()) {
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
	expires := c.cacheClock.Later(c.cacheDuration)
	c.cache.Store(key, cachedBool{value, expires})
	return value, nil
}

type NullFeatureFlagClient struct{}

// NewNullFeatureFlagClient creates a new NullFeatureFlagClient
func NewNullFeatureFlagClient() *NullFeatureFlagClient {
	return &NullFeatureFlagClient{}
}

// CheckGlobalFeature checks if a global feature is enabled
func (c *NullFeatureFlagClient) CheckGlobalFeature(ctx context.Context, feature string) (bool, error) {
	return false, nil
}

// CheckActorFeature checks if a feature is enabled globally or for a given actor
func (c *NullFeatureFlagClient) CheckActorFeature(ctx context.Context, feature string, actorId string) (bool, error) {
	return false, nil
}
