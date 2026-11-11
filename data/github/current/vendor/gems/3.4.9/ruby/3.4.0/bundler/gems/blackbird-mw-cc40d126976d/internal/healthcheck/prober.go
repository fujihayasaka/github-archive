package healthcheck

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"sync"
	"time"

	"github.com/IBM/sarama"
	dsaclient "github.com/github/blackbird/crates/client/pkg/blackbird"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	"github.com/google/uuid"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
)

const (
	proberRequestTimeout = 10 * time.Second // Overall request timeout for prober RPCs
	proberRPCTimeout     = 9 * time.Second  // Timeout passed to blackbird search RPCs

	// minCycleDuration is the minimum amount of time allowed for a cycle
	// through the repositories. The prober will pause if it finishes a fraction
	// of the cycle in less than the same fraction of this total minimum
	// duration. This prevents excessive healing which especially causes
	// problems with embeddings clusters where ingests take a very long time.
	minCycleDuration = 24 * time.Hour
)

// probeResult contains the results of a probing repos in a snapshot interval.
type probeResult struct {
	NextHashValue  uint64         // NextHashValue is the hash value to use for the next check.
	NextCursor     string         // NextCursor is the cursor to use for the next check.
	NumReposProbed int            // NumReposProbed is the number of repositories probed.
	HealDecisions  []healDecision // HealDecisions is a list of healing decisions.
}

var (
	healDiscrepancy        string = "heal_discrepancy"
	healRepoNotFound       string = "heal_repo_not_found"
	healRepoNotIndexed     string = "heal_repo_not_indexed"
	healRepoPermanentError string = "heal_repo_permanent_error"
)

type healDecision struct {
	repoID      types.RepoID
	reason      string
	change      searchpb.RepositoryChanged_Change // Change type. Usually ADMIN_PUSH is what you want. Use ADMIN_REPAIR to force reindexing (necessary to clear permanent errors).
	discrepancy *discrepancy
}

// discrepancy records the repo metadata field and value discrepancies found by comparing repos from Blackbird with the GitHub internal API.
type discrepancy struct {
	field          string
	blackbirdValue string
	githubValue    string
}

type Prober struct {
	store             db.Store
	stamp             routing.Stamp
	pager             cache.Store
	gitClient         gitaccess.Client
	searchClusters    *routing.SearchClusters
	indexerClusters   *routing.IndexerClusters
	limitsCalc        *search.LimitsCalculator
	sharedKafkaClient sarama.Client
	githubClient      github.InternalAPIClient
	repoPublisher     *repo.Publisher
	copilotClient     copilot.Client
	tsReader          *kafka.DelayedTimestampReader
	wg                sync.WaitGroup
}

func NewProber(
	store db.Store,
	pager cache.Store,
	gitClient gitaccess.Client,
	stamp routing.Stamp,
	searchClusters *routing.SearchClusters,
	indexerClusters *routing.IndexerClusters,
	sharedKafkaClient sarama.Client,
	githubClient github.InternalAPIClient,
	repoPublisher *repo.Publisher,
	copilotClient copilot.Client,
	tsReader *kafka.DelayedTimestampReader,
) *Prober {
	return &Prober{
		store:             store,
		stamp:             stamp,
		pager:             pager,
		gitClient:         gitClient,
		searchClusters:    searchClusters,
		indexerClusters:   indexerClusters,
		limitsCalc:        search.NewLimitsCalculator(),
		sharedKafkaClient: sharedKafkaClient,
		copilotClient:     copilot.NewCachingClient(copilotClient, 10*time.Minute),
		githubClient:      githubClient,
		repoPublisher:     repoPublisher,
		tsReader:          tsReader,
	}
}

