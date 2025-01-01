package blackbird

import (
	"bytes"
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/query/timing"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/scoring"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/types"
)

func (c *Cluster) Search(ctx context.Context, query *querypb.Query, queryCtx *search.QueryContext) (*pb.QueryResponse, error) {
	start := time.Now()

	if queryCtx.UsePagination() {
		// If this search includes page, per_page then we'll use the pager...
		// page:0 is special: return ranked results
		// page:1..n: results come from sha range queries (and exclude those returned on page:0).
		return c.searchPages(ctx, query, queryCtx)
	}

	// otherwise, just search normally
	return c.search(ctx, query, queryCtx, start, 0, 0, 0)
}

func (c *Cluster) search(ctx context.Context, query *querypb.Query, queryCtx *search.QueryContext, start time.Time, retries uint32, cost float32, docsReturned int) (*pb.QueryResponse, error) {
	ctx = logging.With(ctx, kvp.Int("retry", int(retries)))
	ctx = statting.WithTags(ctx, stats.Tags{"retry": fmt.Sprintf("%d", retries)})

	cResp, err := c.runQuery(ctx, query, queryCtx)
	if err != nil {
		return nil, err
	}
	cost += cResp.cost
	docsReturned += cResp.docsReturned

	// Filter to documents in accessible repos
	cStats, err := c.filterToAccessibleRepos(ctx, queryCtx, cResp.shardResponses)
	if err != nil {
		return nil, err
	}

	hadShardFailure := cResp.hadShardFailure
	hadShardTimeout := cResp.hadShardTimeout
	hitReturnLimit := cResp.hitReturnLimit
	hitRetrievalLimit := cResp.hitRetrievalLimit
	hitScoringLimit := cResp.hitScoringLimit
	hitLocationLimit := cStats.hitLocationLimit
	saturatedLocations := cStats.saturatedLocations
	notEnoughDocs := cStats.numDocuments < queryCtx.Limits.RequestedDocs
	retryAllowed := !hadShardTimeout && retries < queryCtx.MaxAllowedRetries && queryCtx.Limits.ToRetrieve <= search.ToRetrieveLimit
	retryWouldHelp := hitRetrievalLimit || hitReturnLimit || hitLocationLimit || hitScoringLimit
	timeLeftToRetry := time.Since(start)+cResp.elapsed < queryCtx.Timeout // NB: Assume the retry will take at least as long as the last request

	if notEnoughDocs && retryAllowed && retryWouldHelp && timeLeftToRetry {
		// hitting these blackbird limits means there *are* more docs if we issue
		// another query.
		if hitRetrievalLimit {
			queryCtx.Limits.ToRetrieve *= 4
		}
		if hitScoringLimit {
			queryCtx.Limits.ToRetrieve *= 4
			queryCtx.Limits.ToScore *= 4
		}
		if hitReturnLimit {
			queryCtx.Limits.ToReturn *= 4
		}
		if hitLocationLimit {
			// hitting the mw location limit means we filtered out too many locations
			// due to checking for accessible repos.
			queryCtx.Limits.LocationsLimit *= 4
		}

		logging.Info(ctx, "retrying for more results",
			kvp.Bool("hit_retrieval_limit", hitRetrievalLimit),
			kvp.Bool("hit_return_limit", hitReturnLimit),
			kvp.Bool("hit_location_limit", hitLocationLimit),
			kvp.Bool("hit_scoring_limit", hitScoringLimit),
			kvp.Bool("hit_saturatedLocations", saturatedLocations),
			kvp.Int("new_docs_to_retrieve", int(queryCtx.Limits.ToRetrieve)),
			kvp.Int("new_docs_to_score", int(queryCtx.Limits.ToScore)),
			kvp.Int("new_docs_to_return", int(queryCtx.Limits.ToReturn)),
			kvp.Int("new_locations_limit", int(queryCtx.Limits.LocationsLimit)))

		// Only return the new response if retry was successful, otherwise keep results from
		// the initial try and move on. This can happen if the initial tries didn't get us enough
		// results but subsequent retry failed completely, in this case some results are better than
		// nothing
		retries++
		if resp, err := c.search(ctx, query, queryCtx, start, retries, cost, docsReturned); err == nil {
			return resp, nil
		}
	} else if notEnoughDocs && retryAllowed && saturatedLocations && !queryCtx.DontRetryOnSaturatedLocations && timeLeftToRetry && queryCtx.QuerySource != search.QuerySourceProber && queryCtx.QueryType == search.QueryTypeUser {
		// Hitting saturatedLocations means: one or more docs has at least as many
		// locations as we requested, we didn't get enough docs, and we didn't hit
		// any other limits: bump the location limit and retry the query.
		//
		// NB: the default location limit is 5 so we bump high enough to fill an
		// entire request.
		queryCtx.Limits.LocationsLimit *= 20
		queryCtx.Limits.RequestedLocs *= 20
		// Also, rewrite the query to append the doc SHAs we did get.
		docSHAs := []string{}
		for _, response := range cResp.shardResponses {
			for _, doc := range response.Documents {
				oid := gitaccess.NewObjectIDFromBytes(doc.DocSha)
				docSHAs = append(docSHAs, oid.String()[0:8])
			}
		}
		query = &querypb.Query{
			Kind: querypb.QueryKind_QUERY_KIND_AND,
			Subqueries: []*querypb.Query{
				query,
				{
					Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
					Domain:      querypb.Domain_DOMAIN_SHA,
					ValueString: strings.Join(docSHAs, ","),
				}},
		}

		logging.Info(ctx, "locations saturated, retrying for more results",
			kvp.Bool("hit_retrieval_limit", hitRetrievalLimit),
			kvp.Bool("hit_return_limit", hitReturnLimit),
			kvp.Bool("hit_location_limit", hitLocationLimit),
			kvp.Bool("hit_scoring_limit", hitScoringLimit),
			kvp.Bool("hit_saturatedLocations", saturatedLocations),
			kvp.Int("new_docs_to_retrieve", int(queryCtx.Limits.ToRetrieve)),
			kvp.Int("new_docs_to_score", int(queryCtx.Limits.ToScore)),
			kvp.Int("new_docs_to_return", int(queryCtx.Limits.ToReturn)),
			kvp.Int("new_locations_limit", int(queryCtx.Limits.LocationsLimit)),
			kvp.String("new_query", serialize(query)))

		// Only return the new response if retry was successful, otherwise keep results from
		// the initial try and move on. This can happen if the initial tries didn't get us enough
		// results but subsequent retry failed completely, in this case some results are better than
		// nothing
		retries++
		queryCtx.DontRetryOnSaturatedLocations = true
		if resp, err := c.search(ctx, query, queryCtx, start, retries, cost, docsReturned); err == nil {
			return resp, nil
		}
	}

	timing.Record(ctx, timing.QueryStepRanQuery, start) // NB: inclusive of all retries

	// Now we want a flat list of documents to score
	docs := []*searchpb.GitDocumentMatch{}
	for _, response := range cResp.shardResponses {
		docs = append(docs, response.Documents...)
	}

	// Sort according to score and then SHA
	sort.Slice(docs, func(i, j int) bool {
		if docs[i].ScoringInfo.Score != docs[j].ScoringInfo.Score {
			return docs[i].ScoringInfo.Score > docs[j].ScoringInfo.Score
		}
		return bytes.Compare(docs[i].DocSha, docs[j].DocSha) > 0
	})

	// Rescore (and resort) documents accounting for crowding
	isEmbeddingSearch := parser.IsEmbeddingSearch(query)
	if !isEmbeddingSearch && !experiments.IsExperimentEnabled(ctx, experiments.NoCrowding) {
		scoring.EnforceCrowding(docs)
	}

	limit := int(queryCtx.Limits.RequestedDocs)
	if len(docs) < limit {
		limit = len(docs)
	}
	docs = docs[:limit]

	// Apply blob resolution filtering. Do after we've clamped down to the
	// requested doc limit as this call to spokesd is expensive and we want to
	// send the smallest number of documents possible.
	err = c.blobFilter.Apply(ctx, c.FilterBlobs(), queryCtx.Limits.RequestedLocs, &docs)
	if err != nil {
		logging.Error(ctx, "error resolving blobs", kvp.Err(err))
		return nil, err
	}

	// Note: This call to fetch missing documents used to happen before applying blob filtering,
	// the sequence is now swapped because fetchMissingContent works on query service's document
	// representation. Fetch missing content could possibly drop some documents if it had trouble
	// talking to index hosts so _in some cases_ (195 such instances in last 4 days at the time of
	// writing) we might end up performing blob resolution on more documents than we may return in
	// the end but... it seems like a fair compromise compared to changing the type of blob filter
	// functions.
	pbDocs, errors := c.fetchMissingContent(ctx, mapDocs(docs, queryCtx.Actor.GetTenant()), query, queryCtx, &cost)

	satisfied := true
	if notEnoughDocs && retryWouldHelp {
		satisfied = false
		errors = append(errors, &pb.QueryError{
			Type:    pb.ErrorType_ERROR_TYPE_RESULTS_INCOMPLETE,
			Message: "Results are not exhaustive because query was too expensive to satisfy, consider refining your query!",
		})
	} else if hadShardFailure {
		errors = append(errors, &pb.QueryError{
			Type:    pb.ErrorType_ERROR_TYPE_RESULTS_INCOMPLETE,
			Message: "Results are incomplete due to an internal error, please retry your query.",
		})
	} else if hadShardTimeout {
		errors = append(errors, &pb.QueryError{
			Type:    pb.ErrorType_ERROR_TYPE_RESULTS_INCOMPLETE,
			Message: "Results are incomplete due to an internal timeout, consider retrying or refining your query.",
		})
	} else if retryWouldHelp {
		// If have enough results but gave up then this search then we should stat this search result as non-exhaustive.
		// We don't need to tell the user this just yet.
		statting.Counter(ctx, "query_service.query.results_not_exhaustive", 1, stats.Tags{
			"gave_up":           strconv.FormatBool(retryWouldHelp),
			"had_shard_failure": strconv.FormatBool(hadShardFailure),
			"had_shard_timeout": strconv.FormatBool(hadShardTimeout),
		})
	}

	statting.Counter(ctx, "query_service.query.retries", 1, stats.Tags{
		"satisfied": strconv.FormatBool(satisfied),
		"retries":   strconv.FormatInt(int64(retries), 10),
	})

	logging.Info(ctx, "query response received from all shards",
		kvp.Bool("satisfied", satisfied),
		kvp.Bool("had_shard_failure", hadShardFailure),
		kvp.Bool("had_shard_timeout", hadShardTimeout),
		kvp.Bool("gave_up", retryWouldHelp),
		kvp.Bool("hit_retrieval_limit", hitRetrievalLimit),
		kvp.Bool("hit_return_limit", hitReturnLimit),
		kvp.Bool("hit_location_limit", hitLocationLimit),
		kvp.Bool("hit_scoring_limit", hitScoringLimit),
		kvp.Int("final_docs_to_retrieve", int(queryCtx.Limits.ToRetrieve)),
		kvp.Int("final_docs_to_score", int(queryCtx.Limits.ToScore)),
		kvp.Int("final_docs_to_return", int(queryCtx.Limits.ToReturn)),
		kvp.Int("final_docs_with_content", int(queryCtx.Limits.WithContent)),
		kvp.Int("num_responses", cResp.numResponses),
		kvp.Int("unavailable_shards", cResp.unavailableShards),
		kvp.Int("num_filtered", int(cStats.numFiltered)),
		kvp.Int("num_docs_requested", int(queryCtx.Limits.RequestedDocs)),
		kvp.Int("num_locs_requested", int(queryCtx.Limits.RequestedLocs)),
		kvp.Int("num_locs_limits", int(queryCtx.Limits.LocationsLimit)),
		kvp.Int("num_docs_returned", len(docs)),
		kvp.Int("num_docs_returned_to_user", len(docs)),
		kvp.Int("retries", int(retries)))

	return &pb.QueryResponse{
			Documents: pbDocs,
			Metadata: &pb.Metadata{
				ClusterName:          c.ClusterName(),
				CorpusName:           c.CorpusName(),
				Experiments:          experiments.GetExperiments(ctx),
				QueryAst:             serialize(query),
				TotalCost:            cost,
				Retries:              retries,
				NumFilteredDocuments: cStats.numFiltered,
				Satisfied:            satisfied,
				LimitReached:         retryWouldHelp,
				HadShardFailure:      hadShardFailure || hadShardTimeout,
				IsFailure:            false,
				Timing:               MapTimings(timing.Finish(ctx)),
				Shards:               cResp.metas,
				DocsReturned:         uint32(docsReturned),
				QueryId:              requestid.GetGitHubRequestID(ctx),
			},
			ServingOffsetQueried: int64(cResp.offset),
			QueryErrors:          errors,
		},
		nil
}

