package quota

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/background"
	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/search"
)

// Update the given actor's usage rate for the query we're about to run.
//
// Note that this function always returns a [twirp.Error] for any error that
// occurs.
func PreQuery(ctx context.Context, est RateEstimator, actorID uint32, bucket Bucket) (*RateEstimate, error) {
	var result QuotaResult
	var rates *RateEstimate
	var err error
	if experiments.IsExperimentEnabled(ctx, experiments.ZeroQuota) {
		result = QuotaZeroQuotaExperiment
	} else {
		result, rates, err = est.PreQueryCharge(ctx, bucket.KeyForActor(actorID), bucket.preCharge, bucket.shortTermRateLimit, bucket.longTermRateLimit)
	}
	if err != nil {
		statting.Counter(ctx, "quota.error", 1, stats.Tags{"method": "PreQueryCharge"})
		logging.Error(ctx, "failed to get usage rate estimate", kvp.Err(err))
		return nil, twirp.WrapError(twirp.NewError(twirp.Internal, "failed to get usage rate estimate"), err)
	}

	if result == QuotaShortViolation {
		statting.Counter(ctx, "quota.violation", 1, stats.Tags{"type": "short", "bucket": bucket.name})
	} else if result == QuotaLongViolation {
		statting.Counter(ctx, "quota.violation", 1, stats.Tags{"type": "long", "bucket": bucket.name})
	} else if result == QuotaZeroQuotaExperiment {
		statting.Counter(ctx, "quota.violation", 1, stats.Tags{"type": "zero quota experiment", "bucket": bucket.name})
	}
	logging.Debug(ctx, "quota.PreQuery",
		kvp.Int64("actor_id", int64(actorID)),
		kvp.Stringer("key", rates.key),
		kvp.String("result", result),
		kvp.Float("short_term_rate", rates.ShortTermRate),
		kvp.Float("long_term_rate", rates.LongTermRate))
	if result != QuotaOk {
		logging.Info(ctx, "query quota violated",
			kvp.Int64("actor_id", int64(actorID)),
			kvp.Stringer("key", rates.key),
			kvp.String("reason", result),
			kvp.Float("short_term_rate", rates.ShortTermRate),
			kvp.Float("long_term_rate", rates.LongTermRate))
		return rates, twirp.NewError(twirp.ResourceExhausted, "query rejected because the user is out of quota")
	}
	return rates, nil
}

// Refund unused quota to the actor, or charge them for the excess cost
// incurred.
func PostQuery(ctx context.Context, est RateEstimator, rates *RateEstimate, cost float64) {
	logging.Debug(ctx, "quota.PostQuery", kvp.Stringer("key", rates.key), kvp.Float("cost", cost))
	// NB: If ctx is cancelled (or deadline exceeded due to request timeout) we
	// still want to adjust the quota so create a dedicated background context
	// with a limited timeout.

	bgCtx, cancel := context.WithTimeout(background.Context(ctx), 1*time.Second)
	defer cancel()
	err := est.PostQueryAdjust(bgCtx, rates.key, rates.timestamp, rates.PreCharge, cost)
	if err != nil {
		logging.Error(ctx, "failed to post query adjust", kvp.Err(err))
		statting.Counter(ctx, "quota.error", 1, stats.Tags{"method": "PostQueryAdjust"})
	}
}

// Get a current estimate of a user's usage rates.
func GetRates(ctx context.Context, est RateEstimator, actorID uint32) (map[Bucket]*RateEstimate, error) {
	allRates := make(map[Bucket]*RateEstimate)
	for _, bucket := range allBuckets {
		_, rates, err := est.PreQueryCharge(ctx, bucket.KeyForActor(actorID), 0, bucket.shortTermRateLimit, bucket.longTermRateLimit)
		if err != nil {
			return nil, err
		}
		allRates[bucket] = rates
	}
	return allRates, nil
}

// Reset all of a user's usage rates to 0.
func ResetRates(ctx context.Context, est RateEstimator, actorID uint32) error {
	var allErrors error
	for _, bucket := range allBuckets {
		err := est.ResetRates(ctx, bucket.KeyForActor(actorID))
		if err != nil {
			allErrors = errors.Join(allErrors, err)
		}
	}
	return allErrors
}

