package sweagentd

// Repository represents a GitHub repository with methods to access its ID and owner ID.
type Repository interface {
	GetRepositoryID() int64
	GetOwnerID() int64
}

// RepositoryWithActor extends Repository to include a method for accessing the actor ID.
type RepositoryWithActor interface {
	Actor
	Repository
}

// RepositoryWithName extends Repository to include a method for accessing the repository name.
type RepositoryWithName interface {
	Repository
	GetRepositoryName() string
}

// RepositoryAdapter adapts repository and owner IDs to the Repository interface.
type RepositoryAdapter struct {
	RepoID  int64
	OwnerID int64
}

// GetRepositoryID returns the repository ID.
func (r *RepositoryAdapter) GetRepositoryID() int64 { return r.RepoID }

// GetOwnerID returns the owner ID.
func (r *RepositoryAdapter) GetOwnerID() int64 { return r.OwnerID }
