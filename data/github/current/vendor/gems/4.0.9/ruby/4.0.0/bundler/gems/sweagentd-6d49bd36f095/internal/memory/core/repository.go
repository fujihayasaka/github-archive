package core

// RepositoryID represents a unique identifier for a repository.
type RepositoryID uint64

// Repository represents a repository in the context of the memory service.
type Repository struct {
	ID      RepositoryID `json:"id"`
	NWO     RepoNWO      `json:"nwo"`
	Private bool         `json:"private"`
	OwnerID int64        `json:"owner_id"`
}

// GetRepositoryID returns the repository ID as an int64.
func (r *Repository) GetRepositoryID() int64 {
	return int64(r.ID)
}

// GetOwnerID returns the owner ID.
func (r *Repository) GetOwnerID() int64 {
	return r.OwnerID
}

// repositoryWithActor combines a repository with an actor ID to satisfy the sweagentd.RepositoryWithActor interface.
type repositoryWithActor struct {
	*Repository

	actorID int64
}

// GetActorID returns the actor ID.
func (r *repositoryWithActor) GetActorID() int64 {
	return r.actorID
}
