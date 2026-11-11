package query

import (
	"cmp"
	"context"
	"fmt"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/cenkalti/backoff/v4"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-reqmeta"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/durationpb"

	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/alephcompat"
	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/query/timing"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/redact"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/suggest"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
)

type queryService struct {
	stamp              routing.Stamp
	indexerClusters    *routing.IndexerClusters
	clusters           *routing.SearchClusters
	store              db.Store
	pager              cache.Store
	authClient         *auth.Client
	quotaRateEstimator quota.RateEstimator
	limitsCalc         *search.LimitsCalculator
	treelightsClient   treelights.Client
	gitClient          gitaccess.Client
}

func NewService(
	stamp routing.Stamp,
	indexerClusters *routing.IndexerClusters,
	clusters *routing.SearchClusters,
	store db.Store,
	pager cache.Store,
	authClient *auth.Client,
	quotaRateEstimator quota.RateEstimator,
	treelightsClient treelights.Client,
	gitClient gitaccess.Client,
) pb.QueryAPI {
	return &queryService{
		stamp,
		indexerClusters,
		clusters,
		store,
		pager,
		authClient,
		quotaRateEstimator,
		search.NewLimitsCalculator(),
		treelightsClient,
		gitClient,
	}
}

func (s *queryService) Query(ctx context.Context, req *pb.QueryRequest) (*pb.QueryResponse, error) {
	// Enforce overall request timeout
	timeout := search.SearchTimeout(req.RequestTimeout)
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	resp, err := s.doQueryRPC(ctx, req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "query timed out", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}

		return nil, err
	}

	return resp, nil
}

type commonQueryRequest struct {
	Query                  string
	QueryParser            pb.QueryParser
	DocumentLimit          uint32
	DocumentLocationLimit  uint32
	ScopingQuery           string
	Actor                  *pb.Actor
	EpochID                types.EpochID
	CustomScopes           []*pb.CustomScope
	SnippetOptions         *pb.SnippetOptions
	QueryType              search.QueryType
	RequestTimeout         *durationpb.Duration
	QuerySource            search.QuerySource
	PageNumber             uint32
	ResultsPerPage         uint32
	Experiments            map[string]string
	ReturnEnclosingSymbols bool
	Tenant                 *pb.Tenant
	SingleRepoID           types.RepoID
}

type parsedQuery struct {
	// Just the user query (`CommonQueryRequest.Query`)
	user *parser.Query
	// Full parsed query, including the `ScopingQuery` if any
	full *parser.Query
	// Any errors from parsing, kept around for quota tracking and friendly error messages
	parseError *pb.QueryError
}

func convertQueryRequest(ctx context.Context, req *pb.QueryRequest) *commonQueryRequest {
	return &commonQueryRequest{
		Query:                  req.Query,
		QueryParser:            req.QueryParser,
		DocumentLimit:          req.DocumentLimit,
		DocumentLocationLimit:  req.DocumentLocationLimit,
		ScopingQuery:           req.ScopingQuery,
		Actor:                  req.Actor,
		EpochID:                types.EpochID(req.EpochId),
		CustomScopes:           req.CustomScopes,
		SnippetOptions:         req.SnippetOptions,
		QueryType:              getQueryType(ctx, req.QueryType),
		RequestTimeout:         req.RequestTimeout,
		QuerySource:            getQuerySource(ctx, req.QuerySource),
		PageNumber:             req.PageNumber,
		ResultsPerPage:         req.ResultsPerPage,
		Experiments:            req.Experiments,
		ReturnEnclosingSymbols: req.ReturnEnclosingSymbols,
		Tenant:                 req.Tenant,
	}
}

func convertSuggestRequest(ctx context.Context, req *pb.SuggestRequest) *commonQueryRequest {
	return &commonQueryRequest{
		Query:        req.Query,
		QueryParser:  pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		ScopingQuery: req.ScopingQuery,
		Actor:        req.Actor,
		EpochID:      types.AnyEpoch, // NB: Suggest queries can't select a cluster by epoch
		CustomScopes: req.CustomScopes,
		QueryType:    search.QueryTypeSuggest,
		QuerySource:  search.QuerySourceFE,
		Tenant:       req.Tenant,
		Experiments:  req.Experiments,
	}
}

func convertCountRequest(ctx context.Context, req *pb.CountRequest) *commonQueryRequest {
	return &commonQueryRequest{
		Query:        req.Query,
		QueryParser:  pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		ScopingQuery: req.ScopingQuery,
		Actor:        req.Actor,
		EpochID:      types.EpochID(req.EpochId),
		CustomScopes: req.CustomScopes,
		QueryType:    search.QueryTypeCount,
		QuerySource:  search.QuerySourceFE,
		Experiments:  req.Experiments,
		Tenant:       req.Tenant,
	}
}

func convertLocationRequest(req *pb.AlephLocationRequest, query string, queryType search.QueryType, actor *pb.Actor, tenant *pb.Tenant, experiments map[string]string) *commonQueryRequest {
	return &commonQueryRequest{
		Query:                  query,
		DocumentLimit:          10, // as per Aleph source
		DocumentLocationLimit:  10, // ditto
		ScopingQuery:           fmt.Sprintf("repo_id:%d", req.RepositoryId),
		Actor:                  actor,
		EpochID:                types.AnyEpoch,
		QueryType:              queryType,
		QuerySource:            search.QuerySourceAleph,
		Experiments:            experiments,
		Tenant:                 tenant,
		RequestTimeout:         durationpb.New(search.LocationRequestTimeout),
		ReturnEnclosingSymbols: true,
		SingleRepoID:           types.RepoID(req.RepositoryId),
	}
}

func (q *commonQueryRequest) parse(ctx context.Context) *parsedQuery {
	start := time.Now()

	parserType := q.QueryParser
	if v, ok := q.Experiments[experiments.UseGeyserQueryLanguage]; ok && v != experiments.Disabled {
		parserType = pb.QueryParser_QUERY_PARSER_GEYSER
	}

	var userQuery *parser.Query
	var err error
	switch parserType {
	case pb.QueryParser_QUERY_PARSER_GEYSER:
		userQuery, err = parser.ParseGeyserQuery(ctx, q.Query)
	default:
		userQuery, err = parser.ParseQuery(ctx, q.Query)
	}

	if err != nil {
		statting.Counter(ctx, "query_service.query.parse_errors", 1, stats.Tags{"type": string(q.QueryType)})
		return &parsedQuery{parseError: &queryErrorParseFail}
	}

	parsedScope, err := parser.ParseQuery(ctx, q.ScopingQuery)
	if err != nil {
		statting.Counter(ctx, "query_service.scoping_query.parse_errors", 1, stats.Tags{"type": string(q.QueryType)})
		return &parsedQuery{parseError: &queryErrorScopeParseFail}
	}

	full := userQuery
	if !parsedScope.IsNothing() {
		// Remove range information from the scope, since it isn't part of the user's query
		parser.ClearRangeInformation(parsedScope)
		full = parser.And(userQuery, parsedScope)
	}
	timing.Record(ctx, timing.QueryStepParseQuery, start)

	return &parsedQuery{user: userQuery, full: full}
}

func (s *queryService) doQueryRPC(ctx context.Context, req *pb.QueryRequest) (*pb.QueryResponse, error) {
	rpcStart := time.Now()
	qreq := convertQueryRequest(ctx, req)
	ctx, prepared, err := s.prepareContext(ctx, qreq)
	if err != nil {
		logging.Error(ctx, "prepareContext failed", kvp.Err(err))
		return nil, err
	}

	resp, _, err := s.query(ctx, qreq, prepared, epoch.EpochFeaturesLexical, rpcStart, false /* includeTOSWarning */)
	return resp, err
}

