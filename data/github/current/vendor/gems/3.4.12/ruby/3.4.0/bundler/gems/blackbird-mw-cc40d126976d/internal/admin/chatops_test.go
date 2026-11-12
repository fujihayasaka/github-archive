package admin

import (
	"context"
	"fmt"
	"testing"
	"time"

	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/go-chatops/v2"
	gh "github.com/google/go-github/github"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/publish/backfill"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_Ping(t *testing.T) {
	ctx := context.Background()
	s := srv(t)
	resp, err := s.chatPingHandler(ctx, &chatops.CommandRequest{Method: "ping", Params: map[string]string{}, User: "hubot"})
	require.NoError(t, err)
	require.Equal(t, "pong, hubot!", resp.Result)
}

func Test_CorpusStatus(t *testing.T) {
	ctx := context.Background()
	s := srv(t)
	resp, err := s.chatStatusHandler(ctx, &chatops.CommandRequest{Method: "status", Params: map[string]string{}})
	require.NoError(t, err)
	var status pb.GetCorpusStatusResponse
	err = protojson.Unmarshal([]byte(resp.Result), &status)
	require.NoError(t, err)
	require.Equal(t, len(routing.Corpora)+len(routing.CacheClusterNames), len(status.Statuses))
}

func Test_RepoStatus(t *testing.T) {
	ctx := context.Background()
	s := srv(t)
	resp, err := s.chatStatusHandler(ctx, &chatops.CommandRequest{Method: "status", Params: map[string]string{"owner": "github", "repo": "test-repo"}})
	require.NoError(t, err)
	var status pb.GetRepoStatusResponse
	err = protojson.Unmarshal([]byte(resp.Result), &status)
	require.NoError(t, err)
	require.Equal(t, "github/test-repo", status.RepoNwo)
}

func Test_UserStatus(t *testing.T) {
	ctx := context.Background()
	s := srv(t)
	resp, err := s.chatStatusHandler(ctx, &chatops.CommandRequest{Method: "status", Params: map[string]string{"owner": "github"}})
	require.NoError(t, err)
	var status pb.GetRateLimitQuotaResponse
	err = protojson.Unmarshal([]byte(resp.Result), &status)
	require.NoError(t, err)
	require.Len(t, status.Quotas, 14)
}

func Test_Pin(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, corpus))
	_, err := s.chatPin(ctx, &chatops.CommandRequest{Method: "pin", Params: map[string]string{"corpus": corpus.String(), "ts": "1234567890"}})
	require.NoError(t, err)
	_, err = s.chatPin(ctx, &chatops.CommandRequest{Method: "pin", Params: map[string]string{"corpus": "na"}})
	require.EqualError(t, err, "unable to pin corpus: twirp error invalid_argument: corpus is not valid")
}

func Test_UnPin(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, corpus))
	_, err := s.chatUnpin(ctx, &chatops.CommandRequest{Method: "pin", Params: map[string]string{"corpus": corpus.String()}})
	require.NoError(t, err)
	_, err = s.chatUnpin(ctx, &chatops.CommandRequest{Method: "pin", Params: map[string]string{"corpus": "na"}})
	require.EqualError(t, err, "unable to unpin corpus: twirp error invalid_argument: corpus is not valid")
}

func Test_SetCorpusCacheCluster(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, corpus))
	_, err := s.chatSetCacheCluster(ctx, &chatops.CommandRequest{Method: "set-cache-cluster", Params: map[string]string{"corpus": corpus.String(), "cluster": "cache-001"}})
	require.NoError(t, err)
	_, err = s.chatSetCacheCluster(ctx, &chatops.CommandRequest{Method: "set-cache-cluster", Params: map[string]string{"corpus": "n/a", "cluster": "cache-001"}})
	require.EqualError(t, err, "unable to set cache cluster: invalid corpus name n/a")
	_, err = s.chatSetCacheCluster(ctx, &chatops.CommandRequest{Method: "set-cache-cluster", Params: map[string]string{"corpus": corpus.String(), "cluster": "n/a"}})
	require.EqualError(t, err, "unable to set cache cluster: invalid cache cluster name: n/a")
}

