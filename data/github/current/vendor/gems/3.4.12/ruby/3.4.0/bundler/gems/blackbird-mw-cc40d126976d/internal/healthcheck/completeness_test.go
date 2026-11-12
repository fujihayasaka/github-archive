package healthcheck

import (
	"context"
	"fmt"
	"testing"

	bbclient "github.com/github/blackbird/crates/client/pkg/blackbird"
	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/blackbird/crates/core/pkg/shard"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/test/generator"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func TestApproximateCompletenessProber(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	repoID := types.RepoID(100)
	headOID := helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23")
	searchClusters := helpers.SearchClusters(t)
	indexerClusters := helpers.IndexerClusters(t)

	documents := map[string]gitaccess.ObjectID{}
	for i := 0; i < 500; i++ {
		documents[fmt.Sprintf("/path_%d.txt", i)] = helpers.RandomOID(t)
	}

	fmt.Printf("prepared %d documents\n", len(documents))

	for _, epochMode := range []epoch.EpochMode{
		epoch.EpochModeLegacyHybrid,
		epoch.EpochModeLexical,
		epoch.EpochModeEmbeddings,
		epoch.EpochModeEmbeddingsGraph,
		epoch.EpochModeHybrid,
	} {
		t.Run(fmt.Sprintf("epoch mode %s", epochMode.String()), func(t *testing.T) {
			docs := []*searchpb.GitDocumentMatch{}
			i := 0
			for path, sha := range documents {
				if i%4 == 0 {
					docs = append(docs, &searchpb.GitDocumentMatch{
						DocSha:  shard.DocSHAForEpochMode(sha.Bytes(), path, epochMode),
						BlobSha: sha.Bytes(),
						Content: []byte("qqqq"),
						Locations: []*searchpb.Location{{
							Path:         path,
							RepoId:       uint32(repoID),
							Nwo:          "a/b",
							CommitSha:    headOID.Bytes(),
							IsRepoPublic: true,
						}},
						ScoringInfo:       &searchpb.ScoringInfo{},
						TermMatches:       nil,
						LanguageId:        0,
						TotalLocations:    0,
						RetrievalPosition: 0,
						MinDocsToRetrieve: 0,
						TermEmbeddings:    nil,
					})
				}
				i++
			}

			// Add some incorrect documents (test aserts > 1 extra doc)
			// NOTE: Only one path so this works with both hybrid and embeddings sharding modes
			docs = append(
				docs,
				&searchpb.GitDocumentMatch{
					DocSha:  shard.DocSHAForEpochMode(helpers.OIDFromContent(t, "extra doc 1").Bytes(), "another_path.txt", epochMode),
					BlobSha: helpers.OIDFromContent(t, "extra doc 1").Bytes(),
					Content: []byte("extra doc 1"),
					Locations: []*searchpb.Location{
						{
							Path:         "another_path.txt",
							RepoId:       uint32(repoID),
							Nwo:          "a/b",
							CommitSha:    headOID.Bytes(),
							IsRepoPublic: true,
						},
					},
					ScoringInfo:       &searchpb.ScoringInfo{},
					TermMatches:       nil,
					LanguageId:        0,
					TotalLocations:    0,
					RetrievalPosition: 0,
					MinDocsToRetrieve: 0,
					TermEmbeddings:    nil,
				},
				&searchpb.GitDocumentMatch{
					DocSha:  shard.DocSHAForEpochMode(helpers.OIDFromContent(t, "extra doc 2").Bytes(), "yet_another_path.txt", epochMode),
					BlobSha: helpers.OIDFromContent(t, "extra doc 2").Bytes(),
					Content: []byte("extra doc 2"),
					Locations: []*searchpb.Location{
						{
							Path:         "yet_another_path.txt",
							RepoId:       uint32(repoID),
							Nwo:          "a/b",
							CommitSha:    headOID.Bytes(),
							IsRepoPublic: true,
						},
					},
					ScoringInfo:       &searchpb.ScoringInfo{},
					TermMatches:       nil,
					LanguageId:        0,
					TotalLocations:    0,
					RetrievalPosition: 0,
					MinDocsToRetrieve: 0,
					TermEmbeddings:    nil,
				},
			)

			client := searchClusters.ClientForCorpus(corpus)
			clientRoutes := client.Routes()
			clientRoutes.EpochMode = bbclient.EpochMode(epochMode)
			fakeClient := helpers.FakeClient(t, client)
			fakeClient.RoutesReturns(clientRoutes)

			routes := searchClusters.GetServingRoutes(ctx, corpus)
			helpers.FakeShardClient(t, routes.ServingHosts[0][0]).SearchReturns(&searchpb.SearchResponse{
				Documents: docs,
				Stats:     &searchpb.QueryStats{},
			}, nil)
			helpers.FakeShardClient(t, routes.ServingHosts[1][0]).SearchReturns(&searchpb.SearchResponse{
				Documents: []*searchpb.GitDocumentMatch{},
				Stats:     &searchpb.QueryStats{},
			}, nil)

			repos := map[types.RepoID]*db.Repository{
				repoID: {RepoID: repoID, IsPublic: true},
			}
			store := &dbfakes.FakeStore{}
			store.LoadRepositoriesByIDsStub = func(c context.Context, repoMap map[types.RepoID]*db.Repository) error {
				for id := range repoMap {
					r, ok := repos[id]
					if ok {
						repoMap[id] = r
					}
				}
				return nil
			}
			store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
				return &db.CorpusState{Corpus: c2}, nil
			}

			gitClient := &gitaccessfakes.FakeClient{}
			gitClient.DiffStub = func(ctx context.Context, locationLimit int, t1, t2 *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
				entries := []*gitaccess.DiffEntry{}
				for path, oid := range documents {
					entries = append(entries, &gitaccess.DiffEntry{
						Path:   path,
						OID:    oid,
						Change: gitaccess.Add,
					})
				}
				return gitaccess.RepoDiff{repoID: entries}, nil
			}
			gitClient.GetBlobsStub = func(ctx context.Context, ri types.RepoID, oids []*spokes.ObjectID, f func(*gitaccess.BlobEntry)) error {
				for _, oid := range oids {
					f(&gitaccess.BlobEntry{
						OID:     helpers.OID(t, oid.Id),
						Content: []byte("qqqq"),
					})
				}
				return nil
			}

			index, err := blackbird.GetClusterWithoutBlobResolution(ctx, searchClusters, store, cache.NewInMemory(), corpus)
			require.NoError(t, err)

			githubClient := &githubfakes.FakeInternalAPIClient{}
			repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)
			prober := CompletenessProber{index, repoID, headOID, NewProber(store, cache.NewInMemory(), gitClient, routing.Dotcom, searchClusters, indexerClusters, &mocks.FakeSaramaClient{}, githubClient, repoPublisher, nil /* copilotClient */, helpers.MockDelayedTimestampReader(t))}
			result, err := prober.Check(ctx, false)
			require.NoError(t, err)
			// Since we randomly generate blob SHAs, just verify that we got some of each category
			require.Greater(t, result.Verified, 10)
			require.Greater(t, len(result.Missing), 10)
			require.Greater(t, len(result.Extra), 1)
		})
	}
}