// Used only when the single accessible repository optimization is applicable. Do the snapshot
// query to look up the repository ID. Return the repo ID and cache the results of the snapshot
// query. If anything goes wrong, return 0.
func (r *commonQueryRequest) querySingleRepoID(ctx context.Context, cluster *blackbird.Cluster, tenant *pb.Tenant, nwo types.NWO) (*snapshotpb.SearchSnapshotsResponse, types.RepoID) {
	res, err := cluster.SearchSnapshotsByNWO(ctx, tenant, nwo, r.QuerySource)
	if err != nil {
		logging.Error(ctx, "snapshot search failed when trying to resolve single repo", kvp.Err(err))
		return nil, 0
	}

	for _, s := range res.Snapshots {
		for _, e := range s.Entries {
			// If there is no NWO, exclude the snapshot. This may be the case for some permanent error snapshots.
			if e.Nwo != "" {
				return res, types.RepoID(e.RepoId)
			}
		}
	}
	return res, 0
}

func (s *queryService) query(ctx context.Context, req *commonQueryRequest, prepared *prepareContextResult, cap epoch.EpochFeatures, rpcStart time.Time, includeTOSWarning bool) (*pb.QueryResponse, context.Context, error) {
	limits := s.limitsCalc.Calculate(
		ctx,
		prepared.index.NumShards(),
		req.DocumentLimit,
		req.DocumentLocationLimit,
	)

	// Prepare and issue query tracking quota.
	var response *pb.QueryResponse
	if err := s.withQuota(ctx, prepared.actor.ID, req.QuerySource, req.QueryType, includeTOSWarning, func() (float32, error) {
		var cost float32
		var err error
		response, cost, err = s.performSearch(ctx, req, prepared, limits, rpcStart)
		return cost, err
	}); err != nil {
		return nil, ctx, err
	}

	statResponse(ctx, response)

	return response, ctx, nil
}

func (s *queryService) performSearch(
	ctx context.Context,
	qreq *commonQueryRequest,
	preparedCtx *prepareContextResult,
	limits search.QueryLimits,
	rpcStart time.Time,
) (*pb.QueryResponse, float32, error) {
	actor := preparedCtx.actor
	preparedQuery, err := s.prepareQuery(ctx, qreq, preparedCtx)
	if err != nil {
		return nil, preparedQuery.cost, err
	}
	if preparedQuery.fatal {
		response, err := shortCircuitQueryResult(ctx, preparedCtx.actor, preparedQuery.queryErrors...)
		return response, preparedQuery.cost, err
	}
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx, kvp.String("parsed_query", redact.Redact(parser.Serialize(preparedQuery.query))))
	}

	if mode, ok := experiments.GetExperiment(ctx, experiments.SnippetMode); ok {
		switch mode {
		case experiments.SnippetModeUnified:
			qreq.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_UNIFIED
			if qreq.SnippetOptions.DoubleSnippetContextLines == 0 {
				qreq.SnippetOptions.DoubleSnippetContextLines = 1
			}
			if qreq.SnippetOptions.SingleSnippetContextLines == 0 {
				qreq.SnippetOptions.SingleSnippetContextLines = 3
			}
		case experiments.SnippetModeHighDensity:
			qreq.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_HIGH_DENSITY
		case experiments.SnippetModeAuto:
			qreq.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_AUTO
		case experiments.SnippetModeRaw:
			qreq.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_RAW_MATCHES
		case experiments.SnippetModeLLM:
			qreq.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_LLM
		}
	}

	// Cluster query timeout: the requested timeout from the RPC, minus the time
	// we've spent so far.
	//
	// NB: DO NOT enforce any content.WithTimeout in here (callers must do that).
	timeout := search.SearchTimeout(qreq.RequestTimeout) - time.Since(rpcStart)

	queryCtx := search.BuildFEUserQueryContext(
		actor,
		limits,
		qreq.QueryType,
		qreq.QuerySource,
		timeout,
		parser.GetScopeRepoIDs(preparedQuery.query),
		qreq.SnippetOptions,
		&search.PaginationOptions{
			PageIdx: qreq.PageNumber,
			PerPage: qreq.ResultsPerPage,
		},
		QueryCacheKey(qreq),
		qreq.ReturnEnclosingSymbols,
	)

	response, err := preparedCtx.index.Search(ctx, parser.ConvertToProto(preparedQuery.query), queryCtx)
	if err != nil {
		statting.Counter(ctx, "query_service.query.failure", 1)
		return nil, preparedQuery.cost, err
	}

	// Capture some stats in order to observe how accessible repo/org filters added to global queries are performing and
	// to get some data about the distribution of accessible resource counts for users.
	tags := stats.Tags{
		"filtered_by":  string(preparedQuery.filteredBy),
		"query_type":   string(qreq.QueryType),
		"query_source": string(qreq.QuerySource),
	}
	statting.Distribution(ctx, "query_service.query.accessible_private_repos.count", float64(len(actor.AccessiblePrivateRepoIDs)), tags)
	statting.Distribution(ctx, "query_service.query.accessible_organizations.count", float64(len(actor.AccessibleOrganizationIDs)), tags)
	statting.Distribution(ctx, "query_service.query.num_results_filtered.count", float64(response.Metadata.NumFilteredDocuments), tags)

	response.QueryErrors = append(response.QueryErrors, preparedQuery.queryErrors...)
	response.ProtectedOrganizationIds = actor.ProtectedOrganizationIDs
	return response, response.Metadata.TotalCost + preparedQuery.cost, err
}

func (s *queryService) Suggest(ctx context.Context, req *pb.SuggestRequest) (*pb.SuggestResponse, error) {
	// Enforce overall request timeout
	timeout := search.SuggestTimeout(req.RequestTimeout)
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	resp, err := s.doSuggestRPC(ctx, req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "suggest timed out", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}

		return nil, err
	}

	return resp, nil
}

