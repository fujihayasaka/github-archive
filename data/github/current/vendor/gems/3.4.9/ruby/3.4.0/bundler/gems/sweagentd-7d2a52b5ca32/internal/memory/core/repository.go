package core

import "context"

// RepositoryID represents a unique identifier for a repository.
type RepositoryID uint64

// Repository represents a repository in the context of the memory service.
type Repository struct {
	ID      RepositoryID `json:"id"`
	NWO     RepoNWO      `json:"nwo"`
	Private bool         `json:"private"`
}

// RepositoryStore defines the interface for repository operations.type
type RepositoryStore interface {
	FindByNWO(ctx context.Context, nwo RepoNWO) (*Repository, error)
}
