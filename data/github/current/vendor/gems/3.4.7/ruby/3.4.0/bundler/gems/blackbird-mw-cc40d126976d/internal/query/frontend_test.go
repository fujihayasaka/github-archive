package query

import (
	"context"
	"errors"
	"fmt"
	"math/rand"
	"testing"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/treelights/proto"
)

func TestFrontendQueryClusterFeaturesExperiments(t *testing.T) {
	tests := []struct {
		name        string
		experiments map[string]string
		expected    epoch.EpochFeatures
	}{
		{
			name:        "no experiments",
			experiments: map[string]string{},
			expected:    epoch.EpochFeaturesLexical,
		},
		{
			name:        "prompt_qualifier=1",
			experiments: map[string]string{experiments.PromptQualifier: experiments.Enabled},
			expected:    epoch.EpochFeaturesEmbeddings,
		},
		{
			name:        "prompt_qualifier=bm25",
			experiments: map[string]string{experiments.PromptQualifier: experiments.PromptQualifierBM25},
			expected:    epoch.EpochFeaturesBM25,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ctx := experiments.WithExperiments(context.Background(), test.experiments)
			cap := clusterFeaturesForExperiments(ctx)
			require.Equal(t, test.expected, cap, fmt.Sprintf("expected %v, but got %v", test.expected, cap))
		})
	}
}

func TestFrontendQuery(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := shardsReturn(t, shards, 3)

	service := newTestService(t, corpus, searchClusters, reposForDocs(bbDocs)...)
	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 5, len(response.Results))
	require.Equal(t, uint32(0), response.Page)
	require.Equal(t, uint32(2), response.PageCount)
	require.Equal(t, uint32(6), response.ResultCount)

	// Now try to access page 2, should get just one result
	request = &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		PageNumber:     1,
		ResultsPerPage: 5,
	}

	response, err = service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, uint32(1), response.Page)
	require.Equal(t, uint32(2), response.PageCount)
	require.Equal(t, uint32(6), response.ResultCount)
	require.Equal(t, 1, len(response.Results))
	require.NotNil(t, response.Metadata)
}

func TestFrontendQuerySyntaxHighlightingOnOff(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
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
	fakeTreelights := treelights.NewFakeClient(&proto.HighlightResponse{
		Docs: []*proto.Highlighted{{
			Id: 0,
			Lines: []string{
				"first line",
				"\u001e\u001fsecond\u001f\u001e line",
				"third line",
				"fourth line",
				"fifth line",
				"sixth line",
			},
		}},
	}, nil)
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, 1, len(response.Results[0].Snippets))
	require.Equal(t, 4, len(response.Results[0].Snippets[0].Lines))
	require.Equal(t, "<mark>second</mark> line", response.Results[0].Snippets[0].Lines[0])
	require.Equal(t, "fifth line", response.Results[0].Snippets[0].Lines[3])
	require.Equal(t, pb.SnippetFormat_SNIPPET_FORMAT_HTML, response.Results[0].Snippets[0].Format)
	require.Equal(t, float32(-1.0), response.Results[0].Snippets[0].Score)

	// Snippet is lines 2-6, center = 4
	require.Equal(t, uint32(4), response.Results[0].LineNumber)

	// Try with plaintext format requested, shouldn't use highlighting
	request.SnippetOptions = &pb.SnippetOptions{
		Format: pb.SnippetFormat_SNIPPET_FORMAT_PLAIN_TEXT,
	}
	response, err = service.FrontendQuery(context.Background(), request)
	require.Equal(t, pb.SnippetFormat_SNIPPET_FORMAT_PLAIN_TEXT, response.Results[0].Snippets[0].Format)
	require.NoError(t, err)
}

func TestFrontendQuerySyntaxInvalidSnippet(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shard := routes.ServingHosts[0]
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	bbResp := generator.BlackbirdResponse(t, 0, 1, 1)
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
		},
	}
	bbDocs = append(bbDocs, bbResp.Documents[0])
	c := helpers.FakeShardClient(t, shard[0])
	c.SearchReturns(bbResp, nil)
	c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 1, len(response.Results))
	require.Equal(t, 1, len(response.Results[0].Snippets))
	require.Equal(t, 4, len(response.Results[0].Snippets[0].Lines))
	require.Equal(t, "second", response.Results[0].Snippets[0].Lines[0])
	require.Equal(t, "&lt;script&gt;", response.Results[0].Snippets[0].Lines[3])
	require.Equal(t, pb.SnippetFormat_SNIPPET_FORMAT_HTML, response.Results[0].Snippets[0].Format)
}