func (s *queryService) doSuggestRPC(ctx context.Context, req *pb.SuggestRequest) (*pb.SuggestResponse, error) {
	rpcStart := time.Now()

	qreq := convertSuggestRequest(ctx, req)
	ctx, preparedCtx, err := s.prepareContext(ctx, qreq)
	if err != nil {
		logging.Error(ctx, "prepareContext failed", kvp.Err(err))
		return nil, err
	}

	prepared, err := s.prepareQuery(ctx, qreq, preparedCtx)
	if err != nil {
		return nil, err
	}
	if prepared.fatal {
		return shortCircuitSuggestResult(ctx, prepared.queryErrors...)
	}

	// Map text queries into path queries, so that we don't search content when providing suggestions
	parser.RewriteQueryForSuggestions(prepared.query)
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx, kvp.String("parsed_query", redact.Redact(parser.Serialize(prepared.query))))
	}

	queryCtx := search.BuildFESuggestQueryContext(
		preparedCtx.actor,
		search.SuggestTimeout(req.RequestTimeout)-time.Since(rpcStart),
		parser.GetScopeRepoIDs(prepared.query),
		SuggestCacheKey(req), // NOTE: suggest queries don't make use of the cache key yet...
	)

	// Suggest based on blackbird-mw info
	suggestions := suggest.Suggest(ctx, prepared.query, req.Query, req.CursorPosition, preparedCtx.index, preparedCtx.actor)

	if len(prepared.queryErrors) > 0 || !parser.IsScoped(prepared.query) {
		// Skip reaching out to blackbird if there are any query errors
		// Don't provide path/symbol suggestions for unscoped queries
		return &pb.SuggestResponse{
			Suggestions: suggest.ConvertToProto(suggestions),
			QueryErrors: prepared.queryErrors,
			Metadata: &pb.Metadata{
				QueryAst:    parser.Serialize(prepared.query),
				Experiments: experiments.GetExperiments(ctx),
				Timing:      blackbird.MapTimings(timing.Finish(ctx)),
			},
		}, nil
	}

	// Issue the suggest query tracking user quotas
	var metadata *pb.Metadata
	err = s.withQuota(ctx, queryCtx.Actor.ID, queryCtx.QuerySource, queryCtx.QueryType, false, func() (float32, error) {
		queryResponse, bbErr := preparedCtx.index.Search(ctx, parser.ConvertToProto(prepared.query), queryCtx)
		if bbErr != nil {
			return 0, bbErr
		}

		// Capture some stats in order to observe how accessible repo/org filters added to global queries are performing and
		// to get some data about the distribution of accessible resource counts for users.
		tags := stats.Tags{
			"filtered_by":  string(prepared.filteredBy),
			"query_type":   string(queryCtx.QueryType),
			"query_source": string(queryCtx.QuerySource),
		}
		statting.Distribution(ctx, "query_service.query.accessible_private_repos.count", float64(len(preparedCtx.actor.AccessiblePrivateRepoIDs)), tags)
		statting.Distribution(ctx, "query_service.query.accessible_organizations.count", float64(len(preparedCtx.actor.AccessibleOrganizationIDs)), tags)
		statting.Distribution(ctx, "query_service.query.num_results_filtered.count", float64(queryResponse.Metadata.NumFilteredDocuments), tags)

		suggestions = append(suggestions, suggest.ExtractSuggestionsFromSearch(ctx, queryResponse)...)
		metadata = queryResponse.GetMetadata()
		return queryResponse.Metadata.TotalCost, bbErr
	})
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "query timed out", kvp.Err(err))
		} else {
			logging.Error(ctx, "out of quota or blackbird error returning suggestions", kvp.Err(err))
		}
		// Provide suggestions anyway if quota exceeded (or if blackbird fails):
		// just log the failure.
		if metadata == nil {
			metadata = &pb.Metadata{
				QueryAst:    parser.Serialize(prepared.query),
				Experiments: experiments.GetExperiments(ctx),
				Timing:      blackbird.MapTimings(timing.Finish(ctx)),
			}
		}
	}

	const suggestionsLimit = 6
	suggestions = suggest.RerankSuggestions(suggestions, suggestionsLimit)
	return &pb.SuggestResponse{
		Suggestions: suggest.ConvertToProto(suggestions),
		QueryErrors: prepared.queryErrors,
		Metadata:    metadata,
	}, nil
}

func (s *queryService) Count(ctx context.Context, req *pb.CountRequest) (*pb.CountResponse, error) {
	// Enforce overall request timeout
	timeout := search.CountTimeout(req.RequestTimeout)
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	resp, err := s.doCountRPC(ctx, req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "count timed out", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}

		return nil, err
	}

	return resp, err
}

func (s *queryService) doCountRPC(ctx context.Context, req *pb.CountRequest) (*pb.CountResponse, error) {
	rpcStart := time.Now()

	qreq := convertCountRequest(ctx, req)
	ctx, preparedCtx, err := s.prepareContext(ctx, qreq)
	if err != nil {
		logging.Error(ctx, "prepareContext failed", kvp.Err(err))
		return nil, err
	}
	actor := preparedCtx.actor

	preparedQuery, err := s.prepareQuery(ctx, qreq, preparedCtx)
	if err != nil {
		return nil, err
	}
	if preparedQuery.fatal {
		return shortCircuitCountResult(ctx, actor, preparedQuery.queryErrors...)
	}
	preparedQuery.query = parser.MakeCountQuery(preparedQuery.query)
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx, kvp.String("parsed_query", redact.Redact(parser.Serialize(preparedQuery.query))))
	}

	queryCtx := search.BuildFECountQueryContext(
		actor,
		search.CountTimeout(req.RequestTimeout)-time.Since(rpcStart),
		parser.GetScopeRepoIDs(preparedQuery.query),
		CountCacheKey(req), // NOTE: count queries don't make use of the cache key yet...
	)

	// Issue the count query tracking user quotas
	var resp *pb.CountResponse
	if err = s.withQuota(ctx, queryCtx.Actor.ID, queryCtx.QuerySource, queryCtx.QueryType, false, func() (float32, error) {
		var err error
		if resp, err = preparedCtx.index.Count(ctx, parser.ConvertToProto(preparedQuery.query), queryCtx); err != nil {
			return 0, err
		}
		return resp.GetMetadata().GetTotalCost(), err
	}); err != nil {
		return nil, err
	}

	if len(resp.QueryErrors) != 0 {
		return shortCircuitCountResult(ctx, actor, resp.QueryErrors...)
	}
	resp.QueryErrors = preparedQuery.queryErrors
	resp.ProtectedOrganizationIds = actor.ProtectedOrganizationIDs

	return resp, nil
}

// Corresponds to BlackbirdBackend.ResolveDefinition() in aleph's query/blackbird.go
func (s *queryService) TextDocumentDefinition(ctx context.Context, req *pb.TextDocumentDefinitionRequest) (*pb.TextDocumentDefinitionResponse, error) {
	// Enforce overall request timeout
	ctx, cancel := context.WithTimeout(ctx, search.LocationRequestTimeout)
	defer cancel()

	resp, err := s.doTextDocumentDefinitionRPC(ctx, req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "text document definition timed out", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}

		return nil, err
	}

	return resp, nil
}

func (s *queryService) doTextDocumentDefinitionRPC(ctx context.Context, req *pb.TextDocumentDefinitionRequest) (*pb.TextDocumentDefinitionResponse, error) {
	rpcStart := time.Now()

	var err error
	language, err := s.validateLocationRequest(req.Body, req.Actor)
	if err != nil {
		return nil, err
	} else if language == nil {
		return &pb.TextDocumentDefinitionResponse{
			Body: &pb.AlephLocationResponse{
				Locations:    []*pb.AlephLocation{},
				RepositoryId: req.Body.RepositoryId,
				CommitOid:    req.Body.CommitOid,
			},
		}, nil
	}

	query := buildLocationQuery(search.QueryTypeFindDefinitions, req.Body.SymbolKind, req.Body.SymbolName, language)
	qreq := convertLocationRequest(req.Body, query, search.QueryTypeFindDefinitions, req.Actor, req.Tenant, map[string]string{})
	ctx, prepared, err := s.prepareContext(ctx, qreq)
	if err != nil {
		return nil, err
	}

	resp, _, err := s.query(ctx, qreq, prepared, epoch.EpochFeaturesLexical, rpcStart, false /* includeTOSWarning */)
	if err != nil {
		return nil, err
	}

	locations := []*pb.AlephLocation{}
	for _, doc := range resp.Documents {
		// If the document contains no useful data then we ignore and continue.
		if doc.ScoringInfo == nil || len(doc.ScoringInfo.MatchedSymbols) == 0 || len(doc.Locations) == 0 {
			continue
		}
		// A document's MatchSymbols represent definitions.
		for _, symbol := range doc.ScoringInfo.MatchedSymbols {
			// Ensure case sensitivity by comparing the request query with the document's matched symbol.
			if req.Body.SymbolName != string(doc.Content[symbol.IdentStart:symbol.IdentEnd]) {
				continue
			}
			location, err := alephcompat.DefinitionSymbolDataToLocation(doc, symbol)
			if err != nil {
				return nil, err
			}
			locations = append(locations, location)
		}
	}

	alephResp := &pb.AlephLocationResponse{
		Locations: locations,
	}
	if len(locations) > 0 {
		alephResp.CommitOid = locations[0].Pkg.CommitOid
		alephResp.RepositoryId = locations[0].Pkg.RepositoryId
	}
	return &pb.TextDocumentDefinitionResponse{Body: alephResp}, nil
}

