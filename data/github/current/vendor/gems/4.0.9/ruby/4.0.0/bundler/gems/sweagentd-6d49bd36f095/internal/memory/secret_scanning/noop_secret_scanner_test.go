package secretscanning

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNoopSecretScanner_Scan_ReturnsNoSecrets(t *testing.T) {
	scanner := NewNoopSecretScanner()
	memory := &core.Memory{
		Source: core.MemorySource{
			NWO:  core.RepoNWO{Owner: "owner", Repo: "repo"},
			User: core.User{ID: 1},
		},
		Subject: "test_subject",
		Fact:    "ghp_thisLooksLikeASecretButShouldBeIgnored",
		Reason:  "test_reason",
	}

	secrets, err := scanner.Scan(context.Background(), core.RepoNWO{Owner: "owner", Repo: "repo"}, memory)

	require.NoError(t, err)
	assert.Nil(t, secrets)
}

func TestNoopSecretScanner_Scan_EmptyRepoNWO(t *testing.T) {
	scanner := NewNoopSecretScanner()
	memory := &core.Memory{
		Source: core.MemorySource{
			User: core.User{ID: 1},
		},
	}

	secrets, err := scanner.Scan(context.Background(), core.RepoNWO{}, memory)

	require.NoError(t, err)
	assert.Empty(t, secrets)
}
