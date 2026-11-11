package memoryhttp

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
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

	memory := dto.ToDomain(nwo, user)

	assert.Equal(t, sha, memory.Source.CommitSHA)
	assert.Equal(t, "test-id", memory.ID.String())
	assert.Equal(t, "Test Subject", memory.Subject)
	assert.Equal(t, "test-agent", memory.Source.Agent)
	assert.Equal(t, "interaction-1", memory.Source.InteractionID)
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

	memory := dto.ToDomain(nwo, user)

	assert.Empty(t, memory.Source.CommitSHA)
	assert.Equal(t, "test-id", memory.ID.String())
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