// Run invokes the various probers to run concurrently for each corpus enabled in the environment.
// It also includes a single prober that monitors overall (cross-corpus) system health.
func (p *Prober) Run(ctx context.Context) {
	ctx = logging.With(ctx, kvp.String("component", "prober"))

	run := func(ctx context.Context, f func(ctx context.Context), d time.Duration) {
		p.wg.Add(1)
		go func() {
			defer p.wg.Done()
			defer utils.PanicLogger(ctx)

			ticker := time.NewTicker(d)
			defer ticker.Stop()

			for {
				f(ctx)

				select {
				case <-ticker.C:
					continue
				case <-ctx.Done():
					return
				}
			}

		}()
	}

	run(ctx, p.runHealthProbe, 9*time.Second+time.Duration(rand.Intn(4000)-2000)*time.Millisecond)

	for _, corpus := range p.stamp.EnabledCorpora() {
		corpus := corpus
		run(ctx, func(ctx context.Context) { p.runExemplarProbe(ctx, corpus) }, 9*time.Second+time.Duration(rand.Intn(4000)-2000)*time.Millisecond)
		run(ctx, func(ctx context.Context) { p.runCompletenessProbe(ctx, corpus) }, 1*time.Second)
		run(ctx, p.runRepoMetadataProbe(corpus), 5*time.Second+time.Duration(rand.Intn(4000)-2000)*time.Millisecond)
	}
}

func (p *Prober) Shutdown() {
	p.wg.Wait()
}

// The health probe reports status for each corpus and overall system health.
func (p *Prober) runHealthProbe(ctx context.Context) {
	ctx = logging.With(ctx, kvp.String("prober", "health"))
	ctx = statting.WithTags(ctx, stats.Tags{"prober": "health"})

	clusterHealthStates := []clusterHealthState{}
	for _, corpus := range p.stamp.EnabledCorpora() {
		ctx := requestid.WithGitHubRequestID(ctx, uuid.New().String())
		ctx = logging.With(ctx, kvp.String("corpus", corpus.String()))
		ctx = statting.WithTags(ctx, stats.Tags{"corpus": corpus.String()})

		cluster, err := p.ComputeHealthSummary(ctx, corpus)
		if err != nil {
			logging.Error(ctx, "failed to compute health summary", kvp.Err(err))
			statting.Counter(ctx, "healthcheck.corpus_status", 1, stats.Tags{"category": HealthStateUnknown.String(), "status": HealthStateUnknown.StatsTag()})
			continue
		}
		clusterHealthStates = append(clusterHealthStates, clusterHealthState{cluster.HealthState, cluster.Status.EpochMode})
		ctx = statting.WithTags(ctx, stats.Tags{"epoch_mode": cluster.Status.EpochMode.String()})

		// Stat the health state of the corpus
		statting.Counter(ctx, "healthcheck.corpus_status", 1, stats.Tags{"category": cluster.HealthState.String(), "status": cluster.HealthState.StatsTag()})

		// Stat the current health score (and ingest lag)
		score := p.searchClusters.HealthScore(corpus)
		statting.Gauge(ctx, "healthcheck.corpus_health_score", int64(score*1000)) // why can't you stat a float?
		statting.Gauge(ctx, "prober.max_ingest_lag", cluster.IngestLag.Milliseconds())

		for hostname, host := range cluster.Status.HostStatuses {
			for _, s := range host.Shards {
				statting.Gauge(ctx, "healthcheck.shard_status.serving_ts", s.ServingTs, stats.Tags{"shard_host": hostname, "shard_id": fmt.Sprintf("%d", s.Id)})

				// TODO: Remove this stat as it is based on time.now (note that this might break our
				// existing monitors and graphs)
				delta := time.Since(utils.TimeFromServingTs(s.ServingTs))
				statting.Gauge(ctx, "healthcheck.shard_status.serving_ts_delta", delta.Milliseconds(), stats.Tags{"shard_host": hostname, "shard_id": fmt.Sprintf("%d", s.Id)})
			}
		}
	}

	status := overallSystemHealth(clusterHealthStates)
	statting.Counter(ctx, "healthcheck.system_status", 1, stats.Tags{"status": status})
}

type clusterHealthState struct {
	healthState HealthState
	epochMode   epoch.EpochMode
}