func Test_CorpusManagement(t *testing.T) {
	ctx := context.Background()
	// Serve green by default so that we have at-least one corpus serving
	// when we disable blue. Otherwise we have to force disable blue which
	// not what this test is for.
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, routing.Green))

	fixtures := []struct {
		fixtureName string
		cmd         string
		target      string
		corpus      string
	}{
		{
			fixtureName: "enable serving in blue",
			cmd:         "enable",
			target:      "serving",
			corpus:      "blue",
		},
		{
			fixtureName: "disable serving in blue",
			cmd:         "disable",
			target:      "serving",
			corpus:      "blue",
		},
		{
			fixtureName: "enable indexing in blue",
			cmd:         "enable",
			target:      "indexing",
			corpus:      "blue",
		},
		{
			fixtureName: "disable indexing in blue",
			cmd:         "disable",
			target:      "indexing",
			corpus:      "blue",
		},
	}

	for _, f := range fixtures {
		t.Run(f.fixtureName, func(t *testing.T) {
			resp, err := s.chatConfigureCorpus(ctx,
				&chatops.CommandRequest{
					Method: "corpus",
					Params: map[string]string{"cmd": f.cmd, "target": f.target, "corpus": f.corpus}},
			)
			require.NoError(t, err)
			require.Equal(t, fmt.Sprintf("OK, %s %sd for the %s corpus", f.target, f.cmd, f.corpus), resp.Result)
		})
	}
}

func Test_DisableForce(t *testing.T) {
	ctx := context.Background()
	store := &dbfakes.FakeStore{}
	store.GetCorpusStateStub = func(c1 context.Context, c2 routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: c2, EpochID: 1}, nil
	}
	store.GetEpochReturns(&db.Epoch{EpochID: 1, Description: "test"}, nil)

	s := srvWithStore(t, store, helpers.SearchClustersWithServingCorpus(t, routing.Blue), helpers.CacheClusters(t), helpers.IndexerClusters(t))
	resp, err := s.chatConfigureCorpus(ctx,
		&chatops.CommandRequest{
			Method: "corpus",
			Params: map[string]string{"cmd": "disable", "target": "serving", "corpus": "blue"}},
	)
	require.Nil(t, resp)
	require.EqualError(t, err, "Are you sure you want to disable serving on blue? No other corpora are enabled for serving. (Use --force to override.)")

	// force it
	resp, err = s.chatConfigureCorpus(ctx,
		&chatops.CommandRequest{
			Method: "corpus",
			Params: map[string]string{"cmd": "disable", "target": "serving", "corpus": "blue", "force": ""}},
	)
	require.NoError(t, err)
	require.Equal(t, "OK, serving disabled for the blue corpus", resp.Result)
}

func Test_Backfill(t *testing.T) {
	ctx := context.Background()
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, routing.Green)) // serve green epoch so that we can backfill blue
	resp, err := s.chatBackfill(ctx, &chatops.CommandRequest{
		Method: "corpus",
		User:   "test-user",
		Params: map[string]string{"cmd": "backfill", "corpus": "blue"}})
	require.NoError(t, err)
	require.Contains(t, resp.Result, "Backfill for blue enqueued.")
}

func Test_BackfillLimit(t *testing.T) {
	ctx := context.Background()
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, routing.Green)) // serve green epoch so that we can backfill blue
	resp, err := s.chatBackfill(ctx, &chatops.CommandRequest{
		Method: "corpus",
		User:   "test-user",
		Params: map[string]string{"cmd": "backfill", "corpus": "blue", "limit": "100"}})
	require.NoError(t, err)
	require.Contains(t, resp.Result, "Backfill for blue enqueued.")
}

func Test_BackfillSpecificRepos(t *testing.T) {
	ctx := context.Background()
	s := srvWithSearchClusters(t, helpers.SearchClustersWithServingCorpus(t, routing.Green)) // serve green epoch so that we can backfill blue
	resp, err := s.chatBackfill(ctx, &chatops.CommandRequest{
		Method: "corpus",
		User:   "test-user",
		Params: map[string]string{"cmd": "backfill", "corpus": "blue", "repos": "github/github github/blackbird"}})
	require.NoError(t, err)
	require.Contains(t, resp.Result, "Backfill for blue enqueued.")
}

func Test_BackfillRequiresServingCorpus(t *testing.T) {
	ctx := context.Background()
	store := &dbfakes.FakeStore{
		GetCorpusStateStub: func(ctx context.Context, corpus routing.Corpus) (*db.CorpusState, error) {
			return &db.CorpusState{Corpus: corpus, EpochID: 1}, nil
		},
		CreateEpochStub: func(ctx context.Context, corpus routing.Corpus, description string) (*db.Epoch, error) {
			return &db.Epoch{EpochID: 1, Description: description}, nil
		},
	}
	store.GetEpochReturns(&db.Epoch{EpochID: 1, Description: "test"}, nil)

	s := srvWithStore(t, store, helpers.SearchClustersWithServingCorpus(t, routing.Blue), helpers.CacheClusters(t), helpers.IndexerClusters(t))
	resp, err := s.chatBackfill(ctx, &chatops.CommandRequest{
		Method: "corpus",
		User:   "test-user",
		Params: map[string]string{"cmd": "backfill", "corpus": "blue"}})
	require.Nil(t, resp)
	require.EqualError(t, err, "This is the only corpus enabled for serving, cannot backfill.")

	// force does nothing
	resp, err = s.chatBackfill(ctx, &chatops.CommandRequest{
		Method: "corpus",
		User:   "test-user",
		Params: map[string]string{"cmd": "backfill", "corpus": "blue", "force": ""}})
	require.NoError(t, err)
	require.Contains(t, resp.Result, "Backfill for blue enqueued.")
}

