package query

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/experiments"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/query/timing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
)

const (
	MaxResultsPerPage     = 100
	DefaultResultsPerPage = 30
	MaxResults            = 1000
)

// LegacyQuery converts the query into blackbird format and executes it.
func (s *queryService) LegacyQuery(ctx context.Context, req *pb.LegacyQueryRequest) (*pb.LegacyQueryResponse, error) {
	ctx = experiments.WithExperiments(ctx, req.Experiments) // new-style key/value experiments

	qreq := convertLegacyRequest(ctx, req)

	if experiments.IsExperimentEnabled(ctx, experiments.Pagination) {
		qreq.PageNumber = uint32(req.PageNumber)

		if qreq.ResultsPerPage == 0 || qreq.ResultsPerPage > MaxResultsPerPage {
			qreq.ResultsPerPage = DefaultResultsPerPage
		}
		qreq.ResultsPerPage = uint32(req.ResultsPerPage)
	}

	// If this page is beyond the max results, just return no results
	if qreq.PageNumber > 0 && (qreq.PageNumber-1)*qreq.ResultsPerPage > MaxResults {
		return &pb.LegacyQueryResponse{
			Page:      qreq.PageNumber,
			PageCount: MaxResults / qreq.ResultsPerPage,
			Metadata: &pb.Metadata{
				Experiments: experiments.GetExperiments(ctx),
				Timing:      blackbird.MapTimings(timing.Finish(ctx)),
			},
		}, nil
	}

	queryType := getQueryType(ctx, qreq.QueryType)
	querySource := getQuerySource(ctx, qreq.QuerySource)
	ctx, actor, err := s.prepareContext(ctx, req.Query, queryType, querySource, qreq.ScopingQuery, req.Actor, req.Tenant, req.Experiments)
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

	res, _, err := s.query(ctx, actor, qreq, epoch.EpochFeaturesLexical)
	if err != nil {
		return nil, err
	}

	pg := selectPage(res.Documents, req)
	if experiments.IsExperimentEnabled(ctx, experiments.Pagination) {
		pages := res.ResultCount / uint64(req.ResultsPerPage)
		if res.ResultCount%uint64(req.ResultsPerPage) > 0 {
			pages += 1
		}

		pg = page{
			docs:      res.Documents,
			page:      uint32(req.PageNumber),
			pageCount: uint32(pages),
		}
	}

	// NOTE: Perhaps we can skip fetching content if snippets aren't requested
	results := make([]*pb.SearchResult, 0, len(pg.docs))
	for _, doc := range pg.docs {
		var lines []string

		format := pb.SnippetFormat_SNIPPET_FORMAT_INVALID
		if req.SnippetOptions != nil {
			lines = strings.Split(string(doc.Content), "\n")
			format = pb.SnippetFormat_SNIPPET_FORMAT_PLAIN_TEXT
		}
		results = append(results, convertSearchResult(ctx, req.Tenant, doc, lines, format, format))
	}

	return &pb.LegacyQueryResponse{
		Results:     results,
		QueryErrors: res.QueryErrors,
		Page:        pg.page,
		PageCount:   pg.pageCount,
		ResultCount: uint32(res.ResultCount),
		Metadata:    res.Metadata,
	}, nil
}

func convertLegacyRequest(ctx context.Context, req *pb.LegacyQueryRequest) *pb.QueryRequest {
	source := pb.QuerySource_QUERY_SOURCE_LEGACY_API
	if req.Actor != nil && (req.Actor.ActorId == 159751423 || req.Actor.ActorId == 162577419) {
		source = pb.QuerySource_QUERY_SOURCE_BING
	}

	qreq := &pb.QueryRequest{
		Query:                 req.Query,
		QueryParser:           pb.QueryParser_QUERY_PARSER_GEYSER,
		DocumentLimit:         req.DocumentLimit,
		DocumentLocationLimit: req.DocumentLocationLimit,
		// ScopingQuery:          req.ScopingQuery,
		Actor: req.Actor,
		// EpochId:        req.EpochId,
		// CustomScopes:   req.CustomScopes,
		SnippetOptions: req.SnippetOptions,
		QueryType:      pb.QueryType_QUERY_TYPE_USER_QUERY,
		RequestTimeout: req.RequestTimeout,
		QuerySource:    source,
		// Pagination set later
		// PageNumber:     req.PageNumber,
		// ResultsPerPage: req.ResultsPerPage,
		Experiments: req.Experiments,
		Tenant:      req.Tenant,
	}

	if req.SnippetOptions != nil {
		if val, ok := experiments.GetExperiment(ctx, experiments.SnippetSize); ok {
			if size, err := strconv.ParseUint(val, 10, 32); err == nil {
				qreq.SnippetOptions.MaxTotalLines = uint32(size)
				qreq.SnippetOptions.DoubleSnippetContextLines = uint32(size/2) - 1
				qreq.SnippetOptions.MaxTokens = uint32(size)
			}
		}
	}

	return qreq
}