func overallSystemHealth(clusters []clusterHealthState) string {
	lexicalOK := false
	bm25OK := false
	embeddingsOK := false
	for _, cluster := range clusters {
		if cluster.healthState == HealthStateValid {
			if epoch.EpochFeaturesBM25.SupportedBy(cluster.epochMode) {
				bm25OK = true
			}
			if epoch.EpochFeaturesLexical.SupportedBy(cluster.epochMode) {
				lexicalOK = true
			}
			if epoch.EpochFeaturesEmbeddings.SupportedBy(cluster.epochMode) {
				embeddingsOK = true
			}
		}
	}

	if lexicalOK && bm25OK && embeddingsOK {
		return "healthy"
	}

	return "unhealthy"
}

// The exemplar probe queries a few specific repositories and reports stats.
func (p *Prober) runExemplarProbe(ctx context.Context, corpus routing.Corpus) {
	ctx = logging.With(ctx, kvp.String("prober", "exemplar"), kvp.String("corpus", corpus.String()))
	ctx = statting.WithTags(ctx, stats.Tags{"prober": "exemplar", "corpus": corpus.String()})
	if err := p.runExemplarQueries(ctx, corpus); err != nil {
		recordFailedProbe(ctx, "an exemplar query failed", err)
	}
}

// The completeness probe grabs a random repository and checks that it's been
// properly indexed by comparing what's in blackbird vs. what's in git.
func (p *Prober) runCompletenessProbe(ctx context.Context, corpus routing.Corpus) {
	rid := uuid.New().String()
	ctx = requestid.WithGitHubRequestID(ctx, rid)
	ctx = logging.With(ctx, kvp.String("request_id", rid), kvp.String("prober", "completeness"), kvp.String("corpus", corpus.String()))
	ctx = statting.WithTags(ctx, stats.Tags{"prober": "completeness", "corpus": corpus.String()})

	start := time.Now()
	err := p.runCompletenessChecks(ctx, corpus)
	if err != nil {
		recordFailedProbe(ctx, "completeness check failed", err)
	}
	statting.DistributionMs(ctx, "prober.completeness.duration", time.Since(start))
}