func TestFrontendQuerySyntaxHighlightingFailed(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	// Snippet does not intersect document, making it invalid
	bbResp := generator.BlackbirdResponse(t, 0, 2, 2)
	bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
		{
			StartingLineNumber: 10,
			EndingLineNumber:   15,
			Start:              100,
			End:                150,
		},
	}
	bbResp.Documents[0].Content = []byte(`first
second
third
fourth
fifth
sixth
seventh
`)
	bbDocs = append(bbDocs, bbResp.Documents[0])

	// Starting line is after ending line, invalid snippet
	bbResp.Documents[1].ScoringInfo.Snippets = []*searchpb.Snippet{
		{
			StartingLineNumber: 3,
			EndingLineNumber:   1,
		},
	}
	bbResp.Documents[1].Content = []byte(`first
second
third
fourth
fifth
sixth
seventh
`)
	bbDocs = append(bbDocs, bbResp.Documents[0])
	c := helpers.FakeShardClient(t, shards[0][0])
	c.SearchReturns(bbResp, nil)
	c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))

	// These were invalid snippet line ranges, so they are dropped
	require.Equal(t, 0, len(response.Results[0].Snippets))
	require.Equal(t, 0, len(response.Results[1].Snippets))
	require.EqualValues(t, 12, response.Results[0].LineNumber)
	require.EqualValues(t, 0, response.Results[1].LineNumber)
}

func TestHighDensitySnippets(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	// Snippet does not intersect document, making it invalid
	bbResp := generator.BlackbirdResponse(t, 0, 2, 2)
	bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
		{
			StartingLineNumber: 6,
			EndingLineNumber:   7,
			Start:              32,
			End:                36,
		},
	}
	bbResp.Documents[0].Content = []byte(`first
second
third
fourth
fifth
sixth
seventh
`)
	bbDocs = append(bbDocs, bbResp.Documents[0])
	bbDocs = append(bbDocs, bbResp.Documents[0])
	c := helpers.FakeShardClient(t, shards[0][0])
	c.SearchReturns(bbResp, nil)
	c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(&proto.HighlightResponse{
		Docs: []*proto.Highlighted{{
			Id: 0,
			Lines: []string{
				"first line",
				"\u001e\u001fsecond\u001f\u001e line",
				"third line",
				"fourth line",
				"fifth line",
				"sixth line",
			},
		}},
	}, nil)
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))

	// The byte ranges indicate that the snippets are truncated, so show ellipsis
	require.Equal(t, "sixt…", response.Results[0].Snippets[0].Lines[0])
	require.EqualValues(t, 6, response.Results[0].LineNumber)
}

func TestFrontendHighlightMatchesPlaintext(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 1, 1)
		bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
			{
				StartingLineNumber: 2,
				EndingLineNumber:   6,
				Start:              6,
				End:                34,
			},
			{
				StartingLineNumber: 5,
				EndingLineNumber:   7,
				Start:              41,
				End:                54,
			},
		}
		bbResp.Documents[0].TermMatches = []*searchpb.Range{
			{
				Start: 0,
				End:   10,
			},
			{
				Start: 30,
				End:   34,
			},
			{
				Start: 31,
				End:   34,
			},
			{
				Start: 40,
				End:   55,
			},
		}

		bbResp.Documents[0].Content = []byte(`first
second
third
fourth
<script>
sixth
seventh
eight
`)
		bbDocs = append(bbDocs, bbResp.Documents[0])
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, 2, len(response.Results[0].Snippets))
	require.Equal(t, 4, len(response.Results[0].Snippets[0].Lines))

	// Mark starts before the snippet starts. Should proceed part way through the match.
	require.Equal(t, "<mark>seco</mark>nd", response.Results[0].Snippets[0].Lines[0])
	require.Equal(t, uint32(3), response.Results[0].Snippets[0].MatchCount)
	require.Equal(t, "&lt;scr<mark>ipt&gt;</mark>", response.Results[0].Snippets[0].Lines[3])
	require.Equal(t, pb.SnippetFormat_SNIPPET_FORMAT_HTML, response.Results[0].Snippets[0].Format)

	// Though there are four matches, two overlap, so only three unique matches exist
	require.Equal(t, uint32(3), response.Results[0].MatchCount)

	// Special case, a single match spans several snippet lines. It should be <mark>'ed on each
	// individual line, even though it's just one match
	require.Equal(t, 2, len(response.Results[0].Snippets[1].Lines))
	require.Equal(t, uint32(1), response.Results[0].Snippets[1].MatchCount)
	require.Equal(t, "<mark>seventh</mark>", response.Results[0].Snippets[1].Lines[0])
	require.Equal(t, "<mark>eight</mark>", response.Results[0].Snippets[1].Lines[1])
	require.Equal(t, pb.SnippetFormat_SNIPPET_FORMAT_HTML, response.Results[0].Snippets[0].Format)
}

