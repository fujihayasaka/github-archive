package blackbird

import (
	"context"
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/query/timing"
	"github.com/github/blackbird-mw/internal/search"
)

func (c *Cluster) Count(ctx context.Context, query *querypb.Query, queryCtx *search.QueryContext) (*pb.CountResponse, error) {
	start := time.Now()

	// We don't retry counts, but add these keys for logs and stats
	ctx = logging.With(ctx, kvp.Int("retry", 0))
	ctx = statting.WithTags(ctx, stats.Tags{"retry": "0"})

	cResp, err := c.runQuery(ctx, query, queryCtx)
	if err != nil {
		return &pb.CountResponse{
			QueryErrors: []*pb.QueryError{{
				Type:    pb.ErrorType_ERROR_TYPE_RESULTS_INCOMPLETE,
				Message: "Shards failed to respond to count request",
			}},
			Metadata: &pb.Metadata{
				ClusterName: c.ClusterName(),
				CorpusName:  c.CorpusName(),
				Experiments: experiments.GetExperiments(ctx),
				QueryAst:    serialize(query),
				IsFailure:   true,
				Timing:      MapTimings(timing.Finish(ctx)),
				Shards:      []*pb.ShardMetadata{},
			},
		}, nil
	}

	// Collect the first non saturated bucket for each shard and drop all
	// documents that aren't in this bucket.
	shardResponses := cResp.shardResponses
	nonSaturatedBuckets := make([]bucket, 0, len(shardResponses))
	for _, response := range shardResponses {
		bucket := getFirstNonSaturatedBucket(response)
		nonSaturatedBuckets = append(nonSaturatedBuckets, bucket)
	}

	// Filter out non-accessible repos
	_, err = c.filterToAccessibleRepos(ctx, queryCtx, shardResponses)
	if err != nil {
		return nil, err
	}
	timing.Record(ctx, timing.QueryStepRanQuery, start) // NB: success only and inclusive of query + filter accessible repos

	// Filter out blobs that do not resolve
	docLists := [][]*searchpb.GitDocumentMatch{}
	for _, r := range shardResponses {
		docLists = append(docLists, r.Documents)
	}
	err = c.blobFilter.ApplyL(ctx, c.FilterBlobs(), queryCtx.Limits.RequestedLocs, docLists)
	if err != nil {
		logging.Error(ctx, "error resolving blobs", kvp.Err(err))
		return nil, err
	}

	// Go through remaining documents and compute the count
	count := 0
	isExact := true
	isLowerBound := false
	for i, docs := range docLists {
		bucket := nonSaturatedBuckets[i]
		if !bucket.isExact {
			isExact = false
		}

		n := len(docs) // use the number of docs as the count b/c we might have filtered out some of them
		if bucket.isLowerBound {
			isLowerBound = true
			n = bucket.count // bucket was saturated so use the bucket limit as the count
		}
		count += n * bucket.multiplier
	}

	// Re-scale the shard count if some shards didn't respond
	numResponses := cResp.numResponses
	unavailableShards := cResp.unavailableShards
	if unavailableShards > 0 {
		count = int(float64(count) * float64(numResponses) / float64(numResponses-unavailableShards))
		isExact = false
	}

	mode := pb.CountMode_COUNT_MODE_APPROXIMATE
	if isLowerBound {
		mode = pb.CountMode_COUNT_MODE_LOWER_BOUND
	} else if isExact {
		mode = pb.CountMode_COUNT_MODE_EXACT
	}

	return &pb.CountResponse{
		Count: uint32(count),
		Mode:  mode,
		Metadata: &pb.Metadata{
			ClusterName:     c.ClusterName(),
			CorpusName:      c.CorpusName(),
			Experiments:     experiments.GetExperiments(ctx),
			QueryAst:        serialize(query),
			TotalCost:       cResp.cost,
			Retries:         0,
			HadShardFailure: unavailableShards > 0,
			IsFailure:       false,
			Timing:          MapTimings(timing.Finish(ctx)),
			Shards:          cResp.metas,
			QueryId:         requestid.GetGitHubRequestID(ctx),
		},
		ServingOffsetQueried: int64(cResp.offset),
	}, nil
}

type bucket struct {
	count        int
	multiplier   int
	docs         []*searchpb.GitDocumentMatch
	isLowerBound bool
	isExact      bool
}

func getFirstNonSaturatedBucket(shardResponse *searchpb.SearchResponse) bucket {
	buckets := make([]bucket, constants.MaxTrailingZeros+1)
	firstBucketLimit := constants.CountExactDivorToScore
	bucketLimit := constants.CountApproximateDivorToScore

	for _, doc := range shardResponse.Documents {
		// Put in the right bucket
		oid := gitaccess.NewObjectIDFromBytes(doc.DocSha)
		zeros := oid.TrailingZeros()
		if zeros > constants.MaxTrailingZeros {
			zeros = constants.MaxTrailingZeros
		}

		// If a document has N trailing zeros, it also has N-1 trailing zeros
		for i := 0; i <= zeros; i++ {
			buckets[i].count++
			buckets[i].multiplier = 1
			buckets[i].docs = append(buckets[i].docs, doc)
		}
	}

	// Find the first unsaturated bucket and use it to estimate counts
	for i, bucket := range buckets {
		if i == 0 {
			if bucket.count < firstBucketLimit {
				bucket.isExact = true
				shardResponse.Documents = bucket.docs
				return bucket
			}
		} else if bucket.count < bucketLimit {
			bucket.multiplier = 1 << i
			shardResponse.Documents = bucket.docs
			return bucket
		}
	}

	// All buckets are saturated, which means we only have a lower bound estimate of the count.
	// This is pretty unlikely (currently we have only 1B documents in our index, and only one
	// document with 30 trailing zeros...)
	shardResponse.Documents = []*searchpb.GitDocumentMatch{}
	return bucket{
		count:        bucketLimit,
		multiplier:   1 << constants.MaxTrailingZeros,
		isLowerBound: true,
	}
}
