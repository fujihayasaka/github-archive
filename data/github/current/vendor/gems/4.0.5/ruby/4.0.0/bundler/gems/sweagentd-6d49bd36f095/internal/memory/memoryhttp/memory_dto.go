package memoryhttp

import (
	"strings"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// Vote request field length limits.
const (
	maxVoteAgentLength     = 256
	maxVoteCommitSHALength = 256
	maxVoteFactLength      = 10000
	maxVoteReasonLength    = 10000
)

// VoteRequest represents the request body for voting on a memory.
type VoteRequest struct {
	Fact          string `json:"fact"`
	Direction     string `json:"direction"` // "upvote" or "downvote"
	Agent         string `json:"agent"`
	Reason        string `json:"reason"`
	CommitSHA     string `json:"commitSha,omitempty"`
	BaseModel     string `json:"baseModel,omitempty"`
	InteractionID string `json:"interactionId,omitempty"`
}

// Validate checks that all VoteRequest fields are well-formed.
func (v *VoteRequest) Validate() error {
	if strings.TrimSpace(v.Fact) == "" {
		return goerrors.New("fact cannot be empty")
	}
	if len(v.Fact) > maxVoteFactLength {
		return goerrors.Errorf("fact must be at most %d characters", maxVoteFactLength)
	}
	_, err := v.parseDirection()
	if err != nil {
		return err
	}
	if strings.TrimSpace(v.Reason) == "" {
		return goerrors.New("reason cannot be empty")
	}
	if len(v.Reason) > maxVoteReasonLength {
		return goerrors.Errorf("reason must be at most %d characters", maxVoteReasonLength)
	}
	if len(v.Agent) > maxVoteAgentLength {
		return goerrors.Errorf("agent must be at most %d characters", maxVoteAgentLength)
	}
	if len(v.CommitSHA) > maxVoteCommitSHALength {
		return goerrors.Errorf("commitSha must be at most %d characters", maxVoteCommitSHALength)
	}
	return nil
}

// ToDomain converts the DTO to the core Vote type.
// When repository is nil (user-scoped voting), RepoNWO is left as its zero value.
func (v *VoteRequest) ToDomain(user *requestctx.UserInfo, repository *core.Repository) (*core.Vote, error) {
	err := v.Validate()
	if err != nil {
		return nil, err
	}
	direction, _ := v.parseDirection() // already validated
	vote := &core.Vote{
		Direction: direction,
		Timestamp: time.Now().UTC(),
		Source: core.VoteSource{
			Agent:         v.Agent,
			CommitSHA:     v.CommitSHA,
			UserID:        user.ID,
			UserLogin:     user.Login,
			BaseModel:     v.BaseModel,
			InteractionID: v.InteractionID,
			Reason:        v.Reason,
		},
	}
	if repository != nil {
		vote.Source.RepoNWO = repository.NWO
	}
	return vote, nil
}

// parseDirection converts the string Direction to a core.VoteValue.
func (v *VoteRequest) parseDirection() (core.VoteValue, error) {
	switch strings.ToLower(v.Direction) {
	case "upvote":
		return core.UpVote, nil
	case "downvote":
		return core.DownVote, nil
	default:
		return 0, goerrors.New("direction must be \"upvote\" or \"downvote\"")
	}
}

// MemoryEnablementResponse represents the response body for checking memory enablement.
type MemoryEnablementResponse struct {
	Enabled bool `json:"enabled"`
}

// BatchDeleteRequest represents the request body for batch-deleting memories by ID.
type BatchDeleteRequest struct {
	IDs []string `json:"ids"`
}

// BatchDeleteResponse represents the response body for a batch-delete operation,
// reporting which IDs were successfully deleted and which failed.
type BatchDeleteResponse struct {
	Deleted []string `json:"deleted"`
	Failed  []string `json:"failed"`
}

// MemorySourceDTO represents the source information of a memory.
type MemorySourceDTO struct {
	InteractionID string `json:"interactionId"`
	Agent         string `json:"agent"`
	CommitSHA     string `json:"commitSha,omitempty"`
	BaseModel     string `json:"baseModel,omitempty"`
}

// MemoryDTO represents a memory data transfer object.
// It is used to transfer memory data between the service layer and the HTTP layer.
type MemoryDTO struct {
	ID                    string          `json:"id"`
	Subject               string          `json:"subject"`
	Fact                  string          `json:"fact"`
	Citations             []string        `json:"citations"`
	Reason                string          `json:"reason"`
	Source                MemorySourceDTO `json:"source"`
	Scope                 string          `json:"scope"`
	BillingOrganizationID uint64          `json:"billingOrganizationId,omitempty"`
	BillingEnterpriseID   uint64          `json:"billingEnterpriseId,omitempty"`
}

// Validate MemoryDTO fields are well-formed.
// Citations is the only field that is validated.
func (m *MemoryDTO) Validate() error {
	if len(m.Citations) == 0 {
		return goerrors.New("citations cannot be empty")
	}
	allEmpty := true
	for _, c := range m.Citations {
		if strings.TrimSpace(c) != "" {
			allEmpty = false
			break
		}
	}
	if allEmpty {
		return goerrors.New("citations must not all be empty strings")
	}
	return nil
}

// ToDomain converts a MemoryDTO to a core.Memory domain object.
func (m *MemoryDTO) ToDomain(nwo core.RepoNWO, user requestctx.UserInfo) (*core.Memory, error) {
	err := m.Validate()
	if err != nil {
		return nil, err
	}
	var memoryID core.MemoryID
	if m.ID != "" {
		memoryID = core.MemoryID(m.ID)
	} else {
		memoryID = core.NewMemoryID() // Generate a new ID if not provided
	}
	source := core.MemorySource{
		InteractionID: m.Source.InteractionID,
		NWO:           nwo,
		Agent:         m.Source.Agent,
		CommitSHA:     m.Source.CommitSHA,
		BaseModel:     m.Source.BaseModel,
		User: core.User{
			ID:    user.ID,
			Login: user.Login,
		},
	}
	return core.NewMemory(memoryID, m.Subject, m.Fact, m.Reason, m.Citations, source), nil
}

// FromDomain converts a core.Memory domain object to a MemoryDTO.
func FromDomain(memory *core.Memory) *MemoryDTO {
	return &MemoryDTO{
		ID:        memory.ID.String(),
		Subject:   memory.Subject,
		Fact:      memory.Fact,
		Citations: memory.Citations,
		Reason:    memory.Reason,
		Source: MemorySourceDTO{
			InteractionID: memory.Source.InteractionID,
			Agent:         memory.Source.Agent,
			CommitSHA:     memory.Source.CommitSHA,
			BaseModel:     memory.Source.BaseModel,
		},
		Scope:                 string(memory.Scope),
		BillingOrganizationID: memory.BillingOrganizationID,
		BillingEnterpriseID:   memory.BillingEnterpriseID,
	}
}

// VerboseVoteDTO is the verbose representation of a vote, exposed only to staff users.
type VerboseVoteDTO struct {
	Direction string               `json:"direction"`
	Timestamp time.Time            `json:"timestamp"`
	Source    VerboseVoteSourceDTO `json:"source"`
}

// VerboseVoteSourceDTO is the verbose representation of a vote source.
type VerboseVoteSourceDTO struct {
	Agent         string `json:"agent,omitempty"`
	RepoNWO       string `json:"repoNwo,omitempty"`
	CommitSHA     string `json:"commitSha,omitempty"`
	InteractionID string `json:"interactionId,omitempty"`
	UserID        uint64 `json:"userId,omitempty"`
	UserLogin     string `json:"userLogin,omitempty"`
	BaseModel     string `json:"baseModel,omitempty"`
	Reason        string `json:"reason,omitempty"`
}

// maxVerboseVotes is the maximum number of votes returned in a verbose response.
// Only the most recent votes are included; TotalVoteCount reports the full count.
const maxVerboseVotes = 10

// VerboseMemoryDTO is an extended memory representation returned to verified staff users.
// It embeds the base MemoryDTO and adds internal diagnostics.
type VerboseMemoryDTO struct {
	*MemoryDTO

	Score          float64          `json:"score"`
	Votes          []VerboseVoteDTO `json:"votes"`
	TotalVoteCount int              `json:"totalVoteCount"`
	CreatedAt      time.Time        `json:"createdAt"`
	UpdatedAt      time.Time        `json:"updatedAt"`
	ExpiresAt      time.Time        `json:"expiresAt"`
}

// VerboseFromDomain converts a core.Memory to a VerboseMemoryDTO.
// Only the most recent maxVerboseVotes votes are included in the response;
// TotalVoteCount always reflects the full count.
func VerboseFromDomain(memory *core.Memory) *VerboseMemoryDTO {
	totalVotes := len(memory.Votes)

	// Take only the most recent votes (votes are appended chronologically).
	recentVotes := memory.Votes
	if len(recentVotes) > maxVerboseVotes {
		recentVotes = recentVotes[len(recentVotes)-maxVerboseVotes:]
	}

	votes := make([]VerboseVoteDTO, len(recentVotes))
	for i, v := range recentVotes {
		dir := "upvote"
		if v.Direction == core.DownVote {
			dir = "downvote"
		}
		votes[i] = VerboseVoteDTO{
			Direction: dir,
			Timestamp: v.Timestamp,
			Source: VerboseVoteSourceDTO{
				Agent:         v.Source.Agent,
				RepoNWO:       repoNWOString(v.Source.RepoNWO),
				CommitSHA:     v.Source.CommitSHA,
				InteractionID: v.Source.InteractionID,
				UserID:        v.Source.UserID,
				UserLogin:     v.Source.UserLogin,
				BaseModel:     v.Source.BaseModel,
				Reason:        v.Source.Reason,
			},
		}
	}
	now := time.Now().UTC()
	return &VerboseMemoryDTO{
		MemoryDTO:      FromDomain(memory),
		Score:          memory.Score(now),
		Votes:          votes,
		TotalVoteCount: totalVotes,
		CreatedAt:      memory.CreatedAt,
		UpdatedAt:      memory.UpdatedAt,
		ExpiresAt:      memory.ExpiresAt,
	}
}

// repoNWOString returns the string form of a RepoNWO, or empty string for
// zero-value NWOs so that omitempty correctly omits the field.
func repoNWOString(nwo core.RepoNWO) string {
	if nwo == (core.RepoNWO{}) {
		return ""
	}
	return nwo.String()
}

// PromptVersion represents a semver version identifier for a prompt.
type PromptVersion string

// StoreInstructionsPrompt contains the LLM prompt for when/how to use the store_memory tool.
type StoreInstructionsPrompt struct {
	Prompt        string        `json:"prompt"`
	PromptVersion PromptVersion `json:"promptVersion"`
}

// MemoriesContextPrompt contains the formatted memories prompt for either a
// single-scope (repo-only or user-only) or combined (repo + user) response.
type MemoriesContextPrompt struct {
	Prompt        string        `json:"prompt"`
	PromptVersion PromptVersion `json:"promptVersion"`
	MemoriesCount int           `json:"memoriesCount"`
	// TotalRepositoryMemoriesCount is the total number of memories stored for the repository,
	// regardless of the capped limit returned in the prompt.
	TotalRepositoryMemoriesCount int `json:"totalRepositoryMemoriesCount"`
	// RepoMemoriesCount are only populated for combined prompt responses and count the number of repository-scoped memories included in the prompt.
	RepoMemoriesCount *int `json:"repoMemoriesCount,omitempty"`
	// UserMemoriesCount are only populated for combined prompt responses and count the number of user-scoped memories included in the prompt.
	UserMemoriesCount *int `json:"userMemoriesCount,omitempty"`
	// TotalUserMemoriesCount is the total number of memories stored for the user,
	// regardless of the capped limit returned in the prompt. Only populated for combined prompt responses.
	TotalUserMemoriesCount *int `json:"totalUserMemoriesCount,omitempty"`
}

// ToolDefinition contains metadata for a tool, including its name, description, and definition version.
type ToolDefinition struct {
	Name              string        `json:"name"`
	Description       string        `json:"description"`
	DefinitionVersion PromptVersion `json:"definitionVersion"`
}

// MemoryPromptResponse is the top-level response for the GET /prompt route.
type MemoryPromptResponse struct {
	StoreInstructions   StoreInstructionsPrompt `json:"storeInstructions"`
	MemoriesContext     MemoriesContextPrompt   `json:"memoriesContext"`
	ToolDefinition      ToolDefinition          `json:"toolDefinition"`               // Backward-compatible singular store tool metadata.
	StoreToolDefinition ToolDefinition          `json:"storeToolDefinition"`          // Canonical keyed store tool metadata.
	VoteToolDefinition  *ToolDefinition         `json:"voteToolDefinition,omitempty"` // Optional keyed vote tool metadata.
}
