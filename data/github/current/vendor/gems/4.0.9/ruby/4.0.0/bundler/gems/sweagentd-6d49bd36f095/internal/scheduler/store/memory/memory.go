// Package memory provides an in-memory implementation of interval trigger storage
// for testing and development.
package memory

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	schedulercosmos "github.com/github/sweagentd/internal/scheduler/store/cosmos"
	"github.com/google/uuid"
)

// Store is an in-memory implementation of interval trigger storage.
type Store struct {
	mu      sync.RWMutex
	records map[int64]map[string]*schedulerstore.IntervalTriggerRecord // scopeID -> id -> trigger
}

// NewStore creates a new in-memory Store instance.
func NewStore() *Store {
	return &Store{
		records: make(map[int64]map[string]*schedulerstore.IntervalTriggerRecord),
	}
}

func newETag() *azcore.ETag {
	str := fmt.Sprintf("%q", uuid.NewString())
	etag := azcore.ETag(str)
	return &etag
}

func copyTrigger(t *schedulerstore.IntervalTriggerRecord) *schedulerstore.IntervalTriggerRecord {
	cp := *t
	if t.ETag != nil {
		e := *t.ETag
		cp.ETag = &e
	}
	if t.AnchorHourUTC != nil {
		v := *t.AnchorHourUTC
		cp.AnchorHourUTC = &v
	}
	if t.AnchorDayOfWeek != nil {
		v := *t.AnchorDayOfWeek
		cp.AnchorDayOfWeek = &v
	}
	return &cp
}

// Upsert creates or updates an interval trigger record.
func (m *Store) Upsert(_ context.Context, trigger *schedulerstore.IntervalTriggerRecord) (*schedulerstore.IntervalTriggerRecord, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	cp := copyTrigger(trigger)
	cp.SetTimestamps()
	cp.ETag = newETag()

	if m.records[cp.ScopeID] == nil {
		m.records[cp.ScopeID] = make(map[string]*schedulerstore.IntervalTriggerRecord)
	}

	m.records[cp.ScopeID][cp.ID] = cp

	return copyTrigger(cp), nil
}

// Get retrieves a single interval trigger by scope and ID.
func (m *Store) Get(_ context.Context, scopeID int64, id string) (*schedulerstore.IntervalTriggerRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return nil, schedulercosmos.ErrNotFound
	}

	t, ok := scopeRecords[id]
	if !ok {
		return nil, schedulercosmos.ErrNotFound
	}

	return copyTrigger(t), nil
}

// GetByAgentID retrieves triggers for a specific agent within a scope partition.
func (m *Store) GetByAgentID(_ context.Context, scopeID int64, agentID string) ([]*schedulerstore.IntervalTriggerRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return []*schedulerstore.IntervalTriggerRecord{}, nil
	}

	var results []*schedulerstore.IntervalTriggerRecord
	for _, t := range scopeRecords {
		if t.AgentID == agentID {
			results = append(results, copyTrigger(t))
		}
	}

	return results, nil
}

// Delete removes an interval trigger by ID within a scope partition.
func (m *Store) Delete(_ context.Context, scopeID int64, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return schedulercosmos.ErrNotFound
	}

	if _, ok := scopeRecords[id]; !ok {
		return schedulercosmos.ErrNotFound
	}

	delete(scopeRecords, id)

	if len(scopeRecords) == 0 {
		delete(m.records, scopeID)
	}

	return nil
}

// ListByScopeID retrieves all interval triggers for a scope partition.
func (m *Store) ListByScopeID(_ context.Context, scopeID int64) ([]*schedulerstore.IntervalTriggerRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return []*schedulerstore.IntervalTriggerRecord{}, nil
	}

	results := make([]*schedulerstore.IntervalTriggerRecord, 0, len(scopeRecords))
	for _, t := range scopeRecords {
		results = append(results, copyTrigger(t))
	}

	return results, nil
}

// FindDueTriggers returns triggers that are due for execution (next_run_at <= now AND locked_by == "").
func (m *Store) FindDueTriggers(_ context.Context, now time.Time, limit int) ([]*schedulerstore.IntervalTriggerRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	nowUnix := now.Unix()
	var results []*schedulerstore.IntervalTriggerRecord

	for _, scopeRecords := range m.records {
		for _, t := range scopeRecords {
			if t.NextRunAt <= nowUnix && t.LockedBy == "" {
				results = append(results, copyTrigger(t))
			}
		}
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].NextRunAt < results[j].NextRunAt
	})

	if len(results) > limit {
		results = results[:limit]
	}

	return results, nil
}

// FindStaleLocks returns triggers with locks older than the threshold.
func (m *Store) FindStaleLocks(_ context.Context, threshold time.Time, limit int) ([]*schedulerstore.IntervalTriggerRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	thresholdUnix := threshold.Unix()
	var results []*schedulerstore.IntervalTriggerRecord

	for _, scopeRecords := range m.records {
		for _, t := range scopeRecords {
			if t.LockedBy != "" && t.LockedAt > 0 && t.LockedAt < thresholdUnix {
				results = append(results, copyTrigger(t))
			}
		}
	}

	if len(results) > limit {
		results = results[:limit]
	}

	return results, nil
}

// PatchTrigger applies a partial update to an interval trigger.
// Checks ETag if provided in the patch, applies only non-nil fields.
// Returns the new ETag after the update.
func (m *Store) PatchTrigger(_ context.Context, scopeID int64, id string, patch schedulerstore.IntervalTriggerPatch) (*azcore.ETag, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return nil, schedulercosmos.ErrNotFound
	}

	t, ok := scopeRecords[id]
	if !ok {
		return nil, schedulercosmos.ErrNotFound
	}

	if patch.ETag != nil && (t.ETag == nil || *t.ETag != *patch.ETag) {
		return nil, schedulercosmos.ErrConflict
	}

	if patch.LockedBy != nil {
		t.LockedBy = *patch.LockedBy
	}
	if patch.LockedAt != nil {
		t.LockedAt = *patch.LockedAt
	}
	if patch.NextRunAt != nil {
		t.NextRunAt = *patch.NextRunAt
	}
	if patch.LastRunAt != nil {
		t.LastRunAt = *patch.LastRunAt
	}
	if patch.IntervalType != nil {
		t.IntervalType = *patch.IntervalType
	}
	if patch.AnchorHourUTC != nil {
		v := *patch.AnchorHourUTC
		t.AnchorHourUTC = &v
	}
	if patch.AnchorDayOfWeek != nil {
		v := *patch.AnchorDayOfWeek
		t.AnchorDayOfWeek = &v
	}
	if patch.ActorID != nil {
		t.ActorID = *patch.ActorID
	}
	if patch.ActorLogin != nil {
		t.ActorLogin = *patch.ActorLogin
	}
	if patch.TreeOID != nil {
		t.TreeOID = *patch.TreeOID
	}
	if patch.LastEventUpdatedAt != nil {
		t.LastEventUpdatedAt = *patch.LastEventUpdatedAt
	}
	t.ETag = newETag()

	etag := *t.ETag
	return &etag, nil
}
