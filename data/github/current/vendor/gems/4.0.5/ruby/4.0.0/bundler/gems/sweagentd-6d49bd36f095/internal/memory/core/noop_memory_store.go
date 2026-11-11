package core

import "context"

type noopMemoryStore struct{}

// NewNoopMemoryStore creates a new noopMemoryStore instance.
func NewNoopMemoryStore() MemoryStore {
	return &noopMemoryStore{}
}

func (r *noopMemoryStore) SaveForRepository(ctx context.Context, repoID RepositoryID, memory *Memory) error {
	return nil
}

func (r *noopMemoryStore) SaveBatchForRepository(ctx context.Context, repoID RepositoryID, memories []*Memory) error {
	return nil
}

func (r *noopMemoryStore) FindByRepository(ctx context.Context, repoID RepositoryID) ([]*Memory, error) {
	return []*Memory{}, nil
}

func (r *noopMemoryStore) FindByFactForRepository(ctx context.Context, repoID RepositoryID, fact string) ([]*Memory, error) {
	return nil, nil
}

func (r *noopMemoryStore) FindRecentByRepository(ctx context.Context, repoID RepositoryID, limit uint) ([]*Memory, error) {
	return []*Memory{}, nil
}

func (r *noopMemoryStore) DeleteForRepository(ctx context.Context, repoID RepositoryID, id MemoryID) error {
	return nil
}

func (r *noopMemoryStore) DeleteBatchForRepository(ctx context.Context, repoID RepositoryID, ids []MemoryID) (*BatchDeleteResult, error) {
	return &BatchDeleteResult{Deleted: ids}, nil
}

func (r *noopMemoryStore) DeleteAllForRepository(ctx context.Context, repoID RepositoryID) error {
	return nil
}

func (r *noopMemoryStore) CountByRepository(ctx context.Context, repoID RepositoryID) (int, error) {
	return 0, nil
}

func (r *noopMemoryStore) CountByUser(ctx context.Context, userID uint64, billingFilter *BillingEntity) (int, error) {
	return 0, nil
}

func (r *noopMemoryStore) SaveForUser(ctx context.Context, userID uint64, memory *Memory) error {
	return nil
}

func (r *noopMemoryStore) SaveBatchForUser(ctx context.Context, userID uint64, memories []*Memory) error {
	return nil
}

func (r *noopMemoryStore) FindByUser(ctx context.Context, userID uint64, billingFilter *BillingEntity) ([]*Memory, error) {
	return []*Memory{}, nil
}

func (r *noopMemoryStore) FindByFactForUser(ctx context.Context, userID uint64, fact string) ([]*Memory, error) {
	return nil, nil
}

func (r *noopMemoryStore) FindRecentByUser(ctx context.Context, userID uint64, limit uint, billingFilter *BillingEntity) ([]*Memory, error) {
	return []*Memory{}, nil
}

func (r *noopMemoryStore) DeleteForUser(ctx context.Context, userID uint64, id MemoryID) error {
	return nil
}

func (r *noopMemoryStore) DeleteBatchForUser(ctx context.Context, userID uint64, ids []MemoryID) (*BatchDeleteResult, error) {
	return &BatchDeleteResult{Deleted: ids}, nil
}

func (r *noopMemoryStore) DeleteAllForUser(ctx context.Context, userID uint64) error {
	return nil
}

func (r *noopMemoryStore) ListBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*MemoryPage, error) {
	return &MemoryPage{}, nil
}

func (r *noopMemoryStore) DeleteBillingEntityMemories(ctx context.Context, filter BillingEntityMemoryFilter, pageRequest MemoryPageRequest) (*BillingEntityDeleteResult, error) {
	return &BillingEntityDeleteResult{}, nil
}