// Corresponds to BlackbirdBackend.FindAllReferencesAndEnclosingSymbols() in aleph's query/blackbird.go
func (s *queryService) TextDocumentReferences(ctx context.Context, req *pb.TextDocumentReferencesRequest) (*pb.TextDocumentReferencesResponse, error) {
	// Enforce overall request timeout
	ctx, cancel := context.WithTimeout(ctx, search.LocationRequestTimeout)
	defer cancel()

	resp, err := s.doTextDocumentReferencesRPC(ctx, req)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "text document references timed out", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}

		return nil, err
	}

	return resp, nil
}

func (s *queryService) doTextDocumentReferencesRPC(ctx context.Context, req *pb.TextDocumentReferencesRequest) (*pb.TextDocumentReferencesResponse, error) {
	rpcStart := time.Now()

	var err error
	language, err := s.validateLocationRequest(req.Body, req.Actor)
	if err != nil {
		return nil, err
	} else if language == nil {
		return &pb.TextDocumentReferencesResponse{
			Body: &pb.AlephLocationResponse{
				Locations:    []*pb.AlephLocation{},
				RepositoryId: req.Body.RepositoryId,
				CommitOid:    req.Body.CommitOid,
			},
		}, nil
	}

	queryType := search.QueryTypeFindReferences
	query := buildLocationQuery(queryType, req.Body.SymbolKind, req.Body.SymbolName, language)
	qreq := convertLocationRequest(req.Body, query, queryType, req.Actor, req.Tenant, map[string]string{experiments.RefQualifier: "1"})
	ctx, prepared, err := s.prepareContext(ctx, qreq)
	if err != nil {
		return nil, err
	}

	resp, _, err := s.query(ctx, qreq, prepared, epoch.EpochFeaturesLexical, rpcStart, false /* includeTOSWarning */)
	if err != nil {
		return nil, err
	}
	if req.Body.SymbolKind == entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF || req.Body.SymbolKind == entities.SymbolKind_SYMBOL_KIND_METHOD_DEF {
		var locations []*pb.AlephLocation
		for _, doc := range resp.Documents {
			// If the document contains no useful data, we ignore and continue.
			if doc.ScoringInfo == nil || len(doc.TermMatches) == 0 || len(doc.Locations) == 0 {
				continue
			}

			for _, termMatch := range doc.TermMatches {
				// Blackbird only returns call refs for this kind of query so we know the symbol kind.
				location, err := alephcompat.ReferenceSymbolDataToLocation(doc, termMatch.Start, termMatch.End, entities.SymbolKind_SYMBOL_KIND_CALL_REF)
				if err != nil {
					return nil, err
				}
				locations = append(locations, location)
			}
		}

		alephResp := &pb.AlephLocationResponse{
			Locations: locations,
		}

		if len(locations) > 0 {
			alephResp.CommitOid = locations[0].Pkg.CommitOid
			alephResp.RepositoryId = locations[0].Pkg.RepositoryId
		}

		return &pb.TextDocumentReferencesResponse{Body: alephResp}, nil
	}

	var locations []*pb.AlephLocation
	for _, doc := range resp.Documents {
		// If the document contains no useful data,  we ignore and continue.
		if doc.ScoringInfo == nil || len(doc.TermMatches) == 0 || len(doc.Locations) == 0 {
			continue
		}

		// candidateReferences is a map whose keys are the starting byte offsets of each TermMatch
		// in the document,  and whose values are a candidateReference.  This makes it convenient
		// for comparing a document's MatchedSymbols (i.e. definitions) with its TermMatches.
		var candidateReferences = make(map[uint32]*candidateReference, len(doc.TermMatches))
		for _, termMatch := range doc.TermMatches {
			// Case-sensitive check to ensure the user's query symbol matches the case of the
			// term match returned from blackbird.
			if req.Body.SymbolName != string(doc.Content[termMatch.Start:termMatch.End]) {
				continue
			}

			candidateReferences[termMatch.Start] = &candidateReference{
				start: termMatch.Start,
				end:   termMatch.End,
			}
		}

		// If a MatchedSymbol's starting and ending byte offsets match one of the candidate
		// references,  mark the candidateReference as no longer valid.
		for _, matchedSymbol := range doc.ScoringInfo.MatchedSymbols {
			if candidateRef, ok := candidateReferences[matchedSymbol.IdentStart]; ok {
				if candidateRef.end == matchedSymbol.IdentEnd {
					candidateRef.isDefinition = true
				}
			}
		}

		// Iterate over candidateReferences skipping over any candidates that were found to have the same byte range as a MatchedSymbol definition.
		for _, candidateRef := range candidateReferences {
			// Do not include terms identified as definitions in the returned locations.
			if candidateRef.isDefinition {
				continue
			}

			// We don't have any syntax information for term matches from blackbird, so the symbol kind is unknown.
			location, err := alephcompat.ReferenceSymbolDataToLocation(doc, candidateRef.start, candidateRef.end, entities.SymbolKind_SYMBOL_KIND_UNKNOWN)
			if err != nil {
				return nil, err
			}

			locations = append(locations, location)
		}
	}

	alephResp := &pb.AlephLocationResponse{
		Locations: locations,
	}
	if len(locations) > 0 {
		alephResp.CommitOid = locations[0].Pkg.CommitOid
		alephResp.RepositoryId = locations[0].Pkg.RepositoryId
	}
	return &pb.TextDocumentReferencesResponse{Body: alephResp}, nil
}

type candidateReference struct {
	start        uint32
	end          uint32
	isDefinition bool
}

// Validate whether an incoming location request is well-formed. If required fields are missing, this returns a nil language and a Twirp HTTP error.
// If the language is not recognized, it returns a nil language and nil error, so that callers can return an empty result set for unrecognized languages.
// Otherwise, it returns a non-nil language and nil error.
func (s *queryService) validateLocationRequest(req *pb.AlephLocationRequest, actor *pb.Actor) (*alephcompat.Language, twirp.Error) {
	if req == nil {
		return nil, twirp.InvalidArgumentError("body", "must be present")
	} else if req.SymbolName == "" {
		return nil, twirp.InvalidArgumentError("symbol", "must be present")
	} else if strings.ContainsRune(req.SymbolName, ' ') {
		return nil, twirp.InvalidArgumentError("symbol", "must not have spaces")
	}

	return alephcompat.AllSupportedLanguages.LanguageForNameCaseInsensitive(req.Language), nil
}

