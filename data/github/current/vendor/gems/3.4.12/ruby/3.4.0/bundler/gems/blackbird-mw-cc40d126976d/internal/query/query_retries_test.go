package query

import (
	"context"
	"errors"
	"math/rand"
	"sync"
	"testing"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

const exceededMaxUserQueryRetries = 3

// Tests when we get enough documents in the final try, we should return
// the results we got as part of the final call.
func TestRetries_RetrievalLimit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 3, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	mutex := &sync.Mutex{}
	bbDocs := []*searchpb.GitDocumentMatch{}

	// NB: Since this test uses a stub, we pin to a single public repoid so that
	// repo cache lookup can succeed.
	spec := generator.RepoSpec{
		RepoID:          34,
		OwnerID:         56,
		Public:          true,
		NumLocsPerDoc:   3,
		DocsToReturn:    10,
		DocsWithContent: 10,
	}

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			// initial calls and subsequent retry returns less than 50 results (3 shards * 10), we expect this to be retried
			if fake.SearchCallCount() < exceededMaxUserQueryRetries {
				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
				bbResp.Stats.HitRetrievalLimit = true
			} else {
				// a second retry returns enough results, mark the flag false
				spec2 := generator.RepoSpec{
					RepoID:          34,
					OwnerID:         56,
					Public:          true,
					NumLocsPerDoc:   3,
					DocsToReturn:    int(sr.DocsToReturn),
					DocsWithContent: int(sr.DocsToReturn),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec2)
				bbResp.Stats.HitRetrievalLimit = false
				// only add the documents to verify after we're done with all the retries otherwise we'll end up
				// accumulating docs for all the calls.
				mutex.Lock()
				bbDocs = append(bbDocs, bbResp.Documents...)
				mutex.Unlock()
			}
			return bbResp, nil
		}
	}

	service := newTestService(t, corpus, searchClusters, reposForSpec(spec)...)
	response, err := service.Query(context.Background(), request)

	require.EqualValues(t, 2, response.Metadata.Retries)
	successCheck(t, shards, 50, response, response.Metadata.Shards, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

// Tests when we hit scoring limit
func TestRetries_ScoringLimit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 3, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	mutex := &sync.Mutex{}
	bbDocs := []*searchpb.GitDocumentMatch{}

	// NB: Since this test uses a stub, we pin to a single public repoid so that
	// repo cache lookup can succeed.
	spec := generator.RepoSpec{
		RepoID:          34,
		OwnerID:         56,
		Public:          true,
		NumLocsPerDoc:   3,
		DocsToReturn:    10,
		DocsWithContent: 10,
	}

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			// initial calls and subsequent retry returns less than 50 results (3 shards * 10), we expect this to be retried
			if fake.SearchCallCount() < exceededMaxUserQueryRetries {
				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
				bbResp.Stats.HitScoringLimit = true
			} else {
				// a second retry returns enough results, mark the flag false
				spec2 := generator.RepoSpec{
					RepoID:          34,
					OwnerID:         uint32(56),
					Public:          true,
					NumLocsPerDoc:   3,
					DocsToReturn:    int(sr.DocsToReturn),
					DocsWithContent: int(sr.DocsToReturn),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec2)
				bbResp.Stats.HitScoringLimit = false
				// NB: increase score of docs with content ???
				for _, d := range bbResp.Documents {
					if len(d.Content) > 0 {
						d.ScoringInfo.Score += 100
					}
				}

				// only add the documents to verify after we're done with all the retries otherwise we'll end up
				// accumulating docs for all the calls.
				mutex.Lock()
				bbDocs = append(bbDocs, bbResp.Documents...)
				mutex.Unlock()
			}
			return bbResp, nil
		}
	}

	service := newTestService(t, corpus, searchClusters, reposForSpec(spec)...)
	response, err := service.Query(context.Background(), request)
	require.EqualValues(t, 2, response.Metadata.Retries)
	successCheck(t, shards, 50, response, response.Metadata.Shards, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

// Tests when we never get enough documents despite all the retries, in this case,
// we should return what we got after all the attempts.
func TestRetries_RetrievalLimit_NeverSatisfied(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)
	request.Experiments = experiments.Experiments{experiments.NoCrowding: "1"}
	mutex := &sync.RWMutex{}
	bbDocs := []*searchpb.GitDocumentMatch{}

	// NB: Since this test uses a stub, we pin to a single public repoid so that
	// repo cache lookup can succeed.
	spec := generator.RepoSpec{
		RepoID:          34,
		OwnerID:         56,
		Public:          true,
		NumLocsPerDoc:   1 + rand.Intn(3),
		DocsToReturn:    20,
		DocsWithContent: 20,
	}

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			// Every call to each shard returned 20 docs, 2 * 20 = 20 total docs returned vs 50 requested
			// these calls should be retried every time.
			bbResp := generator.BlackbirdResponseFromSpec(t, spec)
			bbResp.Stats.HitRetrievalLimit = true
			// only add the documents to verify after we're done with all the retries otherwise we'll end up
			// accumulating docs for all the calls.
			if fake.SearchCallCount() == exceededMaxUserQueryRetries {
				mutex.Lock()
				bbDocs = append(bbDocs, bbResp.Documents...)
				mutex.Unlock()
			}
			return bbResp, nil
		}
	}

	service := newTestService(t, corpus, searchClusters, &db.Repository{RepoID: spec.RepoID, OwnerID: spec.OwnerID, IsPublic: true})
	response, err := service.Query(context.Background(), request)
	require.EqualValues(t, 2, response.Metadata.Retries)

	// After enough retries we should return what we got back
	incompleteResultsCheck(t, shards, 40, response, response.Metadata.Shards, err)
	verifyDocOrdering(t, response.Documents, bbDocs)
}

