package hydro

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/github/feature-management-client-go/vexi/v2/internal"
	"github.com/github/feature-management-client-go/vexi/v2/internal/telemetry"
	"github.com/github/go-stats"
)

// CacheReadinessService stores the cache readiness state.
type CacheReadinessService interface {
	SetFeatureFlagsCacheReady(ctx context.Context)
	SetSegmentsCacheReady(ctx context.Context)
	SetCuratedSegmentsCacheReady(ctx context.Context)
	WaitForReady() chan struct{}
	CheckReady() bool
	CheckReadyFeatureFlagsOnly() bool
	CheckReadySegmentsOnly() bool
	CheckReadyCuratedSegmentsOnly() bool
}

type cacheReadinessService struct {
	t                         internal.Telemetry
	featureFlagsCacheReady    atomic.Bool
	segmentsCacheReady        atomic.Bool
	curatedSegmentsCacheReady atomic.Bool
	startTime                 time.Time
}

// NewCacheReadinessService creates a new CacheReadinessService instance.
func NewCacheReadinessService(t internal.Telemetry, areCuratedSegmentsEnabled bool) CacheReadinessService {
	s := &cacheReadinessService{
		t:         t,
		startTime: time.Now(),
	}
	s.curatedSegmentsCacheReady.Store(!areCuratedSegmentsEnabled)
	return s
}

// SetFeatureFlagsCacheReady sets the feature flags cache readiness state to ready.
func (s *cacheReadinessService) SetFeatureFlagsCacheReady(ctx context.Context) {
	s.featureFlagsCacheReady.Store(true)
	s.publishCacheReadinessLatencyTelemetry(ctx, "feature-flags")
}

// SetSegmentsCacheReady sets the segments cache readiness state to ready.
func (s *cacheReadinessService) SetSegmentsCacheReady(ctx context.Context) {
	s.segmentsCacheReady.Store(true)
	s.publishCacheReadinessLatencyTelemetry(ctx, "segments")
}

// SetCuratedSegmentsCacheReady sets the segments cache readiness state to ready.
func (s *cacheReadinessService) SetCuratedSegmentsCacheReady(ctx context.Context) {
	s.curatedSegmentsCacheReady.Store(true)
	s.publishCacheReadinessLatencyTelemetry(ctx, "curated-segments")
}

// WaitForReady will return a channel a service can wait on to signal that the caches are all ready.
func (s *cacheReadinessService) WaitForReady() chan struct{} {
	ready := make(chan struct{})
	go func() {
		for {
			if s.CheckReady() {
				close(ready)
				break
			}

			// TODO: This can be made a lot more performant by using a wait group that is signaled when each cache is ready.
			// Wait for 10 ms before checking again
			time.Sleep(10 * time.Millisecond)
		}
	}()

	return ready
}

// CheckReady returns the cache readiness state.
func (s *cacheReadinessService) CheckReady() bool {
	return s.featureFlagsCacheReady.Load() && s.segmentsCacheReady.Load() && s.curatedSegmentsCacheReady.Load()
}

// CheckReadyFeatureFlagsOnly returns the cache readiness state for feature flags.
func (s *cacheReadinessService) CheckReadyFeatureFlagsOnly() bool {
	return s.featureFlagsCacheReady.Load()
}

// CheckReadySegmentsOnly returns the cache readiness state for segments.
func (s *cacheReadinessService) CheckReadySegmentsOnly() bool {
	return s.segmentsCacheReady.Load()
}

// CheckReadyCuratedSegmentsOnly returns the cache readiness state for curated segments.
func (s *cacheReadinessService) CheckReadyCuratedSegmentsOnly() bool {
	return s.curatedSegmentsCacheReady.Load()
}

func (s *cacheReadinessService) publishCacheReadinessLatencyTelemetry(ctx context.Context, cacheName string) {
	// If the start time is not set log an error and return
	if s.startTime.IsZero() {
		s.t.LogError(ctx, "Start time not set for cache readiness timer")
		return
	}

	// Publish the time it took for the feature flag cache to be ready
	elapsedTime := time.Since(s.startTime)
	s.t.MetricDistributionMs(ctx, telemetry.HydroAdapterCacheRedinessDurationMetricName, stats.Tags{telemetry.CacheName: cacheName}, elapsedTime)

	if s.CheckReady() {
		// Publish the time it took for the cache to be ready
		s.t.MetricDistributionMs(ctx, telemetry.HydroAdapterCacheRedinessDurationMetricName, stats.Tags{telemetry.CacheName: "all"}, time.Since(s.startTime))
	}
}