func srv(t *testing.T) *ChatopsServer {
	s := &dbfakes.FakeStore{}
	s.GetCorpusStateStub = func(_ context.Context, corpus routing.Corpus) (*db.CorpusState, error) {
		return &db.CorpusState{Corpus: corpus, EpochID: 1}, nil
	}
	s.CreateEpochReturns(&db.Epoch{EpochID: 1}, nil)
	s.GetEpochReturns(&db.Epoch{EpochID: 1, Description: "test"}, nil)
	s.GetFirstRepositoryReturns(&db.Repository{RepoID: 1, OwnerLogin: "github", Name: "test-repo"}, nil)
	s.GetRepositoryByNWOReturns(&db.Repository{RepoID: 1, OwnerLogin: "github", Name: "test-repo"}, nil)

	// IndexAPI SearchSnapshots response: used for getting repo status
	indexerClusters := helpers.IndexerClusters(t)
	for _, corpus := range routing.Corpora {
		cluster := indexerClusters.GetCluster(corpus)
		host, err := cluster.GetHost()
		require.NoError(t, err)

		client := helpers.FakeIndexAPI(t, host)
		client.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
			Snapshots: []*snapshotpb.Snapshot{
				{
					Entries: []*snapshotpb.SnapshotEntry{
						{
							EntryId:   123,
							RepoId:    1,
							OwnerId:   123,
							NetworkId: 123,
							Nwo:       "github/test-repo",
							RefName:   "refs/heads/main",
							CommitSha: helpers.UniqueOID(t).Bytes(),
						},
					},
				},
			},
			ServingStatus: &servingpb.ServingStatus{
				Shards: []*servingpb.Shard{
					{
						Id:            host.ShardID,
						ServingOffset: 123,
						ServingTs:     time.Now().UnixMilli(),
					},
				},
			},
		}, nil)

	}

	return srvWithStore(t, s, helpers.SearchClusters(t), helpers.CacheClusters(t), indexerClusters)
}

func srvWithSearchClusters(t *testing.T, searchClusters *routing.SearchClusters) *ChatopsServer {
	return srvWithStore(t, noop.New(), searchClusters, helpers.CacheClusters(t), helpers.IndexerClusters(t))
}

func srvWithStore(t *testing.T, store db.Store, searchClusters *routing.SearchClusters, cacheClusters *routing.CacheClusters, indexerClusters *routing.IndexerClusters) *ChatopsServer {
	ctx := context.Background()
	cfg := env.New(ctx)

	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetUserStub = func(ctx context.Context, s string) (*gh.User, error) {
		return &gh.User{ID: gh.Int64(0), Login: gh.String(s)}, nil
	}
	githubClient.GetRepositoryStub = func(ctx context.Context, repoID types.RepoID) (*github.Repository, error) {
		return &github.Repository{ID: repoID}, nil
	}
	backfillPublisher := backfill.NewPublisher(
		store,
		&mocks.FakeSyncProducer{},
		searchClusters,
		cacheClusters,
		&chat.NoopClient{},
		1,
	)
	repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)
	adminAPI := NewService(
		searchClusters,
		cacheClusters,
		indexerClusters,
		store,
		cache.NewInMemory(),
		&gitaccessfakes.FakeClient{},
		githubClient,
		&chat.NoopClient{},
		mockClusterAdminProvider(),
		&mocks.FakeSaramaClient{},
		routing.TopicConfig{},
		backfillPublisher,
		repoPublisher,
		&mocks.FakeSyncProducer{},
		quota.NewMemoryRateEstimator(),
		&kafkafakes.FakeAssignmentsReader{},
		nil, /* sitesapi */
		routing.Dotcom,
		helpers.MockDelayedTimestampReader(t),
		helpers.NoopConsumerGroupManager(t),
	)
	return NewChatopsService(cfg, adminAPI, &chat.NoopClient{})
}
