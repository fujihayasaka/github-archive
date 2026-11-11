package hydro

import (
	"context"
	"fmt"
	"slices"
	"time"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/puzpuzpuz/xsync/v3"
)

// curatedSegmentMap defines a mapping from custom gates to their corresponding curated segments.
var curatedSegmentMap = map[string][]string{
	"preview_features": {
		"staff_users",
		"staff_repos",
	},
	"github_stars_members": {
		"github_stars_members",
	},
	"shopify_members": {
		"shopify_members",
	},
	"microsoft_team_members": {
		"microsoft_team_members_01",
		"microsoft_team_members_02",
		"microsoft_team_members_03",
		"microsoft_team_members_04",
		"microsoft_team_members_05",
		"microsoft_team_members_06",
		"microsoft_team_members_07",
		"microsoft_team_members_08",
		"microsoft_team_members_09",
		"microsoft_team_members_10",
	},
}

// FeatureFlagEntityUpdater holds the logic of updating the feature flag entities for the hydro cache. This version is passed a xsync.map for storage.
type FeatureFlagEntityUpdater struct {
	cache                  *xsync.MapOf[string, *featureflag.FeatureFlag]
	parser                 messaging.EntityParser
	cacheReadinessService  CacheReadinessService
	curatedSegmentsEnabled bool
	telem                  internal.Telemetry
	logOnUpdate            bool
	owningServices         []string
}

// NewFeatureFlagEntityUpdater creates a new FeatureFlagEntityUpdater.
func NewFeatureFlagEntityUpdater(telem internal.Telemetry, cache *xsync.MapOf[string, *featureflag.FeatureFlag], parser messaging.EntityParser, cacheReadinessService CacheReadinessService, curatedSegmentsEnabled, logOnUpdate bool, owningServices []string) messaging.EntityUpdater {
	return &FeatureFlagEntityUpdater{
		cache:                  cache,
		parser:                 parser,
		cacheReadinessService:  cacheReadinessService,
		curatedSegmentsEnabled: curatedSegmentsEnabled,
		telem:                  telem,
		logOnUpdate:            logOnUpdate,
		owningServices:         owningServices,
	}
}

// NotifyCaughtUp notifies the cache readiness service that the cache is ready for use.
func (u *FeatureFlagEntityUpdater) NotifyCaughtUp(ctx context.Context) {
	u.cacheReadinessService.SetFeatureFlagsCacheReady(ctx)
}

// UpdateEntity is called by the SyncMapProcessor when the SyncMap needs to be updated for a feature flag.
func (u *FeatureFlagEntityUpdater) UpdateEntity(ctx context.Context, key, data []byte, msgTimestamp time.Time) error {
	if len(data) == 0 && len(key) == 0 {
		return vexi_errors.NewValidationError("empty payload and key")
	}

	featureFlagName := string(key)
	featureFlagFromCache, foundInCache := u.cache.Load(featureFlagName)

	// This indicates a tombstone message since payload is empty but key is not.
	// If the message is not a tombstone we'll instead compare the UpdatedAt values of the entity
	// If the message is a tombstone, there is no UpdatedAt value so we instead use the msgTimestamp.
	if len(data) == 0 {
		if !foundInCache {
			// If the message is a tombstone and we don't have the feature flag in the cache, we can ignore it.
			if u.logOnUpdate {
				u.telem.LogDebug(
					ctx,
					"Ignoring tombstone message for feature flag that does not exist in cache",
					kvp.String(telemetry.FeatureFlagFieldName, featureFlagName),
					kvp.Time("hydro.message.timestamp", msgTimestamp))
			}
			return nil
		}

		// If the message is a tombstone and we have the feature flag in the cache, check if the message timestamp is not earlier than the last update time of the feature flag in the cache. ie. The timestamp
		// of the incoming update is later or equal to the last update time of the feature flag in the cache. If so then go ahead and delete the feature flag from the cache.
		if !msgTimestamp.Before(featureFlagFromCache.UpdatedAt) {
			// Delete key from sync maps
			u.cache.Delete(featureFlagName)
			if u.logOnUpdate {
				u.telem.LogInfo(
					ctx,
					"Deleted feature flag",
					kvp.String(telemetry.FeatureFlagFieldName, featureFlagName),
					kvp.String(telemetry.OwningServiceField, featureFlagFromCache.OwningService),
					kvp.Time("hydro.message.timestamp", msgTimestamp))
			}
			return nil
		}

		if u.logOnUpdate {
			u.telem.LogDebug(
				ctx,
				"Ignoring tombstone because it is not more recent than what is in the cache",
				kvp.String(telemetry.FeatureFlagFieldName, featureFlagName),
				kvp.String(telemetry.OwningServiceField,
					featureFlagFromCache.OwningService),
				kvp.Time("hydro.message.timestamp", msgTimestamp))
		}
		// Always skip parsing for tombstone messages
		return nil
	}

	incomingFeatureFlagUpdate, err := u.parser.ParseFeatureFlagMessagePayload(data)
	if err != nil {
		return vexi_errors.NewWrappedError(err, fmt.Sprintf("failed to parse feature flag payload %v", data))
	}

	// Check if the feature flag from the incoming message has a timestamp older than the one in the cache, if so we can ignore the update.
	if foundInCache && incomingFeatureFlagUpdate.UpdatedAt.Before(featureFlagFromCache.UpdatedAt) {
		return nil
	}

	// Ignore flag if it's not for our service
	if len(u.owningServices) > 0 && !slices.Contains(u.owningServices, incomingFeatureFlagUpdate.OwningService) {
		return nil
	}

	if u.curatedSegmentsEnabled {
		for customGate, segments := range curatedSegmentMap {
			u.addCuratedSegments(incomingFeatureFlagUpdate, customGate, segments...)
		}
	}

	u.cache.Store(incomingFeatureFlagUpdate.Name, incomingFeatureFlagUpdate)
	if u.logOnUpdate {
		u.telem.LogInfo(
			ctx,
			"Updated feature flag",
			kvp.String(telemetry.FeatureFlagFieldName, incomingFeatureFlagUpdate.Name),
			kvp.String(telemetry.OwningServiceField, incomingFeatureFlagUpdate.OwningService),
			kvp.Time("timestamp", incomingFeatureFlagUpdate.UpdatedAt))
	}

	return nil
}

// addCuratedSegments replaces a custom gate on a feature flag with a set of curated segments.
func (u *FeatureFlagEntityUpdater) addCuratedSegments(featureFlag *featureflag.FeatureFlag, customGate string, curatedSegments ...string) {
	if index := slices.Index(featureFlag.CustomGates, customGate); index != -1 {
		featureFlag.CustomGates = slices.Delete(featureFlag.CustomGates, index, index+1)
		for _, segment := range curatedSegments {
			if !slices.Contains(featureFlag.Segments, segment) {
				featureFlag.Segments = append(featureFlag.Segments, segment)
			}
		}
	}
}