func buildSearchRequest(ctx context.Context, ast *querypb.Query, queryCtx *search.QueryContext, epochID types.EpochID, servingOffset routing.ServingOffset, shardID uint32) *searchpb.SearchRequest {
	ast.DivorToRetrieve = queryCtx.Limits.ToRetrieve
	ast.DivorToScore = queryCtx.Limits.ToScore
	var snippetOptions *searchpb.SnippetOptions

	if queryCtx.SnippetOptions != nil {
		opt := queryCtx.SnippetOptions

		maxTotalLines := uint32(7)
		if opt.MaxTotalLines != 0 {
			maxTotalLines = opt.MaxTotalLines
		}

		snippetOptions = &searchpb.SnippetOptions{
			Mode:                       searchpb.SnippetMode(opt.Mode),
			DesiredWidth:               opt.DesiredWidth,
			HighDensitySnippetMaxLines: opt.HighDensitySnippetMaxLines,
			MaxTotalLines:              maxTotalLines,
			MaxOverflows:               opt.MaxOverflows,
			SingleSnippetContextLines:  opt.SingleSnippetContextLines,
			DoubleSnippetContextLines:  opt.DoubleSnippetContextLines,
			MaxTokens:                  opt.MaxTokens,
		}
	}

	return &searchpb.SearchRequest{
		QueryAst:               ast,
		QuerySource:            string(queryCtx.QuerySource),
		DocsToReturn:           queryCtx.Limits.ToReturn,
		DocsWithFullInfo:       queryCtx.Limits.WithContent,
		LocationsLimit:         queryCtx.Limits.LocationsLimit,
		TermMatchLimit:         queryCtx.Limits.TermMatchLimit,
		TimeoutMillis:          uint32(queryCtx.Timeout.Milliseconds() - 500), // NB: allow 500ms for post query processing
		ServingOffset:          int64(servingOffset),
		ScoreDocids:            queryCtx.ScoreDocIDs,
		EpochId:                uint32(epochID),
		SnippetOptions:         snippetOptions,
		ShardId:                shardID,
		Experiments:            experiments.GetExperiments(ctx),
		ReturnEnclosingSymbols: queryCtx.ReturnEnclosingSymbols,
	}
}

