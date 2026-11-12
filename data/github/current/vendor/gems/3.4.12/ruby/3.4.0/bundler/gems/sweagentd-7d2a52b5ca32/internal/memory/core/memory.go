// Package core provides types and functions for managing memory identifiers.
package core

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
)

// MemoryID represents a unique identifier for a memory resource.
type MemoryID string

// NewMemoryID generates a new MemoryID.
func NewMemoryID() MemoryID {
	return MemoryID(uuid.NewString())
}

// String returns the string representation of the MemoryID.
func (id MemoryID) String() string {
	return string(id)
}

// RepoNWO represents a repository identifier in the format of "owner/repo".
type RepoNWO struct {
	Owner string
	Repo  string
}

// NewRepoNWO creates a new RepoNWO instance from owner and repo strings.
func NewRepoNWO(owner, repo string) (*RepoNWO, error) {
	if owner == "" {
		return nil, ErrEmptyRepoOwner
	}
	if repo == "" {
		return nil, ErrEmptyRepoName
	}
	return &RepoNWO{
		Owner: owner,
		Repo:  repo,
	}, nil
}

// NewRepoNWOFromString parses a string in the format "owner/repo" into a RepoNWO struct.
func NewRepoNWOFromString(nwo string) (*RepoNWO, error) {
	if nwo == "" {
		return nil, ErrEmptyRepoNWO
	}
	parts := strings.SplitN(nwo, "/", 2)
	if len(parts) != 2 {
		return nil, ErrInvalidRepoNWO
	}
	return &RepoNWO{
		Owner: parts[0],
		Repo:  parts[1],
	}, nil
}

// String returns the string representation of the RepoNWO.
func (r RepoNWO) String() string {
	return r.Owner + "/" + r.Repo
}

// User represents a user in the context of a memory operation.
type User struct {
	ID    uint64 `json:"id"`
	Login string `json:"login"`
}

// NewUser creates a new User instance.
func NewUser(id uint64, login string) User {
	return User{
		ID:    id,
		Login: login,
	}
}

type MemorySource struct {
	InteractionID string  `json:"interactionId"`
	NWO           RepoNWO `json:"nwo"`
	User          User    `json:"user"`
	Agent         string  `json:"agent"`
}

type Memory struct {
	ID        MemoryID     `json:"id"`
	Subject   string       `json:"subject"`
	Fact      string       `json:"fact"`
	Citations []string     `json:"citations"`
	Reason    string       `json:"reason"`
	Source    MemorySource `json:"source"`
	CreatedAt time.Time    `json:"createdAt"`
}

// NewMemory creates a new Memory instance with the given parameters.
func NewMemory(id MemoryID, subject, fact, reason string, citations []string, source MemorySource) *Memory {
	return &Memory{
		ID:        id,
		Subject:   subject,
		Fact:      fact,
		Citations: citations,
		Reason:    reason,
		Source:    source,
	}
}

// MemoryRepository defines the interface for memory storage operations.
type MemoryRepository interface {
	Save(ctx context.Context, repoID RepositoryID, memory *Memory) error
	FindByID(ctx context.Context, repoID RepositoryID, id MemoryID) (*Memory, error)
	FindByRepository(ctx context.Context, repoID RepositoryID) ([]*Memory, error)
	FindRecentByRepository(ctx context.Context, repoID RepositoryID, limit uint) ([]*Memory, error)
	Delete(ctx context.Context, repoID RepositoryID, id MemoryID) error
}

// Errors
var (
	ErrMemoryNotFound = errors.New("memory not found")
	ErrInvalidRepoNWO = errors.New("invalid repository NWO format")
	ErrEmptyRepoNWO   = errors.New("repository NWO cannot be empty")
	ErrEmptyRepoOwner = errors.New("repository owner cannot be empty")
	ErrEmptyRepoName  = errors.New("repository name cannot be empty")
	ErrUnauthorized   = errors.New("unauthorized access")
)