func buildLocationQuery(
	queryType search.QueryType,
	symbolKind entities.SymbolKind,
	symbolName string,
	language *alephcompat.Language,
) string {
	var queryBuilder strings.Builder
	quoteEscapedQuery := strings.ReplaceAll(symbolName, `"`, `\"`)
	switch queryType {
	case search.QueryTypeFindDefinitions:
		queryBuilder.WriteString(fmt.Sprintf("def:\"%s\"", quoteEscapedQuery))
	case search.QueryTypeFindReferences:
		// If a valid symbolKind is set, we can perform a call site query with the ref: qualifier.
		if symbolKind == entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF || symbolKind == entities.SymbolKind_SYMBOL_KIND_METHOD_DEF {
			queryBuilder.WriteString(fmt.Sprintf("ref:%q", quoteEscapedQuery))
		} else {
			// content: scopes the query to terms matched within a document (and not file paths).
			// OR def: retrieves the query definition so it can be filtered out from the TermMatches (i.e. references).
			regexpEscapedQuery := strings.ReplaceAll(regexp.QuoteMeta(symbolName), "/", "\\/")
			queryBuilder.WriteString(fmt.Sprintf("(content:/\\b%s\\b/ OR def:\"%s\")", regexpEscapedQuery, quoteEscapedQuery))
		}
	}

	// Along with the requested language,  blackbird queries always include protobuf as a language.
	languageQuery := []string{fmt.Sprintf("language:\"%s\"", language.Name), "language:\"Protocol Buffer\""}
	languageQueryExclusions := []string{}

	// We attempt to identify any associated languages that are useful for issuing queries to blackbird (e.g. like html+erb for Ruby).
	for _, language := range language.LanguageFamily.Relatives {
		languageQuery = append(languageQuery, fmt.Sprintf("language:\"%s\"", language))
	}

	for _, ext := range language.LanguageFamily.NoQueryExtensions {
		languageQueryExclusions = append(languageQueryExclusions, fmt.Sprintf("path:*.%s", ext))
	}

	queryBuilder.WriteString(" ") // Add a space to separate the symbol query from the language qualifiers.
	fmt.Fprintf(&queryBuilder, "(%s)", strings.Join(languageQuery, " OR "))
	if len(languageQueryExclusions) > 0 {
		fmt.Fprintf(&queryBuilder, " NOT (%s)", strings.Join(languageQueryExclusions, " OR "))
	}

	return queryBuilder.String()
}

func (s *queryService) GetRepositoryStatus(ctx context.Context, req *pb.GetRepositoryStatusRequest) (*pb.GetRepositoryStatusResponse, error) {
	if len(req.RepositoryIds) > 1000 {
		return nil, twirp.InvalidArgumentError("repository_ids", "exceeds max length of 1000")
	}

	// Enforce a rather tight timeout for this request
	ctx, cancel := context.WithTimeout(ctx, 1*time.Second)
	defer cancel()

	// we're going to run the same snapshot query against all clusters
	queries := []*querypb.Query{}
	for _, id := range req.RepositoryIds {
		queries = append(queries, &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_REPO_ID,
			ValueInt:        []int32{int32(id)},
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		})
	}
	queryAst := &querypb.Query{
		Kind:            querypb.QueryKind_QUERY_KIND_OR,
		Subqueries:      queries,
		DivorToRetrieve: 1,
		DivorToScore:    1,
	}

	corpora := []*pb.CorpusStatus{}
	aggregateState := newAggregateState()
	allClusters := []*blackbird.Cluster{}
	lexicalClusters := []*blackbird.Cluster{}
	embeddingClusters := []*blackbird.Cluster{}
	for _, corpus := range s.stamp.EnabledCorpora() {
		cluster, err := blackbird.GetCluster(ctx, s.clusters, s.store, s.pager, s.gitClient, corpus)
		if err != nil {
			logging.Error(ctx, "failed to get a search cluster host for corpus", kvp.Err(err), kvp.String("corpus", corpus.String()))
			continue
		}

		allClusters = append(allClusters, cluster)

		if cluster.IsServing() {
			if epoch.EpochFeaturesLexical.SupportedBy(cluster.EpochMode()) {
				lexicalClusters = append(lexicalClusters, cluster)
			}
			if epoch.EpochFeaturesEmbeddings.SupportedBy(cluster.EpochMode()) {
				embeddingClusters = append(embeddingClusters, cluster)
			}
		}
	}

	var selectedLexicalCluster string
	slices.SortFunc(lexicalClusters, func(i, j *blackbird.Cluster) int { return cmp.Compare(j.HealthScore(), i.HealthScore()) })
	if len(lexicalClusters) > 0 {
		selectedLexicalCluster = lexicalClusters[0].ClusterName()
	}
	var selectedEmbeddingsCluster string
	slices.SortFunc(embeddingClusters, func(i, j *blackbird.Cluster) int { return cmp.Compare(j.HealthScore(), i.HealthScore()) })
	if len(embeddingClusters) > 0 {
		selectedEmbeddingsCluster = embeddingClusters[0].ClusterName()
	}

	for _, cluster := range allClusters {
		var isSelected bool
		if epoch.EpochFeaturesLexical.SupportedBy(cluster.EpochMode()) {
			isSelected = cluster.ClusterName() == selectedLexicalCluster
		}
		if epoch.EpochFeaturesEmbeddings.SupportedBy(cluster.EpochMode()) {
			isSelected = isSelected || (cluster.ClusterName() == selectedEmbeddingsCluster)
		}

		if !isSelected && !req.CheckAllClusters {
			// if we don't need status from all clusters, skip the non-selected ones
			continue
		}

		clusterStateMap := make(map[uint32]*pb.RepositoryStatus, len(req.RepositoryIds))
		corpus := cluster.Corpus()
		var ssResp *snapshotpb.SearchSnapshotsResponse
		var err error
		var servingOffset int64
		if cluster.IsInstantServing() {
			// Do a snapshot search with the index api client (instant index)
			iCluster := s.indexerClusters.GetCluster(corpus)
			host, err := iCluster.GetRandomHost(ctx)
			if err != nil {
				logging.Error(ctx, "failed to get a random (instant) host", kvp.Err(err), kvp.String("corpus", corpus.String()))
				continue
			}
			servingOffset = int64(host.ServingOffset) // NB: This is the routes level serving offset
			ssResp, err = host.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
				QuerySource:       string(search.QuerySourceGetRepoStatus),
				QueryAst:          queryAst,
				TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
				EpochId:           uint32(iCluster.EpochInfo().EpochID),
				ShardId:           host.ShardID,
				ServingOffset:     servingOffset,
				SnapshotsToReturn: uint32(len(req.RepositoryIds)),
			})
			if err != nil {
				logging.Error(ctx, "failed to search (instant) snapshots for this repo", kvp.Err(err), kvp.String("corpus", corpus.String()))
				continue
			}
		} else {
			// Otherwise, do a snapshot search on the search cluster (static index)
			servingOffset = int64(cluster.ServingOffset())
			ssResp, err = cluster.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
				QuerySource:       string(search.QuerySourceGetRepoStatus),
				QueryAst:          queryAst,
				TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
				EpochId:           uint32(cluster.EpochID()),
				ServingOffset:     servingOffset,
				SnapshotsToReturn: uint32(len(req.RepositoryIds)),
			})
			if err != nil {
				logging.Error(ctx, "failed to search snapshots for this repo", kvp.Err(err), kvp.String("corpus", corpus.String()))
				continue
			}
		}
		parseServingSnapshots(isSelected, cluster.IsServing(), cluster.EpochMode(), servingOffset, ssResp.Snapshots, clusterStateMap, aggregateState)

		if req.CheckAllClusters {
			// Check the index api for anything that is actively being crawled.
			h, err := s.indexerClusters.GetCluster(corpus).GetHost()
			if err != nil {
				logging.Error(ctx, "failed to get an index host for corpus", kvp.Err(err), kvp.String("corpus", corpus.String()))
				continue
			}
			indexerRes, err := h.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
				QuerySource:       string(search.QuerySourceGetRepoStatus),
				QueryAst:          queryAst,
				TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
				EpochId:           uint32(cluster.EpochID()),
				ServingOffset:     int64(h.ServingOffset),
				SnapshotsToReturn: uint32(len(req.RepositoryIds)),
				ShardId:           h.ShardID,
			})
			if err != nil {
				logging.Error(ctx, "failed to search snapshots in the index cluster for this repo", kvp.Err(err), kvp.String("corpus", corpus.String()))
				continue
			}
			parseIndexerSnapshots(servingOffset, indexerRes.Snapshots, clusterStateMap)
		}

		// put the repository statuses back in the request order
		repositories := []*pb.RepositoryStatus{}
		for _, id := range req.RepositoryIds {
			if v, ok := clusterStateMap[id]; ok {
				repositories = append(repositories, v)
			} else {
				repositories = append(repositories, &pb.RepositoryStatus{RepositoryId: id})
			}
		}
		corpora = append(corpora, &pb.CorpusStatus{
			CorpusName:       corpus.String(),
			ClusterName:      corpus.ClusterName(),
			ClusterIsServing: cluster.IsServing(),
			ClusterEpochMode: cluster.EpochMode().String(),
			Repositories:     repositories,
		})
	}

	// Summary of state across all (serving) corpora (in request order)
	repositories := []*pb.RepositoryStatus{}
	ctx = statting.WithTags(ctx, stats.Tags{"rpc": "get_repository_status"})
	for _, id := range req.RepositoryIds {
		if !aggregateState.semanticCodeSearchOK[id] {
			logging.Info(ctx, "check index status miss: semantic search not available", kvp.Int("repo_id", int(id)))
			statting.Counter(ctx, "repo_indexed.miss", 1, stats.Tags{"reason": "not_indexed", "index": "embeddings"})
		} else {
			statting.Counter(ctx, "repo_indexed.hit", 1, stats.Tags{"index": "embeddings"})
		}
		if !aggregateState.lexicalSearchOK[id] {
			logging.Info(ctx, "check index status miss: lexical search not available", kvp.Int("repo_id", int(id)))
			statting.Counter(ctx, "repo_indexed.miss", 1, stats.Tags{"reason": "not_indexed", "index": "lexical"})
		} else {
			statting.Counter(ctx, "repo_indexed.hit", 1, stats.Tags{"index": "lexical"})
		}
		repositories = append(repositories, &pb.RepositoryStatus{
			RepositoryId:         id,
			LexicalSearchOk:      aggregateState.lexicalSearchOK[id],
			SemanticCodeSearchOk: aggregateState.semanticCodeSearchOK[id],
			LexicalCommitSha:     aggregateState.lexicalSearchCommit[id],
			SemanticCommitSha:    aggregateState.semanticSearchCommit[id],
		})
	}

	return &pb.GetRepositoryStatusResponse{Corpora: corpora, Repositories: repositories}, nil
}

