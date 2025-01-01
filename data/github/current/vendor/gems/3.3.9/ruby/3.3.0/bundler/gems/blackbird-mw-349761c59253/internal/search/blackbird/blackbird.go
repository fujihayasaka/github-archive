package blackbird

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"math/rand"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/background"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/filter"
	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
)

// Converts a cgo EpochMode to the hydro entities proto representation.
func ConvertEpochMode(m epoch.EpochMode) entities.EpochMode {
	switch m {
	case epoch.EpochModeLegacyHybrid:
		return entities.EpochMode_LEGACY_HYBRID
	case epoch.EpochModeLexical:
		return entities.EpochMode_LEXICAL
	case epoch.EpochModeEmbeddings:
		return entities.EpochMode_EMBEDDINGS
	case epoch.EpochModeEmbeddingsGraph:
		return entities.EpochMode_EMBEDDINGS_GRAPH
	case epoch.EpochModeHybrid:
		return entities.EpochMode_HYBRID
	default:
		panic(fmt.Sprintf("unknown epoch mode: %v", m))
	}
}

// Get a specific cluster by corpus.
//
// Returns a search `Cluster` or an error.
func GetCluster(ctx context.Context, clusters *routing.SearchClusters, store db.Store, cache cache.Store, gitClient gitaccess.Client, corpus routing.Corpus) (*Cluster, error) {
	routes := clusters.GetServingRoutes(ctx, corpus)
	return &Cluster{store, cache, routes, filter.NewUnresolvableBlobs(gitClient), nil /* no shadow traffic */}, nil
}

// Get a specific cluster by corpus but disable post-query blob resolution
// (filtering of blobs based on spokesd verification checks). You only want to
// use this function from a prober. All user queries should use
// `AutoSelectCluster` or `GetCluster`.
//
// Returns a search `Cluster` or an error.
func GetClusterWithoutBlobResolution(ctx context.Context, clusters *routing.SearchClusters, store db.Store, cache cache.Store, corpus routing.Corpus) (*Cluster, error) {
	return GetCluster(ctx, clusters, store, cache, nil /*disables blob resolution*/, corpus)
}