// Tests when the query results get filtered out because of accessible repo ids constraints
// in this case a query should be retried by specifying more results to be returned (if we hit return limit)
// in a hope that the retries will satisfy search.
func TestRetries_ReturnLimit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 3, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			if fake.SearchCallCount() < exceededMaxUserQueryRetries {
				// Only return 10 documents while 50 were requested with the correct flag set for retries, this should trigger
				// a retry.
				spec := generator.RepoSpec{
					RepoID:        1,
					OwnerID:       1,
					Public:        false,
					DocsToReturn:  10,
					NumLocsPerDoc: int(sr.LocationsLimit),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
				bbResp.Stats.HitReturnLimit = true
			} else {
				// on the final retry return the documents requested for
				spec := generator.RepoSpec{
					RepoID:          1,
					OwnerID:         1,
					Public:          false,
					DocsToReturn:    int(sr.DocsToReturn),
					DocsWithContent: int(sr.DocsToReturn), // NB: don't exercise fetchMissingContent
					NumLocsPerDoc:   int(sr.LocationsLimit),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
				bbResp.Stats.HitReturnLimit = false
			}
			return bbResp, nil
		}
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, []*db.Repository{{RepoID: 1, OwnerID: 1}, {RepoID: 2, OwnerID: 1}, {RepoID: 3, OwnerID: 1}}...)
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	successCheck(t, shards, 50, response, response.Metadata.Shards, err)

	require.EqualValues(t, 2, response.Metadata.Retries)
}

// Tests when the query results get filtered out because of accessible repo ids constraints
// in this case a query should be retried by specifying more locations to be returned even
// if we did not hit the return limit in a hope that the one with more locations will satisfy
// the query.
func TestRetries_LocationLimit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 3, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 5)

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			if fake.SearchCallCount() < exceededMaxUserQueryRetries {
				spec := generator.RepoSpec{
					RepoID:          2,
					Public:          false,
					DocsToReturn:    30,
					DocsWithContent: 10,
					NumLocsPerDoc:   int(sr.LocationsLimit),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
			} else {
				// In the last retry return the desired no. of locations/docs from the repo user has access to
				spec := generator.RepoSpec{
					RepoID:          1,
					Public:          false,
					DocsToReturn:    int(sr.DocsToReturn),
					DocsWithContent: int(sr.DocsToReturn), // NB: don't exercise fetchMissingContent
					NumLocsPerDoc:   int(sr.LocationsLimit),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
			}
			return bbResp, nil
		}
	}

	// NB: repos must match what the stub is returning
	//
	// TODO: Fix this test, it strangely needs the actor to have access to only repo_id=1 (and for that repo to be private) ???
	service := newTestService(t, corpus, searchClusters, []*db.Repository{{RepoID: 1}, {RepoID: 2, IsPublic: true}, {RepoID: 3, IsPublic: true}}...)
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	successCheck(t, shards, 50, response, response.Metadata.Shards, err)

	require.EqualValues(t, 2, response.Metadata.Retries)
}

