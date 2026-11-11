package memoryhttp

import (
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// MemorySearchRequest represents the request body for searching memories.
type MemorySearchRequest struct {
	Question string `json:"question"`
	SHA      string `json:"commit"`
}

// MemoryEnablementResponse represents the response body for checking memory enablement.
type MemoryEnablementResponse struct {
	Enabled bool `json:"enabled"`
}

// MemorySourceDTO represents the source information of a memory.
type MemorySourceDTO struct {
	InteractionID string `json:"interactionId"`
	Agent         string `json:"agent"`
	CommitSHA     string `json:"commitSha,omitempty"`
}

// MemoryDTO represents a memory data transfer object.
// It is used to transfer memory data between the service layer and the HTTP layer.
type MemoryDTO struct {
	ID        string          `json:"id"`
	Subject   string          `json:"subject"`
	Fact      string          `json:"fact"`
	Citations []string        `json:"citations"`
	Reason    string          `json:"reason"`
	Source    MemorySourceDTO `json:"source"`
}

// ToDomain converts a MemoryDTO to a core.Memory domain object.
func (m *MemoryDTO) ToDomain(nwo core.RepoNWO, user requestctx.UserInfo) *core.Memory {
	var memoryID core.MemoryID
	if m.ID != "" {
		memoryID = core.MemoryID(m.ID)
	} else {
		memoryID = core.NewMemoryID() // Generate a new ID if not provided
	}
	return &core.Memory{
		ID:        memoryID,
		Subject:   m.Subject,
		Fact:      m.Fact,
		Citations: m.Citations,
		Reason:    m.Reason,
		CreatedAt: time.Now(), // Set the current time as CreatedAt
		Source: core.MemorySource{
			InteractionID: m.Source.InteractionID,
			NWO:           nwo,
			Agent:         m.Source.Agent,
			CommitSHA:     m.Source.CommitSHA,
			User: core.User{
				ID:    user.ID,
				Login: user.Login,
			},
		},
	}
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
		},
	}
}
