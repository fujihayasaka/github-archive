package query

import (
	"context"
	"fmt"
	"testing"
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/noop"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
)

const (
	actorID = 1
	orgID   = 2
)

var (
	privateRepo = &db.Repository{RepoID: 1, OwnerID: orgID, OwnerLogin: "github", Name: "test-repo", IsPublic: false}
	publicRepo  = &db.Repository{RepoID: 2, OwnerID: orgID, OwnerLogin: "github", Name: "test-repo-public", IsPublic: true}
)

// scope (repo or global)
// repo visibility (public or private)
//
// TODO: Add tests for IP address being different from what's in cache (requires changes to fake cache implementation)
func Test_AccessControlMatrix(t *testing.T) {
	fixtures := []struct {
		fixtureName     string
		query           string
		accessibleRepos []*db.Repository // actor's accessible_repo (private repos only in this list)
		bbResults       []*db.Repository // bb shard will return search results for these repos
		returnRepos     []types.RepoID   // filtered repo_ids of docs after access control
	}{
		// Global scoped queries
		{
			fixtureName:     "scope:global search public repo",
			query:           "global",
			accessibleRepos: []*db.Repository{privateRepo},
			bbResults:       []*db.Repository{publicRepo},
			returnRepos:     []types.RepoID{publicRepo.RepoID},
		},
		{
			fixtureName:     "scope:global search accessible private repo",
			query:           "global",
			accessibleRepos: []*db.Repository{privateRepo},
			bbResults:       []*db.Repository{privateRepo},
			returnRepos:     []types.RepoID{privateRepo.RepoID},
		},
		{
			fixtureName:     "scope:global search inaccessible private repo",
			query:           "global",
			accessibleRepos: []*db.Repository{},
			bbResults:       []*db.Repository{privateRepo},
			returnRepos:     []types.RepoID{},
		},

		// TODO: create large enough delta in repo vs. org list to exercise all query re-writing code

		// Repo scoped queries
		{
			fixtureName:     "scope:repo search public repo",
			query:           "hi repo:github/test-repo-public",
			accessibleRepos: []*db.Repository{privateRepo},
			bbResults:       []*db.Repository{publicRepo},
			returnRepos:     []types.RepoID{publicRepo.RepoID},
		},
		{
			fixtureName:     "scope:repo search accessible private repo",
			query:           "hi repo:github/test-repo",
			accessibleRepos: []*db.Repository{privateRepo},
			bbResults:       []*db.Repository{privateRepo},
			returnRepos:     []types.RepoID{privateRepo.RepoID},
		},
		{
			fixtureName:     "scope:repo search inaccessible private repo",
			query:           "hi repo:github/test-repo",
			accessibleRepos: []*db.Repository{},
			bbResults:       []*db.Repository{privateRepo},
			returnRepos:     []types.RepoID{},
		},
	}

	now := time.Now()
	stale := now.Add(-1 * time.Hour)
	for _, servingTs := range []int64{stale.UnixMilli(), now.UnixMilli()} {

		for _, fixture := range fixtures {
			fixture := fixture
			t.Run(fixture.fixtureName, func(t *testing.T) {
				ctx := context.Background()
				corpus := helpers.Corpus(t)
				searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)
				routes := searchClusters.GetServingRoutes(ctx, corpus)
				repoIDs := []uint64{}
				for _, r := range fixture.accessibleRepos {
					repoIDs = append(repoIDs, uint64(r.RepoID))
				}
				authClient := auth.NewClient(cache.NewInMemory(), auth.NewMockzd(actorID, repoIDs), noop.New())
				repos := []*db.Repository{publicRepo, privateRepo}
				store := noop.New(repos...)
				service := NewService(
					routing.Dotcom,
					helpers.IndexerClusters(t),
					searchClusters,
					store,
					cache.NewInMemory(),
					authClient,
					quota.NewMemoryRateEstimator(),
					treelights.NewNoopClient(),
					fakeGitClient(),
					helpers.CopilotClient(t),
				)

				status := &servingpb.ServingStatus{IndexVersion: 1, Shards: []*servingpb.Shard{{ServingTs: servingTs}}}

				for _, shard := range routes.ServingHosts {
					commitOID := helpers.RandomOID(t).Bytes()
					locs := []*searchpb.Location{}
					for _, r := range fixture.bbResults {
						locs = append(locs, &searchpb.Location{RepoId: uint32(r.RepoID), Nwo: r.NWO(), CommitSha: commitOID, IsRepoPublic: r.IsPublic, OwnerId: r.OwnerID})
					}

					docs := []*searchpb.GitDocumentMatch{{Locations: locs, BlobSha: helpers.RandomOID(t).Bytes(), ScoringInfo: generator.ScoringInfo(t), Content: []byte("content")}}
					fake := helpers.FakeShardClientWithRepos(t, shard[0], repos...)
					fake.SearchReturns(&searchpb.SearchResponse{Documents: docs, Stats: generator.Stats(t, docs), ServingStatus: status}, nil)
				}

				response, err := service.Query(context.Background(),
					&pb.QueryRequest{
						Query: fixture.query,
						Actor: &pb.Actor{
							ActorId:     actorID,
							RequestIp:   "127.0.0.1",
							AccessToken: "asdf",
						},
					})
				require.Nil(t, err, "query failed")

				responseRepoIDs := []types.RepoID{}
				for _, d := range response.Documents {
					responseRepoIDs = append(responseRepoIDs, types.RepoID(d.Locations[0].RepoId))
				}
				require.ElementsMatch(t, fixture.returnRepos, responseRepoIDs,
					fmt.Sprintf("%s returned unexpected repositories in results", fixture.fixtureName))
			})
		}
	}
}
