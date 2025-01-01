package blackbird

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/gob"
	"fmt"
	"math"
	"time"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"google.golang.org/protobuf/proto"

	"github.com/github/blackbird-mw/internal/background"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/constants"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/parser"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/types"
)

const (
	MaxPaginationLoopAttempts = 100
	MinDocumentsPerRequest    = 100
	MaxDocumentsPerRequest    = 1000
	FinalSHA                  = "ffffffffffffffff"
)

func (c *Cluster) searchPages(ctx context.Context, q *querypb.Query, qCtx *search.QueryContext) (*pb.QueryResponse, error) {
	start := time.Now()
	// We always need at least the first page of ranked results. Check the cache
	// first, then search only if we need to.
	key := key(c.EpochID(), qCtx)
	shouldUpdateCache := false
	res, err := c.cacheGet(ctx, key)

	defer func() {
		if shouldUpdateCache {
			bgCtx := background.Context(ctx) // NB: we want cacheSet to succeed even if the context is canceled.
			if err := c.cacheSet(bgCtx, key, res); err != nil {
				// We can't take action on the error so just ignore it
				logging.Error(ctx, "failed to set pagination cache, ignoring error", kvp.String("key", key), kvp.Err(err))
			}
		}
	}()

	if err != nil {
		return nil, err
	}
	if res != nil && res.isSatisfied(qCtx) {
		// everything we need is in the cache, respond will fetch missing content.
		return c.respond(ctx, q, qCtx, res)
	}

	if res == nil {
		// nothing in the cache: search for the first page (ranked results) and
		// cache the response.

		// Don't over-score documents, just score as many as we want
		// to return.
		qCtx.Limits.ToScore = qCtx.Limits.ToReturn
		resp, err := c.search(ctx, q, qCtx, start, 0, 0, 0)
		if err != nil {
			return nil, err
		}
		res = SearchResultsFromResponse(qCtx, resp)
		shouldUpdateCache = true
		if res.isSatisfied(qCtx) {
			return c.respond(ctx, q, qCtx, res)
		}
	}

	// Need to count the results in order to get the SHA range
	if !res.HasCount {
		countQuery := parser.MakeCountQueryProto(q)

		cResp, err := c.Count(ctx, countQuery, qCtx)
		if err != nil {
			return nil, err
		}
		res.Count = uint64(cResp.Count)
		res.HasCount = true

		if res.metadata == nil {
			res.metadata = cResp.Metadata
		} else {
			res.metadata.TotalCost += cResp.Metadata.TotalCost
		}

		shouldUpdateCache = true

		// We may just need a count
		if res.isSatisfied(qCtx) {
			return c.respond(ctx, q, qCtx, res)
		}
	}

	// Deep pagination should *not* retry on saturated locations
	qCtx.DontRetryOnSaturatedLocations = true

	for attempts := 0; attempts < MaxPaginationLoopAttempts; attempts++ {
		if attempts == 10 {
			logging.Info(ctx, "warning, many pagination attempts required...", kvp.String("key", key), kvp.Int("per_page", int(qCtx.PaginationOptions.PerPage)), kvp.Int("page_idx", int(qCtx.PaginationOptions.PageIdx)))
		}

		// Request two pages of content
		need := qCtx.PaginationOptions.PerPage
		if need < MinDocumentsPerRequest {
			need = MinDocumentsPerRequest
		}
		if need > MaxDocumentsPerRequest {
			need = MaxDocumentsPerRequest
		}

		// Over-request docs so that we will cover the entire SHA range
		qCtx.Limits.RequestedDocs = need * 2
		qCtx.Limits.ToReturn = need * 2
		qCtx.Limits.ToScore = qCtx.Limits.ToReturn

		shaRangeStart, shaRangeEnd, err := determineSHARange(res.NextSHA, int(need), res.Count)
		if err != nil {
			return nil, err
		}

		// Build exclusion queries
		exclusions := []*querypb.Query{}
		seen := map[gitaccess.ObjectID]bool{}
		for i := 0; i < len(res.Results) && i < res.NumRanked; i++ {
			// Don't write the same SHA multiple times to the exclude list
			oid := gitaccess.NewObjectIDFromBytes(res.Results[i].DocSHA)
			if seen[oid] {
				continue
			} else {
				seen[oid] = true
			}

			exclusions = append(
				exclusions,
				&querypb.Query{
					Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
					Domain:      querypb.Domain_DOMAIN_SHA,
					ValueString: oid.String(),
				},
			)
		}

		rQ := &querypb.Query{
			Kind: querypb.QueryKind_QUERY_KIND_AND,
			Subqueries: []*querypb.Query{
				q, // original query
				{ // SHA range
					Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
					Domain:      querypb.Domain_DOMAIN_SHA,
					ValueString: fmt.Sprintf("%s..%s", shaRangeStart, shaRangeEnd),
				},
				{ // exclusions of ranked results
					Kind: querypb.QueryKind_QUERY_KIND_NOT,
					Subqueries: []*querypb.Query{{
						Kind:       querypb.QueryKind_QUERY_KIND_OR,
						Subqueries: exclusions,
					}},
				},
			},
		}

		// fetch the next page of results and then cache them.
		// TODO: We might want to use a lower level search as this one does too much work (e.g. fetches missing content)
		resp, err := c.search(ctx, rQ, qCtx, start, 0, 0, 0)
		if err != nil {
			return nil, err
		}

		// If we encountered a shard failure, it means we are caching
		// some invalid data which cannot be recovered by retrying,
		// since the retry will just hit the cache!
		if resp.Metadata.HadShardFailure {
			statting.Counter(ctx, "pagination_cached_shard_failure", 1)
		}

		res.append(qCtx, resp, shaRangeEnd)
		shouldUpdateCache = true

		if res.isSatisfied(qCtx) {
			return c.respond(ctx, q, qCtx, res)
		}
	}

	return nil, fmt.Errorf("unable to satisfy pagination after %d attempts, gave up", MaxPaginationLoopAttempts)
}