// currentActor performs validation of the request actor and manages the state
// of the actor's auth cache entry.
//
// Note that b/c we pull the actor out of the proto request, it's not easy to
// implement this as middleware. Each rpc service endpoint that needs to know
// about currentActor must call this and then properly return errors.
//
// All errors returned are twirp errors.
func (s *queryService) currentActor(ctx context.Context, cluster *blackbird.Cluster, req *commonQueryRequest, parsedQuery *parsedQuery) (*models.Actor, *snapshotpb.SearchSnapshotsResponse, error) {
	requestActor := req.Actor
	if err := validateActor(ctx, requestActor); err != nil {
		return nil, nil, err
	}

	if actor := s.authClient.GetActor(ctx, requestActor.ActorId, requestActor.RequestIp, requestActor.SessionId); actor != nil {
		return actor, nil, nil
	}

	logging.Info(
		ctx,
		"actor not in cache",
		kvp.Uint64("actor_id", uint64(requestActor.ActorId)),
		kvp.String("session_id", requestActor.SessionId),
		kvp.String("ip_addr", requestActor.RequestIp),
	)

	cachedSnapshots, repoID := s.trySingleAccessibleRepo(ctx, cluster, req, parsedQuery)
	actor, error := s.buildActor(ctx, requestActor, repoID)
	return actor, cachedSnapshots, error
}

// Try enabling the single accessible repository optimization (ADR 60).
//
// If necessary, this does a snapshot search to get the RepoID of the single repo the user wants to
// query. On success, this returns the repo id and the snapshot search results (if any).
//
// If anything fails here, we silently return `nil, 0` and take the unoptimized path. (That way
// error-handling code isn't duplicated between optimized and unoptimized paths.)
func (s *queryService) trySingleAccessibleRepo(ctx context.Context, cluster *blackbird.Cluster, req *commonQueryRequest, parsedQuery *parsedQuery) (*snapshotpb.SearchSnapshotsResponse, types.RepoID) {
	if req.SingleRepoID != 0 {
		// TextDocumentDefinition/References is inherently single-repo, and the repo id is
		// included in the request.
		return nil, req.SingleRepoID
	}
	if parsedQuery.parseError != nil {
		return nil, 0
	}
	nwo := parser.CheckForSingleRepo(parsedQuery.full)
	if nwo == nil {
		return nil, 0
	}
	return req.querySingleRepoID(ctx, cluster, req.Tenant, *nwo)
}

var errPollingExhausted = errors.New("polling exhausted")

func (s *queryService) buildActor(ctx context.Context, requestActor *pb.Actor, repoID types.RepoID) (*models.Actor, error) {
	var repositoryIDs []uint64
	if repoID != 0 {
		repositoryIDs = append(repositoryIDs, uint64(repoID))
	}

	actor, statusCode, err := s.authClient.BuildActor(ctx, auth.BuildActorRequest{
		ActorID:         requestActor.ActorId,
		AccessToken:     requestActor.AccessToken,
		AccessTokenKind: requestActor.AccessTokenKind,
		RequestIPAddr:   requestActor.RequestIp,
		SessionID:       requestActor.SessionId,
		CacheTTL:        constants.UserACLCacheTTL,
		RepositoryIDs:   repositoryIDs,
	})
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			// blackbird-fe should attempt to re-auth
			return nil, twirp.NewError(twirp.Unauthenticated, "cannot auth actor")
		}

		return nil, twirp.InternalErrorWith(err)
	}

	// Poll Redis if the actor is not in the cache yet.
	attempt := 0
	if statusCode == http.StatusAccepted {
		operation := func() error {
			attempt++
			logging.Info(ctx, "polling for actor in cache", kvp.Int("attempt", attempt))
			actor = s.authClient.GetActor(ctx, requestActor.ActorId, requestActor.RequestIp, requestActor.SessionId)
			if actor == nil {
				return errPollingExhausted
			}
			return nil
		}

		exp := backoff.NewExponentialBackOff()
		exp.InitialInterval = 100 * time.Millisecond
		exp.MaxInterval = 2 * time.Second
		exp.MaxElapsedTime = 8 * time.Second

		err = backoff.Retry(operation, backoff.WithContext(exp, ctx))
		if errors.Is(err, errPollingExhausted) {
			if err = twirp.SetHTTPResponseHeader(ctx, "Retry-After", "3"); err != nil {
				// This would only error if the header key overwrites a header used by Twirp.
				panic(fmt.Sprintf("twirp header invariant err: %v", err))
			}
			twerr := twirp.NewError(twirp.Unavailable, "authorization not ready try again later")
			twerr = twerr.WithMeta("retry_after", "3")
			return nil, twerr
		}
		return actor, err
	}

	return actor, nil
}

// Results of various prep work done by prepareContext, not super tightly related.
type prepareContextResult struct {
	parsedQuery     *parsedQuery
	actor           *models.Actor
	index           search.Index
	cachedSnapshots *snapshotpb.SearchSnapshotsResponse
}

