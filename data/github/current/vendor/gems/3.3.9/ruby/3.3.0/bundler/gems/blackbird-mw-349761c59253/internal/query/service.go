package query

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
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
	"google.golang.org/protobuf/types/known/timestamppb"

	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"

	"github.com/github/blackbird-mw/internal/alephcompat"
	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/background"
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
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/suggest"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
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
	copilot            copilot.Client
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
	copilot copilot.Client,
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
		copilot,
	}
}

func (s *queryService) Query(ctx context.Context, req *pb.QueryRequest) (*pb.QueryResponse, error) {
	queryType := getQueryType(ctx, req.QueryType)
	querySource := getQuerySource(ctx, req.QuerySource)
	ctx, actor, err := s.prepareContext(ctx, req.Query, queryType, querySource, req.ScopingQuery, req.Actor, req.Tenant, req.Experiments)
	if err != nil {
		logging.Error(ctx, "prepareContext failed", kvp.Err(err))
		return nil, err
	}

	// Enforce overall request timeout. Potentially long-running operations
	// should convert context.DeadlineExceeded to twirp.DeadlineExceeded.
	// NB: Do this after prepareContext in case we had to load actor ACL data.
	timeout := search.SearchTimeout(req.RequestTimeout)
	ctx, cancel := context.WithTimeout(ctx, timeout+1*time.Second)
	defer cancel()

	resp, _, err := s.query(ctx, actor, req, epoch.EpochFeaturesLexical)
	return resp, err
}

func (s *queryService) query(ctx context.Context, actor *models.Actor, req *pb.QueryRequest, cap epoch.EpochFeatures) (*pb.QueryResponse, context.Context, error) {
	// NB: DO NOT enforce any content.WithTimeout in here (callers must do that).
	timeout := search.SearchTimeout(req.RequestTimeout)
	rpcStart := time.Now()
	start := rpcStart

	timing.Record(ctx, timing.QueryStepPreparedContext, start)
	start = time.Now()

	ctx, index, err := s.autoSelectCluster(ctx, types.EpochID(req.EpochId), cap)
	if err != nil {
		logging.Error(ctx, "cluster selection failed", kvp.Err(err))
		return nil, ctx, err
	}
	timing.Record(ctx, timing.QueryStepClusterSelection, start)

	limits := s.limitsCalc.Calculate(
		ctx,
		index.NumShards(),
		req.DocumentLimit,
		req.DocumentLocationLimit,
	)

	// Prepare and issue query tracking quota.
	queryType := getQueryType(ctx, req.QueryType)
	querySource := getQuerySource(ctx, req.QuerySource)
	promptRewriter := parser.GetPromptRewriter(ctx, s.copilot, index.Corpus())
	var response *pb.QueryResponse
	if err = s.withQuota(ctx, actor.ID, querySource, queryType, func() (float32, error) {
		var cost float32
		var err error
		response, cost, err = s.performSearch(ctx, req, actor, index, limits, queryType, querySource, promptRewriter, rpcStart, timeout)
		return cost, err
	}); err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "query timed out", kvp.Err(err))
			return nil, ctx, twirp.DeadlineExceeded.Error("query timed out")
		}
		return nil, ctx, err
	}

	statResponse(ctx, response)

	return response, ctx, nil
}