func TestFrontendHighlightMatchesBug(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 1, 1)
		bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
			{
				StartingLineNumber: 1,
				EndingLineNumber:   6,
				Start:              0,
				End:                102,
			},
		}
		bbResp.Documents[0].TermMatches = []*searchpb.Range{
			{Start: 15, End: 54},
			{Start: 58, End: 97},
		}

		bbResp.Documents[0].Content = []byte(`<?php

define('SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL', 'sample_service_abcd_fox_event_type_kill');


`)
		bbDocs = append(bbDocs, bbResp.Documents[0])
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(&proto.HighlightResponse{
		Docs: []*proto.Highlighted{{
			Id: 0,
			Lines: []string{
				"<span class=pl-ent>&lt;?php</span> <span class=pl-en>define</span>(<span class=pl-s>&#39;<span class=pl-s><mark>SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL</mark></span>&#39;</span>, <span class=pl-s>&#39;<span class=pl-s><mark>sample_service_abcd_fox_event_type_kill</mark></span>&#39;</span>);",
				// TODO: Implement and test trimming trailing newlines
				// "",
				// "",
			},
		}},
	}, nil)
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, 1, len(response.Results[0].Snippets))
	require.Equal(t, 1, len(response.Results[0].Snippets[0].Lines))

	require.Len(t, response.Results[0].Snippets[0].Lines, 1)
	require.Equal(t,
		"<span class=pl-ent>&lt;?php</span> <span class=pl-en>define</span>(<span class=pl-s>&#39;<span class=pl-s><mark>SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL</mark></span>&#39;</span>, <span class=pl-s>&#39;<span class=pl-s><mark>sample_service_abcd_fox_event_type_kill</mark></span>&#39;</span>);",
		response.Results[0].Snippets[0].Lines[0])
	require.EqualValues(t, response.Results[0].Snippets[0].StartingLineNumber, 1)
	require.EqualValues(t, response.Results[0].Snippets[0].EndingLineNumber, 6)
}

func TestFrontendHighlightMatchesBug80(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "test",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 1, 1)
		bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
			{
				StartingLineNumber: 3,
				EndingLineNumber:   4,
				Start:              7,
				End:                86,
			},
		}
		bbResp.Documents[0].TermMatches = []*searchpb.Range{
			{Start: 15, End: 54},
			{Start: 58, End: 97},
		}

		bbResp.Documents[0].Content = []byte(`<?php

define('SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL', 'sample_service_abcd_fox_event_type_kill');


`)
		bbDocs = append(bbDocs, bbResp.Documents[0])
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(&proto.HighlightResponse{
		Docs: []*proto.Highlighted{{
			Id: 0,
			Lines: []string{
				"<span class=pl-ent>&lt;?php</span> <span class=pl-en>define</span>(<span class=pl-s>&#39;<span class=pl-s><mark>SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL</mark></span>&#39;</span>, <span class=pl-s>&#39;<span class=pl-s><mark>sample_service_abcd_fox_event_type_kill</mark></span>&#39;</span>);",
			},
		}},
	}, nil)
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, 1, len(response.Results[0].Snippets))
	require.Equal(t, 1, len(response.Results[0].Snippets[0].Lines))

	// NB: We throw away highlighting info b/c we need to ellide the snippet to fit in the 80 char display width.
	// This means we return basically plain text.
	require.Len(t, response.Results[0].Snippets[0].Lines, 1)
	require.Equal(t,
		"define(&#39;<mark>SAMPLE_SERVICE_ABCD_FOX_EVENT_TYPE_KILL</mark>&#39;, &#39;<mark>sample_service_abcd_fox_even</mark>…",
		response.Results[0].Snippets[0].Lines[0])
	require.EqualValues(t, response.Results[0].Snippets[0].StartingLineNumber, 3)
	require.EqualValues(t, response.Results[0].Snippets[0].EndingLineNumber, 4)
}

