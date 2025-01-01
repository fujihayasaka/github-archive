package query

import (
	"fmt"
	"testing"

	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/experiments"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func makeSnapshot(t *testing.T, repoId uint32, commitSHA []byte, offsetId int64, state snapshotpb.SnapshotEntryState, experiments map[string]string) *snapshotpb.Snapshot {
	t.Helper()

	return &snapshotpb.Snapshot{
		Entries: []*snapshotpb.SnapshotEntry{
			{
				RepoId:      repoId,
				CommitSha:   commitSHA,
				Experiments: experiments,
				Versions: []*snapshotpb.SnapshotEntryVersion{
					{
						OffsetId: offsetId,
						State:    state,
					},
				},
			},
		},
	}
}

func TestParseSnapshots(t *testing.T) {
	tests := []struct {
		name        string
		mode        epoch.EpochMode
		isServing   bool
		entryStates []snapshotpb.SnapshotEntryState
		entryoffset int64
		experiments map[string]string

		noStatus          bool // set if you don't expect cluster status to be reported at all for this repo (e.g. it is deleted)
		noAggregateStatus bool // set if you don't expect aggregate status to be reported at all for this repo
		lexicalOk         bool
		semanticCodeOK    bool
		semanticDocsOK    bool
		bm25Ok            bool
		indexStatus       pb.RepositoryCommitStatus_IndexStatus
	}{
		{
			name:        "active snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,

			lexicalOk:   true,
			bm25Ok:      true,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},
		{
			name:        "active snapshot with future offset in hybrid cluster (serving)",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 11,

			lexicalOk:   false,
			bm25Ok:      false,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_WAITING_TO_SERVE,
		},
		{
			name:        "new snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW},
			entryoffset: 1,

			lexicalOk:   false,
			bm25Ok:      false,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXING,
		},
		{
			name:        "deleted and active snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_DELETE},
			entryoffset: 1,

			lexicalOk:   true,
			bm25Ok:      true,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},
		{
			name:        "deleted snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_DELETE},
			entryoffset: 1,

			noStatus:    true,
			lexicalOk:   false,
			bm25Ok:      false,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},

		// Test various experiment flags
		{
			name:        "active snapshot in hybrid cluster (serving) with code embeddings",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,
			experiments: map[string]string{experiments.EnableCodeEmbedding: "1"},

			lexicalOk:      true,
			bm25Ok:         true,
			semanticCodeOK: true,
			semanticDocsOK: true,
			indexStatus:    pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},
		{
			name:        "active snapshot in hybrid cluster (serving) with doc embeddings",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,
			experiments: map[string]string{experiments.EnableDocsEmbedding: "1"},

			lexicalOk:      true,
			bm25Ok:         true,
			semanticCodeOK: false,
			semanticDocsOK: true,
			indexStatus:    pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},

		// Test if cluster is not serving
		{
			name:        "active snapshot in hybrid cluster (not serving) not in aggregate status",
			mode:        epoch.EpochModeLegacyHybrid,
			isServing:   false,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,

			noAggregateStatus: true,
			lexicalOk:         true,
			bm25Ok:            true,
			indexStatus:       pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},
	}

	repoID := uint32(1)
	commitSHA := helpers.RandomOID(t).Bytes()
	servingOffset := int64(10)
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			snapshots := []*snapshotpb.Snapshot{}
			for _, state := range test.entryStates {
				snapshots = append(snapshots, makeSnapshot(t, repoID, commitSHA, test.entryoffset, state, test.experiments))
			}
			a := newAggregateState()
			clusterStateMap := map[uint32]*pb.RepositoryStatus{}
			parseServingSnapshots(test.isServing, test.mode, servingOffset, snapshots, clusterStateMap, a)

			if test.noStatus {
				require.Nil(t, clusterStateMap[repoID])
				return
			}
			require.Equal(t, test.lexicalOk, clusterStateMap[repoID].LexicalSearchOk)
			require.Equal(t, test.semanticCodeOK, clusterStateMap[repoID].SemanticCodeSearchOk)
			require.Equal(t, test.semanticDocsOK, clusterStateMap[repoID].SemanticDocSearchOk)
			require.Equal(t, test.bm25Ok, clusterStateMap[repoID].Bm25SearchOk)
			require.Equal(t, test.indexStatus, clusterStateMap[repoID].Commits[0].Status, fmt.Sprintf("expected %v, got %v", test.indexStatus, clusterStateMap[repoID].Commits[0].Status))

			if test.noAggregateStatus {
				require.Empty(t, a.lexicalSearchOK[repoID])
				require.Empty(t, a.semanticCodeSearchOK[repoID])
				require.Empty(t, a.semanticDocSearchOK[repoID])
				require.Empty(t, a.bm25SearchOK[repoID])
				return
			}
			require.Equal(t, test.lexicalOk, a.lexicalSearchOK[repoID])
			require.Equal(t, test.semanticCodeOK, a.semanticCodeSearchOK[repoID])
			require.Equal(t, test.semanticDocsOK, a.semanticDocSearchOK[repoID])
			require.Equal(t, test.bm25Ok, a.bm25SearchOK[repoID])
		})
	}
}

func TestParseSnapshotsMultipleServingClusters(t *testing.T) {
	repoID := uint32(1)
	commitSHA := helpers.RandomOID(t).Bytes()
	servingOffset := int64(10)
	experiments := map[string]string{experiments.EnableCodeEmbedding: "1"}
	a := newAggregateState()

	snapshots := []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true, epoch.EpochModeLegacyHybrid, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true, epoch.EpochModeEmbeddings, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, true, a.semanticCodeSearchOK[repoID])
	require.Equal(t, true, a.semanticDocSearchOK[repoID])
	require.Equal(t, true, a.bm25SearchOK[repoID])

	// Now we have an embeddings cluster, but the snapshot is NEW, so this repo isn't serving
	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW, experiments)}
	parseServingSnapshots(true, epoch.EpochModeEmbeddings, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	// Can no longer reliably issue embeddings queries
	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, false, a.semanticCodeSearchOK[repoID])
	require.Equal(t, false, a.semanticDocSearchOK[repoID])
	require.Equal(t, true, a.bm25SearchOK[repoID])

	// Now we have a hybrid cluster, but the snapshot is NEW, so this repo isn't serving
	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW, experiments)}
	parseServingSnapshots(true, epoch.EpochModeLegacyHybrid, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	// This repo isn't consistently searchable in **at all* now
	require.Equal(t, false, a.lexicalSearchOK[repoID])
	require.Equal(t, false, a.semanticCodeSearchOK[repoID])
	require.Equal(t, false, a.semanticDocSearchOK[repoID])
	require.Equal(t, false, a.bm25SearchOK[repoID])
}
