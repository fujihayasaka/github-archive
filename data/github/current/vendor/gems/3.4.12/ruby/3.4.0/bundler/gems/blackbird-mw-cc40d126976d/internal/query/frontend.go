package query

import (
	"context"
	"encoding/hex"
	"html"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/blackbird/crates/linguist/pkg/linguist"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"google.golang.org/protobuf/types/known/durationpb"

	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/treelights/proto"
	"github.com/github/blackbird-mw/internal/types"
)

func convertFrontendRequest(ctx context.Context, req *pb.FrontendQueryRequest) *pb.QueryRequest {
	qreq := &pb.QueryRequest{
		Query:                 req.Query,
		QueryParser:           req.QueryParser,
		DocumentLimit:         req.DocumentLimit,
		DocumentLocationLimit: req.DocumentLocationLimit,
		ScopingQuery:          req.ScopingQuery,
		Actor:                 req.Actor,
		// EpochId:               req.EpochId,
		CustomScopes:   req.CustomScopes,
		SnippetOptions: req.SnippetOptions,
		QueryType:      req.QueryType,
		RequestTimeout: req.RequestTimeout,
		QuerySource:    req.QuerySource,
		// NB: Do not set PageNumber or ResultsPerPage here (no pagination for frontend queries)
		// PageNumber:     uint32(req.PageNumber),
		// ResultsPerPage: uint32(req.ResultsPerPage),
		Experiments:            req.Experiments,
		ReturnEnclosingSymbols: req.ReturnEnclosingSymbols,
		Tenant:                 req.Tenant,
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

func convertSearchResult(
	ctx context.Context,
	tenant *pb.Tenant,
	doc *pb.GitDocumentMatch,
	lines []string,
	inputFormat,
	outputFormat pb.SnippetFormat,
) *pb.SearchResult {
	snippets := []*pb.RenderedSnippet{}

	lineNumber := uint32(0)
	nextMatch := 0

	if doc.ScoringInfo != nil {
		for _, snippet := range doc.ScoringInfo.Snippets {
			// NOTE: the line numbers in the protobuf representation are one-indexed
			startLineIndex := int(snippet.StartingLineNumber - 1)
			endLineIndex := int(snippet.EndingLineNumber - 1)
			if endLineIndex > len(lines) {
				// syntax highlighting won't return anything for trailing newlines, just take the last line we have.
				endLineIndex = len(lines)
			}

			// Determine the correct line number to link to. We take the middle of first snippet.
			// TODO(colinwm): calculate this in blackbird when creating snippets
			if lineNumber == 0 && snippet.EndingLineNumber >= snippet.StartingLineNumber {
				lineNumber = uint32(math.Floor(float64(snippet.EndingLineNumber-snippet.StartingLineNumber)/2)) + snippet.StartingLineNumber
			}

			// If the snippet doesn't start at the beginning of a
			// line or end at the end of a line, use plaintext
			// content and insert ellipsis
			leadingEllipsis := false
			trailingEllipsis := false

			if snippet.Start >= snippet.End || int(snippet.End) > len(doc.Content) {
				continue
			}

			if snippet.Start > 0 && doc.Content[int(snippet.Start)-1] != '\n' {
				leadingEllipsis = true
			}

			if int(snippet.End) < len(doc.Content) && doc.Content[int(snippet.End)] != '\n' {
				trailingEllipsis = true
			}

			// If we have plain text but desire HTML, indicate the matches with <mark>...</mark>
			if (leadingEllipsis || trailingEllipsis || inputFormat == pb.SnippetFormat_SNIPPET_FORMAT_PLAIN_TEXT) && outputFormat == pb.SnippetFormat_SNIPPET_FORMAT_HTML {
				matchCount := uint32(0)
				// Skip to the next match contained in the snippet
				for nextMatch < len(doc.TermMatches) && doc.TermMatches[nextMatch].End < snippet.Start {
					nextMatch++
				}

				pos := snippet.Start
				snippetContent := ""
				for nextMatch < len(doc.TermMatches) && doc.TermMatches[nextMatch].Start < snippet.End {
					matchCount++
					var termStart uint32
					if snippet.Start > doc.TermMatches[nextMatch].Start {
						termStart = snippet.Start
					} else {
						termStart = doc.TermMatches[nextMatch].Start
					}

					// Handle overlapping matches by joining the highlights together
					for joinedMatch := nextMatch + 1; joinedMatch < len(doc.TermMatches); joinedMatch++ {
						if doc.TermMatches[joinedMatch].Start > doc.TermMatches[nextMatch].End {
							break
						}

						if doc.TermMatches[joinedMatch].End > doc.TermMatches[nextMatch].End {
							nextMatch = joinedMatch
						}
					}

					if pos > termStart {
						nextMatch++
						continue
					}

					snippetContent += html.EscapeString(string(doc.Content[pos:termStart]))

					var termEnd uint32
					if snippet.End < doc.TermMatches[nextMatch].End {
						termEnd = snippet.End
					} else {
						termEnd = doc.TermMatches[nextMatch].End
					}
					snippetContent += "<mark>"
					snippetContent += strings.Join(strings.Split(html.EscapeString(string(doc.Content[termStart:termEnd])), "\n"), "</mark>\n<mark>")
					snippetContent += "</mark>"

					pos = termEnd
					nextMatch++
				}

				// Add trailing part of snippet
				snippetContent += html.EscapeString(string(doc.Content[pos:snippet.End]))

				start := snippet.Start
				end := snippet.End
				if leadingEllipsis {
					snippetContent = "…" + snippetContent
				}
				if trailingEllipsis {
					snippetContent += "…"
				}

				snippets = append(snippets, &pb.RenderedSnippet{
					Lines:              strings.Split(snippetContent, "\n"),
					StartingLineNumber: snippet.StartingLineNumber,
					EndingLineNumber:   snippet.EndingLineNumber,
					JumpToLineNumber:   (snippet.StartingLineNumber + snippet.EndingLineNumber) / 2,
					Format:             pb.SnippetFormat_SNIPPET_FORMAT_HTML,
					MatchCount:         matchCount,
					Score:              snippet.Score,
					Start:              start,
					End:                end,
				})
			} else if startLineIndex >= 0 && startLineIndex < endLineIndex {
				matchCount := uint32(0)
				// Skip to the next match contained in the snippet
				for nextMatch < len(doc.TermMatches) && doc.TermMatches[nextMatch].End < snippet.Start {
					nextMatch++
				}

				// Count only non-overlapping matches
				pos := uint32(0)
				for nextMatch < len(doc.TermMatches) && doc.TermMatches[nextMatch].Start < snippet.End {
					match := doc.TermMatches[nextMatch]
					if match.Start > pos {
						matchCount++
					}
					pos = match.End
					nextMatch++
				}

				selectedLines := lines[startLineIndex:endLineIndex]

				// TODO: Trim any extra blank trailing newlines to improve the snippet rendering.

				snippets = append(snippets, &pb.RenderedSnippet{
					Lines:              selectedLines,
					StartingLineNumber: snippet.StartingLineNumber,
					EndingLineNumber:   snippet.EndingLineNumber,
					JumpToLineNumber:   (snippet.StartingLineNumber + snippet.EndingLineNumber) / 2,
					Format:             inputFormat,
					MatchCount:         matchCount,
					Score:              snippet.Score,
					Start:              snippet.Start,
					End:                snippet.End,
				})
			} else {
				logging.Error(ctx, "dropping snippet", kvp.Int("num_lines", len(lines)), kvp.Any("snippet", snippet))
			}
		}
	}

	// Look up the language name and color using Linguist
	language := ""
	languageColor := ""
	if name, err := linguist.GetLanguageName(doc.LanguageId); err == nil {
		language = name

	}
	if color, err := linguist.GetLanguageColor(doc.LanguageId); err == nil {
		languageColor = color
	}

	// Collect together duplicate location info
	duplicateLocations := []*pb.DuplicateLocationInfo{}
	for _, loc := range doc.Locations[1:] {
		nwo := types.NWOFromString(loc.RepoNwo).NameWithDisplayOwner(tenant)
		duplicateLocations = append(duplicateLocations, &pb.DuplicateLocationInfo{
			Path:      loc.Path,
			RepoId:    loc.RepoId,
			RepoNwo:   nwo,
			OwnerId:   loc.OwnerId,
			CommitSha: hex.EncodeToString(loc.CommitSha),
		})
	}

	// Count only non-overlapping matches
	matchCount := uint32(0)
	if len(doc.TermMatches) > 0 {
		matchCount++
		pos := doc.TermMatches[0].End
		for _, match := range doc.TermMatches {
			if match.Start > pos {
				matchCount++
			}
			pos = match.End
		}
	}

	var factors []*pb.ScoringContribution
	if experiments.IsExperimentEnabled(ctx, experiments.ExtendedScoringInfo) {
		factors = doc.ScoringInfo.Factors
	}

	loc := doc.Locations[0]
	nwo := types.NWOFromString(loc.RepoNwo).NameWithDisplayOwner(tenant)
	return &pb.SearchResult{
		Path:          loc.Path,
		RepoId:        loc.RepoId,
		RepoNwo:       nwo,
		OwnerId:       loc.OwnerId,
		CommitSha:     hex.EncodeToString(loc.CommitSha),
		RefName:       loc.RefName,
		BlobSha:       hex.EncodeToString(doc.BlobSha),
		LanguageName:  language,
		LanguageId:    doc.LanguageId,
		HasLanguageId: doc.LanguageId != constants.UnknownLanguageId,
		LanguageColor: languageColor,
		Snippets:      snippets,
		MatchCount:    matchCount,
		DebugInfo: &pb.DebugInfo{
			RetrievalPosition: doc.RetrievalPosition,
			Score:             doc.ScoringInfo.Score,
			Factors:           factors,
		},
		LineNumber:         lineNumber,
		TermMatches:        doc.TermMatches,
		MatchedSymbols:     doc.ScoringInfo.MatchedSymbols,
		EnclosingSymbols:   doc.ScoringInfo.EnclosingSymbols,
		DuplicateLocations: duplicateLocations,
		FileSize:           uint32(len(doc.Content)),
	}
}

func isTooBigToHighlight(doc *pb.GitDocumentMatch) bool {
	limit := constants.SyntaxHighlightingMaxFilesize
	if doc.LanguageId == constants.CPPLanguageId || doc.LanguageId == constants.CLanguageID {
		limit = constants.SyntaxHighlightingMaxFilesizeCPP
	}

	return len(doc.Content) > limit
}

func clusterFeaturesForExperiments(ctx context.Context) epoch.EpochFeatures {
	v, _ := experiments.GetExperiment(ctx, experiments.PromptQualifier)
	switch v {
	case experiments.Enabled:
		// prompt_qualifier=1
		return epoch.EpochFeaturesEmbeddings
	case experiments.PromptQualifierBM25:
		// prompt_qualifier=bm25
		return epoch.EpochFeaturesBM25
	default:
		return epoch.EpochFeaturesLexical
	}
}

func (s *queryService) FrontendQuery(ctx context.Context, req *pb.FrontendQueryRequest) (*pb.FrontendQueryResponse, error) {
	ctx = experiments.WithExperiments(ctx, req.Experiments)

	cap := clusterFeaturesForExperiments(ctx)
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

	qreq := convertFrontendRequest(ctx, req)
	res, ctx, err := s.query(ctx, actor, qreq, cap)
	if err != nil {
		return nil, err
	}
	postSearchStart := time.Now()

	facetExtractor := NewFacetsExtractor()
	for _, doc := range res.Documents {
		facetExtractor.AddDocument(doc)
	}

	page := selectPage(res.Documents, req)

	desiredSnippetFormat := pb.SnippetFormat_SNIPPET_FORMAT_HTML
	if req.SnippetOptions != nil && req.SnippetOptions.Format != pb.SnippetFormat_SNIPPET_FORMAT_INVALID {
		desiredSnippetFormat = req.SnippetOptions.Format
	}

	detailedLogging := experiments.IsExperimentEnabled(ctx, experiments.SnippetHighlightLogging)
	hlmap := map[int]*proto.Highlighted{}
	if desiredSnippetFormat == pb.SnippetFormat_SNIPPET_FORMAT_HTML {
		hlreq := &proto.HighlightRequest{Docs: []*proto.Document{}}

		for i, doc := range page.docs {
			tmScope, err := linguist.GetLanguageTMScope(doc.LanguageId)
			if err != nil && doc.LanguageId != constants.UnknownLanguageId {
				logging.Error(ctx, "unrecognized language id", kvp.Int("language_id", int(doc.LanguageId)))
				continue
			}

			if isTooBigToHighlight(doc) {
				continue
			}

			if detailedLogging {
				logging.Info(ctx, "highlighting", kvp.String("tm_scope", tmScope), kvp.Any("matches", doc.TermMatches), kvp.Any("snippets", doc.ScoringInfo.Snippets))
			}
			content := treelights.AddHighlightTokens(doc)
			hlreq.Docs = append(hlreq.Docs, &proto.Document{Id: uint64(i), Scope: tmScope, Content: content})
		}
		hlres, err := s.treelightsClient.HighlightMany(ctx, hlreq)
		if err != nil {
			logging.Error(ctx, "failed to syntax highlight responses, falling back to plain text", kvp.Err(err))
			statting.Counter(ctx, "query_service.documents_failing_highlight", int64(len(hlreq.Docs)))
		}

		if hlres != nil {
			for _, doc := range hlres.Docs {
				hlmap[int(doc.Id)] = doc
			}
		}
	}

	// Convert the responses
	results := make([]*pb.SearchResult, 0, len(page.docs))
	for i, doc := range page.docs {
		if len(doc.Locations) == 0 {
			docSha := gitaccess.NewObjectIDFromBytes(doc.DocSha)
			blobSha := gitaccess.NewObjectIDFromBytes(doc.BlobSha)
			logging.Error(ctx, "skipped document with no locations", kvp.String("doc_sha", docSha.String()), kvp.String("blob_sha", blobSha.String()))
			continue
		}

		var lines []string
		var snippetFormat pb.SnippetFormat
		if highlighted, ok := hlmap[i]; ok {
			for i := range highlighted.Lines {
				lines = append(lines, treelights.ReplaceHighlightTokens(highlighted.Lines[i]))
			}
			if detailedLogging {
				logging.Info(ctx, "highlighted lines", kvp.Any("lines", lines), kvp.Int("num_lines", len(lines)))
			}
			snippetFormat = pb.SnippetFormat_SNIPPET_FORMAT_HTML
		} else {
			lines = strings.Split(string(doc.Content), "\n")
			snippetFormat = pb.SnippetFormat_SNIPPET_FORMAT_PLAIN_TEXT
		}

		result := convertSearchResult(ctx, req.Tenant, doc, lines, snippetFormat, desiredSnippetFormat)
		if detailedLogging {
			logging.Info(ctx, "highlighted result", kvp.Any("result", result))
		}
		results = append(results, result)
	}

	// Adjust post search and total timings for extra time spent in FrontendQuery
	additional := time.Since(postSearchStart)
	res.Metadata.Timing.Overall = durationpb.New(res.Metadata.Timing.Overall.AsDuration() + additional)
	res.Metadata.Timing.PostSearch = durationpb.New(res.Metadata.Timing.PostSearch.AsDuration() + additional)

	return &pb.FrontendQueryResponse{
		Results:                  results,
		QueryErrors:              res.QueryErrors,
		ResultCount:              uint32(len(res.Documents)),
		Page:                     uint32(req.PageNumber),
		PageCount:                page.pageCount,
		Facets:                   facetExtractor.GetFacets(req.Tenant),
		ProtectedOrganizationIds: res.ProtectedOrganizationIds,
		Metadata:                 res.Metadata,
	}, nil
}