// Automatically select a search cluster based on a the following criteria:
//
//  1. If you pass a non-zero epochID, this function will attempt to return the
//     cluster associated with that epoch.
//  2. If the context has a ForceCorpusExperiment flag set, the primary cluster
//     for that corpus will be returned.
//  3. Otherwise the first serving corpus with valid cluster status will be returned.
//
// Returns a search `Cluster` or an error.
func AutoSelectCluster(ctx context.Context, clusters *routing.SearchClusters, store db.Store, cache cache.Store, gitClient gitaccess.Client, epochID types.EpochID, epochFeatures epoch.EpochFeatures, stamp routing.Stamp) (*Cluster, error) {
	// Passing an epoch_id or using feature flags can select a specific corpus to
	// query.
	selectCluster := func(corpus routing.Corpus) (*Cluster, error) {
		return GetCluster(ctx, clusters, store, cache, gitClient, corpus)
	}

	// If an epoch is specified, lookup the corpus serving that epoch
	if epochID != 0 {
		logging.Info(ctx, fmt.Sprintf("looking for corpus with epoch id %d", epochID))
		for _, corpus := range routing.Corpora {
			c := clusters.ClientForCorpus(corpus)
			if c.EpochID() == uint32(epochID) {
				routes := clusters.GetServingRoutes(ctx, corpus)
				return &Cluster{store, cache, routes, filter.NewUnresolvableBlobs(gitClient), nil /*no shadow traffic */}, nil
			}
		}
		return nil, fmt.Errorf("invalid epoch_id %d", epochID)
	}

	// If an experiment to force a (valid) corpus is specified, use that:
	if forceCorpus, ok := experiments.GetExperiment(ctx, experiments.ForceCorpus); ok {
		if corpus, err := routing.CorpusFromString(forceCorpus); err == nil {
			return selectCluster(corpus)
		}
	}

	// Otherwise, pick the best available serving corpus.
	servingRoutes := []*routing.SearchRoutes{}
	shadowRoutes := []*routing.SearchRoutes{}
	for _, corpus := range routing.Corpora {
		c := clusters.ClientForCorpus(corpus)
		epochMode := epoch.EpochMode(c.EpochMode())
		ctx := logging.With(ctx, kvp.Bool("is_serving", c.IsServing()), kvp.String("epoch_mode", epochMode.String()))
		tags := stats.Tags{"cluster": corpus.ClusterName(), "corpus": corpus.String(), "epoch_mode": epochMode.String()}
		score := c.HealthScore()
		statting.Gauge(ctx, "query.cluster.health_score", int64(score*1000), tags)

		if !epochFeatures.SupportedBy(epochMode) {
			continue
		}

		routes := clusters.GetServingRoutes(ctx, corpus)
		if c.IsServing() {
			servingRoutes = append(servingRoutes, routes)
		} else {
			if routes.ShadowTrafficPercent() > 0 {
				shadowRoutes = append(shadowRoutes, routes)
			}
			statting.Gauge(ctx, "query.cluster.serving.primary", 0, tags)
			statting.Gauge(ctx, "query.cluster.serving.secondary", 0, tags)
		}
	}

	if len(servingRoutes) == 0 {
		return nil, errors.New("could not find a serving corpus")
	}

	// Sort the clusters by health score (descending order)
	slices.SortFunc(servingRoutes, func(i, j *routing.SearchRoutes) int {
		return cmp.Compare(j.HealthScore(), i.HealthScore())
	})

	// Serve the highest scoring cluster, allow sending shadow traffic to the rest
	var primary *routing.SearchRoutes
	shadowClusters := []*Cluster{}
	for _, r := range servingRoutes {
		tags := stats.Tags{"cluster": r.Corpus.ClusterName(), "corpus": r.Corpus.String(), "epoch_mode": epoch.EpochMode(r.EpochMode).String()}
		if primary == nil {
			primary = r
			statting.Gauge(ctx, "query.cluster.serving.primary", 1, tags)
			statting.Gauge(ctx, "query.cluster.serving.secondary", 0, tags)
		} else {
			shadowClusters = append(shadowClusters, &Cluster{store, cache, r, filter.NewUnresolvableBlobs(gitClient), nil})
			statting.Gauge(ctx, "query.cluster.serving.primary", 0, tags)
			statting.Gauge(ctx, "query.cluster.serving.secondary", 1, tags)
		}
	}

	// Non-serving clusters can still receive shadow traffic
	for _, r := range shadowRoutes {
		shadowClusters = append(shadowClusters, &Cluster{store, cache, r, filter.NewUnresolvableBlobs(gitClient), nil})
	}

	return &Cluster{store, cache, primary, filter.NewUnresolvableBlobs(gitClient), shadowClusters}, nil
}

type Cluster struct {
	store          db.Store
	cache          cache.Store
	routes         *routing.SearchRoutes
	blobFilter     *filter.UnresolvableBlobs
	shadowClusters []*Cluster
}

func (c *Cluster) Corpus() routing.Corpus {
	return c.routes.Corpus
}

func (c *Cluster) CorpusName() string {
	return c.routes.Corpus.String()
}

func (c *Cluster) ClusterName() string {
	return c.routes.Corpus.ClusterName()
}

// Total number of shards (both available and unavailable)
func (c *Cluster) NumShards() int {
	return len(c.routes.ServingHosts) + c.routes.NumUnavailableShards
}

// Percent of shards that have no hosts available to serve them.
func (c *Cluster) PercentUnavailableShards() float32 {
	return float32(c.routes.NumUnavailableShards) / float32(c.NumShards())
}

func (c *Cluster) EpochID() types.EpochID {
	return c.routes.EpochID
}

func (c *Cluster) EpochMode() epoch.EpochMode {
	return epoch.EpochMode(c.routes.EpochMode)
}

func (c *Cluster) ServingTs() time.Time {
	return c.routes.ServingTs
}

func (c *Cluster) ServingOffset() routing.ServingOffset {
	return c.routes.ServingOffset
}

func (c *Cluster) IsServing() bool {
	return c.routes.IsServing()
}

func (c *Cluster) FilterBlobs() bool {
	return c.routes.BlobFiltering()
}

func (c *Cluster) RandomHost() (*routing.SearchHost, error) {
	h := c.routes.RandomHost()
	if h == nil {
		return nil, fmt.Errorf("no index hosts found for %s/%s", c.CorpusName(), c.ClusterName())
	}
	return h, nil
}

func (c *Cluster) HealthScore() float32 {
	return c.routes.HealthScore()
}

// Does this cluster have shadow traffic routes configured?
func (c *Cluster) CanSendShadowTraffic() bool {
	return len(c.shadowClusters) > 0
}