func (s *queryService) performSearch(
	ctx context.Context,
	req *pb.QueryRequest,
	actor *models.Actor,
	index search.Index,
	limits search.QueryLimits,
	queryType search.QueryType,
	querySource search.QuerySource,
	promptRewriter parser.PromptRewriter,
	rpcStart time.Time,
	timeout time.Duration,
) (*pb.QueryResponse, float32, error) {
	prepared, err := s.prepareQuery(ctx, req.Query, req.ScopingQuery, req.CustomScopes, actor, req.Tenant, index, queryType, req.QueryParser, promptRewriter)
	if err != nil {
		return nil, prepared.cost, err
	}
	if prepared.fatal {
		response, err := shortCircuitQueryResult(ctx, actor, prepared.queryErrors...)
		return response, prepared.cost, err
	}
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx, kvp.String("parsed_query", parser.Serialize(prepared.query)))
	}

	if mode, ok := experiments.GetExperiment(ctx, experiments.SnippetMode); ok {
		switch mode {
		case experiments.SnippetModeUnified:
			req.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_UNIFIED
			if req.SnippetOptions.DoubleSnippetContextLines == 0 {
				req.SnippetOptions.DoubleSnippetContextLines = 1
			}
			if req.SnippetOptions.SingleSnippetContextLines == 0 {
				req.SnippetOptions.SingleSnippetContextLines = 3
			}
		case experiments.SnippetModeHighDensity:
			req.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_HIGH_DENSITY
		case experiments.SnippetModeAuto:
			req.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_AUTO
		case experiments.SnippetModeRaw:
			req.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_RAW_MATCHES
		case experiments.SnippetModeLLM:
			req.SnippetOptions.Mode = pb.SnippetMode_SNIPPET_MODE_LLM
		}
	}
	if promptRewriter != nil && req.SnippetOptions != nil {
		req.SnippetOptions.Mode = promptRewriter.OverrideSnippetMode(req.SnippetOptions.Mode)
	}

	queryCtx := search.BuildFEUserQueryContext(
		actor,
		limits,
		queryType,
		querySource,
		timeout-time.Since(rpcStart),
		parser.GetScopeRepoIDs(prepared.query),
		req.SnippetOptions,
		&search.PaginationOptions{
			PageIdx: req.PageNumber,
			PerPage: req.ResultsPerPage,
		},
		QueryCacheKey(req),
		req.ReturnEnclosingSymbols,
	)
	queryCtx.QuerySource = querySource

	response, err := index.Search(ctx, parser.ConvertToProto(prepared.query), queryCtx)
	if err != nil {
		statting.Counter(ctx, "query_service.query.failure", 1)
		return nil, prepared.cost, err
	}

	response.QueryErrors = append(response.QueryErrors, prepared.queryErrors...)
	response.ProtectedOrganizationIds = actor.ProtectedOrganizationIDs
	return response, response.Metadata.TotalCost + prepared.cost, err

}

