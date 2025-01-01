package ghtwirp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"

	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/utils/requestid"
)

// IsFeatureEnabledForRepository checks if a feature is enabled for a repository
// Not compatible with dark-shipping features: it uses a cache and checks if the FF is enabled globally first.
func (c *client) IsFeatureEnabledForRepository(ctx context.Context, featureFlag string, id int64) bool {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	// First check if the FF is fully enabled for the best cache hit rate.
	if c.IsFeatureEnabledGlobally(ctx, featureFlag) {
		return true
	}

	tags := statter.Tags{"scope": "actor"}
	defer func() {
		c.obs.Counter(ctx, "feature_flag.get", tags, 1)
	}()

	// Repositories use the default flipper actor format of
	// ClassName:DatabaseID
	// https://github.com/github/github/blob/b432ebbc47ca7a11192343fbf1f727d76afddb06/packages/repositories/app/models/repository.rb#L27
	// https://github.com/github/github/blob/b432ebbc47ca7a11192343fbf1f727d76afddb06/lib/github/flipper_actor.rb#L104-L106
	actor := fmt.Sprintf("Repository:%d", id)

	cache := c.twirpCache.FeatureFlagActorCacheFor(actor, featureFlag)
	jsonFlag, ok, err := cache.Get(ctx)
	if err != nil {
		tags["cache_hit"] = strconv.FormatBool(false)
		tags["cache_error"] = strconv.FormatBool(true)
		c.obs.Report(ctx, fmt.Errorf("failed to look up cache: %w", err))
	} else if ok {
		tags["cache_hit"] = strconv.FormatBool(true)
		var isEnabled bool
		err := json.Unmarshal(jsonFlag, &isEnabled)
		if err != nil {
			c.obs.Report(ctx, errors.New("invalid feature flag response in cache"))
		} else {
			return isEnabled
		}
	}
	tags["cache_hit"] = strconv.FormatBool(false)

	ctx, err = c.setUserAgent(ctx)
	if err != nil {
		c.obs.Error(ctx, fmt.Errorf("error setting user agent: %w", err).Error())
		return false
	}
	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	isEnabled := c.isFeatureEnabledForFeatureActors(ctx, featureFlag, []string{actor})

	// caching for future use
	isEnabledJSON, err := json.Marshal(isEnabled)
	if err != nil {
		c.obs.Report(ctx, fmt.Errorf("marshaling token to json for Set: %w", err))
		return isEnabled
	}

	cerr := cache.Set(ctx, isEnabledJSON, isFeatureEnabledForActorCacheExpires)
	if cerr != nil {
		c.obs.Report(ctx, fmt.Errorf("failed to write in cache: %w", cerr))
	}

	return isEnabled
}