func (c *Cluster) runQuery(ctx context.Context, query *querypb.Query, queryCtx *search.QueryContext) (*clusterResponse, error) {
	start := time.Now()
	logging.Info(ctx, "querying all shards",
		kvp.Int("num_shards", len(c.routes.ServingHosts)),
		kvp.Int("num_unavailable_shards", c.routes.NumUnavailableShards),
		kvp.Duration("query_timeout", queryCtx.Timeout),
		kvp.Int("percent_unavailable_shards", int(c.PercentUnavailableShards()*100)),
		kvp.Int("percent_unavailable_shards_allowed", int(queryCtx.MaxPercentUnavailableShards*100)),
		kvp.Int("num_docs_requested", int(queryCtx.Limits.RequestedDocs)),
		kvp.Int("num_locs_requested", int(queryCtx.Limits.RequestedLocs)),
		kvp.Int("num_locs_limit", int(queryCtx.Limits.LocationsLimit)),
		kvp.Int("num_term_matches", int(queryCtx.Limits.TermMatchLimit)),
		kvp.Int("num_docs_to_retrieve", int(queryCtx.Limits.ToRetrieve)),
		kvp.Int("num_docs_to_score", int(queryCtx.Limits.ToScore)),
		kvp.Int("num_docs_to_return", int(queryCtx.Limits.ToReturn)),
		kvp.Int("num_docs_with_content", int(queryCtx.Limits.WithContent)))

	// Issue shadow traffic for some % of queries
	for _, shadowCluster := range c.shadowClusters {
		if rand.Float32() < shadowCluster.routes.ShadowTrafficPercent() {
			go func() {
				defer utils.PanicLogger(ctx)

				// Grab any existing experiments before we create a new context
				existingExperiments := experiments.GetExperiments(ctx)

				// Create a new context for the shadow query as it must outlive the parent request/response
				// cycle and we want dedicated logging/stats keys.
				ctx, cancel := context.WithTimeout(background.Context(ctx), queryCtx.Timeout)
				defer cancel()

				// Bring over any experiments and relevant behaviors.
				ctx = experiments.WithExperiments(ctx, existingExperiments)
				if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
					ctx = logging.With(ctx, kvp.String("query", serialize(query)))
				}

				actor := queryCtx.Actor
				routes := shadowCluster.routes
				querySource := queryCtx.QuerySource
				queryType := queryCtx.QueryType
				epochModeStr := epoch.EpochMode(routes.EpochMode).String()
				ctx = logging.With(ctx,
					kvp.Any("experiments", experiments.GetExperiments(ctx)),
					kvp.Int64("serving_offset", int64(routes.ServingOffset)),
					kvp.String("corpus", routes.Corpus.String()),
					kvp.String("epoch_mode", epochModeStr),
					kvp.String("query_source", string(querySource)),
					kvp.String("query_type", string(queryType)),
					kvp.String("shadow_query", "true"),
					kvp.Float("shadow_percent", float64(routes.ShadowTrafficPercent())),
					kvp.String("tenant_shortcode", actor.GetTenant().GetShortcode()),
					kvp.Uint("actor_id", uint(actor.ID)),
					kvp.Uint("epoch_id", uint(routes.EpochID)))
				ctx = statting.WithTags(ctx,
					stats.Tags{
						"corpus":       routes.Corpus.String(),
						"epoch_mode":   epochModeStr,
						"query_source": string(querySource),
						"query_type":   string(queryType),
						"shadow_query": "true",
					})

				if _, err := shadowCluster.runQuery(ctx, query, queryCtx); err != nil {
					logging.Error(ctx, "[shadow] query failed", kvp.Err(err))
				}
			}()
		}
	}

	epochModeStr := epoch.EpochMode(c.routes.EpochMode).String()
	if c.PercentUnavailableShards() > queryCtx.MaxPercentUnavailableShards {
		logging.Error(ctx, "pre-query: not enough shards available to serve this query")
		statting.DistributionMs(ctx, "query.execute.duration", time.Since(start), stats.Tags{"status": "too_few_shards", "epoch_mode": epochModeStr})
		return nil, fmt.Errorf(
			"not enough shards available to serve the query: %.0f%% (%d of %d) of shards are unavailable, max allowed: %.0f%%",
			c.PercentUnavailableShards()*100,
			c.routes.NumUnavailableShards,
			c.NumShards(),
			queryCtx.MaxPercentUnavailableShards*100)
	}

	res, err := c.fanin(ctx, queryCtx, c.fanout(ctx, query, queryCtx))
	if err != nil {
		status := "error"
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
			status = "timeout"
			logging.Error(ctx, "query timed out")
		} else {
			logging.Error(ctx, "error performing query", kvp.Err(err))
		}
		statting.DistributionMs(ctx, "query.execute.duration", time.Since(start), stats.Tags{"status": status, "epoch_mode": epochModeStr})
		return nil, err
	}

	statting.DistributionMs(ctx, "query.execute.duration", time.Since(start), stats.Tags{"status": "success", "epoch_mode": epochModeStr})
	return res, nil
}

