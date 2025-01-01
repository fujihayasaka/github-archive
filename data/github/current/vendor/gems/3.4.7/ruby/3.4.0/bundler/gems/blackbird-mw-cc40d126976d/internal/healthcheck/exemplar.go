package healthcheck

import (
	"context"
	"fmt"
	"time"

	dsaclient "github.com/github/blackbird/crates/client/pkg/blackbird"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/google/uuid"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/types"
)

// runExemplarQueries runs a list of example queries against high-value
// repositories. It is not as reliable as the completeness prober, but much
// faster and gives a high-level assurance that the index is serving results.
func (p *Prober) runExemplarQueries(ctx context.Context, corpus routing.Corpus) error {
	start := time.Now()

	cluster, err := p.ComputeHealthSummary(ctx, corpus)
	if err != nil {
		return fmt.Errorf("failed to compute health summary: %w", err)
	}

	ctx = logging.With(ctx, kvp.String("corpus", corpus.String()), kvp.String("epoch_mode", cluster.Status.EpochMode.String()))
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": corpus.String(), "epoch_mode": cluster.Status.EpochMode.String()})
	defer func() {
		statting.DistributionMs(ctx, "prober.exemplar_searches.duration", time.Since(start))
	}()

	numProbed := 0
	numProbedOK := 0
	var anyErr error
	for f, exemplars := range exemplars[p.stamp] {
		if f.SupportedBy(cluster.Status.EpochMode) {
			for _, exemplar := range exemplars {
				err := p.runExemplarQuery(ctx, corpus, exemplar)
				if err != nil {
					logging.Error(ctx, "exemplar query failed", kvp.Err(err), kvp.String("exemplar_description", exemplar.description), kvp.String("exemplar_query", exemplar.query))
					anyErr = err
				} else {
					numProbedOK++
					exemplar.lastOK = time.Now()
				}
				numProbed++
				statting.Gauge(ctx, "prober.exemplar_searches.last_ok", int64(time.Since(exemplar.lastOK).Seconds()), stats.Tags{"query": exemplar.query})
			}
		}
	}

	// Report prober status to DSA
	if err := p.searchClusters.ReportProberStatus(ctx, corpus, dsaclient.ProberStatus{
		StartTs:              time.Now().UnixMilli(),
		ServingTs:            cluster.Status.ServingTs.UnixMilli(),
		ServingLagMs:         float32(cluster.ServingLag.Milliseconds()),
		IngestLagMs:          float32(cluster.IngestLag.Milliseconds()),
		NumUnavailableShards: float32(cluster.Status.NumUnavailableShards),
		NumReposProbed:       float32(numProbed),
		NumReposProbedOK:     float32(numProbedOK),
		NumReposIndexed:      float32(cluster.Status.MaxReposIndexed),
	}); err != nil {
		logging.Error(ctx, "failed to report prober status", kvp.Err(err))
	}

	return anyErr
}

type exemplar struct {
	repos       map[types.RepoID]string
	tenant      *pb.Tenant
	description string
	query       string
	experiments experiments.Experiments
	lastOK      time.Time
}

func (e exemplar) getRepoIDs() types.RepoIDSet {
	ids := types.RepoIDSet{}
	for repoID := range e.repos {
		ids[repoID] = true
	}
	return ids
}

