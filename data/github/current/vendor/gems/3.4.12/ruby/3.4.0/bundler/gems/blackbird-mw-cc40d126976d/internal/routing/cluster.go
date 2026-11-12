// NOTES:
//
// 1. The admin needs to talk to the search clusters and cache cluster. The
// admin is also the only thing that should be _setting_ changes to the DSA
// (like serving status). However, this is not enforced by the API.
//
//   - search: for probers
//   - cache cluster: to get the MST for backfill
//
// 2. The crawler needs to talk to cache and the indexer for its corpus:
//   - cache cluster: to publish messages
//   - indexer: to get leases, query index state
//
// 3. Search needs to talk to search cluster only.
//
//	The search needs to _get_ values from the DSA for serving status, etc.
package routing

import (
	"context"
	"fmt"
	"math/rand"
	"net"
	"reflect"
	"sync"
	"syscall"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/blackbird/crates/client/pkg/blackbird"
	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	indexpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/index/v1"
	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/blackbird/crates/core/pkg/shard"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	blackbirdpb "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	"github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
)

type ServingClientFunc func(hostname string) servingpb.ServingAPI

// SearchHost holds details about an individual blackbird host in a search cluster.
type SearchHost struct {
	Hostname  string
	ShardID   uint32
	SearchAPI blackbird.SearchAPI
	client    blackbird.Client
}

func (s *SearchHost) Search(ctx context.Context, request *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
	start := time.Now()
	tags := stats.Tags{"shard": s.Hostname}
	var status *servingpb.ServingStatus
	resp, err := s.SearchAPI.Search(ctx, request)
	if err != nil {
		tags["status"] = "error"
		status = extractServingStatusFromErr(ctx, err)
	} else {
		tags["status"] = "success"
		status = resp.GetServingStatus()
	}
	statting.DistributionMs(ctx, "query_service.blackbird_shard_search.duration", time.Since(start), tags)

	updateStatus(ctx, s.client, s.Hostname, status)

	return resp, err
}

func (s *SearchHost) SearchSnapshots(ctx context.Context, request *snapshotpb.SearchSnapshotsRequest) (*snapshotpb.SearchSnapshotsResponse, error) {
	start := time.Now()

	tags := stats.Tags{"shard": s.Hostname}
	var status *servingpb.ServingStatus
	resp, err := s.SearchAPI.SearchSnapshots(ctx, request)
	if err != nil {
		tags["status"] = "error"
		status = extractServingStatusFromErr(ctx, err)
	} else {
		tags["status"] = "success"
		status = resp.GetServingStatus()
	}
	statting.DistributionMs(ctx, "search_snapshots.duration", time.Since(start), tags)

	updateStatus(ctx, s.client, s.Hostname, status)

	return resp, err
}

func (s *SearchHost) SnapshotsInHashInterval(ctx context.Context, request *snapshotpb.SnapshotsInHashIntervalRequest) (*snapshotpb.SnapshotsInHashIntervalResponse, error) {
	start := time.Now()

	tags := stats.Tags{"shard": s.Hostname}
	var status *servingpb.ServingStatus
	resp, err := s.SearchAPI.SnapshotsInHashInterval(ctx, request)
	if err != nil {
		tags["status"] = "error"
		status = extractServingStatusFromErr(ctx, err)
	} else {
		tags["status"] = "success"
		status = resp.GetServingStatus()
	}

	statting.DistributionMs(ctx, "snapshots_in_hash_interval.duration", time.Since(start), tags)

	updateStatus(ctx, s.client, s.Hostname, status)

	return resp, err
}

// CacheHost holds details about an individual blackbird host in a cache cluster.
type CacheHost struct {
	Hostname string
	ShardID  uint32
	CacheAPI blackbird.CacheAPI
	client   blackbird.Client
}

