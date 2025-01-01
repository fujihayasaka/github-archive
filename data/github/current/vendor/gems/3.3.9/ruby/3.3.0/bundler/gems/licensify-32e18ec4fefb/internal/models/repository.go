package models

import (
	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// RepositoryVisibility represents the visibility of a repository.
type RepositoryVisibility int32

const (
	// RepositoryVisibilityUnknown represents an unknown repository visibility.
	RepositoryVisibilityUnknown RepositoryVisibility = 0
	// RepositoryVisibilityPublic represents a public repository visibility.
	RepositoryVisibilityPublic RepositoryVisibility = 1
	// RepositoryVisibilityPrivate represents a private repository visibility.
	RepositoryVisibilityPrivate RepositoryVisibility = 2
	// RepositoryVisibilityInternal represents an internal repository visibility.
	RepositoryVisibilityInternal RepositoryVisibility = 3
)

func (rv RepositoryVisibility) String() string {
	switch rv {
	case RepositoryVisibilityPublic:
		return "public"
	case RepositoryVisibilityPrivate:
		return "private"
	case RepositoryVisibilityInternal:
		return "internal"
	default:
		return "unknown"
	}
}

// Repository represents details of a repository based on incoming Hydro events.
type Repository struct {
	ID                  uint64
	Visibility          RepositoryVisibility
	ParentID            uint32
	CustomerID          uint64
	IsAdvisoryWorkspace bool
	IsFork              bool
	IsActive            bool
	CollaboratorIDs     []uint64
}

// GetLoggerFields returns a list of relevant fields for logging.
func (r *Repository) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("gh.licensify.repository.id", r.ID),
		kvp.Uint64("gh.licensify.repository.customer_id", r.CustomerID),
		kvp.String("gh.licensify.repository.visibility", r.Visibility.String()),
		kvp.Uint32("gh.licensify.repository.parent_id", r.ParentID),
		kvp.Bool("gh.licensify.repository.is_advisory_workspace", r.IsAdvisoryWorkspace),
		kvp.Bool("gh.licensify.repository.is_fork", r.IsFork),
		kvp.Bool("gh.licensify.repository.is_active", r.IsActive),
		kvp.Uint64s("gh.licensify.repository.collaborator_ids", r.CollaboratorIDs),
	}
}

// MissingRequiredIDs checks if the repository is missing the needed IDs in order
// be processed & queried.
func (r *Repository) MissingRequiredIDs() bool {
	return r.ID == 0 || r.CustomerID == 0
}

// IsPublic checks if the repository is public.
func (r *Repository) IsPublic() bool {
	return r.Visibility == RepositoryVisibilityPublic
}

// VisibilityConsumesLicenses checks if the repository visibility consumes licenses.
func (r *Repository) VisibilityConsumesLicenses() bool {
	return r.Visibility == RepositoryVisibilityPrivate ||
		r.Visibility == RepositoryVisibilityInternal
}

// FeaturesDoNotConsumeLicenses checks if the repository features do not consume licenses.
func (r *Repository) FeaturesDoNotConsumeLicenses() bool {
	return r.IsAdvisoryWorkspace || r.Fork()
}

// Fork checks if the repository is a fork.
func (r *Repository) Fork() bool {
	return r.IsFork || r.ParentID != 0
}

// HasCollaborators checks if the repository has collaborators.
func (r *Repository) HasCollaborators() bool {
	return len(r.CollaboratorIDs) > 0
}
