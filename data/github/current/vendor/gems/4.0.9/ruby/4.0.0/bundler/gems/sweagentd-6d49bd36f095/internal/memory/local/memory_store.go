// Package local provides an in-memory implementation of a repository for managing local data.
package local

import (
	"context"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
)

// MemoryStore is an in-memory implementation of the MemoryStore interface.
type MemoryStore struct {
	mu       sync.RWMutex
	memories map[string]map[core.MemoryID]*core.Memory
}

var _ core.MemoryStore = (*MemoryStore)(nil)

// NewLocalMemoryStore creates a new instance of local MemoryStore.
func NewLocalMemoryStore() core.MemoryStore {
	return &MemoryStore{
		memories: make(map[string]map[core.MemoryID]*core.Memory),
	}
}

// SaveForRepository stores a memory scoped to a repository.
func (r *MemoryStore) SaveForRepository(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	return r.save(repoKey(repoID), memory)
}

// SaveBatchForRepository atomically saves multiple memories scoped to a repository.
func (r *MemoryStore) SaveBatchForRepository(ctx context.Context, repoID core.RepositoryID, memories []*core.Memory) error {
	return r.saveBatch(repoKey(repoID), memories)
}

// FindByRepository retrieves all memories for a given repository.
func (r *MemoryStore) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	return r.findAll(repoKey(repoID))
}

// FindByFactForRepository retrieves memories matching the given fact text within a repository scope.
func (r *MemoryStore) FindByFactForRepository(ctx context.Context, repoID core.RepositoryID, fact string) ([]*core.Memory, error) {
	return r.findByFact(repoKey(repoID), fact)
}

// FindRecentByRepository retrieves the most recent N memories for a given repository.
func (r *MemoryStore) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	return r.findRecent(repoKey(repoID), limit)
}

// DeleteForRepository removes a memory by its ID within a repository scope.
func (r *MemoryStore) DeleteForRepository(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	return r.deleteByID(repoKey(repoID), id)
}

// DeleteBatchForRepository removes specific memories by their IDs within a repository scope.
func (r *MemoryStore) DeleteBatchForRepository(ctx context.Context, repoID core.RepositoryID, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	return r.deleteBatch(repoKey(repoID), ids)
}

// DeleteAllForRepository removes all memories for a given repository.
func (r *MemoryStore) DeleteAllForRepository(ctx context.Context, repoID core.RepositoryID) error {
	return r.deleteAll(repoKey(repoID))
}

// CountByRepository returns the total number of memories stored for a given repository.
func (r *MemoryStore) CountByRepository(ctx context.Context, repoID core.RepositoryID) (int, error) {
	return r.count(repoKey(repoID)), nil
}

// CountByUser returns the total number of memories stored for a given user.
func (r *MemoryStore) CountByUser(ctx context.Context, userID uint64, billingFilter *core.BillingEntity) (int, error) {
	if billingFilter != nil {
		all, err := r.findAll(userKey(userID))
		if err != nil {
			return 0, err
		}
		return len(filterByBilling(all, *billingFilter)), nil
	}
	return r.count(userKey(userID)), nil
}

// SaveForUser stores a memory scoped to a user.
func (r *MemoryStore) SaveForUser(ctx context.Context, userID uint64, memory *core.Memory) error {
	return r.save(userKey(userID), memory)
}

// SaveBatchForUser atomically saves multiple memories scoped to a user.
func (r *MemoryStore) SaveBatchForUser(ctx context.Context, userID uint64, memories []*core.Memory) error {
	return r.saveBatch(userKey(userID), memories)
}

// FindByUser retrieves all memories for a given user.
func (r *MemoryStore) FindByUser(ctx context.Context, userID uint64, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
	all, err := r.findAll(userKey(userID))
	if err != nil {
		return nil, err
	}
	if billingFilter != nil {
		return filterByBilling(all, *billingFilter), nil
	}
	return all, nil
}

// FindByFactForUser retrieves memories matching the given fact text within a user scope.
func (r *MemoryStore) FindByFactForUser(ctx context.Context, userID uint64, fact string) ([]*core.Memory, error) {
	return r.findByFact(userKey(userID), fact)
}

// FindRecentByUser retrieves the most recent N memories for a given user.
func (r *MemoryStore) FindRecentByUser(ctx context.Context, userID uint64, limit uint, billingFilter *core.BillingEntity) ([]*core.Memory, error) {
	if billingFilter != nil {
		all, err := r.findAll(userKey(userID))
		if err != nil {
			return nil, err
		}
		filtered := filterByBilling(all, *billingFilter)
		sort.Slice(filtered, func(i, j int) bool {
			return filtered[i].CreatedAt.After(filtered[j].CreatedAt)
		})
		if uint(len(filtered)) > limit {
			filtered = filtered[:limit]
		}
		return filtered, nil
	}
	return r.findRecent(userKey(userID), limit)
}