func (s *CacheHost) ComputeMst(ctx context.Context, req *cachepb.MstRequest) (*cachepb.MstResponse, error) {
	start := time.Now()

	tags := stats.Tags{"cache_host": s.Hostname}
	var status *servingpb.ServingStatus
	res, err := s.CacheAPI.Mst(ctx, req)
	if err != nil {
		tags["status"] = "error"
		status = extractServingStatusFromErr(ctx, err)
	} else {
		tags["status"] = "success"
		status = res.GetStatus()
	}

	statting.DistributionMs(ctx, "mst.duration", time.Since(start))

	updateStatus(ctx, s.client, s.Hostname, status)

	return res, err
}

// IndexerHost holds details about an individual blackbird host in a indexer cluster.
type IndexerHost struct {
	Hostname      string
	ShardID       uint32
	IndexAPI      blackbird.IndexAPI
	ServingOffset ServingOffset
	client        blackbird.Client
}

func (s *IndexerHost) Index(ctx context.Context, req *indexpb.IndexRequest) (*indexpb.IndexResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.Index(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "index.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) Finalize(ctx context.Context, req *indexpb.FinalizeRequest) (*indexpb.FinalizeResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.Finalize(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "finalize.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) Lease(ctx context.Context, req *indexpb.LeaseRequest) (*indexpb.LeaseResponse, error) {
	start := time.Now()
	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.Lease(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "lease.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) DeleteRepository(ctx context.Context, req *indexpb.DeleteRepositoryRequest) (*indexpb.DeleteRepositoryResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.DeleteRepository(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "delete_repository.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) PermanentError(ctx context.Context, req *indexpb.PermanentErrorRequest) (*indexpb.PermanentErrorResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.PermanentError(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "permanent_error.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) Skip(ctx context.Context, req *indexpb.SkipRequest) (*indexpb.SkipResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.Skip(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "skip.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) GetPermanentError(ctx context.Context, req *indexpb.GetPermanentErrorRequest) (*indexpb.GetPermanentErrorResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	res, err := s.IndexAPI.GetPermanentError(ctx, req)
	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(ctx, "get_permanent_error.duration", time.Since(start), tags)

	return res, err
}

func (s *IndexerHost) SearchSnapshots(ctx context.Context, req *snapshotpb.SearchSnapshotsRequest) (*snapshotpb.SearchSnapshotsResponse, error) {
	start := time.Now()

	tags := stats.Tags{"index_host": s.Hostname}
	var status *servingpb.ServingStatus
	res, err := s.IndexAPI.SearchSnapshots(ctx, req)
	if err != nil {
		tags["status"] = "error"
		status = extractServingStatusFromErr(ctx, err)
	} else {
		tags["status"] = "success"
		status = res.GetServingStatus()
	}

	statting.DistributionMs(ctx, "indexapi_search_snapshots.duration", time.Since(start), tags)

	updateStatus(ctx, s.client, s.Hostname, status)

	return res, err
}

type SearchRoutes struct {
	EpochID              types.EpochID
	EpochMode            blackbird.EpochMode
	Corpus               Corpus
	ServingOffset        ServingOffset
	ServingTs            time.Time
	ServingHosts         [][]*SearchHost // The hosts serving each shard
	NumUnavailableShards int             // The number of shards where no valid serving host was found.

	client blackbird.Client
}

func (r SearchRoutes) RandomHost() *SearchHost {
	if len(r.ServingHosts) == 0 {
		return nil
	}

	return r.ServingHosts[rand.Intn(len(r.ServingHosts))][0]
}

func (r SearchRoutes) BlobFiltering() bool {
	return r.client.BlobFiltering()
}

func (r SearchRoutes) ShadowTrafficPercent() float32 {
	return r.client.ShadowTrafficPercent()
}

func (r SearchRoutes) IsServing() bool {
	return r.client.IsServing()
}

func (r SearchRoutes) HealthScore() float32 {
	score := r.client.HealthScore()
	score -= float32(r.NumUnavailableShards) * 0.1
	return score
}

func (r SearchRoutes) ReportProberStatus(status blackbird.ProberStatus) error {
	return r.client.ReportProberStatus(status)
}

func NewSearchClusters(clients map[Corpus]blackbird.Client) *SearchClusters {
	return &SearchClusters{clients}
}

func NewCacheClusters(clients map[string]blackbird.Client) *CacheClusters {
	return &CacheClusters{clients}
}

// NewIndexerCluster returns an IndexerCluster instance which is for a single
// backend. Use this in the ingest code which is tied to a specific backend.
func NewIndexerCluster(client blackbird.Client) *IndexerCluster {
	return &IndexerCluster{client}
}

// NewIndexerClusters returns an IndexerClusters instance which has a client for
// each backend. Use this in probers or the admin where you need to connect to
// multiple backend clusters.
func NewIndexerClusters(clients map[Corpus]blackbird.Client) *IndexerClusters {
	clusters := map[Corpus]*IndexerCluster{}
	for corpus, client := range clients {
		clusters[corpus] = NewIndexerCluster(client)
	}
	return &IndexerClusters{clusters}
}

type SearchClusters struct {
	clients map[Corpus]blackbird.Client
}

func (s *SearchClusters) ClientForCorpus(corpus Corpus) blackbird.Client {
	return s.clients[corpus]
}

func (s *SearchClusters) Status(ctx context.Context, corpus Corpus) (*ClusterStatusSummary, error) {
	client := s.ClientForCorpus(corpus)
	if client == nil {
		panic(fmt.Sprintf("misconfiguration detected: no client for corpus %q", corpus))
	}

	return clusterStatusSummary(ctx, client)
}

func (s *SearchClusters) HealthScore(corpus Corpus) float32 {
	client := s.ClientForCorpus(corpus)
	if client == nil {
		panic(fmt.Sprintf("misconfiguration detected: no client for corpus %q", corpus))
	}

	return client.HealthScore()
}

func (s *SearchClusters) ReportProberStatus(ctx context.Context, corpus Corpus, status blackbird.ProberStatus) error {
	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "report_prober_status.duration", time.Since(start))
	}()

	client := s.ClientForCorpus(corpus)
	if client == nil {
		panic(fmt.Sprintf("misconfiguration detected: no client for corpus %q", corpus))
	}
	statting.Gauge(ctx, "health_score.num_repos", int64(status.NumReposIndexed))
	statting.Gauge(ctx, "health_score.num_unavail_shards", int64(status.NumUnavailableShards))
	if status.NumReposProbed > 0 {
		statting.Gauge(ctx, "health_score.num_repos_probed", int64(status.NumReposProbed))
		statting.Gauge(ctx, "health_score.num_repos_probed_ok", int64(status.NumReposProbedOK))
		statting.Counter(ctx, "health_score.num_repos_probed_not_ok", int64(status.NumReposProbed-status.NumReposProbedOK))
	}
	return client.ReportProberStatus(status)
}

func (s *SearchClusters) GetServingRoutes(ctx context.Context, corpus Corpus) *SearchRoutes {
	var shards [][]*SearchHost
	client := s.ClientForCorpus(corpus)
	routes := client.Routes()
	for i, hl := range routes.Hosts {
		if len(hl) != 0 {
			var hosts []*SearchHost
			for _, h := range hl {
				logging.Debug(ctx, "dsa: got host for shard", kvp.String("index_host", h.Hostname), kvp.Int("shard_id", i), kvp.String("corpus", corpus.String()), kvp.Int("epoch_id", int(routes.Epoch)), kvp.Int("offset", int(routes.ServingOffset)))
				hosts = append(hosts, &SearchHost{h.Hostname, uint32(i), h.SearchClient, client})
			}
			shards = append(shards, hosts)
		} else {
			// If no hosts are serving a shard, we cannot fully issue the query as results will be
			// incomplete. This is checked in [runQuery](../search/blackbird/blackbird.go:155)
			logging.Error(ctx, "dsa: no host serving shard", kvp.Int("shard_id", i), kvp.String("corpus", corpus.String()), kvp.Int("epoch_id", int(routes.Epoch)), kvp.Int("offset", int(routes.ServingOffset)))
		}
	}

	unavailableShards := len(routes.Hosts) - len(shards)
	servingOffset := ServingOffset(routes.ServingOffset)
	servingTs := utils.TimeFromServingTs(routes.ServingTs)

	return &SearchRoutes{types.EpochID(routes.Epoch), routes.EpochMode, corpus, servingOffset, servingTs, shards, unavailableShards, client}
}

func (c *SearchClusters) SetCorpusIsServing(corpus Corpus, isServing bool) error {
	return c.ClientForCorpus(corpus).SetServing(isServing)
}

func (c *SearchClusters) SetCorpusIndexingPaused(corpus Corpus, paused bool) error {
	return c.ClientForCorpus(corpus).SetIndexingPaused(paused)
}

func (c *SearchClusters) SetCorpusIsHealing(corpus Corpus, isHealing bool) error {
	return c.ClientForCorpus(corpus).SetHealing(isHealing)
}

func (c *SearchClusters) SetCorpusBlobFiltering(corpus Corpus, filter bool) error {
	return c.ClientForCorpus(corpus).SetBlobFiltering(filter)
}

func (c *SearchClusters) SetCorpusShadowTraffic(corpus Corpus, percent float32) error {
	return c.ClientForCorpus(corpus).SetShadowTrafficPercent(percent)
}

func (c *SearchClusters) SetCorpusCacheCluster(corpus Corpus, name string) error {
	if !IsCacheCluster(name) {
		return fmt.Errorf("invalid cache cluster name: %s", name)
	}

	return c.ClientForCorpus(corpus).SetCacheCluster(name)
}

func (c *SearchClusters) SetPin(corpus Corpus, ts int64) error {
	return c.ClientForCorpus(corpus).SetPin(ts)
}

func (c *SearchClusters) UnsetPin(corpus Corpus) error {
	return c.ClientForCorpus(corpus).UnsetPin()
}

// CacheClusterName returns the name of the cache cluster to use for this
// corpus. If not set in the DSA client, it returns the empty string.
func (c *SearchClusters) CacheClusterName(corpus Corpus) string {
	return c.ClientForCorpus(corpus).CacheCluster()
}

// WaitForEpochToServe periodically runs a check for search cluster to
// serve epochID. It should be run in a goroutine, because downloading
// a new epoch and catching up in a branching case can take quite a while.
func (c *SearchClusters) WaitForEpochToServe(
	ctx context.Context,
	corpus Corpus,
	epochID types.EpochID,
	timeout time.Duration,
) (int, error) {
	bck := backoff.NewExponentialBackOff()
	bck.MaxElapsedTime = timeout       // Try for up to this duration, then give up
	bck.MaxInterval = 30 * time.Second // Max delay between attempts. Keeping this small-ish lets us detect success sooner

	attempt := 0
	op := func() error {
		attempt++
		status, err := c.Status(ctx, corpus)
		if err != nil {
			return errors.Wrap(err, "error getting status")
		}
		if status.Epoch == epochID && status.IsServingAllShards() {
			return nil
		}
		// If the cluster that we're waiting on has moved to a future epoch that means we've abandoned
		// this epoch branch and it will never be served. If we don't bail early this function will keep
		// running until it times out, which could be a while (4 hours at the time of writing).
		// We also don't want this condition to be `!=` since it's possible that this call may return
		// an older epoch in the beginning until the DSA state converges.
		if status.Epoch > epochID {
			return backoff.Permanent(fmt.Errorf("detected a newer epoch: %d, give up waiting on epoch: %d to serve", status.Epoch, epochID))
		}
		return errors.Errorf("not yet serving the requested epoch, serving: %d, attempt: %d, expected: %d", status.Epoch, attempt, epochID)
	}

	if err := backoff.Retry(op, bck); err != nil {
		return attempt, err
	}

	return attempt, nil
}

// CacheRequest is an interface that all cache request protobuf messages satisfy.
type CacheRequest interface {
	GetTopicName() string
	GetGitDocument() *blackbirdpb.GitDocument
	GetNumShards() uint32
	GetEpochMode() entities.EpochMode
}

// CacheResponse is an interface that all cache response protobuf messages satisfy.
type CacheResponse interface {
	GetPublished() *cachepb.Published
	GetServingStatus() *servingpb.ServingStatus
}

type CacheClusters struct {
	clients map[string]blackbird.Client
}

func (c *CacheClusters) ClientForCluster(cluster string) (blackbird.Client, error) {
	client, ok := c.clients[cluster]
	if !ok {
		return nil, fmt.Errorf("unknown cluster: %s", cluster)
	}

	return client, nil
}

func (c *CacheClusters) Publish(ctx context.Context, cluster string, req CacheRequest, topic DocumentTopic) (CacheResponse, error) {
	client, err := c.ClientForCluster(cluster)
	if err != nil {
		return nil, fmt.Errorf("error publishing, could not get cluster: %w", err)
	}

	routes := client.Routes()

	// NOTE: We check that the number of shards is > 0 to prevent publishing
	// when the cache server isn't ready, but in order to facilitate shard count
	// changes, we don't check that the cache server has the same number of
	// shards as the request asks for. This allows older index configurations to
	// be used to publish to a newer shard count.
	numShards := uint(len(routes.Hosts))
	if numShards == 0 {
		return nil, errors.New("no cache hosts found")
	}

	if len(req.GetGitDocument().Locations) == 0 {
		panic("at least one location is required to publish a document")
	}

	// NOTE: Use the client's epoch mode, NOT the request's because we want to route to the cache shard that has the content.
	epochMode := epoch.EpochMode(routes.EpochMode)
	shardID := shard.ShardIDForEpochMode(numShards, req.GetGitDocument().ContentSha, req.GetGitDocument().Locations[0].Path, epochMode)
	indexHosts := routes.Hosts[shardID]
	var indexHost *blackbird.IndexHost

	switch {
	case len(indexHosts) > 0:
		indexHost = indexHosts[0]
	case canPublishToAnyHost(req):
		logging.Info(ctx, "missing index host, but can publish content to a random host", kvp.String("cache_cluster", cluster), kvp.Int("shard_id", int(shardID)))
		indexHost, err = routes.RandomHost()
		if err != nil {
			return nil, err
		}
	default:
		return nil, errors.New("no index hosts for shard")
	}

	cacheAPI := indexHost.CacheClient
	if cacheAPI == nil {
		panic(fmt.Sprintf("client for host %q is nil", indexHost.Hostname))
	}

	start := time.Now()
	tags := stats.Tags{"cache_host": indexHost.Hostname, "cache_cluster": cluster}
	var res CacheResponse
	switch r := req.(type) {
	case *cachepb.PublishCacheDocumentRequest:
		res, err = cacheAPI.PublishCacheDocument(ctx, r)
		tags["rpc"] = "publish_cache_document"
	case *cachepb.PublishDeleteDocumentRequest:
		res, err = cacheAPI.PublishDeleteDocument(ctx, r)
		tags["rpc"] = "publish_delete_document"
	case *cachepb.PublishDocumentRequest:
		res, err = cacheAPI.PublishDocument(ctx, r)
		tags["rpc"] = "publish_document"
	default:
		panic(fmt.Sprintf("unexpected request type %q: %+v ", reflect.TypeOf(r), r))
	}

	if err != nil {
		tags["status"] = "error"
	} else {
		tags["status"] = "success"
	}

	statting.DistributionMs(
		ctx,
		"crawl.cache.publish_git_document.rpc.duration",
		time.Since(start),
		tags,
	)

	return res, err
}

// canPublishToAnyHost returns true if it's OK to publish this to any
// host. This is only true if the cache doesn't need to look up content to
// publish the message.
func canPublishToAnyHost(req CacheRequest) bool {
	switch req.(type) {
	case *cachepb.PublishDeleteDocumentRequest:
		return true
	case *cachepb.PublishDocumentRequest:
		return true
	default:
		return false
	}
}

func (c *CacheClusters) Status(ctx context.Context, cluster string) (*ClusterStatusSummary, error) {
	client, err := c.ClientForCluster(cluster)
	if err != nil {
		panic(fmt.Sprintf("misconfiguration detected: no client for cluster %q: %v", cluster, err))
	}

	return clusterStatusSummary(ctx, client)
}

func (c *CacheClusters) RandomHost(cluster string) (*CacheHost, error) {
	client, err := c.ClientForCluster(cluster)
	if err != nil {
		return nil, fmt.Errorf("couldn't find client for cluster: %w", err)
	}

	shards := client.Routes().Hosts
	if len(shards) == 0 {
		return nil, errors.New("no index hosts available")
	}

	// Get a host from any shard that's serving, we try 3 times to
	// get a host.
	for i := 0; i < 3; i++ {
		shardID := rand.Intn(len(shards))
		hl := shards[shardID]
		if len(hl) != 0 {
			return &CacheHost{
				Hostname: hl[0].Hostname,
				CacheAPI: hl[0].CacheClient,
				ShardID:  uint32(shardID),
			}, nil
		}
	}

	return nil, errors.New("couldn't find host after retrying")
}

func (c *CacheClusters) ServingEpochForCluster(ctx context.Context, cluster string) (types.EpochID, error) {
	client, err := c.ClientForCluster(cluster)
	if err != nil {
		return 0, err
	}

	return getServingEpoch(client)
}

// WaitForEpoch periodically runs a check for the cache server to
// serve epochID. It should be run in a goroutine, because downloading
// a new epoch can take over 30 minutes.
func (c *CacheClusters) WaitForEpoch(ctx context.Context, cluster string, epochID types.EpochID, timeout time.Duration) (int, error) {
	ctx = logging.With(ctx, kvp.String("cluster", cluster), kvp.Uint("epoch_id", uint(epochID)))

	bck := backoff.NewExponentialBackOff()
	bck.MaxElapsedTime = timeout       // Try for up to this duration, then give up
	bck.MaxInterval = 30 * time.Second // Max delay between attempts. Keeping this small-ish lets us detect success sooner

	attempt := 0
	op := func() error {
		attempt++
		servingEpoch, err := c.ServingEpochForCluster(ctx, cluster)
		if err != nil {
			return errors.Wrap(err, "could not determine serving epoch")
		}
		if servingEpoch == epochID {
			return nil
		}
		return errors.Errorf("not yet serving the requested epoch serving: %d, attempt: %d, expected: %d", servingEpoch, attempt, epochID)
	}

	if err := backoff.Retry(op, bck); err != nil {
		return attempt, err
	}

	return attempt, nil
}

type IndexerCluster struct {
	client blackbird.Client
}

// CacheCluster returns the name of cache cluster for this cluster.
func (i *IndexerCluster) CacheCluster() string {
	return i.client.CacheCluster()
}

func (i *IndexerCluster) IsIndexingPaused() bool {
	return i.client.IsIndexingPaused()
}

func (i *IndexerCluster) EpochInfo() blackbird.EpochInfo {
	return i.client.EpochInfo()
}

// GetHost returns the IndexerHost that should be used for the next RPC, as
// determined by the client. It should be called before every RPC.
//
// The indexAPI DSA client uses a `SingleHostRouter` which selects the most
// up-to-date host to query (host with the greatest serving offset) so we expect
// `Routes()` to return a single host (the shard is arbitrary).
func (i *IndexerCluster) GetHost() (*IndexerHost, error) {
	routes := i.client.Routes()
	for idx, hl := range routes.Hosts {
		if len(hl) != 0 {
			return &IndexerHost{hl[0].Hostname, uint32(idx), hl[0].IndexClient, ServingOffset(routes.ServingOffset), i.client}, nil
		}
	}

	return nil, errors.New("error: no hosts ready to serve indexer api")
}

type IndexerClusters struct {
	clusters map[Corpus]*IndexerCluster
}

func (i *IndexerClusters) GetCluster(corpus Corpus) *IndexerCluster {
	return i.clusters[corpus]
}

func (i *IndexerClusters) ClientForCorpus(corpus Corpus) (blackbird.Client, error) {
	c, ok := i.clusters[corpus]
	if !ok {
		return nil, fmt.Errorf("unknown corpus: %s", corpus)
	}

	return c.client, nil
}

func (i *IndexerClusters) Status(ctx context.Context, corpus Corpus) (*ClusterStatusSummary, error) {
	cluster := i.clusters[corpus]
	if cluster == nil {
		panic(fmt.Sprintf("misconfiguration detected: no index client for corpus %q", corpus))
	}

	return clusterStatusSummary(ctx, cluster.client)
}

type ServingStatusResponse struct {
	Hostname      string
	ServingStatus *servingpb.ServingStatus
	Error         error
}

type ClusterStatusSummary struct {
	HostStatuses         map[string]*servingpb.ServingStatus
	NumUnavailableShards int
	ServingOffset        int64
	ServingTs            time.Time
	PinnedServingTs      *int64
	Epoch                types.EpochID
	EpochMode            epoch.EpochMode
	NumShards            int
	IsServing            bool
	IsIndexing           bool
	IsHealing            bool
	IsBlobFiltering      bool
	ShadowTrafficPercent float32
	CacheCluster         string
	HealthScore          float32
	IndexVersion         uint32
	BinaryVersion        string
	MaxReposIndexed      uint64
}

func (c *ClusterStatusSummary) IsServingAllShards() bool {
	if c.NumUnavailableShards > 0 {
		return false
	}

	for _, status := range c.HostStatuses {
		for _, shard := range status.Shards {
			if shard.ServingTs == 0 {
				return false
			}
		}
	}

	return true
}

func clusterStatusSummary(ctx context.Context, client blackbird.Client) (*ClusterStatusSummary, error) {
	unavailableShards := 0
	statusResponses := make(chan ServingStatusResponse)
	wg := sync.WaitGroup{}

	// Collect a unique set of hosts first
	hostnames := map[string]*blackbird.IndexHost{}
	routes := client.Routes()
	for _, hosts := range routes.Hosts {
		if len(hosts) == 0 {
			unavailableShards++
			continue
		}

		for _, host := range hosts {
			hostnames[host.Hostname] = host
		}
	}

	// Call the Status RPC to get the most recent status for each host. Note that we're specifically not just using the
	// cached status that DSA updates in a background thread b/c we want to make a status call that includes source kafka
	// offsets.
	for _, host := range hostnames {
		wg.Add(1)
		go func() {
			defer utils.PanicLogger(ctx)
			defer wg.Done()

			req := &servingpb.StatusRequest{IncludeSourceKafkaInfo: true}
			var resp *servingpb.StatusResponse
			var err error
			// NB: We intentionally don't use UpdateStatus here but instead rely on
			// the background DSA client thread to manage this state.
			if host.SearchClient != nil {
				resp, err = host.SearchClient.Status(ctx, req)
			} else if host.IndexClient != nil {
				resp, err = host.IndexClient.Status(ctx, req)
			} else if host.CacheClient != nil {
				resp, err = host.CacheClient.Status(ctx, req)
			} else {
				panic("must have either at least one host client set")
			}

			if err != nil {
				logging.Error(ctx, "status request failed", kvp.Err(err), kvp.String("index_host", host.Hostname))
			} else {
				statusResponses <- ServingStatusResponse{
					Hostname:      host.Hostname,
					ServingStatus: resp.GetStatus(),
					Error:         nil,
				}
			}
		}()
	}

	go func() {
		wg.Wait()
		close(statusResponses)
	}()

	var indexVersion uint32
	var binaryVersion string
	var maxRepoCount uint64
	hostStatuses := make(map[string]*servingpb.ServingStatus, len(routes.Hosts))
	for response := range statusResponses {
		hostStatuses[response.Hostname] = response.ServingStatus

		// NB: It is possible that shards/hosts are on different binary and/or index versions.
		if binaryVersion == "" && response.ServingStatus.Sha != "" {
			binaryVersion = response.ServingStatus.Sha
			indexVersion = response.ServingStatus.IndexVersion
		}

		for _, shard := range response.ServingStatus.Shards {
			if maxRepoCount < shard.RepoCount {
				maxRepoCount = shard.RepoCount
			}
		}
	}

	return &ClusterStatusSummary{
		HostStatuses:         hostStatuses,
		NumUnavailableShards: unavailableShards,
		ServingOffset:        routes.ServingOffset,
		ServingTs:            utils.TimeFromServingTs(routes.ServingTs),
		PinnedServingTs:      client.Pin(),
		Epoch:                types.EpochID(routes.Epoch),
		EpochMode:            epoch.EpochMode(routes.EpochMode),
		NumShards:            len(routes.Hosts),
		IsServing:            client.IsServing(),
		IsIndexing:           !client.IsIndexingPaused(),
		IsHealing:            client.IsHealing(),
		IsBlobFiltering:      client.BlobFiltering(),
		ShadowTrafficPercent: client.ShadowTrafficPercent(),
		CacheCluster:         client.CacheCluster(),
		HealthScore:          client.HealthScore(),
		IndexVersion:         indexVersion,
		BinaryVersion:        binaryVersion,
		MaxReposIndexed:      maxRepoCount,
	}, nil
}

func getServingEpoch(client blackbird.Client) (types.EpochID, error) {
	routes := client.Routes()

	if routes.Epoch == 0 {
		return 0, errors.New("could not determine epoch ID")
	}

	if len(routes.Hosts) == 0 {
		return 0, errors.New("could not determine epoch ID: no shards")
	}

	if routes.ServingOffset == 0 {
		return 0, errors.New("could not determine epoch ID: serving offset 0")
	}

	return types.EpochID(routes.Epoch), nil
}

// Extract a serialized serving status from a twirp error if possible. See `UpdateStatus` for where
// status is reported back to DSA. Returns one of the following:
//
//	nil:                       Status should not be reported.
//	an empty ServingStatus:    Report that the host is unreachable.
//	a populated ServingStatus: Report to DSA.
func extractServingStatusFromErr(ctx context.Context, err error) *servingpb.ServingStatus {
	if err == nil {
		return nil
	}

	// TODO: Errors that SHOULD cause a host to be removed from routing. If there are enough of these they should be
	// moved to a helper function.
	var opError *net.OpError
	if errors.As(err, &opError) && opError.Err == syscall.ECONNREFUSED {
		// This host is dead or otherwise unreachable, setting a blank serving status will remove the
		// host from DSA.
		logging.Error(ctx, "call to a search host failed but no serving status on error: remove host", kvp.Err(err))
		return &servingpb.ServingStatus{}
	}

	status, extractErr := blackbird.ServingStatus(err)
	if extractErr != nil {
		// some sort of bug in encoding/decoding status on the twirp error we don't know the state of
		// the shard, leave status as nil which means: don't update DSA for this host.
		logging.Error(ctx, "failed to extract serving status from error: ignored", kvp.Err(extractErr))
	}
	return status
}

// Update the serving status of a index host. An empty/default status will clear
// all shard assignments for the host, a nil status will be ignored. It reports
// a metric so we can see how long this takes.
//
// This should be called on both success and error responses from all RPCs.
func updateStatus(ctx context.Context, client blackbird.Client, hostname string, status *servingpb.ServingStatus) {
	start := time.Now()

	if ctx.Err() != nil {
		// If the ctx is canceled, don't update status.
		return
	}

	if client == nil {
		return
	}

	if status == nil {
		logging.Info(ctx, "dsa: nil status, will not update host", kvp.String("index_host", hostname))
		return
	}

	if status == (&servingpb.ServingStatus{}) {
		logging.Info(ctx, "dsa: empty status, removing host", kvp.String("index_host", hostname), kvp.Any("status", status))
	}

	client.UpdateStatus(hostname, status)

	statting.DistributionMs(ctx, "dsa.update_status.duration", time.Since(start))
}