func TestFrontendHighlightingComplex(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.FrontendQueryRequest{
		Query:                 "SQUARE ENIX",
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}
	bbDocs := []*searchpb.GitDocumentMatch{}
	for shardID, shard := range shards {
		bbResp := generator.BlackbirdResponse(t, shardID, 1, 1)
		bbResp.Documents[0].ScoringInfo.Snippets = []*searchpb.Snippet{
			{
				StartingLineNumber: 1,
				EndingLineNumber:   6,
				Start:              1,
				End:                250,
			},
		}
		bbResp.Documents[0].TermMatches = []*searchpb.Range{
			{
				Start: 193,
				End:   199,
			},
			{
				Start: 200,
				End:   204,
			},
		}

		bbResp.Documents[0].Content = []byte(`
<font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Price:</B>
$19.99</font><br>
<font size="3" FACE="Helvetica,Arial,Geneva,Swiss,SunSans-Regular"><B>Copyright</B>
℗ 2015 SQUARE ENIX</font></td>
</tr>
</table></TD></TR>
</TABLE>`)
		bbDocs = append(bbDocs, bbResp.Documents[0])
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(bbResp, nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	store := fakeStoreWithReposForCorpus(t, corpus, reposForDocs(bbDocs)...)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 2, len(response.Results))
	require.Equal(t, 1, len(response.Results[0].Snippets))
	require.Equal(t, uint32(250), response.Results[0].FileSize)
	require.Equal(t, []string{
		"&lt;font size=&#34;3&#34; FACE=&#34;Helvetica,Arial,Geneva,Swiss,SunSans-Regular&#34;&gt;&lt;B&gt;Price:&lt;/B&gt;",
		"$19.99&lt;/font&gt;&lt;br&gt;",
		"&lt;font size=&#34;3&#34; FACE=&#34;Helvetica,Arial,Geneva,Swiss,SunSans-Regular&#34;&gt;&lt;B&gt;Copyright&lt;/B&gt;",
		"℗ 2015 <mark>SQUARE</mark> <mark>ENIX</mark>&lt;/font&gt;&lt;/td&gt;",
		"&lt;/tr&gt;",
		"&lt;/table&gt;&lt;/TD&gt;&lt;/TR&gt;",
		"&lt;/TABLE&gt;",
	}, response.Results[0].Snippets[0].Lines)
}

func TestResultCount(t *testing.T) {
	corpus := helpers.Corpus(t)
	shardCount := 32
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, shardCount, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := &pb.CountRequest{
		Query: "Test",
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}

	s1 := rand.NewSource(4)
	r1 := rand.New(s1)
	shardResponses := []*searchpb.SearchResponse{}
	for i := 0; i < shardCount; i++ {
		shardResponses = append(shardResponses, &searchpb.SearchResponse{
			Documents:     []*searchpb.GitDocumentMatch{},
			Stats:         &searchpb.QueryStats{},
			ServingStatus: generator.Status(t),
		})
	}

	for i := 0; i < 1024; i++ {
		data := make([]byte, 20)
		r1.Read(data)

		shard := r1.Intn(shardCount)

		if shardResponses[shard].Documents == nil {
			shardResponses[shard].Documents = []*searchpb.GitDocumentMatch{}
		}
		shardResponses[shard].Documents = append(shardResponses[shard].Documents, &searchpb.GitDocumentMatch{
			DocSha:  data,
			BlobSha: helpers.RandomOID(t).Bytes(),
			Locations: []*searchpb.Location{{
				Path:         "/path/to/file/test.txt",
				RepoId:       uint32(123),
				Nwo:          "a/b",
				CommitSha:    data,
				OwnerId:      321,
				IsRepoPublic: true,
			}},
			TermMatches:       nil,
			Content:           nil,
			LanguageId:        0,
			TotalLocations:    0,
			ScoringInfo:       nil,
			RetrievalPosition: 0,
			MinDocsToRetrieve: 0,
			TermEmbeddings:    nil,
		})
	}

	for i, shard := range shards {
		c := helpers.FakeShardClient(t, shard[0])
		c.SearchReturns(shardResponses[i], nil)
		c.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{}, nil)
	}

	store := fakeStoreWithReposForCorpus(
		t,
		corpus,
		&db.Repository{
			Name:       "repo",
			OwnerLogin: "owner",
			RepoID:     123,
			OwnerID:    321,
			IsPublic:   true,
		},
	)
	fakeTreelights := treelights.NewFakeClient(nil, errors.New("bad luck"))
	service := NewService(
		routing.Dotcom,
		helpers.IndexerClusters(t),
		searchClusters,
		store,
		cache.NewInMemory(),
		newTestAuthClient(t, generator.TestActorID, []uint64{1}),
		quota.NewMemoryRateEstimator(),
		fakeTreelights,
		fakeGitClient(),
		helpers.CopilotClient(t),
	)

	response, err := service.Count(context.Background(), request)
	require.NoError(t, err)
	require.Equal(t, 0, len(response.QueryErrors))
	require.Equal(t, 1008, int(response.Count))
}

func Test_FrontendQuery_Shortcircuit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	request := &pb.FrontendQueryRequest{
		Query:                 "", // NOTE: this parses to nothing -> not sent to shards
		DocumentLimit:         100,
		DocumentLocationLimit: 100,
		QueryParser:           pb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		Actor: &pb.Actor{
			ActorId:     1,
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		ResultsPerPage: 5,
	}

	service := newTestService(t, corpus, searchClusters)
	response, err := service.FrontendQuery(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response.Metadata)
	require.Len(t, response.QueryErrors, 1)
	require.Equal(t, &queryErrorIsNothing, response.QueryErrors[0])
	require.Empty(t, response.Results)
}