func (c *Cluster) fanout(ctx context.Context, query *querypb.Query, queryCtx *search.QueryContext) chan *routing.ShardResponse {
	wg := sync.WaitGroup{}
	responses := make(chan *routing.ShardResponse)
	for _, shardHosts := range c.routes.ServingHosts {
		wg.Add(1)
		go func(hosts []*routing.SearchHost) {
			start := time.Now()
			defer wg.Done()

			// Temp: get some stats about how often we don't see the expected two hosts per shard
			if len(hosts) < 2 {
				logging.Error(ctx, "dsa: fewer than two hosts serving this shard", kvp.Int("num_hosts", len(hosts)), kvp.Int("shard_id", int(hosts[0].ShardID)), kvp.Int("epoch_id", int(c.EpochID())), kvp.Int("offset", int(c.ServingOffset())))
				statting.Counter(ctx, "query_service.missing_hosts", 1, stats.Tags{"num_hosts": fmt.Sprintf("%d", len(hosts))})
			} else {
				statting.Counter(ctx, "query_service.got_expected_hosts", 1, stats.Tags{"num_hosts": fmt.Sprintf("%d", len(hosts))})
			}

			shardID := hosts[0].ShardID // NB: All hosts in the slice are serving this shard id.
			var request = buildSearchRequest(ctx, query, queryCtx, c.routes.EpochID, c.routes.ServingOffset, shardID)

			var servingHost string
			var response *searchpb.SearchResponse
			var err error
			numFailedHosts := 0
			shardUnavailable := true
			for i, host := range hosts {
				response, err = host.Search(ctx, request)
				if err != nil {
					if !errors.Is(err, context.DeadlineExceeded) && !errors.Is(err, context.Canceled) {
						logging.Error(ctx, "index host failed to respond", kvp.Err(err), kvp.String("index_host", host.Hostname), kvp.Int("shard_id", int(shardID)), kvp.Int("try", i))
					}
					numFailedHosts++
				} else {
					servingHost = host.Hostname
					shardUnavailable = false
					break
				}
			}

			responses <- &routing.ShardResponse{
				ServingHost:      servingHost,
				ShardID:          shardID,
				BBResponse:       response,
				Offset:           routing.ServingOffset(request.GetServingOffset()),
				Duration:         time.Since(start),
				ShardUnavailable: shardUnavailable,
				NumFailedHosts:   numFailedHosts,
				LastError:        err,
			}
		}(shardHosts)
	}

	go func() {
		wg.Wait()
		close(responses)
	}()

	return responses
}

