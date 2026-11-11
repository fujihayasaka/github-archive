// Package agentsync handles syncing custom agent configurations from GitHub
// repositories to CosmosDB. It consumes sweagentd.v1.AgentsUpdated Hydro events
// and reconciles agent config files with the persistent store.
//
// The package is structured to allow reuse of core syncing logic (file fetching,
// reconciliation) for other file types in the .github/agents directory in the
// future, without being tightly coupled to the specific agent config format.
package agentsync

import (
	"context"

	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/sweagentd"
)

// Directory constants for agent config file locations.
const (
	// RepoAgentsDir is the directory within a repository where custom agent configs live.
	RepoAgentsDir = ".github/agents"
	// OrgAgentsDir is the directory within org/enterprise repos where privileged agent configs live.
	OrgAgentsDir = "agents"
)

// orgRepoNames are the repository names that indicate an org-scoped agent repository.
var orgRepoNames = map[string]bool{
	".github":         true,
	".github-private": true,
}

// IsOrgAgentRepo returns true if the repository name indicates an org-scoped agent repository.
func IsOrgAgentRepo(repoName string) bool {
	return orgRepoNames[repoName]
}

// DirectoryForScope returns the correct agent config directory for the given scope.
func DirectoryForScope(scope string) string {
	if scope == agentconfig.ScopeRepository {
		return RepoAgentsDir
	}
	return OrgAgentsDir
}

// SyncEvent represents a parsed and validated AgentsUpdated event ready for processing.
type SyncEvent struct {
	// Scope is one of "repository", "organization", or "enterprise".
	Scope string
	// ScopeID is the CosmosDB partition key. Its meaning depends on Scope:
	//   - repository:   the repo ID
	//   - organization: the owner (org) ID
	//   - enterprise:   the business ID (from Repository.business_id in the Hydro entity)
	//
	// For enterprise scope, the business ID is the correct partition key — NOT the
	// org owner ID. The Hydro Repository entity carries business_id when the repo's
	// org belongs to an enterprise. See handleEnterpriseSyncIfNeeded for details.
	ScopeID int64
	// RepoID is the GitHub repository ID where the files live.
	RepoID int64
	// RepoName is the repository name.
	RepoName string
	// OwnerID is the repository owner's user/org ID.
	OwnerID int64
	// OwnerLogin is the repository owner's login.
	OwnerLogin string
	// CommitSHA is the commit that triggered the event.
	CommitSHA string
	// ChangedFiles is the list of files changed in the push.
	ChangedFiles []ChangedFile
	// ActorID is the user ID of the pusher.
	ActorID int64
	// ActorLogin is the login of the pusher.
	ActorLogin string
	// BusinessID is the enterprise/business ID from the Hydro Repository entity
	// (Repository.business_id). This is set when the repo's org belongs to an
	// enterprise. Used as the ScopeID for enterprise-scoped records — the
	// EnterpriseAgentsResponse twirp proto only returns repository_id, so
	// business_id must come from the Hydro event itself.
	BusinessID int64
	// Directory is the directory to scan for agent files.
	Directory string
}

// GetRepositoryID implements sweagentd.Repository.
func (e *SyncEvent) GetRepositoryID() int64 { return e.RepoID }

// GetOwnerID implements sweagentd.Repository.
func (e *SyncEvent) GetOwnerID() int64 { return e.OwnerID }

// ChangedFile represents a file change in a push.
type ChangedFile struct {
	ChangeType   ChangeType
	CurrentPath  string
	PreviousPath string
}

// ChangeType represents the type of file change.
type ChangeType int

// Change type constants.
const (
	ChangeTypeUnknown      ChangeType = 0
	ChangeTypeAddition     ChangeType = 1
	ChangeTypeModification ChangeType = 2
	ChangeTypeDeletion     ChangeType = 3
	ChangeTypeRename       ChangeType = 4
)

// HasOnlyModifications returns true if all changed files are modifications
// (no additions, deletions, or renames). This enables an optimization where
// we skip the full directory listing and only update changed files.
func (e *SyncEvent) HasOnlyModifications() bool {
	if len(e.ChangedFiles) == 0 {
		return false
	}
	for _, f := range e.ChangedFiles {
		if f.ChangeType != ChangeTypeModification {
			return false
		}
	}
	return true
}

// AgentStore defines the operations the sync service needs from the agent config store.
// Implementations include cosmos.Store (production) and memory.Store (testing).
type AgentStore interface {
	List(ctx context.Context, scopeID int64) ([]*store.AgentRecord, error)
	Upsert(ctx context.Context, record *store.AgentRecord) (*store.AgentRecord, error)
	Delete(ctx context.Context, scopeID int64, id string) error
}

// FileReader defines the operations the sync service needs for reading files from git.
type FileReader interface {
	ListTrees(ctx context.Context, repoID uint64, path string) ([]*sweagentd.SpokesObject, string, error)
	ReadBlobObjects(ctx context.Context, repoID uint64, oids []string) ([][]byte, error)
	ReadBlobByObjectIDPath(ctx context.Context, repoID uint64, oid, path string) ([]byte, error)
}

// SyncResult contains the outcome of a reconciliation operation.
type SyncResult struct {
	Added   int
	Updated int
	Deleted int
	Errors  int
}