// List of exemplar queries. These should be fairly stable search terms so that
// it doesn't break because something in the repo changed.
var exemplars = map[routing.Stamp]map[epoch.EpochFeatures][]exemplar{
	// dotcom has dedicated lexical and embeddings clusters
	routing.Dotcom: {
		epoch.EpochFeaturesLexical: {
			{
				repos:       map[types.RepoID]string{types.RepoID(3): "github/github"},
				description: "github/github",
				query:       "repo:github/github GitHub.config",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(3): "github/github"},
				description: "github/github readme",
				query:       "repo:github/github path:/README.md$/",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(3): "github/github"},
				description: "github/github bm25",
				query:       "repo:github/github prompt:\"where is the blackbird service called?\"",
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.PromptQualifierBM25},
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(2325298): "torvalds/linux"},
				description: "torvalds/linux",
				query:       "repo:torvalds/linux io_uring",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(253831084): "github/blackbird"},
				description: "github/blackbird",
				query:       "repo:github/blackbird QueryStream",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(1725199): "github-linguist/linguist"},
				description: "github-linguist/linguist",
				query:       "repo:github-linguist/linguist Rust",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(2211243): "apache/kafka"},
				description: "apache/kafka",
				query:       "repo:apache/kafka System.currentTimeMillis",
			},
			{
				description: "org with uppercase chars",
				query:       "org:DataDog",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(46020406): "instacart/carrot"},
				description: "favorite customer",
				query:       "repo:instacart/carrot",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(15539164): "databricks/universe"},
				description: "large monorepo that has experienced indexing problems",
				query:       "repo:databricks/universe",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(322927650): "anthropics/anthropic"},
				description: "large monorepo that has experienced indexing problems",
				query:       "repo:anthropics/anthropic",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(616702163): "dropbox-internal/server"},
				description: "large monorepo that has experienced indexing problems",
				query:       "repo:dropbox-internal/server",
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(251663834): "robinhoodmarkets/rh"},
				description: "large monorepo that has experienced indexing problems",
				query:       "repo:robinhoodmarkets/rh",
			},
			// BM25 queries
			{
				repos:       map[types.RepoID]string{types.RepoID(253831084): "github/blackbird"},
				description: "github/blackbird bm25",
				query:       `repo:github/blackbird prompt:"how is the document SHA computed for a document?"`,
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.PromptQualifierBM25},
			},
		},
		epoch.EpochFeaturesEmbeddings: {
			{
				repos:       map[types.RepoID]string{types.RepoID(3): "github/github"},
				description: "github/github embeddings",
				query:       `repo:github/github prompt:"where is the blackbird service called?"`,
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.Enabled},
			},
			{
				repos:       map[types.RepoID]string{types.RepoID(253831084): "github/blackbird"},
				description: "github/blackbird embeddings",
				query:       `repo:github/blackbird prompt:"how is the document SHA computed for a document?"`,
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.Enabled},
			},
		},
	},
	// We run hybrid clusters in proxima
	routing.StaffWUS201: {
		epoch.EpochFeaturesLexical: {
			{
				repos:       map[types.RepoID]string{types.RepoID(2211821): "github/octoshift"},
				description: "github/octoshift in the github tenant",
				query:       "repo:github/octoshift CustomerQueue",
				tenant:      &pb.Tenant{Shortcode: "iaharvqc"},
			},
			// BM25 query
			{
				repos:       map[types.RepoID]string{types.RepoID(2211821): "github/octoshift"},
				description: "github/octoshift bm25",
				query:       "repo:github/octoshift prompt:\"where is the customer queue defined?\"",
				tenant:      &pb.Tenant{Shortcode: "iaharvqc"},
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.PromptQualifierBM25},
			},
		},
		epoch.EpochFeaturesEmbeddings: {
			{
				repos:       map[types.RepoID]string{types.RepoID(2211821): "github/octoshift"},
				description: "github/octoshift embeddings",
				query:       "repo:github/octoshift prompt:\"where is the customer queue defined?\"",
				tenant:      &pb.Tenant{Shortcode: "iaharvqc"},
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.Enabled},
			},
		},
	},
	// See: https://github.com/github/blackbird/blob/main/docs/proxima-cheat-sheet.md#stamps-active
	routing.ProdWEU01: genericProximaExemplars("ts6phzva", types.RepoID(1020816)), // https://devportal.githubapp.com/proxima/stamps/prod-weu-01/tenants/test-prodweu01
	routing.ProdSDC01: genericProximaExemplars("zoeyc8od", types.RepoID(10856)),   // https://devportal.githubapp.com/proxima/stamps/prod-sdc-01/tenants/test-prodsdc01
	routing.ProdAE01:  genericProximaExemplars("k9779lvl", types.RepoID(51)),      // https://devportal.githubapp.com/proxima/stamps/prod-ae-01/tenants/stafftools-prodae01
}