// This function:
// - figures out which page we're serving
// - merge up all responses
// - for anything in res that doesn't have content, go fetch it and merge those in too.
func (c *Cluster) respond(ctx context.Context, q *querypb.Query, qCtx *search.QueryContext, res *SearchResults) (*pb.QueryResponse, error) {
	start := qCtx.PaginationOptions.PageIdx * qCtx.PaginationOptions.PerPage
	end := start + qCtx.PaginationOptions.PerPage
	if int(end) > len(res.Results) {
		end = uint32(len(res.Results))
	}
	if start > end {
		start = end
	}
	docs := []*pb.GitDocumentMatch{}
	for _, r := range res.Results[start:end] {
		docSHA := gitaccess.NewObjectIDFromBytes(r.DocSHA)
		if doc, ok := res.docs[docSHA]; ok {
			// Find the matching location and emit it as its own document
			for _, loc := range doc.Locations {
				if loc.RepoId == r.RepoID && loc.Path == r.Path && loc.RefName == r.Ref {
					d := proto.Clone(doc).(*pb.GitDocumentMatch)
					d.Locations = []*pb.Location{loc}
					docs = append(docs, d)
					break
				}
			}

			continue
		}

		// Stub GitDocumentMatch: will be filled in by fetchMissingContent
		doc := &pb.GitDocumentMatch{
			DocSha:  r.DocSHA,
			BlobSha: nil,
			Locations: []*pb.Location{{
				RepoId:  uint32(r.RepoID),
				RepoNwo: r.RepoNWO,
				Path:    r.Path,
				RefName: r.Ref,
			}},
			TermMatches:       nil,
			Content:           nil,
			LanguageId:        constants.UnknownLanguageId,
			TotalLocations:    0, // TODO: Does it matter that this is unset?
			ScoringInfo:       nil,
			RetrievalPosition: 0, // TODO: Does it matter that this is unset?

		}
		docs = append(docs, doc)
	}

	var errors []*pb.QueryError
	var fetchMissingContentCost float32
	docs, errors = c.fetchMissingContent(ctx, docs, q, qCtx, &fetchMissingContentCost)

	if res.metadata == nil {
		res.metadata = &pb.Metadata{
			ClusterName:          c.ClusterName(),
			CorpusName:           c.CorpusName(),
			Experiments:          experiments.GetExperiments(ctx),
			QueryAst:             serialize(q),
			TotalCost:            float32(quota.PaginationCacheOnlyCost) + fetchMissingContentCost,
			Retries:              0,
			NumFilteredDocuments: 0,
			Satisfied:            true,
			LimitReached:         false,
			HadShardFailure:      false,
			IsFailure:            false,
			DocsReturned:         uint32(len(docs)),
			QueryId:              requestid.GetGitHubRequestID(ctx),
		}
	} else {
		res.metadata.TotalCost += fetchMissingContentCost
	}

	if res.NextSHA == FinalSHA || uint64(len(res.Results)) > res.Count {
		res.CountMode = pb.CountMode_COUNT_MODE_EXACT
		res.Count = uint64(len(res.Results))
	}

	return &pb.QueryResponse{
		Documents:                docs,
		QueryErrors:              errors,
		ProtectedOrganizationIds: qCtx.Actor.ProtectedOrganizationIDs,
		Metadata:                 res.metadata,
		ServingOffsetQueried:     res.ServingOffset,
		ResultCount:              res.Count,
		CountMode:                res.CountMode,
	}, nil
}

