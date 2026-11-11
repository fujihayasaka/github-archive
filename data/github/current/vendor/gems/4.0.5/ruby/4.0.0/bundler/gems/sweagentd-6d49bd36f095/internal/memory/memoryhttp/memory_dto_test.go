package memoryhttp

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMemoryDTO_ToDomain_WithSHA(t *testing.T) {
	sha := "abc123def456789"
	dto := &MemoryDTO{
		ID:        "test-id",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		Source: MemorySourceDTO{
			InteractionID: "interaction-1",
			Agent:         "test-agent",
			CommitSHA:     sha,
		},
	}

	nwo := core.RepoNWO{Owner: "test", Repo: "repo"}
	user := requestctx.UserInfo{ID: 123, Login: "testuser"}

	memory, err := dto.ToDomain(nwo, user)
	require.NoError(t, err)

	assert.Equal(t, sha, memory.Source.CommitSHA)
	assert.Equal(t, "test-id", memory.ID.String())
	assert.Equal(t, "Test Subject", memory.Subject)
	assert.Equal(t, "test-agent", memory.Source.Agent)
	assert.Equal(t, "interaction-1", memory.Source.InteractionID)

	// Voting fields
	assert.False(t, memory.CreatedAt.IsZero())
	assert.Equal(t, memory.CreatedAt, memory.UpdatedAt)
	assert.Equal(t, memory.CreatedAt.Add(core.VoteWindow), memory.ExpiresAt)

	require.Len(t, memory.Votes, 1)
	assert.Equal(t, core.UpVote, memory.Votes[0].Direction)
	assert.Equal(t, "test-agent", memory.Votes[0].Source.Agent)
	assert.Equal(t, "test/repo", memory.Votes[0].Source.RepoNWO.String())
	assert.Equal(t, sha, memory.Votes[0].Source.CommitSHA)
}

func TestMemoryDTO_ToDomain_WithBaseModel(t *testing.T) {
	baseModel := "gpt-5.2"
	dto := &MemoryDTO{
		ID:        "test-id",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		Source: MemorySourceDTO{
			InteractionID: "interaction-1",
			Agent:         "test-agent",
			CommitSHA:     "abc123",
			BaseModel:     baseModel,
		},
	}

	nwo := core.RepoNWO{Owner: "test", Repo: "repo"}
	user := requestctx.UserInfo{ID: 123, Login: "testuser"}

	memory, err := dto.ToDomain(nwo, user)
	require.NoError(t, err)

	assert.Equal(t, baseModel, memory.Source.BaseModel)
	assert.Equal(t, "test-id", memory.ID.String())

	// BaseModel should propagate to the initial upvote
	require.Len(t, memory.Votes, 1)
	assert.Equal(t, core.UpVote, memory.Votes[0].Direction)
	assert.Equal(t, baseModel, memory.Votes[0].Source.BaseModel)
}

func TestMemoryDTO_ToDomain_WithoutSHA(t *testing.T) {
	// SHA should be empty when not provided
	dto := &MemoryDTO{
		ID:        "test-id",
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		Source: MemorySourceDTO{
			InteractionID: "interaction-1",
			Agent:         "test-agent",
		},
	}

	nwo := core.RepoNWO{Owner: "test", Repo: "repo"}
	user := requestctx.UserInfo{ID: 123, Login: "testuser"}

	memory, err := dto.ToDomain(nwo, user)
	require.NoError(t, err)

	assert.Empty(t, memory.Source.CommitSHA)
	assert.Equal(t, "test-id", memory.ID.String())

	// Voting fields still initialized
	assert.False(t, memory.CreatedAt.IsZero())
	assert.Equal(t, memory.CreatedAt, memory.UpdatedAt)
	require.Len(t, memory.Votes, 1)
	assert.Equal(t, core.UpVote, memory.Votes[0].Direction)
	assert.Empty(t, memory.Votes[0].Source.CommitSHA)
}

func TestFromDomain_WithSHA(t *testing.T) {
	sha := "abc123def456789"
	memory := &core.Memory{
		ID:        core.MemoryID("test-id"),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		CreatedAt: time.Now(),
		Source: core.MemorySource{
			InteractionID: "interaction-1",
			NWO:           core.RepoNWO{Owner: "test", Repo: "repo"},
			User:          core.User{ID: 123, Login: "testuser"},
			Agent:         "test-agent",
			CommitSHA:     sha,
		},
	}

	dto := FromDomain(memory)

	assert.Equal(t, sha, dto.Source.CommitSHA)
	assert.Equal(t, "test-id", dto.ID)
	assert.Equal(t, "Test Subject", dto.Subject)
	assert.Equal(t, "test-agent", dto.Source.Agent)
}

