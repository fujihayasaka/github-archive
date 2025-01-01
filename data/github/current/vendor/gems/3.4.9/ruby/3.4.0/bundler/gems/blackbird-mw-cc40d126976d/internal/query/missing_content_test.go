package query

import (
	"context"
	"errors"
	"fmt"
	"testing"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_FetchMissingContent(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)
	// document corpus between the 2 shards
	spec := generator.RepoSpec{
		RepoID:          1,
		OwnerID:         1,
		Public:          false,
		NumLocsPerDoc:   1,
		DocsToReturn:    100,
		DocsWithContent: 100,
	}
	docCorpus := generator.BlackbirdResponseFromSpec(t, spec).Documents

	shard1 := routes.ServingHosts[0]
	shard1Fake := helpers.FakeShardClient(t, shard1[0])
	shard1Fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		// for the first time around send low no. of docs with content initially.
		docs := []*searchpb.GitDocumentMatch{}
		if shard1Fake.SearchCallCount() < 2 {
			// send 25 of the 50 matches
			for i := 0; i < 25; i++ {
				doc := docCorpus[i]
				if i > 19 {
					// send 5 docs without content
					docs = append(docs, gitDocumentMatchWithoutContent(t, doc))
				} else {
					docs = append(docs, doc)
				}

			}
		} else {
			requestedDocs := map[gitaccess.ObjectID]*searchpb.DocId{}
			for _, docid := range sr.ScoreDocids {
				requestedDocs[gitaccess.NewObjectIDFromBytes(docid.DocSha)] = docid
			}
			// All 10 missing shas should have been requested from this shard but we will only return 5
			// out of those, other 5 will be returned from a different shard
			require.Equal(t, 10, len(requestedDocs))
			for i := 20; i < 25; i++ {
				docs = append(docs, docCorpus[i])
			}
		}
		return &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, docs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	shard2 := routes.ServingHosts[1]
	shard2Fake := helpers.FakeShardClient(t, shard2[0])
	shard2Fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		// for the first time around send low no. of docs with content intially.
		docs := []*searchpb.GitDocumentMatch{}
		if shard2Fake.SearchCallCount() < 2 {
			// send the remaining 25 of the 50 matches
			for i := 25; i < 50; i++ {
				doc := docCorpus[i]
				if i > 44 {
					// send 5 docs without content
					docs = append(docs, gitDocumentMatchWithoutContent(t, doc))
				} else {
					docs = append(docs, doc)
				}

			}
		} else {
			requestedDocs := map[gitaccess.ObjectID]*searchpb.DocId{}
			for _, docid := range sr.ScoreDocids {
				requestedDocs[gitaccess.NewObjectIDFromBytes(docid.DocSha)] = docid
			}
			// All 10 missing shas should have been requested from this shard but we will only return 5
			// out of those, other 5 will be returned from a different shard
			require.Equal(t, 10, len(requestedDocs))
			for i := 45; i < 50; i++ {
				docs = append(docs, docCorpus[i])
			}
		}
		return &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, docs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, reposForSpec(spec)...)
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	successCheck(t, shards, 50, response, response.Metadata.Shards, err)

	require.EqualValues(t, 0, response.Metadata.Retries)
}