func (c *Cluster) cacheGet(ctx context.Context, key string) (*SearchResults, error) {
	data, err := c.cache.Get(ctx, key)
	if err == cache.KeyNotPresent {
		return nil, nil
	}

	if err != nil {
		return nil, err
	}
	var results SearchResults
	if err := results.Unmarshal(data); err != nil {
		return nil, err
	}
	return &results, nil
}

func (c *Cluster) cacheSet(ctx context.Context, key string, res *SearchResults) error {
	data, err := res.Marshal()
	if err != nil {
		return err
	}
	return c.cache.Set(ctx, key, data, 1*time.Hour)
}

func convertResults(qCtx *search.QueryContext, resp *pb.QueryResponse) []*ResultDoc {
	// Because we're dealing with the user-facing representation, we have to add back in tenant suffixes
	// to save things in the cache.
	tenant := qCtx.Actor.GetTenant()
	results := []*ResultDoc{}

	// Append only the first locations first, so we get some diversity near
	// the top of the search results
	for _, doc := range resp.Documents {
		for _, loc := range doc.Locations {
			nwo := types.NWOFromString(loc.RepoNwo).NameWithUniqueOwner(tenant)
			results = append(results, &ResultDoc{
				RepoID:  loc.RepoId,
				RepoNWO: nwo,
				DocSHA:  doc.DocSha,
				Path:    loc.Path,
				Ref:     loc.RefName,
			})
			break
		}
	}

	// Append the duplicates at the end
	for _, doc := range resp.Documents {
		if len(doc.Locations) > 1 {
			for _, loc := range doc.Locations[1:] {
				nwo := types.NWOFromString(loc.RepoNwo).NameWithUniqueOwner(tenant)
				results = append(results, &ResultDoc{
					RepoID:  loc.RepoId,
					RepoNWO: nwo,
					DocSHA:  doc.DocSha,
					Path:    loc.Path,
					Ref:     loc.RefName,
				})
			}
		}
	}
	return results
}

type SearchResults struct {
	Results       []*ResultDoc
	NumRanked     int // results before this index are ranked and should be excluded from sha sorted queries
	NextSHA       string
	ServingOffset int64
	Count         uint64
	HasCount      bool
	CountMode     pb.CountMode

	docs     map[gitaccess.ObjectID]*pb.GitDocumentMatch
	metadata *pb.Metadata
}

func SearchResultsFromResponse(qCtx *search.QueryContext, resp *pb.QueryResponse) *SearchResults {
	nextSHA := gitaccess.NullObjectID.String()
	// Unset the next SHA to indicate that we have exhausted the results
	count := uint64(0)
	hasCount := false

	// If we have enough docs directly from the ranked request, we don't
	// need to separately try to estimate the count
	if len(resp.Documents) < int(qCtx.Limits.ToReturn) {
		nextSHA = FinalSHA
		count = uint64(len(resp.Documents))
		hasCount = true
	}
	return &SearchResults{
		Results:       convertResults(qCtx, resp),
		NumRanked:     len(resp.Documents),
		NextSHA:       nextSHA,
		ServingOffset: resp.ServingOffsetQueried,
		HasCount:      hasCount,
		Count:         count,

		metadata: resp.Metadata,
		docs:     map[gitaccess.ObjectID]*pb.GitDocumentMatch{},
	}
}

