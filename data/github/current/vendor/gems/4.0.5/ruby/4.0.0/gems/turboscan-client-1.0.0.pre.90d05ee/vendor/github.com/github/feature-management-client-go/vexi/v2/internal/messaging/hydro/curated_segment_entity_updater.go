package hydro

import (
	"context"
	"fmt"
	"time"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/messaging"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/puzpuzpuz/xsync/v3"
)

// CuratedSegmentEntityUpdater holds the logic of updating the segment entities for the hydro cache. This version is passed a xsync.map for storage.
type CuratedSegmentEntityUpdater struct {
	cache                 *xsync.MapOf[string, *segment.Segment]
	timestampCache        *xsync.MapOf[string, time.Time]
	parser                messaging.EntityParser
	cacheReadinessService CacheReadinessService
	telem                 internal.Telemetry
	logOnUpdate           bool
}

// NewCuratedSegmentEntityUpdater creates a new CuratedSegmentEntityUpdater.
func NewCuratedSegmentEntityUpdater(telem internal.Telemetry, cache *xsync.MapOf[string, *segment.Segment], timestampCache *xsync.MapOf[string, time.Time], parser messaging.EntityParser, cacheReadinessService CacheReadinessService, logOnUpdate bool) messaging.EntityUpdater {
	return &CuratedSegmentEntityUpdater{
		cache:                 cache,
		timestampCache:        timestampCache,
		parser:                parser,
		cacheReadinessService: cacheReadinessService,
		telem:                 telem,
		logOnUpdate:           logOnUpdate,
	}
}

// NotifyCaughtUp notifies the cache readiness service that the cache is ready for use.
func (u *CuratedSegmentEntityUpdater) NotifyCaughtUp(ctx context.Context) {
	u.cacheReadinessService.SetCuratedSegmentsCacheReady(ctx)
}

// UpdateEntity is called by the SyncMapProcessor when the SyncMap needs to be updated for a segment.
func (u *CuratedSegmentEntityUpdater) UpdateEntity(ctx context.Context, key, data []byte, updateTimestamp time.Time) error {
	if len(data) == 0 && len(key) == 0 {
		return vexi_errors.NewValidationError("empty payload and key")
	}

	segmentName := string(key)

	// Check if the updateTimestamp is newer than the value in the timestampCache or the value isn't in the timestampCache
	// If we have a value and this message is newer than the value we have do the delete or update, otherwise discard it.
	if ts, ok := u.timestampCache.Load(segmentName); ok && !updateTimestamp.After(ts) {
		return nil
	}

	// This indicates a tombstone message since payload is empty but key is not.
	if len(data) == 0 {
		// Delete key from sync maps
		u.cache.Delete(segmentName)
		u.timestampCache.Delete(segmentName)
		if u.logOnUpdate {
			u.telem.LogInfo(ctx, "deleted curated segment",
				kvp.String(telemetry.SegmentFieldName, segmentName),
				kvp.Time("hydro.message.timestamp", updateTimestamp))
		}
		return nil
	}

	seg, err := u.parser.ParseSegmentMessagePayload(data)
	if err != nil {
		return vexi_errors.NewWrappedError(err, fmt.Sprintf("failed to parse segment payload %v", data))
	}

	u.cache.Store(seg.Name, seg)
	u.timestampCache.Store(seg.Name, updateTimestamp)
	if u.logOnUpdate {
		u.telem.LogInfo(ctx, "updated curated segment",
			kvp.String(telemetry.SegmentFieldName, segmentName),
			kvp.Time("hydro.message.timestamp", updateTimestamp))
	}

	return nil
}
