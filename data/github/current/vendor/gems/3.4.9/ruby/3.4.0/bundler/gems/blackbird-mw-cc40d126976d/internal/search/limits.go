package search

import (
	"context"
	"math"
	"sync"
	"time"

	"github.com/github/blackbird/crates/core/pkg/limits"
	"github.com/github/go-telemetry/statting"
)

// QueryLimits contains limits to set on a request to a blackbird shard. These
// limits vary for different queries. E.g., a user submitted search query
// carries different limits vs a suggest or prober query.
//
// `RequestedDocs` and `RequestedLocs` are provided by the caller and represent
// cluster-level limits (aggregate of all shards). Other fields *can* be
// calculated and are per-shard where noted.
type QueryLimits struct {
	RequestedDocs  uint32 // Number of documents requested by the caller
	RequestedLocs  uint32 // Number of locations per document requested by the caller
	LocationsLimit uint32 // Location limit sent to blackbird. Can be different than RequestedLocs in order to score more locations than you return.
	TermMatchLimit uint32 // Number of term matches per document requested by the caller

	ToRetrieve  uint32 // Number of results to retrieve (per shard)
	ToScore     uint32 // Number of results to score (per shard)
	ToReturn    uint32 // Number of results to return (per shard)
	WithContent uint32 // Number of results with full content and scoring info to return (per shard)
}

// LimitsCalculator is responsible for calculating blackbird shard request
// limits. The goal of the calculator is to set some sensible initial values and
// calculate how many documents with content should be requested from blackbird.
//
// For example, if we want 100 documents and there are 32 shards we might
// request 100 documents from each shard (so that we can aggregate and sort to
// return the best 100 documents). However, there's no reason to fetch content
// for all 3200 documents so we calculate the probable number of documents
// that'll be used from each shard to set `WithContent`.
//
// If it turns out that after re-sorting the aggregate results that some
// documents don't have content then an additional request to blackbird is made
// to fetch content for those specific doc ids.
//
// Since computing `WitContent` is expensive, we cache the calculation.
type LimitsCalculator struct {
	cache map[cacheKey]uint32
	mutex sync.RWMutex
}

func NewLimitsCalculator() *LimitsCalculator {
	return &LimitsCalculator{
		cache: map[cacheKey]uint32{
			// NB: Pre-fill the most common values.
			{centile: 0.95, numDocs: 100, numShards: 32}: 9,
			{centile: 0.99, numDocs: 100, numShards: 32}: 10,
		},
	}
}

const (
	DefaultDocsLimit      uint32 = 100                  // Default number of documents (or snapshots) to return.
	DefaultLocsLimit      uint32 = 10                   // Default number of locations (or entries) to return per result.
	RetrieveAllDocs       uint32 = math.MaxUint32       // Set DivorToRetrieve to this value to have blackbird retrieve all documents.
	ToRetrieveLimit       uint32 = 200_000              // Max ToRetrieve value for retried user queries
	DefaultDocsToScore    uint32 = DefaultDocsLimit * 5 // Default value for DivorToScore which is 5 * DefaultDocsLimit.
	maxDocsToReturn              = 10_000
	maxDocsToScore               = 10_000
	minLocsLimit                 = 5   // Minimum number of locations for user queries
	defaultTermMatchLimit uint32 = 100 // Default number of term matches to calculate per document.
)

// Calculate per shard limits in order to meet overall request goal of N documents.
func (b *LimitsCalculator) Calculate(ctx context.Context, numShards int, requestedDocs, requestedLocs uint32) QueryLimits {
	if requestedDocs == 0 {
		requestedDocs = DefaultDocsLimit
	}

	if requestedLocs == 0 {
		requestedLocs = DefaultLocsLimit
	}

	// Always fetch at least n locations from blackbird (so that we can score
	// enough to return relevant results first).
	locLimit := max(requestedLocs, minLocsLimit)

	// Guess at how many docs/shard for which we'll want content.
	const centile = 0.95
	withContent := b.getDocsPerShard(ctx, centile, requestedDocs, numShards)

	// Score 3x more docs/shard than we want content for (up to a maxDocsToScore limit).
	toScore := min(3*withContent, maxDocsToScore)

	// Return everything we score (up to the docLimit) so that we can sort/rank
	// across shards.
	toReturn := min(toScore, requestedDocs)

	// Retrieve *many* more docs than we score.
	toRetrieve := min(100*toScore, ToRetrieveLimit)

	return QueryLimits{
		RequestedDocs:  requestedDocs,
		RequestedLocs:  requestedLocs,
		LocationsLimit: locLimit,
		TermMatchLimit: defaultTermMatchLimit,
		ToRetrieve:     toRetrieve,
		ToScore:        toScore,
		ToReturn:       toReturn,
		WithContent:    withContent,
	}
}

type cacheKey struct {
	centile   float64
	numDocs   uint32
	numShards int
}

func (b *LimitsCalculator) get(key cacheKey) (uint32, bool) {
	b.mutex.RLock()
	defer b.mutex.RUnlock()
	limit, ok := b.cache[key]
	return limit, ok
}

func (b *LimitsCalculator) set(key cacheKey, limit uint32) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	b.cache[key] = limit
}

func (b *LimitsCalculator) fetch(key cacheKey, f func() uint32) uint32 {
	if limit, ok := b.get(key); ok {
		return limit
	}
	limit := f()
	b.set(key, limit)
	return limit
}

func (b *LimitsCalculator) getDocsPerShard(ctx context.Context, centile float64, numDocs uint32, numShards int) uint32 {
	return b.fetch(cacheKey{centile, numDocs, numShards}, func() uint32 {
		start := time.Now()
		defer func() {
			statting.DistributionMs(ctx, "limits.calculation", time.Since(start))
		}()
		return limits.CalcLikelyDocsPerShard(centile, numDocs, int32(numShards))
	})
}