func genericProximaExemplars(shortcode string, repoID types.RepoID) map[epoch.EpochFeatures][]exemplar {
	return map[epoch.EpochFeatures][]exemplar{
		epoch.EpochFeaturesLexical: {
			{
				repos:       map[types.RepoID]string{repoID: "rnkaufman/test-search"},
				description: "rnkaufman/test-search",
				query:       "repo:rnkaufman/test-search jsonfile",
				tenant:      &pb.Tenant{Shortcode: shortcode},
			},
			// BM25 query
			{
				repos:       map[types.RepoID]string{repoID: "rnkaufman/test-search"},
				description: "rnkaufman/test-search bm25",
				query:       "repo:rnkaufman/test-search prompt:\"json\"",
				tenant:      &pb.Tenant{Shortcode: shortcode},
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.PromptQualifierBM25},
			},
		},
		epoch.EpochFeaturesEmbeddings: {
			{
				repos:       map[types.RepoID]string{repoID: "rnkaufman/test-search"},
				description: "rnkaufman/test-search embeddings",
				query:       "repo:rnkaufman/test-search prompt:\"check links on markdown files\"",
				tenant:      &pb.Tenant{Shortcode: shortcode},
				experiments: experiments.Experiments{experiments.PromptQualifier: experiments.Enabled},
			},
		},
	}
}

func (p *Prober) runExemplarQuery(ctx context.Context, corpus routing.Corpus, exemplar exemplar) error {
	start := time.Now()
	rid := uuid.New().String()
	ctx = requestid.WithGitHubRequestID(ctx, rid)
	ctx = experiments.WithExperiments(ctx, exemplar.experiments)
	ctx = logging.With(ctx, kvp.String("request_id", rid), kvp.String("query", exemplar.query))

	ctx, cancel := context.WithTimeout(ctx, proberRequestTimeout)
	defer cancel()

	parsed, err := parser.ParseQuery(ctx, exemplar.query)
	if err != nil {
		panic(fmt.Sprintf("exemplar query %q didn't parse: %+v", exemplar.query, err))
	}

	index, err := blackbird.GetClusterWithoutBlobResolution(ctx, p.searchClusters, p.store, p.pager, corpus)
	if err != nil {
		return err
	}

	// NB: 0 is the ghost user, probers need access to the exemplar query's
	// repository, but they don't look at specific results.
	actor := &models.Actor{ID: 0, AccessiblePrivateRepoIDs: exemplar.getRepoIDs()}

	// Let's make sure that the repo is present in the index first. Otherwise the subsequent
	// rewriting will produce an invalid AST.
	for repoID := range exemplar.getRepoIDs() {
		repo, err := index.GetRepositoryByID(ctx, actor, repoID)
		if err != nil {
			return err
		}
		if repo == nil {
			return fmt.Errorf("repo ID %d does not exist in the index", repoID)
		}
	}

	promptRewriter := parser.GetPromptRewriter(ctx, p.copilotClient, corpus)

	if _, _, err = parser.RewriteQuery(ctx, parsed, actor, exemplar.tenant, index, nil /* custom scopes map */, promptRewriter); err != nil {
		return err
	}

	queryCtx := search.BuildQueryContext(
		actor,
		search.QueryLimits{
			RequestedDocs:  1,
			RequestedLocs:  1,
			LocationsLimit: 1,
			TermMatchLimit: 1,
			ToRetrieve:     300,
			ToScore:        3,
			ToReturn:       1,
			WithContent:    0, // NB: Probers do not need any content
		},
		search.DefaultRetries,
		search.ProbersUnavailableShardsPercent,
		proberRPCTimeout,
		search.QueryTypeExemplar,
		search.QuerySourceProber,
		parser.GetScopeRepoIDs(parsed),
		nil, /* snippetOptions */
		nil, /* paginationOptions */
		parser.Serialize(parsed),
		false, /* returnEnclosingSymbols */
	)

	defer func() {
		statting.DistributionMs(ctx, "prober.exemplar_search.duration", time.Since(start), stats.Tags{"query": exemplar.query})
	}()

	res, err := index.Search(ctx, parser.ConvertToProto(parsed), queryCtx)
	switch {
	case err != nil:
		return err
	case len(res.QueryErrors) > 0:
		for _, e := range res.QueryErrors {
			return fmt.Errorf("query errors in exemplar query: %s: %s", e.Type, e.Message)
		}
	case len(res.Documents) == 0:
		return errors.New("query returned no results")
	}

	return nil
}