// Tests when we don't get enough results on initial query but subsequent retries fails completely
// in this case we should return whatever results we had on the first try instead of returning a
// complete failure.
func TestRetries_FailureOnRetry(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			if fake.SearchCallCount() < 2 {
				spec := generator.RepoSpec{
					RepoID:          1,
					Public:          false,
					DocsToReturn:    5,
					DocsWithContent: 5,
					NumLocsPerDoc:   int(sr.LocationsLimit),
				}

				bbResp = generator.BlackbirdResponseFromSpec(t, spec)
			} else {
				return nil, errors.New("shard down")
			}
			return bbResp, nil
		}
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, &db.Repository{RepoID: 1})
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	successCheck(t, shards, 10, response, response.Metadata.Shards, err)

	require.EqualValues(t, 0, response.Metadata.Retries)
}

// Tests when we don't get enough results and we don't hit any limits either
func TestRetries_LimitsNotHit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			spec := generator.RepoSpec{
				RepoID:          1,
				Public:          false,
				DocsToReturn:    5,
				DocsWithContent: 5,
				NumLocsPerDoc:   int(sr.LocationsLimit),
			}

			bbResp = generator.BlackbirdResponseFromSpec(t, spec)
			return bbResp, nil
		}
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, &db.Repository{RepoID: 1})
	response, err := service.Query(context.Background(), request)
	successCheck(t, shards, 10, response, response.Metadata.Shards, err)

	require.EqualValues(t, 0, response.Metadata.Retries)
}

// Tests retries in the case where we don't get enough documents AND locations
// on at least one document are saturated.
func TestRetries_LocationSaturation(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 5, 5)

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			if fake.SearchCallCount() == 1 {
				require.EqualValues(t, 5, sr.LocationsLimit)
			} else if fake.SearchCallCount() == 2 {
				require.EqualValues(t, 100, sr.LocationsLimit)
			}
			var bbResp *searchpb.SearchResponse
			spec := generator.RepoSpec{
				RepoID:          1,
				DocsToReturn:    1,
				DocsWithContent: 1,
				NumLocsPerDoc:   int(sr.LocationsLimit),
			}

			bbResp = generator.BlackbirdResponseFromSpec(t, spec)
			return bbResp, nil
		}
	}

	service := newTestService(t, corpus, searchClusters, &db.Repository{RepoID: 1})
	response, err := service.Query(context.Background(), request)
	successCheck(t, shards, 2, response, response.Metadata.Shards, err) // NB: 2 docs expected - one from each try

	require.EqualValues(t, 1, response.Metadata.Retries)
}

// Tests when we got enough results but we also hit some limits after enough retries, we shouldn't show
// warning to the user in that case
func TestRetries_EnoughResults_LimitsHit(t *testing.T) {
	corpus := helpers.Corpus(t)
	searchClusters := helpers.SearchClustersWithServingCorpus(t, corpus)
	routes := searchClusters.GetServingRoutes(context.Background(), corpus)
	shards := routes.ServingHosts
	request := generator.QueryServiceRequest(t, "test", 50, 1)

	for _, shard := range shards {
		fake := helpers.FakeShardClient(t, shard[0])
		fake.SearchStub = func(c context.Context, sr *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			var bbResp *searchpb.SearchResponse
			spec := generator.RepoSpec{
				RepoID:          1,
				Public:          false,
				DocsToReturn:    25,
				DocsWithContent: 25,
				NumLocsPerDoc:   int(sr.LocationsLimit),
			}

			bbResp = generator.BlackbirdResponseFromSpec(t, spec)
			bbResp.Stats.HitRetrievalLimit = true
			return bbResp, nil
		}
	}

	// NB: repos must match what the stub is returning
	service := newTestService(t, corpus, searchClusters, &db.Repository{RepoID: 1})
	response, err := service.Query(context.Background(), request)
	require.NoError(t, err)
	successCheck(t, shards, 50, response, response.Metadata.Shards, err)

	require.EqualValues(t, 0, response.Metadata.Retries)
}
