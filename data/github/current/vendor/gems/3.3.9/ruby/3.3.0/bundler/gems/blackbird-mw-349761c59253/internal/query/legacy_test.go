package query

import (
	"context"
	"errors"
	"testing"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"
)

func Test_LegacyQuery(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts
	request := &pb.LegacyQueryRequest{
		Query:                 "test in:path",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := shardsReturn(t, shards, 3)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.LegacyQuery(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 5, len(response.Results))
	require.EqualValues(t, 0, response.Page)
	require.EqualValues(t, 2, response.PageCount)

	// Now try to access page 2, should get just one result
	request = &pb.LegacyQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     1,
		ResultsPerPage: 5,
	}

	response, err = service.LegacyQuery(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, uint32(1), response.Page)
	require.Equal(t, uint32(2), response.PageCount)
	require.Equal(t, 1, len(response.Results))
	require.NotNil(t, response.Metadata)

	// Now try to access page 500, should get no results
	request = &pb.LegacyQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     500,
		ResultsPerPage: 5,
	}

	response, err = service.LegacyQuery(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 0, len(response.Results))
	require.NotNil(t, response.Metadata)
}

func Test_LegacyQueryWithSnippets(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(ctx, corpus)
	shards := routes.ServingHosts

	bbDocs := []*searchpb.GitDocumentMatch{}
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 1, 1)
		bbResp.Documents[0].Content = []byte(`first
second
third
fourth
<script>
sixth
seventh
`)
		bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
			{
				StartingLineNumber: 2,
				EndingLineNumber:   6,
				Start:              6,
				End:                34,
				Score:              -1.0,
			},
		}

		bbDocs = append(bbDocs, bbResp.Documents[0])
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}
	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)

	// Now request snippets
	request := &pb.LegacyQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     0,
		ResultsPerPage: 5,
		SnippetOptions: &pb.SnippetOptions{
			DesiredWidth: 120,
			Format:       pb.SnippetFormat_SNIPPET_FORMAT_PLAIN_TEXT,
		},
	}

	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []int64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)
	response, err := service.LegacyQuery(ctx, request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, len(response.Results[0].Snippets), 1)
	require.NotNil(t, response.Metadata)
}
