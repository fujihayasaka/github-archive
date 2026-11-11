package core

import "context"

type noopMemoryRepository struct{}

// NewNoopMemoryRepository creates a new noopMemoryRepository instance.
func NewNoopMemoryRepository() MemoryRepository {
	return &noopMemoryRepository{}
}

// Save saves a memory to the repository.
func (r *noopMemoryRepository) Save(ctx context.Context, repoID RepositoryID, memory *Memory) error {
	// No operation for noop repository
	return nil
}

// FindByID retrieves a memory by its ID from the repository.
func (r *noopMemoryRepository) FindByID(ctx context.Context, repoID RepositoryID, id MemoryID) (*Memory, error) {
	// No operation for noop repository
	return nil, nil
}

// FindByRepository retrieves all memories from the repository.
func (r *noopMemoryRepository) FindByRepository(ctx context.Context, repoID RepositoryID) ([]*Memory, error) {
	// No operation for noop repository
	return make([]*Memory, 0), nil
}

// FindRecentByRepository retrieves the most recent N memories from the repository.
func (r *noopMemoryRepository) FindRecentByRepository(ctx context.Context, repoID RepositoryID, limit uint) ([]*Memory, error) {
	// No operation for noop repository
	return make([]*Memory, 0), nil
}

// Delete removes a memory from the repository.
func (r *noopMemoryRepository) Delete(ctx context.Context, repoID RepositoryID, id MemoryID) error {
	// No operation for noop repository
	return nil
}
