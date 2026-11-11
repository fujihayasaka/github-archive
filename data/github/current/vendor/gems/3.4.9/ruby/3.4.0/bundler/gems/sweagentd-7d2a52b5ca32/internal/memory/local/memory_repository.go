// Package memorylocal provides an in-memory implementation of a repository for managing local data.
package memorylocal

import (
	"context"
	"errors"
	"slices"
	"sync"

	"github.com/github/sweagentd/internal/memory/core"
)

// LocalMemoryRepository is an in-memory implementation of the MemoryRepository interface.
type LocalMemoryRepository struct {
	mu       sync.RWMutex
	memories map[core.RepositoryID]map[core.MemoryID]*core.Memory // key is repository ID, value is map of memory ID to memory
}

var _ core.MemoryRepository = (*LocalMemoryRepository)(nil)

// NewLocalMemoryRepository creates a new instance of LocalMemoryRepository.
func NewLocalMemoryRepository() core.MemoryRepository {
	return &LocalMemoryRepository{
		memories: make(map[core.RepositoryID]map[core.MemoryID]*core.Memory),
	}
}

// Save stores a memory in the repository.
func (r *LocalMemoryRepository) Save(ctx context.Context, repoID core.RepositoryID, memory *core.Memory) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if memory == nil {
		return errors.New("memory cannot be nil")
	}

	// Initialize repository map if it doesn't exist
	if r.memories[repoID] == nil {
		r.memories[repoID] = make(map[core.MemoryID]*core.Memory)
	}

	r.memories[repoID][memory.ID] = memory
	return nil
}

// FindByID retrieves a memory by its ID and repository ID.
func (r *LocalMemoryRepository) FindByID(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) (*core.Memory, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	repoMemories, exists := r.memories[repoID]
	if !exists {
		return nil, core.ErrMemoryNotFound
	}

	memory, exists := repoMemories[id]
	if !exists {
		return nil, core.ErrMemoryNotFound
	}
	return memory, nil
}

// FindByRepository retrieves all memories for a given repository ID.
func (r *LocalMemoryRepository) FindByRepository(ctx context.Context, repoID core.RepositoryID) ([]*core.Memory, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	repoMemories, exists := r.memories[repoID]
	if !exists {
		return []*core.Memory{}, nil
	}

	var results []*core.Memory
	for _, memory := range repoMemories {
		results = append(results, memory)
	}
	return results, nil
}

// FindRecentByRepository retrieves the most recent N memories for a given repository ID.
func (r *LocalMemoryRepository) FindRecentByRepository(ctx context.Context, repoID core.RepositoryID, limit uint) ([]*core.Memory, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	// Default limit to 10 if not specified or invalid
	if limit <= 0 {
		limit = 10
	}

	repoMemories, exists := r.memories[repoID]
	if !exists {
		return []*core.Memory{}, nil
	}

	var results []*core.Memory
	for _, memory := range repoMemories {
		results = append(results, memory)
	}

	// Sort by creation time descending (most recent first)
	// Use slices.SortFunc to sort by CreatedAt descending
	slices.SortFunc(results, func(a, b *core.Memory) int {
		if a.CreatedAt.After(b.CreatedAt) {
			return -1
		}
		if a.CreatedAt.Before(b.CreatedAt) {
			return 1
		}
		return 0
	})

	// Limit the results
	if len(results) > int(limit) {
		results = results[:limit]
	}

	return results, nil
}

// Delete removes a memory by its ID.
func (r *LocalMemoryRepository) Delete(ctx context.Context, repoID core.RepositoryID, id core.MemoryID) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	repoMemories, exists := r.memories[repoID]
	if !exists {
		return core.ErrMemoryNotFound
	}

	if _, exists := repoMemories[id]; !exists {
		return core.ErrMemoryNotFound
	}
	delete(repoMemories, id)

	// Clean up empty repository map if no memories left
	if len(repoMemories) == 0 {
		delete(r.memories, repoID)
	}
	return nil
}
