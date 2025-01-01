package ts

import (
	"slices"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestBatchAuditEntries(t *testing.T) {
	logicalAlertsByID := map[LogicalAlertID]*LogicalAlert{
		1: {
			Number: 101,
		},
		2: {
			Number: 102,
		},
	}
	events := []*TimelineEvent{
		{
			EventType:      TimelineEventTypeAlertCreated,
			RepositoryID:   1,
			LogicalAlertID: 1,
			CommitOid:      "abc",
			Ref:            "refs/heads/main",
		},
		{
			EventType:      TimelineEventTypeAlertCreated,
			RepositoryID:   1,
			LogicalAlertID: 2,
			CommitOid:      "abc",
			Ref:            "refs/heads/main",
		},
		{
			EventType:      TimelineEventTypeAlertCreated,
			RepositoryID:   1,
			LogicalAlertID: 2,
			CommitOid:      "abc",
			Ref:            "refs/heads/other",
		},
		{
			EventType:      TimelineEventTypeAlertClosedBecameFixed,
			RepositoryID:   1,
			LogicalAlertID: 2,
			CommitOid:      "abc",
			Ref:            "refs/heads/main",
		},
	}
	dismissalApproverID := uint64(100)
	batches := slices.Collect(BatchAuditEntries(events, logicalAlertsByID, &dismissalApproverID))

	require.ElementsMatch(t, []AuditEntryBatch{
		{
			EventType:           TimelineEventTypeAlertCreated,
			RepositoryID:        1,
			ActorID:             nil,
			CommitOID:           "abc",
			Ref:                 "refs/heads/main",
			AlertNumbers:        []uint32{101, 102},
			DismissalApproverID: &dismissalApproverID,
		},
		{
			EventType:           TimelineEventTypeAlertCreated,
			RepositoryID:        1,
			ActorID:             nil,
			CommitOID:           "abc",
			Ref:                 "refs/heads/other",
			AlertNumbers:        []uint32{102},
			DismissalApproverID: &dismissalApproverID,
		},
		{
			EventType:           TimelineEventTypeAlertClosedBecameFixed,
			RepositoryID:        1,
			ActorID:             nil,
			CommitOID:           "abc",
			Ref:                 "refs/heads/main",
			AlertNumbers:        []uint32{102},
			DismissalApproverID: &dismissalApproverID,
		},
	}, batches)
}
