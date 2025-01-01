package ts

import (
	"crypto/sha256"
	"encoding/hex"
	"iter"
	"maps"
	"strings"
)

type AuditEntryBatch struct {
	EventType           TimelineEventType
	RepositoryID        RepositoryEID
	ActorID             *UserEID
	CommitOID           Sha
	Ref                 string
	AlertNumbers        []uint32
	DismissalApproverID *uint64
}

func (b *AuditEntryBatch) Hash() string {
	separator := []byte{0}
	h := sha256.New()
	h.Write([]byte(b.EventType.String()))
	h.Write(separator)
	h.Write(uint64ToBytes(uint64(b.RepositoryID)))
	h.Write(separator)
	if b.ActorID != nil {
		h.Write(uint64ToBytes(uint64(*b.ActorID)))
	}
	h.Write(separator)
	h.Write([]byte(b.CommitOID))
	h.Write(separator)
	h.Write([]byte(b.Ref))
	h.Write(separator)
	if b.DismissalApproverID != nil {
		h.Write(uint64ToBytes(*b.DismissalApproverID))
	}
	return hex.EncodeToString(h.Sum(nil))
}

func BatchAuditEntries(events []*TimelineEvent, logicalAlertsByID map[LogicalAlertID]*LogicalAlert, dismissalApproverID *uint64) iter.Seq[AuditEntryBatch] {
	batches := map[string]AuditEntryBatch{}
	for _, event := range events {
		la, ok := logicalAlertsByID[event.LogicalAlertID]
		if !ok {
			continue
		}
		// Ignore pull request events for alerts that are not unique to the pull request.
		// This preserves the behavior from before we started batching events, but could likely be removed if we wanted to emit audit log entries for these even
		if event.NonUnique && strings.HasPrefix(event.Ref, "refs/pull/") {
			continue
		}
		batch := AuditEntryBatch{
			EventType:           event.EventType,
			RepositoryID:        event.RepositoryID,
			ActorID:             event.UserID,
			CommitOID:           event.CommitOid,
			Ref:                 event.Ref,
			AlertNumbers:        []uint32{la.Number},
			DismissalApproverID: dismissalApproverID,
		}
		hash := batch.Hash()
		if existingBatch, ok := batches[hash]; ok {
			existingBatch.AlertNumbers = append(existingBatch.AlertNumbers, la.Number)
			batches[hash] = existingBatch
		} else {
			batches[hash] = batch
		}
	}
	return maps.Values(batches)
}