func TestExactCompletenessProber(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClusters(t)
	indexClusters := helpers.IndexerClusters(t)

	corpus := helpers.Corpus(t)
	repoID := types.RepoID(100)
	headOID := helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23")

	for _, epochMode := range []epoch.EpochMode{
		epoch.EpochModeLegacyHybrid,
		epoch.EpochModeLexical,
		epoch.EpochModeEmbeddings,
		epoch.EpochModeEmbeddingsGraph,
		epoch.EpochModeHybrid,
	} {
		t.Run(fmt.Sprintf("epoch mode %s", epochMode.String()), func(t *testing.T) {
			client := searchClusters.ClientForCorpus(corpus)
			clientRoutes := client.Routes()
			clientRoutes.EpochMode = bbclient.EpochMode(epochMode)
			fakeClient := helpers.FakeClient(t, client)
			fakeClient.RoutesReturns(clientRoutes)

			routes := searchClusters.GetServingRoutes(ctx, corpus)
			require.EqualValues(t, epochMode, routes.EpochMode)
			require.Equal(t, epochMode, epoch.EpochMode(routes.EpochMode))
			helpers.FakeShardClient(t, routes.ServingHosts[0][0]).SearchReturns(&searchpb.SearchResponse{
				Documents: []*searchpb.GitDocumentMatch{
					{
						// This doc is expected from the spokes payload
						DocSha:  shard.DocSHAForEpochMode(helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23").Bytes(), "x/y/z.txt", epochMode),
						BlobSha: helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23").Bytes(),
						Content: []byte("asdf"),
						Locations: []*searchpb.Location{{
							Path:         "x/y/z.txt",
							RepoId:       uint32(repoID),
							Nwo:          "a/b",
							CommitSha:    headOID.Bytes(),
							IsRepoPublic: true,
						}},
						ScoringInfo: &searchpb.ScoringInfo{},
					},
				},
				Stats:         &searchpb.QueryStats{},
				ServingStatus: generator.Status(t),
			}, nil)
			helpers.FakeShardClient(t, routes.ServingHosts[1][0]).SearchReturns(&searchpb.SearchResponse{
				Documents: []*searchpb.GitDocumentMatch{
					{
						// This doc is not present in the spokes payload
						DocSha:  shard.DocSHAForEpochMode(helpers.OID(t, "8cc665305d268a1248b7dc1ea4887f08cce6a4d0").Bytes(), "does_not_exist.txt", epochMode),
						BlobSha: helpers.OID(t, "8cc665305d268a1248b7dc1ea4887f08cce6a4d0").Bytes(),
						Content: []byte("asdf"),
						Locations: []*searchpb.Location{{
							Path:         "does_not_exist.txt",
							RepoId:       uint32(repoID),
							Nwo:          "a/b",
							CommitSha:    headOID.Bytes(),
							IsRepoPublic: true,
						}},
						ScoringInfo: &searchpb.ScoringInfo{},
					},
				},

				Stats:         &searchpb.QueryStats{},
				ServingStatus: generator.Status(t),
			}, nil)

			repos := map[types.RepoID]*db.Repository{
				repoID: {RepoID: repoID, IsPublic: true},
			}
			store := &dbfakes.FakeStore{}
			store.LoadRepositoriesByIDsStub = func(c context.Context, repoMap map[types.RepoID]*db.Repository) error {
				for id := range repoMap {
					r, ok := repos[id]
					if ok {
						repoMap[id] = r
					}
				}
				return nil
			}
			store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
				return &db.CorpusState{Corpus: c2}, nil
			}

			gitClient := &gitaccessfakes.FakeClient{}
			gitClient.DiffReturns(gitaccess.RepoDiff{repoID: []*gitaccess.DiffEntry{
				{
					Path:   "x/y/z.txt",
					OID:    helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23"),
					Change: gitaccess.Add,
				},
				{
					Path:   "README.md",
					OID:    helpers.OID(t, "99d132885f045ff055e6f93d9c25173c09af9b0d"),
					Change: gitaccess.Add,
				},
			}}, nil)
			gitClient.GetBlobsStub = func(ctx context.Context, ri types.RepoID, oids []*spokes.ObjectID, f func(*gitaccess.BlobEntry)) error {
				for _, oid := range oids {
					switch oid.Id {
					case "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23":
						f(&gitaccess.BlobEntry{
							OID:     helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23"),
							Content: []byte("this is some test content"),
						})
					case "99d132885f045ff055e6f93d9c25173c09af9b0d":
						f(&gitaccess.BlobEntry{
							OID:     helpers.OID(t, "99d132885f045ff055e6f93d9c25173c09af9b0d"),
							Content: []byte("extra content"),
						})
					default:
						panic(fmt.Sprintf("Unexpected test oid %q", oid.Id))
					}

				}

				return nil
			}

			index, err := blackbird.GetClusterWithoutBlobResolution(ctx, searchClusters, store, cache.NewInMemory(), corpus)
			require.NoError(t, err)

			githubClient := &githubfakes.FakeInternalAPIClient{}
			repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)
			prober := CompletenessProber{index, repoID, headOID, NewProber(store, cache.NewInMemory(), gitClient, routing.Dotcom, searchClusters, indexClusters, &mocks.FakeSaramaClient{}, githubClient, repoPublisher, nil /* copilotClient */, helpers.MockDelayedTimestampReader(t))}
			result, err := prober.Check(ctx, false)
			require.NoError(t, err)
			require.Equal(t, 1, len(result.Extra))
			require.Equal(t, 1, result.Verified)
			require.Equal(t, 1, len(result.Missing))
		})
	}
}

