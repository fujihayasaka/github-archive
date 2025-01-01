package blackbird

import (
	"context"
	"testing"

	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/parser"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_BuildCacheFromQuery(t *testing.T) {
	ctx := context.Background()
	corpus := helpers.Corpus(t)
	const (
		repoID  = 1
		ownerID = 123
	)
	actor := &models.Actor{
		ID:                        1,
		AccessiblePrivateRepoIDs:  types.RepoIDSet{repoID: true},
		AccessibleOrganizationIDs: types.U32Set{ownerID: true},
	}

	searchClusters := helpers.SearchClustersNWithServingCorpus(t, 1, corpus)

	client := searchClusters.ClientForCorpus(corpus).(*mocks.FakeBlackbirdClient)
	host := client.Routes().Hosts[0][0].SearchClient.(*mocks.FakeSearchAPI)
	host.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{
		Snapshots: []*snapshotpb.Snapshot{{
			Entries: []*snapshotpb.SnapshotEntry{
				{
					EntryId:        456,
					RepoId:         repoID,
					OwnerId:        ownerID,
					Nwo:            "",
					PermanentError: "HEAD of default ref not found",
				},
			},
		}},
		ServingStatus: &servingpb.ServingStatus{},
	}, nil)

	cluster := Cluster{
		routes: searchClusters.GetServingRoutes(ctx, corpus),
	}

	cache, err := cluster.BuildCacheFromQuery(ctx, false, actor, parser.ConvertToProto(parser.RepoID(repoID)))
	require.NoError(t, err)
	require.Equal(t, 1, host.SearchSnapshotsCallCount())
	require.Empty(t, cache.ReposByID)
	require.Empty(t, cache.ReposByNWO)
}
