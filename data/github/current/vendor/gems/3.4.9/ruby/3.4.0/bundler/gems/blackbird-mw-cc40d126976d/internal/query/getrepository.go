package query

import (
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

type aggregateState struct {
	lexicalSearchOK      map[uint32]bool
	lexicalSearchCommit  map[uint32]string
	semanticCodeSearchOK map[uint32]bool
	semanticDocSearchOK  map[uint32]bool
	semanticSearchCommit map[uint32]string
	bm25SearchOK         map[uint32]bool
}

func newAggregateState() *aggregateState {
	return &aggregateState{
		lexicalSearchOK:      make(map[uint32]bool),
		lexicalSearchCommit:  make(map[uint32]string),
		semanticCodeSearchOK: make(map[uint32]bool),
		semanticDocSearchOK:  make(map[uint32]bool),
		semanticSearchCommit: make(map[uint32]string),
		bm25SearchOK:         make(map[uint32]bool),
	}
}

func parseServingSnapshots(clusterIsSelected, clusterIsServing bool, epochMode epoch.EpochMode, servingOffset int64, snapshots []*snapshotpb.Snapshot, clusterStateMap map[uint32]*pb.RepositoryStatus, aggregateState *aggregateState) {
	lexicalSearchOK := false
	lexicalCommitSHA := ""
	semanticCodeSearchOK := false
	semanticDocSearchOK := false
	semanticCommitSHA := ""
	bm25SearchOK := false
	for _, s := range snapshots {
		for _, entry := range s.Entries {
			var status pb.RepositoryCommitStatus_IndexStatus
			var permanentError *pb.RepositoryCommitStatus_PermanentError
			if entry.PermanentError != "" {
				status = pb.RepositoryCommitStatus_INDEX_STATUS_PERMANENT_ERROR
				permanentError = &pb.RepositoryCommitStatus_PermanentError{
					ErrorMsg:  entry.PermanentError,
					ErrorType: entry.PermanentErrorType.String(),
				}
			} else {
				// NB: We want the active version OR the last version: iterate in reverse until we find one.
				for i := len(entry.Versions); i > 0; i-- {
					version := entry.Versions[i-1]

					if version.State == snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE && version.OffsetId <= servingOffset {
						// searchable
						status = pb.RepositoryCommitStatus_INDEX_STATUS_INDEXED
						lexicalSearchOK = epoch.EpochFeaturesLexical.SupportedBy(epochMode)
						bm25SearchOK = epoch.EpochFeaturesBM25.SupportedBy(epochMode)
						lexicalCommitSHA = gitaccess.NewObjectIDFromBytes(entry.CommitSha).String()

						if _, ok := entry.Experiments[experiments.EnableCodeEmbedding]; ok {
							semanticCodeSearchOK = epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode)
							semanticDocSearchOK = epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode)
							semanticCommitSHA = gitaccess.NewObjectIDFromBytes(entry.CommitSha).String()
						} else if _, ok := entry.Experiments[experiments.EnableDocsEmbedding]; ok {
							semanticDocSearchOK = epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode)
						}
					} else if version.State == snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE {
						// not searchable yet: finished crawling, but waiting for offset to serve
						status = pb.RepositoryCommitStatus_INDEX_STATUS_WAITING_TO_SERVE
					} else if version.State == snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW {
						// not searchable yet: still crawling
						status = pb.RepositoryCommitStatus_INDEX_STATUS_INDEXING
					} else {
						// deleted or inactive, keep looking
						continue
					}
					break
				}
			}

			if status == pb.RepositoryCommitStatus_INDEX_STATUS_UNKNOWN {
				// deleted or inactive, don't record
				break
			}

			commit := &pb.RepositoryCommitStatus{
				CommitSha:      gitaccess.NewObjectIDFromBytes(entry.CommitSha).String(),
				Experiments:    entry.Experiments,
				PermanentError: permanentError,
				Status:         status,
			}

			if v, ok := clusterStateMap[entry.RepoId]; ok {
				v.Commits = append(v.Commits, commit)
			} else {
				clusterStateMap[entry.RepoId] = &pb.RepositoryStatus{
					RepositoryId:         entry.RepoId,
					LexicalSearchOk:      lexicalSearchOK,
					SemanticCodeSearchOk: semanticCodeSearchOK,
					SemanticDocSearchOk:  semanticDocSearchOK,
					Bm25SearchOk:         bm25SearchOK,
					Commits:              []*pb.RepositoryCommitStatus{commit},
				}
			}

			// Aggregate status computed for serving clusters only
			if !clusterIsServing {
				continue
			}

			if epoch.EpochFeaturesLexical.SupportedBy(epochMode) {
				if v, ok := aggregateState.lexicalSearchOK[entry.RepoId]; ok {
					aggregateState.lexicalSearchOK[entry.RepoId] = v && lexicalSearchOK
				} else {
					aggregateState.lexicalSearchOK[entry.RepoId] = lexicalSearchOK
				}
				if clusterIsSelected {
					aggregateState.lexicalSearchCommit[entry.RepoId] = lexicalCommitSHA
				}
			}
			if epoch.EpochFeaturesBM25.SupportedBy(epochMode) {
				if v, ok := aggregateState.bm25SearchOK[entry.RepoId]; ok {
					aggregateState.bm25SearchOK[entry.RepoId] = v && bm25SearchOK
				} else {
					aggregateState.bm25SearchOK[entry.RepoId] = bm25SearchOK
				}
			}

			if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
				if v, ok := aggregateState.semanticCodeSearchOK[entry.RepoId]; ok {
					aggregateState.semanticCodeSearchOK[entry.RepoId] = v && semanticCodeSearchOK
				} else {
					aggregateState.semanticCodeSearchOK[entry.RepoId] = semanticCodeSearchOK
				}
				if v, ok := aggregateState.semanticDocSearchOK[entry.RepoId]; ok {
					aggregateState.semanticDocSearchOK[entry.RepoId] = v && semanticDocSearchOK
				} else {
					aggregateState.semanticDocSearchOK[entry.RepoId] = semanticDocSearchOK
				}
				if clusterIsSelected {
					aggregateState.semanticSearchCommit[entry.RepoId] = semanticCommitSHA
				}
			}
		}
	}
}