// The repo metadata probe iterates over repository metadata in a snapshot index
// with the goal to maintain stable repo metadata in Blackbird compared with the
// `repositories` table in dotcom.
func (p *Prober) runRepoMetadataProbe(corpus routing.Corpus) func(context.Context) {
	// hashValue tracks the most recently returned hash value from the
	// snapshot interval search used by the repo metadata prober.
	// cursor tracks the cursor returned from the repo batch query endpoint.
	// Both values represent where the next check should begin for snapshot
	// search and for iterating over all repos in dotcom. These values
	// are closed over in the returned function below, and their updated values
	// are reassigned based on the return values from the `Check` method.
	hashValue := rand.Uint64()
	cursor := "1"

	return func(ctx context.Context) {
		start := time.Now()
		rid := uuid.New().String()
		ctx = requestid.WithGitHubRequestID(ctx, rid)
		ctx = logging.With(ctx,
			kvp.String("request_id", rid),
			kvp.String("stamp", string(p.stamp)),
			kvp.String("prober", "repo_metadata"),
			kvp.String("corpus", corpus.String()),
			kvp.Uint64("hashValue", hashValue),
			kvp.String("cursor", cursor),
			kvp.Int("batch_size", batchSize),
		)
		ctx = statting.WithTags(ctx, stats.Tags{"prober": "repo_metadata", "corpus": corpus.String()})

		cluster, err := p.ComputeHealthSummary(ctx, corpus)
		if err != nil {
			recordFailedProbe(ctx, "repo metadata probe failed to get cluster status", err)
			return
		}
		ctx = logging.With(ctx, kvp.Bool("healing_enabled", cluster.Status.IsHealing))
		ctx = statting.WithTags(ctx, stats.Tags{"epoch_mode": cluster.Status.EpochMode.String()})

		repoMetadataProber := newRepoMetadataProber(p)
		skipReason := ShouldSkipProbe(cluster)
		if skipReason != "" {
			logging.Info(ctx, "skipping repo metadata check", kvp.String("reason", skipReason))
			return
		}

		probeResult, err := repoMetadataProber.Check(ctx, corpus, hashValue, cursor)
		if err != nil {
			statting.DistributionMs(ctx, "prober.repo_metadata.duration", time.Since(start), stats.Tags{"status": "error"})
			recordFailedProbe(ctx, "repo metadata check failed", err)
			return
		}

		statting.DistributionMs(ctx, "prober.repo_metadata.duration", time.Since(start), stats.Tags{"status": "success"})

		for _, healDecision := range probeResult.HealDecisions {
			statsTags := stats.Tags{"heal_reason": healDecision.reason}
			logFields := []kvp.Field{kvp.String("heal_reason", healDecision.reason), kvp.Uint64("repo_id", uint64(healDecision.repoID))}
			if healDecision.discrepancy != nil && healDecision.discrepancy.field != "" {
				statsTags = statsTags.Merge(stats.Tags{"heal_field": healDecision.discrepancy.field})
				logFields = append(logFields, kvp.String("heal_field", healDecision.discrepancy.field), kvp.String("heal_bb_value", healDecision.discrepancy.blackbirdValue), kvp.String("heal_gh_value", healDecision.discrepancy.githubValue))
			}
			logging.Info(ctx, "healing action required", logFields...)
			statting.Counter(ctx, "prober.repo_metadata.heal", 1, statsTags)
			if cluster.Status.IsHealing {
				err := p.repoPublisher.PublishChange(ctx, healDecision.repoID, healDecision.change, corpus.String())
				if err != nil {
					logging.Error(ctx, "repo metadata failed to publish", kvp.Err(err))
					return
				}
			}
		}

		intervalDuration := time.Since(start)
		pauseDuration := targetDuration(hashValue, probeResult.NextHashValue) - intervalDuration

		// Finally, update the hash value and cursor for the next iteration.
		hashValue = probeResult.NextHashValue
		cursor = probeResult.NextCursor

		// Only report prober status in dotcom to debug problems with repo
		// metadata prober checks in proxima stamps.
		if p.stamp == routing.Dotcom {
			// Report prober status to DSA
			if err := p.searchClusters.ReportProberStatus(ctx, corpus, dsaclient.ProberStatus{
				StartTs:              time.Now().UnixMilli(),
				ServingTs:            cluster.Status.ServingTs.UnixMilli(),
				ServingLagMs:         float32(cluster.ServingLag.Milliseconds()),
				IngestLagMs:          float32(cluster.IngestLag.Milliseconds()),
				NumUnavailableShards: float32(cluster.Status.NumUnavailableShards),
				NumReposProbed:       float32(probeResult.NumReposProbed),
				NumReposProbedOK:     float32(probeResult.NumReposProbed - len(probeResult.HealDecisions)),
				NumReposIndexed:      float32(cluster.Status.MaxReposIndexed),
			}); err != nil {
				logging.Error(ctx, "failed to report prober status", kvp.Err(err))
			}
		}

		if pauseDuration > 0 {
			logging.Info(
				ctx,
				"finished fraction of repo metadata probe cycle under minimum target duration, pausing",
				kvp.Duration("interval_duration", intervalDuration),
				kvp.Duration("pause_duration", pauseDuration),
			)
			time.Sleep(pauseDuration)
		}
	}
}

// Record a failed prober, noop if the context is cancelled.
func recordFailedProbe(ctx context.Context, msg string, err error) {
	if ctx.Err() != nil {
		return
	}
	logging.Error(ctx, msg, kvp.Err(err))
	statting.Counter(ctx, "prober.failed_probe_attempts", 1)
}

// targetDuration calculates how long to a probe interval SHOULD take based on
// the minimum cycle duration (minCycleDuration).
func targetDuration(hashValue, nextHashValue uint64) time.Duration {
	intervalFraction := float64(nextHashValue-hashValue) / math.MaxUint64
	targetDuration := time.Duration(intervalFraction * float64(minCycleDuration))

	return targetDuration
}