func (c *Cluster) fetchMissingContent(ctx context.Context, docs []*pb.GitDocumentMatch, query *querypb.Query, queryCtx *search.QueryContext, cost *float32) ([]*pb.GitDocumentMatch, []*pb.QueryError) {
	queryErrors := []*pb.QueryError{}
	start := time.Now()
	defer func() {
		timing.Record(ctx, timing.QueryStepFetchedMissingContent, start)
	}()

	if queryCtx.Limits.WithContent == 0 {
		// NB: Probers set WithContent to zero which means don't bother fetching missing content
		return docs, queryErrors
	}

	docIDs := []*searchpb.DocId{}
	missingContentIdx := make(map[gitaccess.ObjectID][]int)
	for idx, doc := range docs {
		if len(doc.Content) == 0 {
			locIds := []*searchpb.LocationId{}
			for _, loc := range doc.Locations {
				locIds = append(locIds, &searchpb.LocationId{RepoId: loc.RepoId, Path: loc.Path, RefName: loc.RefName})
			}

			docIDs = append(docIDs, &searchpb.DocId{DocSha: doc.DocSha, Locations: locIds})
			missingContentIdx[gitaccess.NewObjectIDFromBytes(doc.DocSha)] = append(missingContentIdx[gitaccess.NewObjectIDFromBytes(doc.DocSha)], idx)
		}
	}

	if len(docIDs) == 0 {
		return docs, queryErrors
	}

	logging.Info(ctx, "fetching missing content", kvp.Int("num_docs_missing_content", len(docIDs)))
	statting.Counter(ctx, "query_service.fetch_missing_content", 1)
	statting.Counter(ctx, "query_service.fetch_missing_content.num_docs", int64(len(docIDs)))

	// Construct a blackbird search request with just the desired doc ids.
	fetchMissingQueryCtx := &search.QueryContext{
		ScoreDocIDs:  docIDs, // NB: Request just the these doc_ids
		ScopeRepoIDs: queryCtx.ScopeRepoIDs,
		Actor:        queryCtx.Actor,
		Limits: search.QueryLimits{
			RequestedDocs:  0, // Ignored b/c ScoreDocIDs is set
			RequestedLocs:  0, // Ignored b/c ScoreDocIDs is set
			LocationsLimit: 0, // Ignored b/c ScoreDocIDs is set
			TermMatchLimit: queryCtx.Limits.TermMatchLimit,
			ToRetrieve:     uint32(len(docIDs)),
			ToScore:        uint32(len(docIDs)),
			ToReturn:       0, // Ignored b/c ScoreDocIDs is set
			WithContent:    uint32(len(docIDs)),
		},
		MaxAllowedRetries: queryCtx.MaxAllowedRetries,
		Timeout:           queryCtx.Timeout,
		QueryType:         queryCtx.QueryType,
		QuerySource:       queryCtx.QuerySource,
		SnippetOptions:    queryCtx.SnippetOptions,
	}

	hadShardFailure := false
	hadShardTimeout := false
	hitRetrievalLimit := false
	hitReturnLimit := false
	hitScoringLimit := false

	for sr := range c.fanout(ctx, query, fetchMissingQueryCtx) {
		hadShardFailure = hadShardFailure || sr.QueryStats().GetHadPanic()
		hadShardTimeout = hadShardTimeout || sr.QueryStats().GetHadTimeout()
		hitRetrievalLimit = hitRetrievalLimit || sr.QueryStats().GetHitRetrievalLimit()
		hitReturnLimit = hitReturnLimit || sr.QueryStats().GetHitReturnLimit()
		hitScoringLimit = hitScoringLimit || sr.QueryStats().GetHitScoringLimit()

		if sr.ShardUnavailable {
			logging.Error(ctx, "could not fetch missing content: shard not available", kvp.Int("shard_id", int(sr.ShardID)))
			continue
		}

		*cost += sr.QueryStats().Cost
		// If we successfully fetched the documents with content then replace the docs in place with content
		for _, docWithContent := range sr.BBResponse.Documents {
			for _, idx := range missingContentIdx[gitaccess.NewObjectIDFromBytes(docWithContent.DocSha)] {
				docs[idx].BlobSha = docWithContent.BlobSha
				docs[idx].Content = docWithContent.Content
				docs[idx].ScoringInfo = mapScoringInfo(docWithContent.ScoringInfo)
				docs[idx].TermMatches = mapTermMatches(docWithContent.TermMatches)
				docs[idx].LanguageId = docWithContent.LanguageId

				for _, loc := range docs[idx].Locations {
					for _, locWithContent := range docWithContent.Locations {
						if loc.RepoId == locWithContent.RepoId && loc.Path == locWithContent.Path && loc.RefName == locWithContent.RefName {
							loc.OwnerId = locWithContent.OwnerId
							loc.CommitSha = locWithContent.CommitSha
							loc.RepoScore = locWithContent.RepoScore
							loc.IsRepoPublic = locWithContent.IsRepoPublic
							loc.Score = locWithContent.Score
							loc.RepoNwo = locWithContent.Nwo
							loc.NetworkId = locWithContent.NetworkId

							break
						}
					}
				}
			}
		}
	}

	// Remove docs that STILL don't have any content
	docsWithoutContent := 0
	docsWithContent := make([]*pb.GitDocumentMatch, 0, len(docs))
	for _, doc := range docs {
		if len(doc.Content) != 0 {
			docsWithContent = append(docsWithContent, doc)
		} else {
			docsWithoutContent++
			// NOTE: If we didn't find the document, we probably won't have filled in the blob SHA, so trying to log it will panic.
			docBlobOID := "missing"
			if len(doc.BlobSha) != 0 {
				docBlobOID = gitaccess.NewObjectIDFromBytes(doc.BlobSha).String()
			}

			logging.Error(ctx, "fetchMissingContent returned blank content for doc, removing from results",
				kvp.String("doc_sha", gitaccess.NewObjectIDFromBytes(doc.DocSha).String()),
				kvp.String("doc_blob_oid", docBlobOID),
				kvp.Bool("had_shard_failure", hadShardFailure),
				kvp.Bool("had_shard_timeout", hadShardTimeout),
				kvp.Bool("hit_retrieval_limit", hitRetrievalLimit),
				kvp.Bool("hit_return_limit", hitReturnLimit),
				kvp.Bool("hit_scoring_limit", hitScoringLimit),
			)
		}
	}

	if docsWithoutContent > 0 {
		// Log an error if are returning docs without content
		logging.Error(ctx, "filtered docs without content", kvp.Int("filtered", docsWithoutContent), kvp.Int("remaining", len(docsWithContent)))
		statting.Counter(ctx, "query_service.docs_without_content", int64(docsWithoutContent))
		queryErrors = append(queryErrors, &pb.QueryError{
			Type:    pb.ErrorType_ERROR_TYPE_RESULTS_INCOMPLETE,
			Message: "Some results may be missing due to a temporary problem loading content, please try your query again.",
		})
	}

	return docsWithContent, queryErrors
}