func (s *queryService) prepareContext(ctx context.Context, req *commonQueryRequest) (context.Context, *prepareContextResult, error) {
	ctx = timing.Start(ctx)
	ctx = experiments.WithExperiments(ctx, req.Experiments) // new-style key/value experiments

	ctx = logging.With(ctx,
		kvp.String("query_type", string(req.QueryType)),
		kvp.String("query_source", string(req.QuerySource)))
	ctx = statting.WithTags(ctx,
		stats.Tags{
			"query_type":   string(req.QueryType),
			"query_source": string(req.QuerySource),
		})

	parsedQuery := req.parse(ctx)

	if len(req.Query) > constants.MaxQueryLengthInBytes {
		return ctx, nil, twirp.NewError(twirp.InvalidArgument, "query exceeds max length")
	}

	start := time.Now()
	ctx, cluster, err := s.autoSelectCluster(ctx, req.EpochID, epoch.EpochFeaturesLexical)
	if err != nil {
		logging.Error(ctx, "cluster selection failed", kvp.Err(err))
		return ctx, nil, err
	}
	timing.Record(ctx, timing.QueryStepClusterSelection, start)

	start = time.Now()
	actorModel, cachedSnapshots, err := s.currentActor(ctx, cluster, req, parsedQuery)
	if err != nil {
		logging.Error(ctx, "could not find an actor", kvp.Err(err))
		return ctx, nil, err
	}

	// Set the tenant on the actor (if there is one).
	actorModel.SetTenant(req.Tenant)

	ctx = applyStaffOnlyExperiments(ctx, actorModel)
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx,
			kvp.String("query", redact.Redact(req.Query)),
			kvp.String("scoping_query", redact.Redact(req.ScopingQuery)))
	}

	ctx = logging.With(ctx,
		kvp.Uint64("actor_id", uint64(actorModel.ID)),
		kvp.String("tenant_shortcode", actorModel.GetTenant().GetShortcode()),
		kvp.Any("experiments", experiments.GetExperiments(ctx)))

	if copilotLicense := copilot.GetLicense(ctx); copilotLicense != nil {
		ctx = logging.With(ctx,
			kvp.String("copilot_sku", copilotLicense.Sku),
			kvp.Bool("copilot_has_limited_access", copilotLicense.HasLimitedAccess))
		ctx = statting.WithTags(ctx,
			stats.Tags{"copilot_has_limited_access": fmt.Sprintf("%t", copilotLicense.HasLimitedAccess)})
	}
	timing.Record(ctx, timing.QueryStepPreparedContext, start)

	return ctx, &prepareContextResult{parsedQuery: parsedQuery, actor: actorModel, index: cluster, cachedSnapshots: cachedSnapshots}, nil
}

// Auto select a cluster and setup telemetry in context.
func (s *queryService) autoSelectCluster(ctx context.Context, epochID types.EpochID, cap epoch.EpochFeatures) (context.Context, *blackbird.Cluster, error) {
	index, err := blackbird.AutoSelectCluster(ctx, s.clusters, s.store, s.pager, s.gitClient, epochID, cap, s.stamp)
	if err != nil {
		return ctx, nil, errors.WithMessage(err, "failed to auto select a cluster")
	}

	ctx = logging.With(ctx,
		kvp.String("corpus", index.CorpusName()),
		kvp.Uint("epoch_id", uint(index.EpochID())),
		kvp.Int64("serving_offset", int64(index.ServingOffset())))

	// modify the global request metadata so the Twirp hooks can use it
	//
	// NOTE: This modifies the tags on the RequestMetadata, not a copy. This
	// should be thread safe because every request has its own context.
	if rmeta, ok := reqmeta.GetRequestMetadata(ctx); ok {
		rmeta.TagStatsWith(stats.Tags{"corpus": index.CorpusName(), "epoch_mode": index.EpochMode().String()})
	}

	return ctx, index, nil
}

func (s *queryService) withQuota(ctx context.Context, actorID uint64, querySource search.QuerySource, queryType search.QueryType, includeTOSWarning bool, f func() (float32, error)) error {
	if querySource == search.QuerySourceProber {
		// Prober traffic. Skip quota tracking.
		_, err := f()
		return err
	}

	bucket := quota.FindBucket(queryType, copilot.GetLicense(ctx))
	rates, err := quota.PreQuery(ctx, s.quotaRateEstimator, actorID, bucket, includeTOSWarning)
	if err != nil {
		// If a query is rejected b/c the actor is out of quota, don't continue to pre-charge them.
		if rates != nil {
			quota.PostQuery(ctx, s.quotaRateEstimator, rates, float64(0))
		}

		return err
	}

	cost, err := f()

	if float64(cost)*2 > rates.PreCharge {
		logging.Error(ctx, "observed surprisingly high cost!", kvp.Float("cost", float64(cost)), kvp.Float("precharge", float64(rates.PreCharge)), kvp.Int("actor_id", int(actorID)))
	}

	if err != nil {
		// cost is zero on error: adjust to the constant ErrorCharge.
		cost = float32(quota.ErrorCharge)
	}

	statting.Distribution(ctx, "query.cost_distribution", float64(cost))
	quota.PostQuery(ctx, s.quotaRateEstimator, rates, float64(cost))
	return err
}

func applyStaffOnlyExperiments(ctx context.Context, actor *models.Actor) context.Context {
	if len(experiments.StaffEnabled) > 0 && actor.IsGitHubStaff() {
		return experiments.WithExperiments(ctx, experiments.StaffEnabled)
	}

	return ctx
}

type prepareQueryResult struct {
	query       *parser.Query
	queryErrors []*pb.QueryError
	cost        float32
	fatal       bool
	filteredBy  parser.FilteredBy
}

func (s *queryService) prepareQuery(
	ctx context.Context,
	req *commonQueryRequest,
	prepared *prepareContextResult,
) (prepareQueryResult, error) {
	var prepareQueryCost float32
	fatal := func(queryErrors ...*pb.QueryError) (prepareQueryResult, error) {
		return prepareQueryResult{
			query:       nil,
			queryErrors: queryErrors,
			cost:        prepareQueryCost,
			fatal:       true,
		}, nil
	}

	parsedQuery := prepared.parsedQuery
	if parsedQuery.parseError != nil {
		return fatal(parsedQuery.parseError)
	}

	start := time.Now()

	// Map text queries into path queries, so that we don't search content when providing suggestions
	if req.QueryType == search.QueryTypeSuggest {
		parser.RewriteQueryForSuggestions(prepared.parsedQuery.full)
	}

	scopes, qerrs := extractCustomScopes(ctx, req.CustomScopes)
	if qerrs != nil {
		return fatal(qerrs...)
	}

	rewriteErrors, filteredBy, err := parser.RewriteQuery(ctx, parsedQuery.full, prepared.actor, req.Tenant, prepared.index, scopes, prepared.cachedSnapshots)
	if err != nil {
		return prepareQueryResult{cost: 0}, err
	}
	timing.Record(ctx, timing.QueryStepRewriteQuery, start)
	start = time.Now()

	// Check for warnings and errors within the query AST
	queryErrors, satisfiable := parser.LintQuery(ctx, req.Query, parsedQuery.user, parsedQuery.full)

	queryErrors = append(queryErrors, rewriteErrors...)
	parseErrors := parser.ConvertQueryErrorToProto(queryErrors)

	// If the query is satisfiable, but when combined with the scope it is not, we should advise
	// the client to remove the scoping query
	if satisfiable && !parser.IsSatisfiable(parsedQuery.full) {
		parseErrors = append(parseErrors, &queryErrorUnsatisfiable)
	}

	// Don't run query simplification in suggest mode, since some
	// qualifiers may be partially completed, which would be simplified to
	// Nothing
	if req.QueryType != search.QueryTypeSuggest {
		parser.SimplifyQuery(parsedQuery.full)
	}

	timing.Record(ctx, timing.QueryStepLintQuery, start)

	// Quit early if there were any fatal errors
	for _, err := range parseErrors {
		if err.Type == pb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL || err.Type == pb.ErrorType_ERROR_TYPE_SCOPE_UNSATISFIABLE {
			return fatal(parseErrors...)
		}
	}

	if parsedQuery.full.IsNothing() {
		// Only indicate the query is not satisfiable if there isn't already an error.
		// A lot of the time, this error accompanies other errors but doesn't really
		// add any new information.
		if len(parseErrors) == 0 {
			parseErrors = append(parseErrors, &queryErrorIsNothing)
		}
		return fatal(parseErrors...)
	}
	return prepareQueryResult{
		query:       parsedQuery.full,
		queryErrors: parseErrors,
		cost:        prepareQueryCost,
		filteredBy:  filteredBy,
	}, nil
}