func Test_CompletenessProberMaxLocationsExceeded(t *testing.T) {
	ctx := context.Background()
	searchClusters := helpers.SearchClusters(t)
	indexerClusters := helpers.IndexerClusters(t)

	corpus := helpers.Corpus(t)
	repoID := types.RepoID(100)
	headOID := helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23")
	blobOID := helpers.OID(t, "b47be1a64ad1cbf1ea10f27183bf227c8c6b7e23")

	for _, corpus := range routing.Corpora {
		routes := searchClusters.GetServingRoutes(ctx, corpus)
		helpers.FakeShardClient(t, routes.ServingHosts[0][0]).SearchReturns(&searchpb.SearchResponse{
			Documents:     []*searchpb.GitDocumentMatch{},
			Stats:         &searchpb.QueryStats{},
			ServingStatus: generator.Status(t),
		}, nil)
		helpers.FakeShardClient(t, routes.ServingHosts[1][0]).SearchStub = func(ctx context.Context, req *searchpb.SearchRequest) (*searchpb.SearchResponse, error) {
			locations := []*searchpb.Location{}
			for i := 0; i < blackbirdLocationLimit; i++ {
				loc := &searchpb.Location{
					Path:         fmt.Sprintf("file-copy-%d.txt", i),
					RepoId:       uint32(repoID),
					Nwo:          "a/b",
					CommitSha:    headOID.Bytes(),
					IsRepoPublic: true,
				}
				locations = append(locations, loc)
			}
			return &searchpb.SearchResponse{
				Documents: []*searchpb.GitDocumentMatch{
					{
						// This doc is expected from the spokes payload, but it has the max number of locations
						DocSha:            blobOID.Bytes(), // NOTE: Using blob SHA as doc SHA because this test is only possible in lexical sharding mode
						BlobSha:           blobOID.Bytes(),
						Content:           []byte("asdf"),
						Locations:         locations,
						ScoringInfo:       &searchpb.ScoringInfo{},
						TermMatches:       nil,
						LanguageId:        0,
						TotalLocations:    0,
						RetrievalPosition: 0,
						MinDocsToRetrieve: 0,
						TermEmbeddings:    nil,
					},
				},
				Stats:         &searchpb.QueryStats{},
				ServingStatus: generator.Status(t),
			}, nil
		}
	}

	repos := map[types.RepoID]*db.Repository{
		repoID: {RepoID: repoID, IsPublic: true},
	}
	store := &dbfakes.FakeStore{}
	store.LoadRepositoriesByIDsStub = func(c context.Context, repoMap map[types.RepoID]*db.Repository) error {
		for id := range repoMap {
			r, ok := repos[id]
			if ok {
				repoMap[id] = r
			}
		}
		return nil
	}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2}, nil
	}

	gitClient := &gitaccessfakes.FakeClient{}
	gitClient.DiffStub = func(ctx context.Context, locationLimit int, base *gitaccess.Treeish, head *gitaccess.Treeish) (gitaccess.RepoDiff, error) {
		diffEntries := []*gitaccess.DiffEntry{}
		for i := 0; i < blackbirdLocationLimit+1; i++ {
			diffEntry := &gitaccess.DiffEntry{
				Path:   fmt.Sprintf("file-copy-%d.txt", i),
				OID:    blobOID,
				Change: gitaccess.Add,
			}
			diffEntries = append(diffEntries, diffEntry)
		}

		return gitaccess.RepoDiff{repoID: diffEntries}, nil
	}
	gitClient.GetBlobsStub = func(ctx context.Context, ri types.RepoID, oids []*spokes.ObjectID, f func(*gitaccess.BlobEntry)) error {
		for _, oid := range oids {
			if oid.Id == blobOID.String() {
				f(&gitaccess.BlobEntry{
					OID:     blobOID,
					Content: []byte("this is some test content"),
				})
			} else {
				panic(fmt.Sprintf("unexpected blob OID %q", oid.Id))
			}
		}

		return nil
	}

	index, err := blackbird.GetClusterWithoutBlobResolution(ctx, searchClusters, store, cache.NewInMemory(), corpus)
	require.NoError(t, err)

	githubClient := &githubfakes.FakeInternalAPIClient{}
	repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)
	prober := CompletenessProber{index, repoID, headOID, NewProber(store, cache.NewInMemory(), gitClient, routing.Dotcom, searchClusters, indexerClusters, &mocks.FakeSaramaClient{}, githubClient, repoPublisher, nil /* copilotClient */, helpers.MockDelayedTimestampReader(t))}
	result, err := prober.Check(ctx, false)
	require.NoError(t, err)
	require.Equal(t, 0, len(result.Extra))
	require.Equal(t, blackbirdLocationLimit, result.Verified)
	require.Equal(t, 0, len(result.Missing))
}

func Test_EmptyCompletenessSummaryOK(t *testing.T) {
	summary := CompletenessSummary{}
	require.True(t, summary.IsOK())
}