// Rate limiting bucket
type Bucket struct {
	name               string
	preCharge          float64
	shortTermRateLimit int
	longTermRateLimit  int
	rust               bool
}

func (b Bucket) KeyForActor(actorID uint32) Key {
	return Key{bucket: b.name, actorID: actorID, rust: b.rust}
}

func (b Bucket) Name() string {
	return b.name
}

func (b Bucket) Precharge() float64 {
	return b.preCharge
}

func (b Bucket) ShortTermRateLimit() int {
	return b.shortTermRateLimit
}

func (b Bucket) LongTermRateLimit() int {
	return b.longTermRateLimit
}

type Key struct {
	bucket  string
	actorID uint32
	rust    bool
}

func (k Key) String() string {
	// The braces surrounding the actor ID are a Redis hashtag, which causes
	// Redis Cluster to place all keys for the actor on the same shard.
	if k.rust {
		return fmt.Sprintf("quota:v1:%s-{%d}", k.bucket, k.actorID)
	}
	return fmt.Sprintf("v2:{%d}-%s", k.actorID, k.bucket)
}

func FindBucket(queryType search.QueryType, license *copilot.License) Bucket {
	if license != nil && license.HasLimitedAccess {
		if bucket, ok := freemiumBuckets[string(queryType)]; ok {
			return bucket
		}
		return freemiumUserQueryBucket
	}

	if bucket, ok := buckets[string(queryType)]; ok {
		return bucket
	}
	return userQueryBucket
}

func newBucket(key string, preCharge float64) Bucket {
	return Bucket{key, preCharge, standardShortTermRateLimit, standardLongTermRateLimit, false}
}

func newFreemiumBucket(key string, preCharge float64) Bucket {
	return Bucket{key, preCharge, freemiumShortTermRateLimit, freemiumLongTermRateLimit, false}
}

func newRustBucket(key string, shortTermRateLimit int, longTermRateLimit int) Bucket {
	return Bucket{key, 0.0, shortTermRateLimit, longTermRateLimit, true}
}

func newRustLimitedBucket(key string, shortTermRateLimit int, longTermRateLimit int) Bucket {
	return Bucket{
		name:               key + "-limited",
		preCharge:          0.0,
		shortTermRateLimit: shortTermRateLimit,
		longTermRateLimit:  int(rustLimitedAccessFactor * float64(longTermRateLimit)),
		rust:               true,
	}
}

const (
	copilotFreemiumBucketName = "copilot-freemium"

	rustChunksOnlineBucketName   = "chunks-online"
	rustChunksBatchBucketName    = "chunks-batch"
	rustSemanticSearchBucketName = "semantic-search"
)