func parseIndexerSnapshots(servingOffset int64, snapshots []*snapshotpb.Snapshot, clusterStateMap map[uint32]*pb.RepositoryStatus) {
	for _, s := range snapshots {
		for _, entry := range s.Entries {
			var status pb.RepositoryCommitStatus_IndexStatus
			// only care about the last version (if any)
			if len(entry.Versions) == 0 {
				continue
			}
			version := entry.Versions[len(entry.Versions)-1]

			var permanentError *pb.RepositoryCommitStatus_PermanentError
			if entry.PermanentError != "" {
				status = pb.RepositoryCommitStatus_INDEX_STATUS_PERMANENT_ERROR
				permanentError = &pb.RepositoryCommitStatus_PermanentError{
					ErrorMsg:  entry.PermanentError,
					ErrorType: entry.PermanentErrorType.String(),
				}
			} else {
				// find commits actively being crawled that aren't already in the list
				if version.State == snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_ACTIVE && version.OffsetId > servingOffset {
					// not searchable yet: finished crawling, but waiting for offset to serve
					status = pb.RepositoryCommitStatus_INDEX_STATUS_WAITING_TO_SERVE
				} else if version.State == snapshotpb.SnapshotEntryState_SNAPSHOT_ENTRY_STATE_NEW {
					// not searchable yet: still crawling
					status = pb.RepositoryCommitStatus_INDEX_STATUS_INDEXING
				} else {
					break
				}
			}

			commit := &pb.RepositoryCommitStatus{
				CommitSha:      gitaccess.NewObjectIDFromBytes(entry.CommitSha).String(),
				Experiments:    entry.Experiments,
				PermanentError: permanentError,
				Status:         status,
			}
			if v, ok := clusterStateMap[entry.RepoId]; ok {
				// Only add the commit if it's not already in the list
				exists := false
				for _, c := range v.Commits {
					if c.CommitSha == commit.CommitSha {
						exists = true
					}
				}
				if !exists {
					v.Commits = append(v.Commits, commit)
				}
			} else {
				// no state for this repo yet
				clusterStateMap[entry.RepoId] = &pb.RepositoryStatus{
					RepositoryId: entry.RepoId,
					Commits:      []*pb.RepositoryCommitStatus{commit},
				}
			}
		}
	}
}