func Test_CannotFetchMissingContent(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)
	// document corpus between the 2 shards
	spec := generator.RepoSpec{
		RepoID:          1,
		OwnerID:         1,
		Public:          true,
		NumLocsPerDoc:   1,
		DocsToReturn:    100,
		DocsWithContent: 100,
	}
	docCorpus := generator.BlackbirdResponseFromSpec(t, spec).Documents

	shard1 := routes.ServingHosts[0]
	shard1Fake := helpers.FakeShardClient(t, shard1[0])
	// always send the docs with missing content
	shard1Fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		docs := []*searchpb.GitDocumentMatch{}
		if shard1Fake.SearchCallCount() < 2 {
			for i := 0; i < 25; i++ {
				doc := docCorpus[i]
				if i > 19 {
					// send 5 docs without content
					docs = append(docs, gitDocumentMatchWithoutContent(t, doc))
				} else {
					docs = append(docs, doc)
				}
			}
		}

		return &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, docs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	shard2 := routes.ServingHosts[1]
	shard2Fake := helpers.FakeShardClient(t, shard2[0])
	shard2Fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
		docs := []*searchpb.GitDocumentMatch{}
		if shard2Fake.SearchCallCount() < 2 {
			for i := 25; i < 50; i++ {
				doc := docCorpus[i]
				if i > 44 {
					// send 5 docs without content
					docs = append(docs, gitDocumentMatchWithoutContent(t, doc))
				} else {
					docs = append(docs, doc)
				}
			}
		}

		return &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, docs),
			ServingStatus: generator.Status(t),
		}, nil
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, reposForSpec(spec)...)
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	// We should only have 40 docs since content for remaining docs was not returned
	incompleteResultsCheck(t, shards, 40, response, response.Metadata.Shards, err)
	require.Equal(t, response.QueryErrors[0].Message, "Some results may be missing due to a temporary problem loading content, please try your query again.")

	require.EqualValues(t, 0, response.Metadata.Retries)
}

// When the call to fetch missing content fails we should return what we have have drop the documents
// without the content.
func Test_FetchMissingContentFails(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 5, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)

	for i := 0; i < len(shards); i++ {
		spec := generator.RepoSpec{
			RepoID:          1,
			OwnerID:         1,
			Public:          true,
			NumLocsPerDoc:   1,
			DocsToReturn:    10,
			DocsWithContent: 8,
			ShardID:         i,
		}

		docs := generator.BlackbirdResponseFromSpec(t, spec).Documents
		fake := helpers.FakeShardClient(t, shards[i][0])

		// Initial call to search succeeds for all the hosts but all of them return some missing content
		fake.SearchReturnsOnCall(0, &searchpb.SearchResponse{
			Documents:     docs,
			Stats:         generator.Stats(t, docs),
			ServingStatus: generator.Status(t),
		}, nil)

		// Second call to all the shards should be for fetching the missing content
		// First index host should fail to return missing content, otherwise we fill in the content for the docs that have missing content and
		// return it
		if i == 0 {
			fake.SearchReturnsOnCall(1, &searchpb.SearchResponse{
				ServingStatus: generator.Status(t),
			}, errors.New("failed to fetch missing content"))
		} else {
			docsWithContent := []*searchpb.GitDocumentMatch{}
			for j, doc := range docs {
				if len(doc.Content) == 0 {
					doc.Content = []byte(fmt.Sprintf("content-%d-%d", j, i))
					docsWithContent = append(docsWithContent, doc)
				}
			}

			fake.SearchReturnsOnCall(1, &searchpb.SearchResponse{
				Documents:     docsWithContent,
				Stats:         generator.Stats(t, docs),
				ServingStatus: generator.Status(t),
			}, nil)
		}
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, helpers.RepositoriesWithID(t, 1)...)
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	require.NotNil(t, response, "unexpected nil response")

	// We should have 48 docs since one shard failed and content for remaining docs was not returned
	require.Equal(t, 48, len(response.Documents), "unexpected number of docs received")
	require.Equal(t, len(shards), len(response.Metadata.Shards), "unexpected number of shard metas received")

	// Check just the first (failed) shard
	for _, meta := range response.Metadata.Shards {
		require.Empty(t, meta.Error)
	}
}

func gitDocumentMatchWithoutContent(t *testing.T, doc *searchpb.GitDocumentMatch) *searchpb.GitDocumentMatch {
	return &searchpb.GitDocumentMatch{
		TermMatches:       doc.TermMatches,
		Locations:         doc.Locations,
		Content:           nil,
		BlobSha:           doc.BlobSha,
		LanguageId:        doc.LanguageId,
		TotalLocations:    doc.TotalLocations,
		ScoringInfo:       doc.ScoringInfo,
		RetrievalPosition: doc.RetrievalPosition,
		MinDocsToRetrieve: doc.MinDocsToRetrieve,
		TermEmbeddings:    doc.TermEmbeddings,
		DocSha:            doc.DocSha,
	}
}
