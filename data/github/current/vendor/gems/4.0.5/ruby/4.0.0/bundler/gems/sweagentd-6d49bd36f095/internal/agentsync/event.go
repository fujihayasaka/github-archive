package agentsync

import (
	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	sweagentdv1 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1"
	sweagentdv1entities "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1/entities"
	"github.com/github/sweagentd/internal/agentconfig"
	"github.com/github/sweagentd/internal/goerrors"
	"google.golang.org/protobuf/proto"
)

// ParseAgentsUpdated unmarshals a raw Hydro message into a sweagentd.v1.AgentsUpdated proto.
func ParseAgentsUpdated(msg []byte) (*sweagentdv1.AgentsUpdated, error) {
	message := new(sweagentdv1.AgentsUpdated)
	err := proto.Unmarshal(msg, message)
	if err != nil {
		return nil, goerrors.Errorf("failed to unmarshal AgentsUpdated: %w", err)
	}
	return message, nil
}

// NewSyncEvent creates a SyncEvent from a parsed AgentsUpdated message.
// It determines the scope, scopeID, and directory based on the repository properties.
func NewSyncEvent(msg *sweagentdv1.AgentsUpdated) (*SyncEvent, error) {
	repo := msg.GetRepository()
	if repo == nil {
		return nil, goerrors.New("AgentsUpdated event missing repository")
	}
	if msg.GetCommitSha() == "" {
		return nil, goerrors.New("AgentsUpdated event missing commit_sha")
	}

	repoID := int64(repo.GetId())
	if repoID == 0 {
		return nil, goerrors.New("AgentsUpdated event has zero repository ID")
	}

	ownerID := ownerIDFromRepo(repo)
	ownerLogin := ownerLoginFromMsg(msg)

	scope, scopeID, err := determineScope(repo, ownerID)
	if err != nil {
		return nil, goerrors.Errorf("failed to determine scope: %w", err)
	}

	actorID, actorLogin := actorFromMsg(msg)
	if actorID == 0 {
		return nil, goerrors.New("AgentsUpdated event missing actor ID")
	}
	if actorLogin == "" {
		return nil, goerrors.New("AgentsUpdated event missing actor login")
	}

	event := &SyncEvent{
		Scope:      scope,
		ScopeID:    scopeID,
		RepoID:     repoID,
		RepoName:   repo.GetName(),
		OwnerID:    ownerID,
		OwnerLogin: ownerLogin,
		CommitSHA:  msg.GetCommitSha(),
		Directory:  DirectoryForScope(scope),
		ActorID:    actorID,
		ActorLogin: actorLogin,
		BusinessID: businessIDFromRepo(repo),
	}

	for _, cf := range msg.GetChangedFiles() {
		event.ChangedFiles = append(event.ChangedFiles, toChangedFile(cf))
	}

	return event, nil
}

// determineScope determines the agent scope from the repository properties.
//
// Rules:
//   - If the repo name is ".github" or ".github-private", it's an org-scoped agent repo.
//     ScopeID is the owner ID (which is the org ID).
//   - Otherwise, it's a repository-scoped agent config.
//     ScopeID is the repo ID.
//
// Enterprise scope is NOT determined here. An org-scoped repo (.github/.github-private)
// may also be the enterprise agent config repo. That detection requires a twirp call
// to EnterpriseAgents and is handled in handleEnterpriseSyncIfNeeded. When enterprise
// scope applies, the ScopeID is overridden to the business ID (from Repository.business_id
// in the Hydro event), not the org owner ID.
func determineScope(repo *entities.Repository, ownerID int64) (scope string, scopeID int64, err error) {
	repoName := repo.GetName()
	repoID := int64(repo.GetId())

	if IsOrgAgentRepo(repoName) {
		if ownerID == 0 {
			return "", 0, goerrors.Errorf("org-scoped repo %q has no owner_id", repoName)
		}
		return agentconfig.ScopeOrganization, ownerID, nil
	}

	return agentconfig.ScopeRepository, repoID, nil
}

func ownerIDFromRepo(repo *entities.Repository) int64 {
	if v := repo.GetOwnerId(); v != nil {
		return int64(v.GetValue())
	}
	return 0
}

// businessIDFromRepo extracts the enterprise/business ID from the Repository entity.
// This field is populated by the monolith when the repo's org belongs to an enterprise.
// It is the correct partition key for enterprise-scoped agent records in CosmosDB.
func businessIDFromRepo(repo *entities.Repository) int64 {
	if v := repo.GetBusinessId(); v != nil {
		return int64(v.GetValue())
	}
	return 0
}

func ownerLoginFromMsg(msg *sweagentdv1.AgentsUpdated) string {
	if owner := msg.GetRepositoryOwner(); owner != nil {
		return owner.GetLogin()
	}
	return ""
}

func actorFromMsg(msg *sweagentdv1.AgentsUpdated) (int64, string) {
	if actor := msg.GetActor(); actor != nil {
		return int64(actor.GetId()), actor.GetLogin()
	}
	return 0, ""
}

func toChangedFile(cf *sweagentdv1entities.ChangedFile) ChangedFile {
	return ChangedFile{
		ChangeType:   ChangeType(cf.GetChangeType()),
		CurrentPath:  cf.GetCurrentPath(),
		PreviousPath: cf.GetPreviousPath(),
	}
}
