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
		indexStatus       pb.RepositoryCommitStatus_IndexStatus
	}{
		{
			name:        "active snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,

			lexicalOk:   true,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},
		{
			name:        "active snapshot with future offset in hybrid cluster (serving)",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 11,

			lexicalOk:   false,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_WAITING_TO_SERVE,
		},
		{
			name:        "new snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW},
			entryoffset: 1,

			lexicalOk:   false,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXING,
		},
		{
			name:        "deleted and active snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_DELETE},
			entryoffset: 1,

			lexicalOk:   true,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},
		{
			name:        "deleted snapshot in hybrid cluster (serving)",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_DELETE},
			entryoffset: 1,

			noStatus:    true,
			lexicalOk:   false,
			indexStatus: pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},

		// Test various experiment flags
		{
			name:        "active snapshot in hybrid cluster (serving) with code embeddings",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   true,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,
			experiments: map[string]string{experiments.EnableCodeEmbedding: "1"},

			lexicalOk:      true,
			semanticCodeOK: true,
			semanticDocsOK: true,
			indexStatus:    pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED,
		},

		// Test if cluster is not serving
		{
			name:        "active snapshot in hybrid cluster (not serving) not in aggregate status",
			mode:        epoch.EpochModeHybridGraph,
			isServing:   false,
			entryStates: []snapshotpb.SnapshotEntryState{snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE},
			entryoffset: 1,

			noAggregateStatus: true,
			lexicalOk:         true,
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
			parseServingSnapshots(true /* clusterIsSelected */, test.isServing, test.mode, servingOffset, snapshots, clusterStateMap, a)

			if test.noStatus {
				require.Nil(t, clusterStateMap[repoID])
				return
			}
			require.Equal(t, test.lexicalOk, clusterStateMap[repoID].LexicalSearchOk)
			require.Equal(t, test.semanticCodeOK, clusterStateMap[repoID].SemanticCodeSearchOk)
			require.Equal(t, test.indexStatus, clusterStateMap[repoID].Commits[0].Status, fmt.Sprintf("expected %v, got %v", test.indexStatus, clusterStateMap[repoID].Commits[0].Status))

			if test.noAggregateStatus {
				require.Empty(t, a.lexicalSearchOK[repoID])
				require.Empty(t, a.semanticCodeSearchOK[repoID])
				return
			}
			require.Equal(t, test.lexicalOk, a.lexicalSearchOK[repoID])
			require.Equal(t, test.semanticCodeOK, a.semanticCodeSearchOK[repoID])
		})
	}
}

func TestParseSnapshotsMultipleServingClusters(t *testing.T) {
	repoID := uint32(1)
	lexicalCommitOID := helpers.RandomOID(t).Bytes()
	commitSHA := helpers.RandomOID(t).Bytes()
	servingOffset := int64(10)
	experiments := map[string]string{experiments.EnableCodeEmbedding: "1"}
	a := newAggregateState()

	// lexical cluster: primary
	snapshots := []*snapshotpb.Snapshot{makeSnapshot(t, repoID, lexicalCommitOID, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeLexical, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	// embeddings cluster: primary
	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeEmbeddingsGraph, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, true, a.semanticCodeSearchOK[repoID])

	// Simulate a NEW snapshot in the embeddings cluster: this repo isn't serving
	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW, experiments)}
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeEmbeddingsGraph, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	// Can no longer reliably issue embeddings queries
	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, false, a.semanticCodeSearchOK[repoID])

	// Simulate a NEW snapshot in the semantic cluster: this repo isn't serving
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeLexical, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	// This repo isn't consistently searchable in **at all* now
	require.Equal(t, false, a.lexicalSearchOK[repoID])
	require.Equal(t, false, a.semanticCodeSearchOK[repoID])
}

func TestParseSnapshotsAutoClusterSelection(t *testing.T) {
	repoID := uint32(1)
	commitOID := helpers.RandomOID(t)
	commitSHA := commitOID.Bytes()
	lexicalCommitOID := helpers.RandomOID(t)
	lexicalCommitSHA := lexicalCommitOID.Bytes()
	servingOffset := int64(10)
	experiments := map[string]string{experiments.EnableCodeEmbedding: "1"}
	a := newAggregateState()

	// 2 clusters: one lexical (selected as primary), one embeddings (selected as primary)

	snapshots := []*snapshotpb.Snapshot{makeSnapshot(t, repoID, lexicalCommitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeLexical, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, false, a.semanticCodeSearchOK[repoID])
	require.Equal(t, lexicalCommitOID.String(), a.lexicalSearchCommit[repoID])
	require.Equal(t, "", a.semanticSearchCommit[repoID])

	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeEmbeddingsGraph, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, true, a.semanticCodeSearchOK[repoID])
	require.Equal(t, lexicalCommitOID.String(), a.lexicalSearchCommit[repoID])
	require.Equal(t, commitOID.String(), a.semanticSearchCommit[repoID])
}

func TestParseSnapshotsAutoClusterSelectionHybrid(t *testing.T) {
	repoID := uint32(1)
	commitOID := helpers.RandomOID(t)
	commitSHA := commitOID.Bytes()
	servingOffset := int64(10)
	experiments := map[string]string{experiments.EnableCodeEmbedding: "1"}
	a := newAggregateState()

	// 2 clusters: both hybrid (one selected as primary, one not)

	snapshots := []*snapshotpb.Snapshot{makeSnapshot(t, repoID, helpers.RandomOID(t).Bytes(), 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(false /* clusterIsSelected */, true, epoch.EpochModeHybridGraph, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	snapshots = []*snapshotpb.Snapshot{makeSnapshot(t, repoID, commitSHA, 1, snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE, experiments)}
	parseServingSnapshots(true /* clusterIsSelected */, true, epoch.EpochModeHybridGraph, servingOffset, snapshots, map[uint32]*pb.RepositoryStatus{}, a)

	require.Equal(t, true, a.lexicalSearchOK[repoID])
	require.Equal(t, true, a.semanticCodeSearchOK[repoID])
	require.Equal(t, commitOID.String(), a.lexicalSearchCommit[repoID])
	require.Equal(t, commitOID.String(), a.semanticSearchCommit[repoID])
}