type ResultDoc struct {
	// DocSHA is the Document SHA used for sharding.
	DocSHA  []byte
	Path    string
	Ref     string
	RepoID  uint32
	RepoNWO string
}

func (s *SearchResults) isSatisfied(qCtx *search.QueryContext) bool {
	// Must provide a count estimate
	if !s.HasCount {
		return false
	}

	// Give up if one of the requests gave up
	if s.metadata != nil && s.metadata.LimitReached {
		return true
	}

	// Check if we have enough results to satisfy the request.
	// If there isn't a NextSHA: these results are exhaustive.
	return len(s.Results) >= int((qCtx.PaginationOptions.PageIdx+1)*qCtx.PaginationOptions.PerPage) || s.NextSHA == FinalSHA
}

func (s *SearchResults) append(qCtx *search.QueryContext, resp *pb.QueryResponse, nextSHA string) {
	s.Results = append(s.Results, convertResults(qCtx, resp)...)

	if s.docs == nil {
		s.docs = make(map[gitaccess.ObjectID]*pb.GitDocumentMatch)
	}
	for _, d := range resp.Documents {
		s.docs[gitaccess.NewObjectIDFromBytes(d.BlobSha)] = d
	}

	s.NextSHA = nextSHA

	if s.metadata == nil {
		s.metadata = resp.Metadata
	} else {
		// Merge together metadata from all requests
		s.metadata.TotalCost += resp.Metadata.TotalCost
		s.metadata.Retries += resp.Metadata.Retries
		s.metadata.NumFilteredDocuments += resp.Metadata.NumFilteredDocuments
		s.metadata.HadShardFailure = s.metadata.HadShardFailure || resp.Metadata.HadShardFailure
		s.metadata.LimitReached = false
		s.metadata.IsFailure = false
		s.metadata.Satisfied = s.metadata.Satisfied && resp.Metadata.Satisfied
		s.metadata.DocsReturned += uint32(len(resp.Documents))
	}
}

func (a SearchResults) Marshal() ([]byte, error) {
	var buf bytes.Buffer
	err := gob.NewEncoder(&buf).Encode(a)
	return buf.Bytes(), err
}

func (a *SearchResults) Unmarshal(data []byte) error {
	return gob.NewDecoder(bytes.NewReader(data)).Decode(a)
}

func key(epochID types.EpochID, qCtx *search.QueryContext) string {
	return fmt.Sprintf("blackbird:v3:pagination:%d:%d:%s:%x",
		epochID,
		qCtx.Actor.ID,
		qCtx.Actor.Hash(),
		qCtx.QueryCacheKey,
	)
}

func determineSHARange(nextSHA string, desiredResults int, totalResults uint64) (string, string, error) {
	// We only store the shortened 64bit SHA as NextSHA, so pad with zeroes
	for len(nextSHA) < 40 {
		nextSHA += "0"
	}

	startSHA, err := gitaccess.NewObjectIDFromSHA(nextSHA)
	if err != nil {
		return FinalSHA, FinalSHA, err
	}

	shaRangeStart := binary.BigEndian.Uint64(startSHA.Bytes()[0:8])
	shaRangeEnd := uint64(math.MaxUint64)

	stepSize := float64(desiredResults) / float64(totalResults)
	if stepSize < 1 {
		shaStepSize := uint64(float64(math.MaxUint64) * stepSize)

		// Prevent overflow, in case shaRangeStart + shaStepSize > MaxUint64
		if shaRangeStart < math.MaxUint64-shaStepSize {
			shaRangeEnd = shaRangeStart + shaStepSize
		}
	}

	// If there is almost no SHA range left, just jump the end directly to 0xffffffff...
	if (uint64(math.MaxUint64) - shaRangeEnd) < (uint64(math.MaxUint64) / 1000) {
		shaRangeEnd = uint64(math.MaxUint64)
	}

	return fmt.Sprintf("%016x", shaRangeStart), fmt.Sprintf("%016x", shaRangeEnd), nil
}