func (c *Cluster) fanin(ctx context.Context, queryCtx *search.QueryContext, responses chan *routing.ShardResponse) (*clusterResponse, error) {
	start := time.Now()
	var numResponses int
	var hadShardFailure bool
	var hadShardTimeout bool
	var hitReturnLimit bool
	var hitRetrievalLimit bool
	var hitScoringLimit bool
	var unavailableShards int
	var numHostsFailed int
	var cost float32
	var docsReturned int
	var offset routing.ServingOffset
	var lastError error
	shardResponses := []*searchpb.SearchResponse{}
	metas := []*pb.ShardMetadata{}
	for sr := range responses {
		numResponses++
		numHostsFailed += sr.NumFailedHosts
		metas = append(metas, mapShardMetadata(sr))
		if sr.ShardUnavailable {
			unavailableShards++
			lastError = sr.LastError
			hadShardFailure = true
			continue
		}

		shardResponses = append(shardResponses, sr.BBResponse)

		offset = sr.Offset // NB: They will all be the same
		hadShardFailure = hadShardFailure || sr.QueryStats().GetHadPanic()
		hadShardTimeout = hadShardTimeout || sr.QueryStats().GetHadTimeout()
		hitRetrievalLimit = hitRetrievalLimit || sr.QueryStats().GetHitRetrievalLimit()
		hitReturnLimit = hitReturnLimit || sr.QueryStats().GetHitReturnLimit()
		hitScoringLimit = hitScoringLimit || sr.QueryStats().GetHitScoringLimit()
		cost += sr.QueryStats().GetCost()
		docsReturned += len(sr.BBResponse.Documents)

		logging.Debug(ctx, "index host responded for shard",
			kvp.Int("shard_id", int(sr.ShardID)),
			kvp.Float("cost", float64(sr.QueryStats().GetCost())),
			kvp.Int("docs_retrieved", int(sr.QueryStats().GetDocsRetrieved())),
			kvp.Int("docs_scored", int(sr.QueryStats().GetDocsScored())),
			kvp.Int("locations_retrieved", int(sr.QueryStats().GetLocationsRetrieved())),
			kvp.Int("locations_scored", int(sr.QueryStats().GetLocationsScored())),
			kvp.Bool("had_panic", sr.QueryStats().GetHadPanic()),
			kvp.Bool("had_timeout", sr.QueryStats().GetHadTimeout()),
			kvp.Bool("hit_retrieval_limit", sr.QueryStats().GetHitRetrievalLimit()),
			kvp.Bool("hit_return_limit", sr.QueryStats().GetHitReturnLimit()),
			kvp.Bool("hit_scoring_limit", sr.QueryStats().GetHitScoringLimit()),
		)
		statting.Counter(ctx, "query_service.docs_retrieved", int64(sr.QueryStats().GetDocsRetrieved()))
		statting.Counter(ctx, "query_service.docs_scored", int64(sr.QueryStats().GetDocsScored()))
	}

	statting.Distribution(ctx, "query_service.blackbird_num_hosts_failed", float64(numHostsFailed))
	statting.Distribution(ctx, "query_service.blackbird_unavailable_shards", float64(unavailableShards))

	percentUnavailable := float32(unavailableShards) / float32(c.NumShards())
	if percentUnavailable > queryCtx.MaxPercentUnavailableShards {
		logging.Error(ctx, "post-query: not enough shards responded")
		return nil, fmt.Errorf(
			"not enough shards responded to serve the query: %.0f%% (%d of %d) of shards are unresponsive, max allowed: %.0f%%: %w",
			percentUnavailable*100,
			unavailableShards,
			c.NumShards(),
			queryCtx.MaxPercentUnavailableShards*100,
			lastError)
	} else if percentUnavailable > 0 {
		logging.Error(ctx, "post-query: did not get a response from some shards; within the allowed unavailable threshold; results incomplete", kvp.Int("num_unresponsive_shards", unavailableShards))
	}

	return &clusterResponse{
			numResponses,
			hadShardFailure,
			hadShardTimeout,
			hitReturnLimit,
			hitRetrievalLimit,
			hitScoringLimit,
			unavailableShards,
			shardResponses,
			metas,
			cost,
			docsReturned,
			offset,
			time.Since(start),
		},
		nil
}

type clusterResponse struct {
	numResponses      int
	hadShardFailure   bool
	hadShardTimeout   bool
	hitReturnLimit    bool
	hitRetrievalLimit bool
	hitScoringLimit   bool
	unavailableShards int
	shardResponses    []*searchpb.SearchResponse
	metas             []*pb.ShardMetadata
	cost              float32
	docsReturned      int
	offset            routing.ServingOffset
	elapsed           time.Duration
}

type filterResponse struct {
	hitLocationLimit   bool
	saturatedLocations bool
	numDocuments       uint32
	numFiltered        uint32
}

