package query

import (
	"context"
	"fmt"
	"strings"
	"testing"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/experiments"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_PaginationRankedQueryOnly(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersExt(t, 1, 1, 1, 0, 0, 0, corpus, false /*no blob filtering*/)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts

	request := &pb.QueryRequest{
		Query:                 "test in:path",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     0,
		ResultsPerPage: 10,
		Experiments:    experiments.Experiments{experiments.UseGeyserQueryLanguage: experiments.Enabled},
	}
	bbDocs := generator.BlackbirdResponse(t, 0, 3, 3).Documents

	c := helpers.FakeShardClient(t, shards[0][0])
	c.SearchStub = func(ctx context.Context, req *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		// Don't expect a count query to be executed
		require.Equal(t, false, detectCountQuery(req.QueryAst))

		return &searchpb.SearchResponse{
			Documents:     bbDocs,
			Stats:         generator.Stats(t, bbDocs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Empty(t, response.QueryErrors)
	require.Equal(t, locCountBB(bbDocs), len(response.Documents))
}

func Test_PaginationDeep(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersExt(t, 1, 1, 1, 0, 0, 0, corpus, false /*no blob filtering*/)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts

	bbDocs := generator.BlackbirdResponseFromSpec(t, generator.RepoSpec{
		RepoID:          1,
		OwnerID:         1,
		NumLocsPerDoc:   1,
		DocsToReturn:    650,
		DocsWithContent: 650,
		ShardID:         0,
	}).Documents
	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)

	position := 0
	client := helpers.FakeShardClient(t, shards[0][0])
	client.SearchStub = func(ctx context.Context, req *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		// Detect count queries via trailing zeros trait
		if detectCountQuery(req.QueryAst) {
			return &searchpb.SearchResponse{
				Documents:     bbDocs,
				Stats:         generator.Stats(t, bbDocs),
				ServingStatus: generator.Status(t),
			}, nil
		}

		if req.DocsToReturn == 0 {
			// Fetch missing content request
			return &searchpb.SearchResponse{
				Documents:     bbDocs[0:100],
				Stats:         generator.Stats(t, bbDocs),
				ServingStatus: generator.Status(t),
			}, nil
		}

		end := position + 100
		if position == 0 {
			end = int(req.DocsToReturn)
		}
		if end > len(bbDocs) {
			end = len(bbDocs)
		}
		docs := bbDocs[position:end]
		position = end

		return &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, bbDocs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	request := &pb.QueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     6,
		ResultsPerPage: 100,
	}
	response, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)

	// The seventh page still has 50 results
	require.Equal(t, 50, locCount(response.Documents))

	// Assert the sha ranges
	shaRanges := []string{}
	for i := 0; i < client.SearchCallCount(); i++ {
		_, req := client.SearchArgsForCall(i)
		shaRange := requestedShaRange(t, req.QueryAst)
		if shaRange != "" {
			shaRanges = append(shaRanges, shaRange)
		}
	}

	// The count estimate is 768, and our page size is 100, so each
	// page must cover about 13% of the SHA range, or a step of
	// about 0x19 for each page.
	expectedShaRanges := []string{
		"0000000000000000..1900000000000000",
		"1900000000000000..3200000000000000",
		"3200000000000000..4b00000000000000",
		"4b00000000000000..6400000000000000",
		"6400000000000000..7d00000000000000",
		"7d00000000000000..9600000000000000",
		"9600000000000000..af00000000000000",
		"af00000000000000..c800000000000000",
		"c800000000000000..e100000000000000",
		"e100000000000000..fa00000000000000",
		"fa00000000000000..ffffffffffffffff",
	}

	require.Equal(t, expectedShaRanges, shaRanges, "unexpected SHA ranges for pagination. Anything that changes the document SHA generation may require changes to this test")

	request.PageNumber = 0
	response, err = service.Query(ctx, request)
	require.NoError(t, err)

	// The first page is already in cache, should just hit the "fetch missing content" condition
	require.Equal(t, 100, locCount(response.Documents))
}

func Test_PaginationFlattenedLocations(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersExt(t, 1, 1, 1, 0, 0, 0, corpus, false /*no blob filtering*/)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts

	request := &pb.QueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     2,
		ResultsPerPage: 100,
	}
	bbDocs := generator.BlackbirdResponse(t, 0, 125, 125).Documents
	for i, doc := range bbDocs {
		// Set two locations per doc. With 125 docs, this means 250 results
		doc.Locations = doc.Locations[0:1]
		doc.Locations = append(doc.Locations, &searchpb.Location{
			Path:         fmt.Sprintf("%s-2", doc.Locations[0].Path),
			RepoId:       doc.Locations[0].RepoId,
			Nwo:          doc.Locations[0].Nwo,
			OwnerId:      doc.Locations[0].OwnerId,
			CommitSha:    doc.Locations[0].CommitSha,
			RefName:      doc.Locations[0].RefName,
			RepoScore:    doc.Locations[0].RepoScore,
			IsRepoPublic: doc.Locations[0].IsRepoPublic,
		})
		doc.ScoringInfo.Score = float32(-i)
	}

	position := 0

	c := helpers.FakeShardClient(t, shards[0][0])
	c.SearchStub = func(ctx context.Context, req *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		// Detect count queries via trailing zeros trait
		if detectCountQuery(req.QueryAst) {
			return &searchpb.SearchResponse{
				Documents:     bbDocs,
				Stats:         generator.Stats(t, bbDocs),
				ServingStatus: generator.Status(t),
			}, nil
		}

		if req.DocsToReturn == 0 {
			// Fetch missing content request
			return &searchpb.SearchResponse{
				Documents:     bbDocs[0:100],
				Stats:         generator.Stats(t, bbDocs),
				ServingStatus: generator.Status(t),
			}, nil
		}

		end := position + int(req.DocsToReturn)
		if end > len(bbDocs) {
			end = len(bbDocs)
		}
		docs := bbDocs[position:end]
		position = end

		return &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, bbDocs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.Query(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)

	// The third page is the last one, and just has 50 results
	require.Equal(t, 50, locCount(response.Documents))

	request.PageNumber = 0
	response, err = service.Query(ctx, request)
	require.NoError(t, err)

	// The first page is already in cache, should just hit the "fetch missing content" condition
	require.Equal(t, 100, locCount(response.Documents))
}

func locCount(docs []*pb.GitDocumentMatch) int {
	count := 0
	for _, doc := range docs {
		count += len(doc.Locations)
	}
	return count
}

func locCountBB(docs []*searchpb.GitDocumentMatch) int {
	count := 0
	for _, doc := range docs {
		count += len(doc.Locations)
	}
	return count
}

func detectCountQuery(query *querypb.Query) bool {
	if query.Kind == querypb.QueryKind_QUERY_KIND_QUALIFIER && query.Domain == querypb.Domain_DOMAIN_TRAIT && strings.HasPrefix(query.ValueString, "trailing_zeros") {
		return true
	}

	for _, sq := range query.Subqueries {
		isCount := detectCountQuery(sq)
		if isCount {
			return true
		}
	}

	return false
}

// requestedShaRange extracts the value of the sha qualifier from query. It
// returns the empty string if there is no SHA qualifier. If the SHA qualifier
// is invalid, it fails the test.
func requestedShaRange(t *testing.T, query *querypb.Query) string {
	if query.Kind == querypb.QueryKind_QUERY_KIND_QUALIFIER && query.Domain == querypb.Domain_DOMAIN_SHA {
		if strings.Contains(query.ValueString, "..") {
			return query.ValueString
		} else {
			require.Fail(t, "invalid SHA qualifier, this shouldn't be possible: %q", query.ValueString)
		}
	}

	for _, sq := range query.Subqueries {
		rng := requestedShaRange(t, sq)
		if rng != "" {
			return rng
		}
	}

	return ""
}