// DeleteForUser removes a memory by its ID within a user scope.
func (r *MemoryStore) DeleteForUser(ctx context.Context, userID uint64, id core.MemoryID) error {
	return r.deleteByID(userKey(userID), id)
}

// DeleteBatchForUser removes specific memories by their IDs within a user scope.
func (r *MemoryStore) DeleteBatchForUser(ctx context.Context, userID uint64, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	return r.deleteBatch(userKey(userID), ids)
}

// DeleteAllForUser removes all memories for a given user.
func (r *MemoryStore) DeleteAllForUser(ctx context.Context, userID uint64) error {
	return r.deleteAll(userKey(userID))
}

// ListBillingEntityMemories retrieves one page of user memories filtered by a billing entity.
func (r *MemoryStore) ListBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.MemoryPage, error) {
	if filter.IsZero() {
		return nil, core.ErrInvalidBillingFilter
	}
	if filter.UserID == 0 {
		return nil, core.ErrInvalidUserFilter
	}
	if pageRequest.SnapshotTime.IsZero() {
		return nil, core.ErrInvalidSnapshotTime
	}

	var filtered []*core.Memory
	r.mu.RLock()
	for key, memories := range r.memories {
		if key != userKey(filter.UserID) {
			continue
		}
		for _, memory := range memories {
			if !memory.CreatedAt.After(pageRequest.SnapshotTime) && matchesBillingEntityMemoryFilter(memory, filter) {
				memoryCopy := *memory
				filtered = append(filtered, &memoryCopy)
			}
		}
	}
	r.mu.RUnlock()

	slices.SortFunc(filtered, func(a, b *core.Memory) int {
		if a.Source.User.ID < b.Source.User.ID {
			return -1
		}
		if a.Source.User.ID > b.Source.User.ID {
			return 1
		}
		if a.CreatedAt.Before(b.CreatedAt) {
			return -1
		}
		if a.CreatedAt.After(b.CreatedAt) {
			return 1
		}
		return strings.Compare(a.ID.String(), b.ID.String())
	})

	offset := 0
	if pageRequest.ContinuationToken != "" {
		parsedOffset, parseErr := strconv.Atoi(pageRequest.ContinuationToken)
		if parseErr != nil || parsedOffset < 0 {
			return nil, core.ErrInvalidContinuation
		}
		offset = parsedOffset
	}
	if offset >= len(filtered) || pageRequest.Limit == 0 {
		return &core.MemoryPage{}, nil
	}

	end := min(offset+int(pageRequest.Limit), len(filtered))

	nextToken := ""
	if end < len(filtered) {
		nextToken = strconv.Itoa(end)
	}

	return &core.MemoryPage{
		Memories:          filtered[offset:end],
		ContinuationToken: nextToken,
	}, nil
}

func matchesBillingEntityMemoryFilter(memory *core.Memory, filter core.BillingEntityMemoryFilter) bool {
	if memory == nil {
		return false
	}
	if filter.OrganizationID != 0 && memory.BillingOrganizationID != filter.OrganizationID {
		return false
	}
	if filter.EnterpriseID != 0 && memory.BillingEnterpriseID != filter.EnterpriseID {
		return false
	}
	return true
}

// DeleteBillingEntityMemories deletes one bounded page of user memories filtered by a billing entity.
func (r *MemoryStore) DeleteBillingEntityMemories(ctx context.Context, filter core.BillingEntityMemoryFilter, pageRequest core.MemoryPageRequest) (*core.BillingEntityDeleteResult, error) {
	// Reuse List to find the matching page of memories.
	page, err := r.ListBillingEntityMemories(ctx, filter, pageRequest)
	if err != nil {
		return nil, err
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	key := userKey(filter.UserID)
	var deleted uint
	for _, m := range page.Memories {
		if _, ok := r.memories[key][m.ID]; ok {
			delete(r.memories[key], m.ID)
			deleted++
		}
	}

	// After deletion the offset-based token from List is stale (items shifted).
	// Instead, check whether more matching items remain: if so, return "0" so
	// the caller re-scans from the start; otherwise return empty to signal done.
	nextToken := ""
	if deleted > 0 {
		for _, memory := range r.memories[key] {
			if !memory.CreatedAt.After(pageRequest.SnapshotTime) && matchesBillingEntityMemoryFilter(memory, filter) {
				nextToken = "0"
				break
			}
		}
	}

	return &core.BillingEntityDeleteResult{
		DeletedCount:      deleted,
		ContinuationToken: nextToken,
	}, nil
}

func repoKey(repoID core.RepositoryID) string { return fmt.Sprintf("repo:%d", repoID) }
func userKey(userID uint64) string            { return fmt.Sprintf("user:%d", userID) }

func (r *MemoryStore) save(key string, memory *core.Memory) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if memory == nil {
		return goerrors.New("memory cannot be nil")
	}

	if r.memories[key] == nil {
		r.memories[key] = make(map[core.MemoryID]*core.Memory)
	}

	r.memories[key][memory.ID] = memory
	return nil
}