func (s *queryService) Suggest(ctx context.Context, req *pb.SuggestRequest) (*pb.SuggestResponse, error) {
	rpcStart := time.Now()
	start := rpcStart

	ctx, actor, err := s.prepareContext(ctx, req.Query, search.QueryTypeSuggest, search.QuerySourceFE, req.ScopingQuery, req.Actor, req.Tenant, req.Experiments)
	if err != nil {
		logging.Error(ctx, "prepareContext failed", kvp.Err(err))
		return nil, err
	}
	timing.Record(ctx, timing.QueryStepPreparedContext, start)
	start = time.Now()

	// Enforce overall request timeout. Potentially long-running operations
	// should convert context.DeadlineExceeded to twirp.DeadlineExceeded.
	// NB: Do this after prepareContext in case we had to load actor ACL data.
	timeout := search.SearchTimeout(req.RequestTimeout)
	ctx, cancel := context.WithTimeout(ctx, timeout+1*time.Second)
	defer cancel()

	ctx, index, err := s.autoSelectCluster(ctx, types.AnyEpoch, epoch.EpochFeaturesLexical) // NB: Suggest queries can't select a cluster by epoch
	if err != nil {
		logging.Error(ctx, "cluster selection failed", kvp.Err(err))
		return nil, err
	}
	timing.Record(ctx, timing.QueryStepClusterSelection, start)

	promptRewriter := s.getPromptRewriter(ctx, index.Corpus())
	prepared, err := s.prepareQuery(ctx, req.Query, req.ScopingQuery, req.CustomScopes, actor, req.Tenant, index, search.QueryTypeSuggest, pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0, promptRewriter)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "timed out in prepareQuery", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}
		return nil, err
	}
	if prepared.fatal {
		return shortCircuitSuggestResult(ctx, actor, prepared.queryErrors...)
	}

	// Map text queries into path queries, so that we don't search content when providing suggestions
	parser.RewriteQueryForSuggestions(prepared.query)
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx, kvp.String("parsed_query", parser.Serialize(prepared.query)))
	}

	queryCtx := search.BuildFESuggestQueryContext(
		actor,
		timeout-time.Since(rpcStart),
		parser.GetScopeRepoIDs(prepared.query),
		SuggestCacheKey(req), // NOTE: suggest queries don't make use of the cache key yet...
	)

	// Suggest based on blackbird-mw info
	suggestions := suggest.Suggest(ctx, prepared.query, req.Query, req.CursorPosition, index, actor)

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
	err = s.withQuota(ctx, queryCtx.Actor.ID, queryCtx.QuerySource, queryCtx.QueryType, func() (float32, error) {
		queryResponse, bbErr := index.Search(ctx, parser.ConvertToProto(prepared.query), queryCtx)
		if bbErr != nil {
			return 0, bbErr
		}

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
	rpcStart := time.Now()
	start := rpcStart

	ctx, actor, err := s.prepareContext(ctx, req.Query, search.QueryTypeCount, search.QuerySourceFE, req.ScopingQuery, req.Actor, req.Tenant, req.Experiments)
	if err != nil {
		logging.Error(ctx, "prepareContext failed", kvp.Err(err))
		return nil, err
	}
	timing.Record(ctx, timing.QueryStepPreparedContext, start)
	start = time.Now()

	// Enforce overall request timeout. Potentially long-running operations
	// should convert context.DeadlineExceeded to twirp.DeadlineExceeded.
	// NB: Do this after prepareContext in case we had to load actor ACL data.
	timeout := search.CountTimeout(req.RequestTimeout)
	ctx, cancel := context.WithTimeout(ctx, timeout+1*time.Second)
	defer cancel()

	ctx, index, err := s.autoSelectCluster(ctx, types.EpochID(req.EpochId), epoch.EpochFeaturesLexical)
	if err != nil {
		logging.Error(ctx, "cluster selection failed", kvp.Err(err))
		return nil, err
	}
	timing.Record(ctx, timing.QueryStepClusterSelection, start)

	promptRewriter := s.getPromptRewriter(ctx, index.Corpus())
	prepared, err := s.prepareQuery(ctx, req.Query, req.ScopingQuery, req.CustomScopes, actor, req.Tenant, index, search.QueryTypeCount, pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0, promptRewriter)
	if err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "timed out in prepareQuery", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}
		return nil, err
	}
	if prepared.fatal {
		return shortCircuitCountResult(ctx, actor, prepared.queryErrors...)
	}
	prepared.query = parser.MakeCountQuery(prepared.query)
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx, kvp.String("parsed_query", parser.Serialize(prepared.query)))
	}

	queryCtx := search.BuildFECountQueryContext(
		actor,
		timeout-time.Since(rpcStart),
		parser.GetScopeRepoIDs(prepared.query),
		CountCacheKey(req), // NOTE: count queries don't make use of the cache key yet...
	)

	// Issue the count query tracking user quotas
	var resp *pb.CountResponse
	if err = s.withQuota(ctx, queryCtx.Actor.ID, queryCtx.QuerySource, queryCtx.QueryType, func() (float32, error) {
		var err error
		if resp, err = index.Count(ctx, parser.ConvertToProto(prepared.query), queryCtx); err != nil {
			return 0, err
		}
		return resp.GetMetadata().GetTotalCost(), err
	}); err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			logging.Error(ctx, "query timed out", kvp.Err(err))
			return nil, twirp.DeadlineExceeded.Error("query timed out")
		}
		return nil, err
	}

	if len(resp.QueryErrors) != 0 {
		return shortCircuitCountResult(ctx, actor, resp.QueryErrors...)
	}
	resp.QueryErrors = prepared.queryErrors
	resp.ProtectedOrganizationIds = actor.ProtectedOrganizationIDs

	return resp, nil
}

func (s *queryService) RefreshAuthCaches(ctx context.Context, req *pb.RefreshAuthCachesRequest) (*pb.RefreshAuthCachesResponse, error) {
	if err := validateActor(ctx, req.Actor); err != nil {
		return nil, err
	}

	rates, err := quota.PreQuery(ctx, s.quotaRateEstimator, req.Actor.ActorId, quota.AccessibleResources)
	if rates != nil {
		defer quota.PostQuery(ctx, s.quotaRateEstimator, rates, 0.0)
	}
	if err != nil {
		statting.Counter(ctx, "query.accessible_resources.rate_limit_exceeded", 1, map[string]string{"handler": "RefreshAuthCaches"})
		logging.Error(ctx, "accessible resources rate limit exceeded", kvp.Err(err))
		return nil, err
	}

	actor, err := s.buildActor(ctx, req.Actor)
	if err != nil {
		return nil, err
	}

	err = s.setActor(ctx, actor)
	if err != nil {
		return nil, err
	}

	return &pb.RefreshAuthCachesResponse{
		UserCacheExpiresAt: timestamppb.New(time.Now().Add(constants.UserACLCacheTTL)),
	}, nil
}