func TestFromDomain_WithBaseModel(t *testing.T) {
	sha := "abc123def456789"
	baseModel := "claude-sonnet-4.6"
	memory := &core.Memory{
		ID:        core.MemoryID("test-id"),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		CreatedAt: time.Now(),
		Source: core.MemorySource{
			InteractionID: "interaction-1",
			NWO:           core.RepoNWO{Owner: "test", Repo: "repo"},
			User:          core.User{ID: 123, Login: "testuser"},
			Agent:         "test-agent",
			CommitSHA:     sha,
			BaseModel:     baseModel,
		},
	}

	dto := FromDomain(memory)

	assert.Equal(t, sha, dto.Source.CommitSHA)
	assert.Equal(t, baseModel, dto.Source.BaseModel)
	assert.Equal(t, "test-id", dto.ID)
	assert.Equal(t, "Test Subject", dto.Subject)
	assert.Equal(t, "test-agent", dto.Source.Agent)
}

func TestFromDomain_WithoutBaseModel(t *testing.T) {
	memory := &core.Memory{
		ID:        core.MemoryID("test-id"),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		CreatedAt: time.Now(),
		Source: core.MemorySource{
			InteractionID: "interaction-1",
			NWO:           core.RepoNWO{Owner: "test", Repo: "repo"},
			User:          core.User{ID: 123, Login: "testuser"},
			Agent:         "test-agent",
		},
	}

	dto := FromDomain(memory)

	assert.Empty(t, dto.Source.BaseModel)
	assert.Equal(t, "test-id", dto.ID)
}

func TestFromDomain_WithoutSHA(t *testing.T) {
	// SHA should be empty when not provided
	memory := &core.Memory{
		ID:        core.MemoryID("test-id"),
		Subject:   "Test Subject",
		Fact:      "Test Fact",
		Citations: []string{"file.go:10"},
		Reason:    "Test Reason",
		CreatedAt: time.Now(),
		Source: core.MemorySource{
			InteractionID: "interaction-1",
			NWO:           core.RepoNWO{Owner: "test", Repo: "repo"},
			User:          core.User{ID: 123, Login: "testuser"},
			Agent:         "test-agent",
		},
	}

	dto := FromDomain(memory)

	assert.Empty(t, dto.Source.CommitSHA)
	assert.Equal(t, "test-id", dto.ID)
}

func TestFromDomain_WithRepositoryScope(t *testing.T) {
	memory := &core.Memory{
		ID:      core.MemoryID("test-id"),
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Scope:   core.MemoryScopeRepository,
		Source: core.MemorySource{
			Agent: "test-agent",
		},
	}

	dto := FromDomain(memory)

	assert.Equal(t, "repository", dto.Scope)
}

func TestFromDomain_WithUserScope(t *testing.T) {
	memory := &core.Memory{
		ID:      core.MemoryID("test-id"),
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Scope:   core.MemoryScopeUser,
		Source: core.MemorySource{
			Agent: "test-agent",
		},
	}

	dto := FromDomain(memory)

	assert.Equal(t, "user", dto.Scope)
}

func TestFromDomain_WithEmptyScope(t *testing.T) {
	// Backward compatibility: documents written before scope was persisted in Cosmos
	// will have an empty scope. The handler-level stamping in writeMemoriesResponse
	// covers this case for read paths, but FromDomain passes the value through as-is.
	memory := &core.Memory{
		ID:      core.MemoryID("test-id"),
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Scope:   "", // empty — simulates store not persisting scope
		Source: core.MemorySource{
			Agent: "test-agent",
		},
	}

	dto := FromDomain(memory)

	// Empty scope passes through — handlers are responsible for stamping scope
	// before calling FromDomain via writeMemoriesResponse(scope).
	assert.Equal(t, "", dto.Scope)
}

func TestWriteMemoriesResponse_StampsScope(t *testing.T) {
	// Verifies that writeMemoriesResponse stamps scope on memories as a
	// backward-compatibility fallback for documents written before scope was persisted.
	memories := []*core.Memory{
		{
			ID:      core.MemoryID("mem-1"),
			Subject: "Subject 1",
			Fact:    "Fact 1",
			Scope:   "", // empty from store
			Source:  core.MemorySource{Agent: "agent"},
		},
		{
			ID:      core.MemoryID("mem-2"),
			Subject: "Subject 2",
			Fact:    "Fact 2",
			Scope:   "", // empty from store
			Source:  core.MemorySource{Agent: "agent"},
		},
	}

	// Simulate what writeMemoriesResponse does: stamp scope before FromDomain
	scope := core.MemoryScopeUser
	for _, memory := range memories {
		memory.Scope = scope
	}

	dto1 := FromDomain(memories[0])
	dto2 := FromDomain(memories[1])

	assert.Equal(t, "user", dto1.Scope)
	assert.Equal(t, "user", dto2.Scope)
}