func extractCustomScopes(ctx context.Context, scopes []*pb.CustomScope) (map[string]*parser.Query, []*pb.QueryError) {
	customScopes := make(map[string]*parser.Query)
	for _, scope := range scopes {
		sq, err := parser.ParseQuery(ctx, scope.Query)
		if err != nil {
			return nil, []*pb.QueryError{{
				Type:    pb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL,
				Message: fmt.Sprintf("Unable to parse custom scope %v!", scope.Name),
			}}
		}
		customScopes[scope.Name] = sq
	}
	return customScopes, nil
}

// Return a populated recordedQueryResult for an error condition that doesn't result in a search
func shortCircuitQueryResult(ctx context.Context, actor *models.Actor, qerrs ...*pb.QueryError) (*pb.QueryResponse, error) {
	return &pb.QueryResponse{
			QueryErrors:              qerrs,
			ProtectedOrganizationIds: actor.ProtectedOrganizationIDs,
			Metadata: &pb.Metadata{
				Experiments: experiments.GetExperiments(ctx),
				IsFailure:   true,
				Timing:      blackbird.MapTimings(timing.Finish(ctx)),
			},
		},
		nil
}

// Return a populated recordedSuggestResult for an error condition that doesn't result in a search
func shortCircuitSuggestResult(ctx context.Context, qerrs ...*pb.QueryError) (*pb.SuggestResponse, error) {
	return &pb.SuggestResponse{
			QueryErrors: qerrs,
			Metadata: &pb.Metadata{
				Experiments: experiments.GetExperiments(ctx),
				IsFailure:   true,
				Timing:      blackbird.MapTimings(timing.Finish(ctx)),
			},
		},
		nil
}

// Return a populated recordedQueryResult for an error condition that doesn't result in a search
func shortCircuitCountResult(ctx context.Context, actor *models.Actor, qerrs ...*pb.QueryError) (*pb.CountResponse, error) {
	return &pb.CountResponse{
			QueryErrors:              qerrs,
			ProtectedOrganizationIds: actor.ProtectedOrganizationIDs,
			Metadata: &pb.Metadata{
				Experiments: experiments.GetExperiments(ctx),
				IsFailure:   true,
				Timing:      blackbird.MapTimings(timing.Finish(ctx)),
			},
		},
		nil
}

func statResponse(ctx context.Context, response *pb.QueryResponse) {
	parts := []string{}

	if len(response.QueryErrors) > 0 {
		parts = append(parts, "errors")
	} else {
		parts = append(parts, "success")
	}

	if len(response.Documents) > 0 {
		parts = append(parts, "with_results")
	} else {
		parts = append(parts, "no_results")
	}

	statting.Counter(ctx, "query_service.query.response", 1, stats.Tags{"type": strings.Join(parts, "_")})

	for _, qErr := range response.QueryErrors {
		statting.Counter(ctx, "query_service.query.query_error", 1, stats.Tags{"type": qErr.Type.String()})
	}
}

func validateActor(ctx context.Context, actor *pb.Actor) twirp.Error {
	if actor == nil {
		logging.Error(ctx, "no actor in request")
		return twirp.NewError(twirp.Unauthenticated, "unauthenticated: no actor provided")
	}

	if actor.GetActorId() == 0 {
		logging.Error(ctx, "no Actor ID in request")
		return twirp.NewError(twirp.InvalidArgument, "unauthenticated: no actor ID provided")
	}

	if actor.GetAccessToken() == "" {
		logging.Error(ctx, "no access token in request")
		return twirp.NewError(twirp.InvalidArgument, "unauthenticated: no access token provided")
	}

	if actor.GetRequestIp() == "" {
		logging.Error(ctx, "no IP address in request")
		return twirp.NewError(twirp.InvalidArgument, "unauthenticated: no IP address provided")
	}

	return nil
}

var (
	queryErrorParseFail = pb.QueryError{
		Type:    pb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL,
		Message: "unable to parse query!",
	}
	queryErrorScopeParseFail = pb.QueryError{
		Type:    pb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL,
		Message: "Unable to parse scoping query!",
	}
	queryErrorUnsatisfiable = pb.QueryError{
		Type:    pb.ErrorType_ERROR_TYPE_SCOPE_UNSATISFIABLE,
		Message: "The current scope makes this query unsatisfiable",
	}
	queryErrorIsNothing = pb.QueryError{
		Type:    pb.ErrorType_ERROR_TYPE_QUERY_PARSING_WARNING,
		Message: "Query is not satisfiable",
	}
)

// Returns the right blackbird.QueryType for the given request QueryType. Defaults to
// `search.QueryTypeUser` if the given `qt` is invalid or `QueryType_QUERY_TYPE_UNSPECIFIED`.
func getQueryType(ctx context.Context, qt pb.QueryType) search.QueryType {
	switch qt {
	case pb.QueryType_QUERY_TYPE_USER_QUERY:
		return search.QueryTypeUser
	case pb.QueryType_QUERY_TYPE_FIND_DEFINITIONS:
		return search.QueryTypeFindDefinitions
	case pb.QueryType_QUERY_TYPE_FIND_REFERENCES:
		return search.QueryTypeFindReferences
	default:
		logging.Info(ctx, fmt.Sprintf("no queryType set, defaulting to %s", search.QueryTypeUser), kvp.Stringer("queryType", qt))
		return search.QueryTypeUser
	}
}

// Returns the right blackbird.QuerySource for the given request QuerySource. Defaults to
// `search.QuerySourceFE` if the given `qs` is invalid or `QuerySource_QUERY_SOURCE_UNSPECIFIED`.
func getQuerySource(ctx context.Context, qs pb.QuerySource) search.QuerySource {
	switch qs {
	case pb.QuerySource_QUERY_SOURCE_FRONTEND:
		return search.QuerySourceFE
	case pb.QuerySource_QUERY_SOURCE_LEGACY_API:
		return search.QuerySourceLegacyAPI
	case pb.QuerySource_QUERY_SOURCE_PROBER:
		return search.QuerySourceProber
	case pb.QuerySource_QUERY_SOURCE_COPILOT_API:
		return search.QuerySourceCopilotAPI
	case pb.QuerySource_QUERY_SOURCE_GRAPHQL_API:
		return search.QuerySourceGraphQLAPI
	case pb.QuerySource_QUERY_SOURCE_COPILOT_IDE:
		return search.QuerySourceCopilotIDE
	case pb.QuerySource_QUERY_SOURCE_BING:
		return search.QuerySourceBing
	case pb.QuerySource_QUERY_SOURCE_ALEPH:
		return search.QuerySourceAleph
	case pb.QuerySource_QUERY_SOURCE_COPILOT_WORKSPACE:
		return search.QuerySourceCopilotWorkspace
	default:
		logging.Info(ctx, fmt.Sprintf("no querySource set, defaulting to %s", search.QuerySourceFE), kvp.Stringer("querySource", qs))
		return search.QuerySourceFE
	}
}
