package experiments

import (
	"context"
	"fmt"
	"maps"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/observability"
)

const (
	// DefaultCacheTTL is the default time-to-live for cached assignments.
	DefaultCacheTTL = 10 * time.Minute
	// DefaultMaxCacheSize is the default maximum size for the assignments cache.
	DefaultMaxCacheSize = 1000
	// DefaultCleanupInterval is the default interval for cleaning up expired cache entries.
	DefaultCleanupInterval = 1 * time.Minute
)

// CacheKey represents the key for caching assignments based on request parameters.
type CacheKey struct {
	RandomizationUnit string // String representation of the randomization unit
	TrafficFilters    string // String representation of traffic filters
}

// AssignmentsCache manages multiple cached assignments with different cache keys.
type AssignmentsCache struct {
	mu      sync.RWMutex
	entries map[CacheKey]*Assignments
	ctx     context.Context
	config  CacheConfig
	obsv    observability.Exporters
}

// CacheConfig holds configuration parameters for the assignments cache.
type CacheConfig struct {
	TTL             time.Duration
	MaxSize         int
	CleanupInterval time.Duration
}

// NewDefaultCacheConfig returns a CacheConfig with default values.
func NewDefaultCacheConfig() CacheConfig {
	return CacheConfig{
		TTL:             DefaultCacheTTL,
		MaxSize:         DefaultMaxCacheSize,
		CleanupInterval: DefaultCleanupInterval,
	}
}

// NewAssignmentsCache creates a new empty assignments cache and starts the background cleanup worker.
func NewAssignmentsCache(ctx context.Context, obsv observability.Exporters, cacheConfig CacheConfig) *AssignmentsCache {
	return newAssignmentsCacheWithWorker(ctx, obsv, cacheConfig, true)
}

// NewAssignmentsCacheWithWorker creates a new assignments cache with optional background worker.
func newAssignmentsCacheWithWorker(ctx context.Context, obsv observability.Exporters, cacheConfig CacheConfig, startWorker bool) *AssignmentsCache {
	ac := &AssignmentsCache{
		entries: make(map[CacheKey]*Assignments),
		ctx:     ctx,
		config:  cacheConfig,
		obsv:    obsv,
	}

	if startWorker {
		// Start background cleanup worker
		go ac.backgroundWorker()
	}

	return ac
}

// Get retrieves cached assignments for the given cache key if valid and not expired.
func (ac *AssignmentsCache) Get(cacheKey CacheKey) *Assignments {
	ac.mu.RLock()
	assignment, exists := ac.entries[cacheKey]
	if !exists {
		ac.mu.RUnlock()
		return nil
	}

	if !assignment.expired(ac.config.TTL) {
		ac.mu.RUnlock()
		return assignment
	}
	ac.mu.RUnlock()

	// Expired, remove from cache
	ac.mu.Lock()
	defer ac.mu.Unlock()
	delete(ac.entries, cacheKey)
	return nil
}

// Set stores assignments in the cache with the given cache key.
func (ac *AssignmentsCache) Set(cacheKey CacheKey, assignments *Assignments) {
	ac.mu.Lock()
	defer ac.mu.Unlock()

	ac.entries[cacheKey] = assignments
}

// backgroundWorker runs periodic cleanup tasks.
func (ac *AssignmentsCache) backgroundWorker() {
	ticker := time.NewTicker(ac.config.CleanupInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ac.ctx.Done():
			return
		case <-ticker.C:
			ac.cleanupExpired()
			ac.reduceCacheSize()
		}
	}
}

// reduceCacheSize removes the oldest entries when cache exceeds maxCacheSize.
func (ac *AssignmentsCache) reduceCacheSize() {
	ac.mu.Lock()
	defer ac.mu.Unlock()

	if len(ac.entries) <= ac.config.MaxSize {
		return
	}

	ac.obsv.LoggerWithTelemetry(ac.ctx).Warn("assignments cache size exceeded max size, reducing cache", kvp.Int("currentSize", len(ac.entries)), kvp.Int("maxSize", ac.config.MaxSize))

	// Create a slice of entries with their keys and last update times
	type entryWithKey struct {
		key        CacheKey
		lastUpdate time.Time
	}

	entries := make([]entryWithKey, 0, len(ac.entries))
	for key, assignment := range ac.entries {
		entries = append(entries, entryWithKey{
			key:        key,
			lastUpdate: assignment.lastUpdate,
		})
	}

	// Sort by last update time (oldest first)
	slices.SortFunc(entries, func(a, b entryWithKey) int {
		if a.lastUpdate.Before(b.lastUpdate) {
			return -1
		} else if b.lastUpdate.Before(a.lastUpdate) {
			return 1
		}
		return 0
	})

	// Remove oldest entries until we're at 80% of max size to avoid frequent cleanups
	targetSize := int(float64(ac.config.MaxSize) * 0.8)
	numToRemove := len(ac.entries) - targetSize

	for _, entry := range entries[:numToRemove] {
		delete(ac.entries, entry.key)
	}
}

func (ac *AssignmentsCache) cleanupExpired() {
	ac.mu.Lock()
	defer ac.mu.Unlock()

	for key, assignment := range ac.entries {
		if assignment.expired(ac.config.TTL) {
			delete(ac.entries, key)
		}
	}
}

// Assignments is the cache for feature assignments.
type Assignments struct {
	Response          *CopilotExpAssignmentResponse
	Features          map[string]any
	AssignmentContext string
	lastUpdate        time.Time
}

// Assignment represents a single feature assignment.
type Assignment struct {
	Variation any
	Context   string
}

// NewVSCodeAssignments extracts all the feature key/value pairs from the config
func NewVSCodeAssignments(expResponse *CopilotExpAssignmentResponse) *Assignments {
	features := make(map[string]any)
	for _, config := range expResponse.Configs {
		if config.ID != "vscode" {
			continue // Skip disabled configs
		}
		maps.Copy(features, config.Parameters)
	}
	return &Assignments{
		Response:          expResponse,
		Features:          features,
		AssignmentContext: expResponse.AssignmentContext,
		lastUpdate:        time.Now(),
	}
}

// GetVariation retrieves the variation for a given feature name.
// TODO: This should be a private function. It is currently public because of
// Padawan's usage in the jobutils package.
func (fg *Assignments) GetVariation(featureName string) (assignment *Assignment, found bool) {
	if value, exists := fg.Features[featureName]; exists {
		return &Assignment{
			Variation: value,
			Context:   fg.AssignmentContext,
		}, true
	}
	return nil, false
}

func (fg *Assignments) expired(ttl time.Duration) bool {
	return time.Since(fg.lastUpdate) >= ttl
}

// GenerateCacheKey creates a cache key from the randomization unit and traffic filters.
func GenerateCacheKey(randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) CacheKey {
	var randomizationUnitStr string
	if randomizationUnit != nil {
		randomizationUnitStr = fmt.Sprintf("%s:%s", randomizationUnit.Header.String(), randomizationUnit.Value)
	}

	var trafficFiltersStr string
	if len(trafficFilters) > 0 {
		var filters []string
		for _, tf := range trafficFilters {
			if tf != nil {
				filters = append(filters, fmt.Sprintf("%s:%s", tf.Header.String(), tf.Value))
			}
		}
		if len(filters) > 0 {
			// Sort filters to ensure consistent cache keys regardless of order
			sort.Strings(filters)
			trafficFiltersStr = fmt.Sprintf("[%s]", strings.Join(filters, " "))
		}
	}

	return CacheKey{
		RandomizationUnit: randomizationUnitStr,
		TrafficFilters:    trafficFiltersStr,
	}
}