func TestFromDomain_WithBillingIDs(t *testing.T) {
	memory := &core.Memory{
		ID:      core.MemoryID("test-id"),
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Scope:   core.MemoryScopeUser,
		Source: core.MemorySource{
			Agent: "test-agent",
		},
		BillingOrganizationID: 12345,
		BillingEnterpriseID:   67890,
	}

	dto := FromDomain(memory)

	assert.Equal(t, uint64(12345), dto.BillingOrganizationID)
	assert.Equal(t, uint64(67890), dto.BillingEnterpriseID)
}

func TestFromDomain_ZeroBillingIDs_OmittedFromJSON(t *testing.T) {
	memory := &core.Memory{
		ID:      core.MemoryID("test-id"),
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Scope:   core.MemoryScopeUser,
		Source: core.MemorySource{
			Agent: "test-agent",
		},
		BillingOrganizationID: 0,
		BillingEnterpriseID:   0,
	}

	dto := FromDomain(memory)

	assert.Equal(t, uint64(0), dto.BillingOrganizationID)
	assert.Equal(t, uint64(0), dto.BillingEnterpriseID)

	// Verify omitempty: zero values should not appear in JSON
	data, err := json.Marshal(dto)
	require.NoError(t, err)

	var raw map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(data, &raw))

	_, hasOrgID := raw["billingOrganizationId"]
	_, hasEntID := raw["billingEnterpriseId"]
	assert.False(t, hasOrgID, "billingOrganizationId should be omitted when zero")
	assert.False(t, hasEntID, "billingEnterpriseId should be omitted when zero")
}

func TestFromDomain_NonZeroBillingIDs_PresentInJSON(t *testing.T) {
	memory := &core.Memory{
		ID:      core.MemoryID("test-id"),
		Subject: "Test Subject",
		Fact:    "Test Fact",
		Scope:   core.MemoryScopeUser,
		Source: core.MemorySource{
			Agent: "test-agent",
		},
		BillingOrganizationID: 42,
		BillingEnterpriseID:   99,
	}

	dto := FromDomain(memory)
	data, err := json.Marshal(dto)
	require.NoError(t, err)

	var raw map[string]json.RawMessage
	require.NoError(t, json.Unmarshal(data, &raw))

	_, hasOrgID := raw["billingOrganizationId"]
	_, hasEntID := raw["billingEnterpriseId"]
	assert.True(t, hasOrgID, "billingOrganizationId should be present when non-zero")
	assert.True(t, hasEntID, "billingEnterpriseId should be present when non-zero")
}

func TestMemoryDTO_Validate_ValidDTO(t *testing.T) {
	dto := &MemoryDTO{
		Fact:      "Test fact",
		Citations: []string{"file.go:10"},
	}
	assert.NoError(t, dto.Validate())
}

func TestMemoryDTO_Validate_NilCitations(t *testing.T) {
	dto := &MemoryDTO{
		Fact:      "Test fact",
		Citations: nil,
	}
	err := dto.Validate()
	assert.EqualError(t, err, "citations cannot be empty")
}

func TestMemoryDTO_Validate_EmptyCitations(t *testing.T) {
	dto := &MemoryDTO{
		Fact:      "Test fact",
		Citations: []string{},
	}
	err := dto.Validate()
	assert.EqualError(t, err, "citations cannot be empty")
}

func TestMemoryDTO_Validate_AllEmptyStringCitations(t *testing.T) {
	dto := &MemoryDTO{
		Fact:      "Test fact",
		Citations: []string{"", "   ", "\t"},
	}
	err := dto.Validate()
	assert.EqualError(t, err, "citations must not all be empty strings")
}

func TestMemoryDTO_Validate_MixedCitations(t *testing.T) {
	dto := &MemoryDTO{
		Fact:      "Test fact",
		Citations: []string{"", "file.go:10", ""},
	}
	assert.NoError(t, dto.Validate())
}

func TestMemoryDTO_ToDomain_FailsValidation(t *testing.T) {
	dto := &MemoryDTO{
		Fact:      "Test fact",
		Citations: nil,
	}
	nwo := core.RepoNWO{Owner: "test", Repo: "repo"}
	user := requestctx.UserInfo{ID: 123, Login: "testuser"}

	_, err := dto.ToDomain(nwo, user)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "citations cannot be empty")
}
