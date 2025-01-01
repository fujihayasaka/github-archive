package quota

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/background"
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
		result, rates, err = est.PreQueryCharge(ctx, bucket.KeyForActor(actorID), bucket.Precharge())
	}
	if err != nil {
		statting.Counter(ctx, "quota.error", 1, stats.Tags{"method": "PreQueryCharge"})
		logging.Error(ctx, "failed to get usage rate estimate", kvp.Err(err))
		return nil, twirp.WrapError(twirp.NewError(twirp.Internal, "failed to get usage rate estimate"), err)
	}

	if result == QuotaShortViolation {
		statting.Counter(ctx, "quota.violation", 1, stats.Tags{"type": "short", "bucket": string(bucket)})
	} else if result == QuotaLongViolation {
		statting.Counter(ctx, "quota.violation", 1, stats.Tags{"type": "long", "bucket": string(bucket)})
	} else if result == QuotaZeroQuotaExperiment {
		statting.Counter(ctx, "quota.violation", 1, stats.Tags{"type": "zero quota experiment", "bucket": string(bucket)})
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
	for bucket := range buckets {
		_, rates, err := est.PreQueryCharge(ctx, bucket.KeyForActor(actorID), 0)
		if err != nil {
			return nil, err
		}
		allRates[bucket] = rates
	}
	return allRates, nil
}

// Reset all of a user's usage rates to 0.
func ResetRates(ctx context.Context, est RateEstimator, actorID uint32) error {
	for bucket := range buckets {
		err := est.ResetRates(ctx, bucket.KeyForActor(actorID))
		if err != nil {
			return err
		}
	}
	return nil
}

type Bucket string

const AccessibleResources Bucket = Bucket("accessible-resources")

var buckets = map[Bucket]float64{
	AccessibleResources:                     AccessibleResourcesPreCharge,
	Bucket(search.QueryTypeUser):            userQueryPreCharge,
	Bucket(search.QueryTypeFindDefinitions): findDefsPreCharge,
	Bucket(search.QueryTypeFindReferences):  findRefsPreCharge,
	Bucket(search.QueryTypeSuggest):         suggestPreCharge,
	Bucket(search.QueryTypeCount):           countPreCharge,
	Bucket(search.QueryTypeSimilarity):      similarityPreCharge,
}

func (b Bucket) KeyForActor(actorID uint32) Key {
	return Key{bucket: string(b), actorID: actorID}
}

func (b Bucket) Precharge() float64 {
	return buckets[b]
}

type Key struct {
	bucket  string
	actorID uint32
}

func (k Key) String() string {
	// The braces surrounding the actor ID are a Redis hashtag, which causes
	// Redis Cluster to place all keys for the actor on the same shard.
	return fmt.Sprintf("v2:{%d}-%s", k.actorID, k.bucket)
}

const (
	// Per-actor usage quota in cost/sec, max allowed short-term spike
	shortTermRateLimit = 8000
	// Per-actor usage quota in cost/sec, max allowed steady-state rate
	longTermRateLimit = 200

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

	// Allows max two concurrent accessible resources calls.
	AccessibleResourcesPreCharge float64 = shortTermRateLimit * 20.0

	// On error, we don't want to use the full pre-charge for the query, but an
	// error means we don't have a cost for PostAdjust so we give each error a
	// little bit of charge to prevent abuse.
	ErrorCharge float64 = 1000.0

	// Pagination cached response cost
	PaginationCacheOnlyCost float64 = 1000.0

	// Flat charge to account for cost of embeddings calls required in similarity search pre-query
	CAPIEmbeddingsCharge float64 = 1000.0
)