var (
	// Set of standard rate limiting buckets for different types of queries.
	buckets = map[string]Bucket{
		string(search.QueryTypeUser):            userQueryBucket,
		string(search.QueryTypeFindDefinitions): findDefsBucket,
		string(search.QueryTypeFindReferences):  findRefsBucket,
		string(search.QueryTypeSuggest):         suggestBucket,
		string(search.QueryTypeCount):           countBucket,
		string(search.QueryTypeSimilarity):      similarityBucket,
	}
	userQueryBucket  = newBucket(string(search.QueryTypeUser), userQueryPreCharge)
	findDefsBucket   = newBucket(string(search.QueryTypeFindDefinitions), findDefsPreCharge)
	findRefsBucket   = newBucket(string(search.QueryTypeFindReferences), findRefsPreCharge)
	suggestBucket    = newBucket(string(search.QueryTypeSuggest), suggestPreCharge)
	countBucket      = newBucket(string(search.QueryTypeCount), countPreCharge)
	similarityBucket = newBucket(string(search.QueryTypeSimilarity), similarityPreCharge)

	// Buckets for freemium copilot users. These rate limits are a bit stricter and both lexical and semantic queries
	// share the same rate limiting key.
	freemiumBuckets = map[string]Bucket{
		string(search.QueryTypeUser):       freemiumUserQueryBucket,
		string(search.QueryTypeSimilarity): freemiumSimilarityBucket,
	}
	freemiumUserQueryBucket  = newFreemiumBucket(copilotFreemiumBucketName, userQueryPreCharge)
	freemiumSimilarityBucket = newFreemiumBucket(copilotFreemiumBucketName, similarityPreCharge)

	// internal list of all buckets for admin interactions
	allBuckets = []Bucket{
		userQueryBucket,
		findDefsBucket,
		findRefsBucket,
		suggestBucket,
		countBucket,
		similarityBucket,
		freemiumUserQueryBucket,
		freemiumSimilarityBucket,
		rustChunksOnlineBucket,
		rustChunksOnlineLimitedBucket,
		rustChunksBatchBucket,
		rustChunksBatchLimitedBucket,
		rustSemanticSearchBucket,
		rustSemanticSearchLimitedBucket,
	}

	// Buckets populated from Rust services. The numbers below are copied from
	// blackbird-mw-{analysis,semantic}/src/quota.rs. If they get out of sync, the
	// `banned_seconds` numbers in the admin UI will be inaccurate.
	rustOnlineShort                 = 8000
	rustOnlineLong                  = 200
	rustBatchShort                  = rustOnlineShort * 10
	rustBatchLong                   = rustOnlineLong * 10
	rustSemanticSearchShort         = 8000
	rustSemanticSearchLong          = 200
	rustLimitedAccessFactor         = 0.2
	rustChunksOnlineBucket          = newRustBucket(rustChunksOnlineBucketName, rustOnlineShort, rustOnlineLong)
	rustChunksOnlineLimitedBucket   = newRustLimitedBucket(rustChunksOnlineBucketName, rustOnlineShort, rustOnlineLong)
	rustChunksBatchBucket           = newRustBucket(rustChunksBatchBucketName, rustBatchShort, rustBatchLong)
	rustChunksBatchLimitedBucket    = newRustLimitedBucket(rustChunksBatchBucketName, rustBatchShort, rustBatchLong)
	rustSemanticSearchBucket        = newRustBucket(rustSemanticSearchBucketName, rustSemanticSearchShort, rustSemanticSearchLong)
	rustSemanticSearchLimitedBucket = newRustLimitedBucket(rustSemanticSearchBucketName, rustSemanticSearchShort, rustSemanticSearchLong)
)

const (
	// Standard limits for lexical code search and semantic search (with a full copilot license)
	standardShortTermRateLimit = 8000 // Per-actor usage quota in cost/sec, max allowed short-term spike
	standardLongTermRateLimit  = 200  // Per-actor usage quota in cost/sec, max allowed steady-state rate

	// Special limits for freemium copilot users (semantic searches only)
	freemiumShortTermRateLimit = 5000 // Per-actor usage quota in cost/sec, max allowed short-term spike
	freemiumLongTermRateLimit  = 80   // Per-actor usage quota in cost/sec, max allowed steady-state rate

	// The amount of time (in seconds) that it takes for the short- and
	// long-term rates to decay by 50%.
	shortTermHalfLifeSeconds float64 = 60.0
	longTermHalfLifeSeconds  float64 = 4.0 * 60.0 * 60.0

	// Amount to pre-charge against the actor's quota for a query. To
	// prevent DoS attacks, the pre-charge must be proportional to the
	// maximum possible query cost. Suggest queries have a very short
	// timeout, so they have a lower maximum cost.
	userQueryPreCharge  float64 = 150000.0
	findDefsPreCharge   float64 = 100000.0 // expected to be less costly than other user queries
	findRefsPreCharge   float64 = 150000.0
	countPreCharge      float64 = 150000.0
	suggestPreCharge    float64 = 750.0
	similarityPreCharge float64 = userQueryPreCharge + CAPIEmbeddingsCharge // TODO: tune this

	// On error, we don't want to use the full pre-charge for the query, but an
	// error means we don't have a cost for PostAdjust so we give each error a
	// little bit of charge to prevent abuse.
	ErrorCharge float64 = 1000.0

	// Pagination cached response cost
	PaginationCacheOnlyCost float64 = 1000.0

	// Flat charge to account for cost of embeddings calls required in similarity search pre-query
	CAPIEmbeddingsCharge float64 = 1000.0
)