func (r *MemoryStore) saveBatch(key string, memories []*core.Memory) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	for _, memory := range memories {
		if memory == nil {
			return goerrors.New("memory cannot be nil")
		}
	}

	if r.memories[key] == nil {
		r.memories[key] = make(map[core.MemoryID]*core.Memory)
	}

	for _, memory := range memories {
		r.memories[key][memory.ID] = memory
	}
	return nil
}

func (r *MemoryStore) findByFact(key, fact string) ([]*core.Memory, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	keyMemories, exists := r.memories[key]
	if !exists {
		return nil, nil
	}

	var results []*core.Memory
	for _, memory := range keyMemories {
		if memory.Fact != fact {
			continue
		}
		cp := *memory
		cp.Votes = make([]core.Vote, len(memory.Votes))
		copy(cp.Votes, memory.Votes)
		cp.Citations = make([]string, len(memory.Citations))
		copy(cp.Citations, memory.Citations)
		results = append(results, &cp)
	}

	// Sort by UpdatedAt descending so the most recent is first,
	// matching the Cosmos store ORDER BY c.updated_at DESC behavior.
	slices.SortFunc(results, func(a, b *core.Memory) int {
		if a.UpdatedAt.After(b.UpdatedAt) {
			return -1
		}
		if a.UpdatedAt.Before(b.UpdatedAt) {
			return 1
		}
		return 0
	})

	return results, nil
}

func (r *MemoryStore) count(key string) int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.memories[key])
}

func (r *MemoryStore) findAll(key string) ([]*core.Memory, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	keyMemories, exists := r.memories[key]
	if !exists {
		return []*core.Memory{}, nil
	}

	var results []*core.Memory
	for _, memory := range keyMemories {
		results = append(results, memory)
	}
	return results, nil
}

func (r *MemoryStore) findRecent(key string, limit uint) ([]*core.Memory, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	if limit <= 0 {
		limit = 10
	}

	keyMemories, exists := r.memories[key]
	if !exists {
		return []*core.Memory{}, nil
	}

	var results []*core.Memory
	for _, memory := range keyMemories {
		results = append(results, memory)
	}

	// Keep newest memories first so the limit returns the most recent entries.
	slices.SortFunc(results, func(a, b *core.Memory) int {
		if a.CreatedAt.After(b.CreatedAt) {
			return -1
		}
		if a.CreatedAt.Before(b.CreatedAt) {
			return 1
		}
		return 0
	})

	if len(results) > int(limit) {
		results = results[:limit]
	}

	return results, nil
}

func (r *MemoryStore) deleteByID(key string, id core.MemoryID) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	keyMemories, exists := r.memories[key]
	if !exists {
		return core.ErrMemoryNotFound
	}

	if _, exists := keyMemories[id]; !exists {
		return core.ErrMemoryNotFound
	}
	delete(keyMemories, id)

	if len(keyMemories) == 0 {
		delete(r.memories, key)
	}
	return nil
}

func (r *MemoryStore) deleteBatch(key string, ids []core.MemoryID) (*core.BatchDeleteResult, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	keyMemories, exists := r.memories[key]
	if exists {
		for _, id := range ids {
			delete(keyMemories, id)
		}

		if len(keyMemories) == 0 {
			delete(r.memories, key)
		}
	}

	return &core.BatchDeleteResult{Deleted: ids}, nil
}

func (r *MemoryStore) deleteAll(key string) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	delete(r.memories, key)
	return nil
}

func filterByBilling(memories []*core.Memory, filter core.BillingEntity) []*core.Memory {
	var result []*core.Memory
	for _, m := range memories {
		if m.BillingOrganizationID == filter.OrganizationID && m.BillingEnterpriseID == filter.EnterpriseID {
			result = append(result, m)
		}
	}
	return result
}
