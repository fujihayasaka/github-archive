// Package memory provides an in-memory implementation of custom agent storage
// for testing and development.
package memory

import (
	"context"
	"fmt"
	"maps"
	"sync"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/google/uuid"
)

// Store is an in-memory implementation of custom agent storage.
type Store struct {
	mu      sync.RWMutex
	records map[int64]map[string]*store.AgentRecord // scopeID -> id -> record
}

// NewStore creates a new in-memory Store instance.
func NewStore() *Store {
	return &Store{
		records: make(map[int64]map[string]*store.AgentRecord),
	}
}

func newETag() *azcore.ETag {
	str := fmt.Sprintf("%q", uuid.NewString())
	etag := azcore.ETag(str)
	return &etag
}

func copyRecord(r *store.AgentRecord) *store.AgentRecord {
	cp := *r
	if r.ETag != nil {
		e := *r.ETag
		cp.ETag = &e
	}

	// Deep-copy Ancestors slice
	if r.Ancestors != nil {
		cp.Ancestors = make([]store.AgentAncestor, len(r.Ancestors))
		copy(cp.Ancestors, r.Ancestors)
	}

	// Deep-copy Config reference types
	if r.Config.Tools != nil {
		cp.Config.Tools = make([]string, len(r.Config.Tools))
		copy(cp.Config.Tools, r.Config.Tools)
	}
	if r.Config.Metadata != nil {
		cp.Config.Metadata = make(map[string]string, len(r.Config.Metadata))
		maps.Copy(cp.Config.Metadata, r.Config.Metadata)
	}
	if r.Config.Handoffs != nil {
		cp.Config.Handoffs = make([]sweagentd.CustomAgentHandoff, len(r.Config.Handoffs))
		copy(cp.Config.Handoffs, r.Config.Handoffs)
	}

	// Deep-copy MCPServers and their nested reference types
	if r.Config.MCPServers != nil {
		cp.Config.MCPServers = make([]store.MCPServer, len(r.Config.MCPServers))
		for i, s := range r.Config.MCPServers {
			cp.Config.MCPServers[i] = s
			if s.Tools != nil {
				cp.Config.MCPServers[i].Tools = make([]string, len(s.Tools))
				copy(cp.Config.MCPServers[i].Tools, s.Tools)
			}
			if s.Args != nil {
				cp.Config.MCPServers[i].Args = make([]string, len(s.Args))
				copy(cp.Config.MCPServers[i].Args, s.Args)
			}
			if s.Env != nil {
				cp.Config.MCPServers[i].Env = make(map[string]string, len(s.Env))
				maps.Copy(cp.Config.MCPServers[i].Env, s.Env)
			}
			if s.Headers != nil {
				cp.Config.MCPServers[i].Headers = make(map[string]string, len(s.Headers))
				maps.Copy(cp.Config.MCPServers[i].Headers, s.Headers)
			}
		}
	}

	return &cp
}

// Upsert creates or updates an agent record.
func (m *Store) Upsert(_ context.Context, record *store.AgentRecord) (*store.AgentRecord, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if record == nil {
		return nil, goerrors.New("agent record cannot be nil")
	}

	record.SetTimestamps()
	record.UpdatedAt = time.Now().Unix()
	record.ETag = newETag()

	if m.records[record.ScopeID] == nil {
		m.records[record.ScopeID] = make(map[string]*store.AgentRecord)
	}

	stored := copyRecord(record)
	m.records[record.ScopeID][record.ID] = stored

	return copyRecord(stored), nil
}

// Get retrieves a single agent record by ID.
func (m *Store) Get(_ context.Context, scopeID int64, id string) (*store.AgentRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return nil, store.ErrAgentNotFound
	}

	record, ok := scopeRecords[id]
	if !ok {
		return nil, store.ErrAgentNotFound
	}

	return copyRecord(record), nil
}

// GetByPath retrieves an agent record by file path within a scope partition.
func (m *Store) GetByPath(_ context.Context, scopeID int64, path string) (*store.AgentRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return nil, store.ErrAgentNotFound
	}

	for _, record := range scopeRecords {
		if record.Path == path {
			return copyRecord(record), nil
		}
	}

	return nil, store.ErrAgentNotFound
}

// List retrieves all agent records for a scope partition.
func (m *Store) List(_ context.Context, scopeID int64) ([]*store.AgentRecord, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return []*store.AgentRecord{}, nil
	}

	results := make([]*store.AgentRecord, 0, len(scopeRecords))
	for _, record := range scopeRecords {
		results = append(results, copyRecord(record))
	}

	return results, nil
}

// Delete removes a single agent record by ID.
func (m *Store) Delete(_ context.Context, scopeID int64, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	scopeRecords, ok := m.records[scopeID]
	if !ok {
		return store.ErrAgentNotFound
	}

	if _, ok := scopeRecords[id]; !ok {
		return store.ErrAgentNotFound
	}

	delete(scopeRecords, id)

	if len(scopeRecords) == 0 {
		delete(m.records, scopeID)
	}

	return nil
}

// DeleteByScopeID removes all agent records for a given scope partition.
func (m *Store) DeleteByScopeID(_ context.Context, scopeID int64) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	delete(m.records, scopeID)
	return nil
}