// Corresponds to BlackbirdBackend.ResolveDefinition() in aleph's query/blackbird.go
func (s *queryService) TextDocumentDefinition(ctx context.Context, req *pb.TextDocumentDefinitionRequest) (*pb.TextDocumentDefinitionResponse, error) {
	actor, err := s.currentActor(ctx, req.Actor) // check for auth+quota
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(ctx, search.LocationRequestTimeout)
	defer cancel()

	language, err := s.validateLocationRequest(ctx, req.Body, req.Actor)
	if err != nil {
		return nil, err
	}

	var queryBuilder strings.Builder
	quoteEscapedQuery := strings.Replace(req.Body.SymbolName, "\"", "\\\"", -1)
	queryBuilder.WriteString(fmt.Sprintf("def:\"%s\"", quoteEscapedQuery))

	resp, err := s.locationRequest(ctx, &queryBuilder, search.QueryTypeFindDefinitions, language, req.Body, actor, req.Actor, req.Tenant)
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
	actor, err := s.currentActor(ctx, req.Actor) // check for auth+quota
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(ctx, search.LocationRequestTimeout)
	defer cancel()

	language, err := s.validateLocationRequest(ctx, req.Body, req.Actor)
	if err != nil {
		return nil, err
	}

	// Escape regex values and slashes
	query := req.Body.SymbolName
	regexpEscapedQuery := strings.Replace(regexp.QuoteMeta(query), "/", "\\/", -1)
	quoteEscapedQuery := strings.Replace(query, `"`, `\"`, -1)
	queryType := search.QueryTypeFindReferences

	var queryBuilder strings.Builder

	// If a valid symbolKind is set, we can perform a call site query with the ref: qualifier.
	if req.Body.SymbolKind == entities.SymbolKind_SYMBOL_KIND_FUNCTION_DEF || req.Body.SymbolKind == entities.SymbolKind_SYMBOL_KIND_METHOD_DEF {
		queryBuilder.WriteString(fmt.Sprintf("ref:%q", quoteEscapedQuery))
		resp, err := s.locationRequest(ctx, &queryBuilder, queryType, language, req.Body, actor, req.Actor, req.Tenant)
		if err != nil {
			return nil, err
		}

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

	// content: scopes the query to terms matched within a document (and not file paths).
	// OR def: retrieves the query definition so it can be filtered out from the TermMatches (i.e. references).
	queryBuilder.WriteString(fmt.Sprintf("(content:/\\b%s\\b/ OR def:\"%s\")", regexpEscapedQuery, quoteEscapedQuery))

	resp, err := s.locationRequest(ctx, &queryBuilder, queryType, language, req.Body, actor, req.Actor, req.Tenant)
	if err != nil {
		return nil, err
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
			if query != string(doc.Content[termMatch.Start:termMatch.End]) {
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

func (s *queryService) validateLocationRequest(ctx context.Context, req *pb.AlephLocationRequest, actor *pb.Actor) (*alephcompat.Language, error) {
	if req == nil {
		return nil, twirp.InvalidArgumentError("body", "must be present")
	} else if err := validateActor(ctx, actor); err != nil {
		return nil, err
	} else if req.SymbolName == "" {
		return nil, twirp.InvalidArgumentError("symbol", "must be present")
	} else if strings.ContainsRune(req.SymbolName, ' ') {
		return nil, twirp.InvalidArgumentError("symbol", "must not have spaces")
	}

	language := alephcompat.AllSupportedLanguages.LanguageForNameCaseInsensitive(req.Language)
	if language == nil {
		return nil, twirp.InvalidArgumentError("language", fmt.Sprintf("not recognized: %s", req.Language))
	}
	return language, nil
}

// A native replacement for BlackbirdBackend.performQuery() in aleph's query/blackbird.go
func (s *queryService) locationRequest(ctx context.Context, queryBuilder *strings.Builder, queryType search.QueryType, language *alephcompat.Language, req *pb.AlephLocationRequest, actor *models.Actor, pbActor *pb.Actor, tenant *pb.Tenant) (*pb.QueryResponse, error) {
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
	queryBuilder.WriteString(fmt.Sprintf("(%s)", strings.Join(languageQuery, " OR ")))
	if len(languageQueryExclusions) > 0 {
		queryBuilder.WriteString(fmt.Sprintf(" NOT (%s)", strings.Join(languageQueryExclusions, " OR ")))
	}

	queryRequest := locationRequestToQueryRequest(req, queryBuilder, queryType, pbActor, tenant)
	response, _, err := s.query(ctx, actor, queryRequest, epoch.EpochFeaturesLexical)
	return response, err
}

func locationRequestToQueryRequest(req *pb.AlephLocationRequest, queryBuilder *strings.Builder, queryType search.QueryType, actor *pb.Actor, tenant *pb.Tenant) *pb.QueryRequest {
	pbQueryType := pb.QueryType_QUERY_TYPE_FIND_DEFINITIONS
	if queryType == search.QueryTypeFindReferences {
		pbQueryType = pb.QueryType_QUERY_TYPE_FIND_REFERENCES
	}
	return &pb.QueryRequest{
		Query:                  queryBuilder.String(),
		DocumentLimit:          10, // as per Aleph source
		DocumentLocationLimit:  10, // ditto
		ScopingQuery:           fmt.Sprintf("repo_id:%d", req.RepositoryId),
		Actor:                  actor,
		EpochId:                uint32(types.AnyEpoch),
		QueryType:              pbQueryType,
		QuerySource:            pb.QuerySource_QUERY_SOURCE_ALEPH,
		Experiments:            map[string]string{"ref_qualifier": "1"},
		Tenant:                 tenant,
		RequestTimeout:         durationpb.New(search.LocationRequestTimeout),
		ReturnEnclosingSymbols: true,
	}
}

func (s *queryService) WarmCaches(ctx context.Context, req *pb.WarmCachesRequest) (*pb.WarmCachesResponse, error) {
	if err := validateActor(ctx, req.Actor); err != nil {
		return nil, err
	}

	if actor := s.authClient.GetActor(ctx, req.Actor.ActorId, req.Actor.RequestIp, req.Actor.SessionId); actor != nil {
		timeUntilExpiry := time.Until(time.Unix(actor.CacheExpiryTime, 0))
		if timeUntilExpiry > (constants.UserACLCacheTTL / 2) {
			return &pb.WarmCachesResponse{
				UserCacheExpiresAt: timestamppb.New(time.Unix(actor.CacheExpiryTime, 0)),
			}, nil
		}
	}

	rates, err := quota.PreQuery(ctx, s.quotaRateEstimator, req.Actor.ActorId, quota.AccessibleResources)
	if rates != nil {
		defer quota.PostQuery(ctx, s.quotaRateEstimator, rates, 0.0)
	}
	if err != nil {
		statting.Counter(ctx, "query.accessible_resources.rate_limit_exceeded", 1, map[string]string{"handler": "WarmCaches"})
		logging.Error(ctx, "accessible resources rate limit exceeded", kvp.Err(err))
		return nil, err
	}

	actor, err := s.buildActor(ctx, req.Actor)
	if err != nil {
		return nil, err
	}

	err = s.setActor(ctx, actor)
	if err != nil {
		return nil, err
	}

	return &pb.WarmCachesResponse{
		UserCacheExpiresAt: timestamppb.New(time.Now().Add(constants.UserACLCacheTTL)),
	}, nil
}

func (s *queryService) GetRepositoryStatus(ctx context.Context, req *pb.GetRepositoryStatusRequest) (*pb.GetRepositoryStatusResponse, error) {
	if len(req.RepositoryIds) > 1000 {
		return nil, twirp.InvalidArgumentError("repository_ids", "exceeds max length of 1000")
	}

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
	for _, corpus := range routing.Corpora {
		// Do a snapshot search on the search cluster
		cluster, err := blackbird.GetCluster(ctx, s.clusters, s.store, s.pager, s.gitClient, corpus)
		if err != nil {
			logging.Error(ctx, "failed to get a search cluster host for corpus", kvp.Err(err), kvp.String("corpus", corpus.String()))
			continue
		}
		servingOffset := int64(cluster.ServingOffset())
		res, err := cluster.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
			QuerySource:       string(search.QuerySourceGetRepoStatus),
			QueryAst:          queryAst,
			TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
			EpochId:           uint32(cluster.EpochID()),
			ServingOffset:     servingOffset,
			SnapshotsToReturn: uint32(len(req.RepositoryIds)),
			EntriesLimit:      1,
		})
		if err != nil {
			logging.Error(ctx, "failed to search snapshots for this repo", kvp.Err(err), kvp.String("corpus", corpus.String()))
			continue
		}
		clusterStateMap := make(map[uint32]*pb.RepositoryStatus, len(req.RepositoryIds))
		parseServingSnapshots(cluster.IsServing(), cluster.EpochMode(), servingOffset, res.Snapshots, clusterStateMap, aggregateState)

		// now check the index api for anything that is actively being crawled.
		h, err := s.indexerClusters.GetCluster(corpus).GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get an index host for corpus", kvp.Err(err), kvp.String("corpus", corpus.String()))
			continue
		}
		res, err = h.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
			QuerySource:       string(search.QuerySourceGetRepoStatus),
			QueryAst:          queryAst,
			TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
			EpochId:           uint32(cluster.EpochID()),
			ServingOffset:     int64(h.ServingOffset),
			SnapshotsToReturn: uint32(len(req.RepositoryIds)),
			EntriesLimit:      1,
			ShardId:           h.ShardID,
		})
		if err != nil {
			logging.Error(ctx, "failed to search snapshots in the index cluster for this repo", kvp.Err(err), kvp.String("corpus", corpus.String()))
			continue
		}
		parseIndexerSnapshots(servingOffset, res.Snapshots, clusterStateMap)

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
	for _, id := range req.RepositoryIds {
		repositories = append(repositories, &pb.RepositoryStatus{
			RepositoryId:         id,
			LexicalSearchOk:      aggregateState.lexicalSearchOK[id],
			SemanticCodeSearchOk: aggregateState.semanticCodeSearchOK[id],
			SemanticDocSearchOk:  aggregateState.semanticDocSearchOK[id],
			Bm25SearchOk:         aggregateState.bm25SearchOK[id],
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
func (s *queryService) currentActor(ctx context.Context, requestActor *pb.Actor) (*models.Actor, error) {
	if err := validateActor(ctx, requestActor); err != nil {
		return nil, err
	}

	if experiments.IsExperimentEnabled(ctx, experiments.NewAccessibleResourcesCache) {
		if actor := s.authClient.GetActorV2(ctx, requestActor.ActorId, requestActor.RequestIp, requestActor.SessionId); actor != nil {
			return actor, nil
		}

		logging.Info(ctx, "actor not in cache", kvp.Uint64("actor_id", uint64(requestActor.ActorId)), kvp.String("session_id", requestActor.SessionId))

		return s.buildActorV2(ctx, requestActor)
	} else {
		if actor := s.authClient.GetActor(ctx, requestActor.ActorId, requestActor.RequestIp, requestActor.SessionId); actor != nil {
			go func(ctx context.Context) {
				defer utils.PanicLogger(ctx)
				// Compare the actors between the two cache versions.
				if actorV2 := s.authClient.GetActorV2(ctx, requestActor.ActorId, requestActor.RequestIp, requestActor.SessionId); actorV2 != nil {
					equal := actor.Equal(ctx, actorV2)
					statting.Counter(ctx, "query.cmp_auth_entries", 1, stats.Tags{"equal": fmt.Sprintf("%t", equal)})
				}
			}(background.Context(ctx))
			return actor, nil
		}

		// If the actor is not in the cache, build the actor via the auth service,
		// and track with the accessible resources bucket.
		rates, err := quota.PreQuery(ctx, s.quotaRateEstimator, requestActor.ActorId, quota.AccessibleResources)
		if rates != nil {
			defer quota.PostQuery(ctx, s.quotaRateEstimator, rates, 0.0)
		}
		if err != nil {
			handler, ok := twirp.MethodName(ctx)
			if !ok {
				handler = "unknown"
			}
			statting.Counter(ctx, "query.accessible_resources.rate_limit_exceeded", 1, stats.Tags{"handler": handler})
			logging.Error(ctx, "accessible resources rate limit exceeded", kvp.Uint64("actor_id", uint64(requestActor.ActorId)), kvp.String("twirp_method", handler), kvp.Err(err))
			return nil, err
		}

		actor, err := s.buildActor(ctx, requestActor)
		if err != nil {
			return nil, err
		}

		return actor, s.setActor(ctx, actor)
	}
}

func (s *queryService) buildActorV2(ctx context.Context, requestActor *pb.Actor) (*models.Actor, error) {
	actor, statusCode, err := s.authClient.BuildActorV2(ctx, auth.BuildActorRequest{
		ActorID:         requestActor.ActorId,
		AccessToken:     requestActor.AccessToken,
		AccessTokenKind: requestActor.AccessTokenKind,
		RequestIPAddr:   requestActor.RequestIp,
		SessionID:       requestActor.SessionId,
		CacheTTL:        constants.UserACLCacheTTL,
	})
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			// blackbird-fe should attempt to re-auth
			return nil, twirp.NewError(twirp.Unauthenticated, "cannot auth actor")
		}

		return nil, twirp.InternalErrorWith(err)
	}

	// Poll Redis if the actor is not in the cache yet.
	if statusCode == http.StatusAccepted {
		operation := func() error {
			actor = s.authClient.GetActorV2(ctx, requestActor.ActorId, requestActor.RequestIp, requestActor.SessionId)
			if actor == nil {
				return errors.New("actor not in cache")
			}
			return nil
		}
		err = backoff.Retry(operation, retry.LowLatencyBackoff(ctx, 3))
		return actor, err
	}

	return actor, nil
}

func (s *queryService) buildActor(ctx context.Context, requestActor *pb.Actor) (*models.Actor, error) {
	actor, err := s.authClient.BuildActor(ctx, auth.BuildActorRequest{
		ActorID:         requestActor.ActorId,
		AccessToken:     requestActor.AccessToken,
		AccessTokenKind: requestActor.AccessTokenKind,
		RequestIPAddr:   requestActor.RequestIp,
		SessionID:       requestActor.SessionId,
		CacheTTL:        constants.UserACLCacheTTL,
	})
	if err != nil {
		logging.Error(ctx, "could not build actor", kvp.Err(err))
		if errors.Is(err, auth.ErrUnauthorized) {
			// blackbird-fe should attempt to re-auth
			return nil, twirp.NewError(twirp.Unauthenticated, "cannot auth actor")
		}
		return nil, twirp.InternalErrorWith(err)
	}

	return actor, nil
}

func (s *queryService) setActor(ctx context.Context, actor *models.Actor) error {
	err := s.authClient.SetActor(ctx, actor, constants.UserACLCacheTTL)
	if err != nil {
		logging.Error(ctx, "could not set actor", kvp.Err(err))
		return twirp.InternalErrorWith(err)
	}

	return nil
}

func (s *queryService) prepareContext(
	ctx context.Context,
	query string,
	queryType search.QueryType,
	querySource search.QuerySource,
	scopingQuery string,
	actor *pb.Actor,
	tenant *pb.Tenant,
	exps experiments.Experiments,
) (context.Context, *models.Actor, error) {
	ctx = timing.Start(ctx)
	ctx = experiments.WithExperiments(ctx, exps) // new-style key/value experiments

	if len(query) > constants.MaxQueryLengthInBytes {
		return ctx, nil, twirp.NewError(twirp.InvalidArgument, "query exceeds max length")
	}

	actorModel, err := s.currentActor(ctx, actor)
	if err != nil {
		logging.Error(ctx, "could not find an actor", kvp.Err(err))
		return ctx, nil, err
	}

	// Set the tenant on the actor (if there is one).
	actorModel.SetTenant(tenant)

	ctx = applyStaffOnlyExperiments(ctx, actorModel)
	if !experiments.IsExperimentEnabled(ctx, experiments.DisableQueryLogging) {
		ctx = logging.With(ctx,
			kvp.String("query", query),
			kvp.String("scoping_query", scopingQuery))
	}

	ctx = logging.With(ctx,
		kvp.String("query_type", string(queryType)),
		kvp.String("query_source", string(querySource)),
		kvp.Any("experiments", experiments.GetExperiments(ctx)),
		kvp.Uint64("actor_id", uint64(actorModel.ID)),
		kvp.String("tenant_shortcode", actorModel.GetTenant().GetShortcode()))

	ctx = statting.WithTags(ctx,
		stats.Tags{
			"query_type":   string(queryType),
			"query_source": string(querySource),
		})

	return ctx, actorModel, nil
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
		rmeta.TagStatsWith(stats.Tags{"corpus": index.CorpusName()})
	}

	return ctx, index, nil
}

func (s *queryService) withQuota(ctx context.Context, actorID uint32, querySource search.QuerySource, queryType search.QueryType, f func() (float32, error)) error {
	if querySource == search.QuerySourceProber {
		// Prober traffic. Skip quota tracking.
		_, err := f()
		return err
	}

	rates, err := quota.PreQuery(ctx, s.quotaRateEstimator, actorID, quota.Bucket(queryType))
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
}

func (s *queryService) prepareQuery(
	ctx context.Context,
	query string,
	scopingQuery string,
	customScopes []*pb.CustomScope,
	actor *models.Actor,
	tenant *pb.Tenant,
	searchIndex search.Index,
	queryType search.QueryType,
	parserType pb.QueryParser,
	promptRewriter parser.PromptRewriter,
) (prepareQueryResult, error) {
	start := time.Now()

	var prepareQueryCost float32
	fatal := func(queryErrors ...*pb.QueryError) (prepareQueryResult, error) {
		return prepareQueryResult{
			query:       nil,
			queryErrors: queryErrors,
			cost:        prepareQueryCost,
			fatal:       true,
		}, nil
	}

	if experiments.IsExperimentEnabled(ctx, experiments.UseGeyserQueryLanguage) {
		parserType = pb.QueryParser_QUERY_PARSER_GEYSER
	}

	var userQuery *parser.Query
	var err error
	switch parserType {
	case pb.QueryParser_QUERY_PARSER_GEYSER:
		userQuery, err = parser.ParseGeyserQuery(ctx, query)
	default:
		userQuery, err = parser.ParseQuery(ctx, query)
	}

	if err != nil {
		statting.Counter(ctx, "query_service.query.parse_errors", 1, stats.Tags{"type": string(queryType)})
		return fatal(&queryErrorParseFail)
	}

	parsedScope, err := parser.ParseQuery(ctx, scopingQuery)
	if err != nil {
		statting.Counter(ctx, "query_service.scoping_query.parse_errors", 1, stats.Tags{"type": string(queryType)})
		return fatal(&queryErrorScopeParseFail)
	}

	parsed := userQuery
	if !parsedScope.IsNothing() {
		// Remove range information from the scope, since it isn't part of the user's query
		parser.ClearRangeInformation(parsedScope)
		parsed = parser.And(userQuery, parsedScope)
	}
	timing.Record(ctx, timing.QueryStepParseQuery, start)
	start = time.Now()

	// Map text queries into path queries, so that we don't search content when providing suggestions
	if queryType == search.QueryTypeSuggest {
		parser.RewriteQueryForSuggestions(parsed)
	}

	scopes, qerrs := extractCustomScopes(ctx, customScopes)
	if qerrs != nil {
		return fatal(qerrs...)
	}

	rewriteErrors, embeddingCount, err := parser.RewriteQuery(ctx, parsed, actor, tenant, searchIndex, scopes, promptRewriter)
	prepareQueryCost = promptRewriter.Cost(embeddingCount)
	if err != nil {
		return prepareQueryResult{
			cost: prepareQueryCost,
		}, err
	}
	timing.Record(ctx, timing.QueryStepRewriteQuery, start)
	start = time.Now()

	// Check for warnings and errors within the query AST
	queryErrors, satisfiable := parser.LintQuery(ctx, query, userQuery, parsed)

	queryErrors = append(queryErrors, rewriteErrors...)
	parseErrors := parser.ConvertQueryErrorToProto(queryErrors)

	// If the query is satisfiable, but when combined with the scope it is not, we should advise
	// the client to remove the scoping query
	if satisfiable && !parser.IsSatisfiable(parsed) {
		parseErrors = append(parseErrors, &queryErrorUnsatisfiable)
	}

	// Don't run query simplification in suggest mode, since some
	// qualifiers may be partially completed, which would be simplified to
	// Nothing
	if queryType != search.QueryTypeSuggest {
		parser.SimplifyQuery(parsed)
	}

	timing.Record(ctx, timing.QueryStepLintQuery, start)

	// Quit early if there were any fatal errors
	for _, err := range parseErrors {
		if err.Type == pb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL || err.Type == pb.ErrorType_ERROR_TYPE_SCOPE_UNSATISFIABLE {
			return fatal(parseErrors...)
		}
	}

	if parsed.IsNothing() {
		// Only indicate the query is not satisfiable if there isn't already an error.
		// A lot of the time, this error accompanies other errors but doesn't really
		// add any new information.
		if len(parseErrors) == 0 {
			parseErrors = append(parseErrors, &queryErrorIsNothing)
		}
		return fatal(parseErrors...)
	}
	return prepareQueryResult{
		query:       parsed,
		queryErrors: parseErrors,
		cost:        prepareQueryCost,
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
func shortCircuitSuggestResult(ctx context.Context, actor *models.Actor, qerrs ...*pb.QueryError) (*pb.SuggestResponse, error) {
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

func validateActor(ctx context.Context, actor *pb.Actor) error {
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
	case pb.QueryType_QUERY_TYPE_SIMILARITY:
		return search.QueryTypeSimilarity
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
	default:
		logging.Info(ctx, fmt.Sprintf("no querySource set, defaulting to %s", search.QuerySourceFE), kvp.Stringer("querySource", qs))
		return search.QuerySourceFE
	}
}

func (s *queryService) getPromptRewriter(ctx context.Context, corpus routing.Corpus) parser.PromptRewriter {
	if value, ok := experiments.GetExperiment(ctx, experiments.PromptQualifier); ok {
		switch value {
		case experiments.Enabled:
			model, dimensions := corpus.DefaultEmbeddingModel()
			return parser.NewEmbeddingsRewriter(s.copilot, model, dimensions)
		case experiments.PromptQualifierBM25:
			return parser.BM25PromptRewriter{}
		}
	}

	return parser.DisallowPromptQueries{}
}
