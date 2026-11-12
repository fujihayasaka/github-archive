package hydro

import (
	"context"
	"fmt"
	"slices"
	"time"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/puzpuzpuz/xsync/v3"
)

// SegmentEntityUpdater holds the logic of updating the segment entities for the hydro cache. This version is passed a xsync.map for storage.
type SegmentEntityUpdater struct {
	cache                 *xsync.MapOf[string, *segment.Segment]
	parser                messaging.EntityParser
	cacheReadinessService CacheReadinessService
	telem                 internal.Telemetry
	logOnUpdate           bool
	owningServices        []string
}

// NewSegmentEntityUpdater creates a new SegmentEntityUpdater.
func NewSegmentEntityUpdater(telem internal.Telemetry, cache *xsync.MapOf[string, *segment.Segment], parser messaging.EntityParser, cacheReadinessService CacheReadinessService, logOnUpdate bool, owningServices []string) messaging.EntityUpdater {
	return &SegmentEntityUpdater{
		cache:                 cache,
		parser:                parser,
		cacheReadinessService: cacheReadinessService,
		telem:                 telem,
		logOnUpdate:           logOnUpdate,
		owningServices:        owningServices,
	}
}

// NotifyCaughtUp notifies the cache readiness service that the cache is ready for use.
func (u *SegmentEntityUpdater) NotifyCaughtUp(ctx context.Context) {
	u.cacheReadinessService.SetSegmentsCacheReady(ctx)
}

// UpdateEntity is called by the SyncMapProcessor when the SyncMap needs to be updated for a segment.
func (u *SegmentEntityUpdater) UpdateEntity(ctx context.Context, key, data []byte, msgTimestamp time.Time) error {
	if len(data) == 0 && len(key) == 0 {
		return vexi_errors.NewValidationError("empty payload and key")
	}

	segmentName := string(key)
	segmentFromCache, foundInCache := u.cache.Load(segmentName)

	// This indicates a tombstone message since payload is empty but key is not.
	// If the message is not a tombstone we'll instead compare the UpdatedAt values of the entity
	// If the message is a tombstone, there is no UpdatedAt value so we instead use the msgTimestamp.
	if len(data) == 0 {
		if !foundInCache {
			// If the message is a tombstone and we don't have the segment in the cache, we can ignore it.
			if u.logOnUpdate {
				u.telem.LogDebug(ctx, "Ignoring tombstone message for segment that does not exist in cache",
					kvp.String(telemetry.SegmentFieldName, segmentName),
					kvp.Time("hydro.message.timestamp", msgTimestamp))
			}
			return nil
		}

		// If the message is a tombstone and we have the segment in the cache, check if the message timestamp is not earlier than the last update time of the segment in the cache. ie. The timestamp
		// of the incoming update is later or equal to the last update time of the segment in the cache. If so then go ahead and delete the segment from the cache.
		if !msgTimestamp.Before(segmentFromCache.UpdatedAt) {
			// Delete key from sync maps
			u.cache.Delete(segmentName)
			if u.logOnUpdate {
				u.telem.LogInfo(ctx, "Deleted segment",
					kvp.String(telemetry.SegmentFieldName, segmentName),
					kvp.String(telemetry.OwningServiceField, segmentFromCache.OwningService),
					kvp.Time("hydro.message.timestamp", msgTimestamp))
			}
			return nil
		}

		if u.logOnUpdate {
			u.telem.LogDebug(ctx, "Ignoring tombstone because it is not more recent than what is in the cache",
				kvp.String(telemetry.SegmentFieldName, segmentName),
				kvp.String(telemetry.OwningServiceField, segmentFromCache.OwningService),
				kvp.Time("hydro.message.timestamp", msgTimestamp))
		}
		// Always skip parsing for tombstone messages
		return nil
	}

	incomingSegmentUpdate, err := u.parser.ParseSegmentMessagePayload(data)
	if err != nil {
		return vexi_errors.NewWrappedError(err, fmt.Sprintf("failed to parse segment payload %v", data))
	}

	// Check if the segment from the incoming message has a timstamp older than the one in the cache, if so we can ignore the update.
	if foundInCache && incomingSegmentUpdate.UpdatedAt.Before(segmentFromCache.UpdatedAt) {
		return nil
	}

	shouldCheckOwning := incomingSegmentUpdate.OwningService != "" && len(u.owningServices) > 0
	if shouldCheckOwning && !slices.Contains(u.owningServices, incomingSegmentUpdate.OwningService) {
		return nil
	}

	u.cache.Store(incomingSegmentUpdate.Name, incomingSegmentUpdate)
	if u.logOnUpdate {
		u.telem.LogInfo(ctx, "Updated segment",
			kvp.String(telemetry.SegmentFieldName, segmentName),
			kvp.String(telemetry.OwningServiceField, incomingSegmentUpdate.OwningService),
			kvp.Time("timestamp", incomingSegmentUpdate.UpdatedAt))
	}

	return nil
}