func (c *Cluster) filterToAccessibleRepos(ctx context.Context, queryCtx *search.QueryContext, shardResponses []*searchpb.SearchResponse) (*filterResponse, error) {
	start := time.Now()
	fallbackRepoMap, err := c.fallbackRepoMap(ctx, shardResponses)
	if err != nil {
		return nil, err
	}

	// Filter out locations that are in repos that aren't accessible to this actor
	numDocuments := uint32(0)
	numFiltered := uint32(0)
	hitLocationLimit := false
	saturatedLocations := false
	actor := queryCtx.Actor
	for _, response := range shardResponses {
		docs := []*searchpb.GitDocumentMatch{}
		for _, doc := range response.Documents {
			filteredLocs := []*searchpb.Location{}
			for _, loc := range doc.Locations {
				if len(fallbackRepoMap) > 0 {

					// Shards are stale, check repo visibility in the db
					statting.Counter(ctx, "query.db_visibility_check.count", 1, stats.Tags{"reason": "stale_shards"})
					repo, ok := fallbackRepoMap[types.RepoID(loc.RepoId)]
					if ok && repo != nil && repo.IsAccessibleBy(actor) {
						filteredLocs = append(filteredLocs, loc)
					} else {
						numFiltered++
					}

				} else {
					// Trust blackbird's repo visibility
					if loc.IsRepoPublic || actor.AccessiblePrivateRepoIDs[types.RepoID(loc.RepoId)] {
						filteredLocs = append(filteredLocs, loc)
					} else {
						numFiltered++
					}
				}
			}

			// If blackbird returned the no. of documents we asked but we still couldn't get enough locations requested
			// by the user query then we need to retry.
			if len(doc.Locations) == int(queryCtx.Limits.LocationsLimit) && len(filteredLocs) < int(queryCtx.Limits.RequestedLocs) {
				hitLocationLimit = true
			}

			// Track if we got exactly as many locations as we requested. If we also
			// end up not getting enough docs to fulfill the query it may be worth
			// retrying with a larger locations limit.
			if len(doc.Locations) == int(queryCtx.Limits.RequestedLocs) {
				saturatedLocations = true
			}

			if len(filteredLocs) > 0 {
				doc.Locations = filteredLocs
				docs = append(docs, doc)
				numDocuments++
			}
		}
		response.Documents = docs
	}

	statting.Counter(ctx, "query.process_shard_responses.filtered_locations.count", int64(numFiltered))
	statting.DistributionMs(ctx, "query.filter_to_accessible_repos.duration", time.Since(start))

	return &filterResponse{hitLocationLimit, saturatedLocations, numDocuments, numFiltered}, nil
}

func (c *Cluster) fallbackRepoMap(ctx context.Context, responses []*searchpb.SearchResponse) (map[types.RepoID]*db.Repository, error) {
	fallbackRepoMap := map[types.RepoID]*db.Repository{}
	const maxStaleness = 30 * time.Minute
	if time.Since(c.ServingTs()) > maxStaleness {
		// Results are stale by more than 30 mins, must check repo visibility in the db
		for _, response := range responses {
			for _, doc := range response.Documents {
				for _, loc := range doc.Locations {
					fallbackRepoMap[types.RepoID(loc.RepoId)] = nil
				}
			}
		}
		err := c.store.LoadRepositoriesByIDs(ctx, fallbackRepoMap)
		if err != nil {
			return nil, err
		}
	}
	return fallbackRepoMap, nil
}

// Helper for logging queries
func serialize(queries ...*querypb.Query) string {
	if len(queries) == 0 {
		return ""
	} else if len(queries) == 1 {
		query := queries[0]
		if query.Kind == querypb.QueryKind_QUERY_KIND_SUBSTRING || query.Kind == querypb.QueryKind_QUERY_KIND_REGEX {
			return fmt.Sprintf("%s_%s(%q:%s)", domainToString(query.Domain), kindToString(query.Kind), query.ValueString, divorToString(query))
		} else if query.Kind == querypb.QueryKind_QUERY_KIND_QUALIFIER {
			if len(query.Subqueries) > 0 {
				return fmt.Sprintf("%s(%s %s)", domainToString(query.Domain), serialize(query.Subqueries...), divorToString(query))
			} else if query.ValueString == "" {
				return fmt.Sprintf("%s(%v:%s)", domainToString(query.Domain), query.ValueInt, divorToString(query))
			}
			return fmt.Sprintf("%s(%q:%s)", domainToString(query.Domain), query.ValueString, divorToString(query))
		}
		return fmt.Sprintf("%s(%s:%s)", kindToString(query.Kind), serialize(query.Subqueries...), divorToString(query))
	} else {
		rendered := []string{}
		for _, query := range queries {
			rendered = append(rendered, serialize(query))
		}
		return strings.Join(rendered, ",")
	}
}

func divorToString(query *querypb.Query) string {
	if query.DivorToRetrieve == 0 && query.DivorToScore == 0 {
		return ""
	}
	return fmt.Sprintf("to_retrieve=%d,to_score=%d", query.DivorToRetrieve, query.DivorToScore)
}

func kindToString(kind querypb.QueryKind) string {
	return strings.TrimPrefix(kind.String(), "QUERY_KIND_")
}

func domainToString(domain querypb.Domain) string {
	return strings.TrimPrefix(domain.String(), "DOMAIN_")
}
