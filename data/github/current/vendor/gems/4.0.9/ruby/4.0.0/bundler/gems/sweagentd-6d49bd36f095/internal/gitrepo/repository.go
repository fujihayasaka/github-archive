// Package gitrepo provides functionality for fetching repositories from GitHub.
// This is used by both the customagent and skills package to fetch content from the repositories,
// namely the configuration files that define the agents and skills.
package gitrepo

import "context"

// SHA length constants for git hashes
const (
	SHA1Length   = 40
	SHA256Length = 64
)

// Repo represents basic repository information.
type Repo interface {
	GetID() int64
	GetName() string
	GetOwnerID() int64
	GetOwnerName() string
}

// RepoProvider abstracts fetching repository metadata.
type RepoProvider interface {
	GetRepository(ctx context.Context, owner, repo string) (Repo, error)
	GetRepositoryByID(ctx context.Context, repoID int64) (Repo, error)
}

// IsValidSHA checks if a version string is a valid SHA (either SHA1 or SHA256).
func IsValidSHA(version string) bool {
	return len(version) == SHA1Length || len(version) == SHA256Length
}
