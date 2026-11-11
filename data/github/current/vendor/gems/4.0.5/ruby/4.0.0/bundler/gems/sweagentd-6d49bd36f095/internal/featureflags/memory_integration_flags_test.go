package featureflags_test

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/stretchr/testify/assert"
)

func TestContextWithIntegrationID(t *testing.T) {
	ctx := context.Background()

	// No integration ID set → empty string.
	assert.Equal(t, "", featureflags.IntegrationIDFromContext(ctx))

	// Round-trip through context.
	ctx = featureflags.ContextWithIntegrationID(ctx, "copilot-developer")
	assert.Equal(t, "copilot-developer", featureflags.IntegrationIDFromContext(ctx))
}

func TestContextWithIntegrationIDEmpty(t *testing.T) {
	ctx := featureflags.ContextWithIntegrationID(context.Background(), "")
	assert.Equal(t, "", featureflags.IntegrationIDFromContext(ctx))
}

func TestMemoryVotingFlagForIntegration(t *testing.T) {
	tests := []struct {
		name          string
		integrationID string
		wantFlag      string
	}{
		// Coding Agents (CCA + 3P)
		{name: "claude-code", integrationID: "claude-code", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCodingAgent},
		{name: "claude-code-cloud", integrationID: "claude-code-cloud", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCodingAgent},
		{name: "codex-cloud", integrationID: "codex-cloud", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCodingAgent},
		{name: "openai-codex-cli", integrationID: "openai-codex-cli", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCodingAgent},
		{name: "copilot-developer", integrationID: "copilot-developer", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCodingAgent},
		{name: "copilot-developer-dev", integrationID: "copilot-developer-dev", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCodingAgent},
		// CCR
		{name: "copilot-pr-reviews", integrationID: "copilot-pr-reviews", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCCR},
		{name: "copilot-pr-reviews-dev", integrationID: "copilot-pr-reviews-dev", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCCR},
		// CLI
		{name: "copilot-developer-cli", integrationID: "copilot-developer-cli", wantFlag: featureflags.CopilotSWEAgentMemoryVotingCLI},
		// VS Code
		{name: "vscode-chat", integrationID: "vscode-chat", wantFlag: featureflags.CopilotSWEAgentMemoryVotingVSCode},
		{name: "vscode-chat-dev", integrationID: "vscode-chat-dev", wantFlag: featureflags.CopilotSWEAgentMemoryVotingVSCode},
		// Unknown / empty → voting disabled
		{name: "unknown integration", integrationID: "some-unknown-client", wantFlag: ""},
		{name: "empty integration", integrationID: "", wantFlag: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := featureflags.MemoryVotingFlagForIntegration(tt.integrationID)
			assert.Equal(t, tt.wantFlag, got)
		})
	}
}

func TestMemoryVotingFlagFromContext(t *testing.T) {
	t.Run("known integration in context", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "vscode-chat")
		assert.Equal(t, featureflags.CopilotSWEAgentMemoryVotingVSCode, featureflags.MemoryVotingFlagFromContext(ctx))
	})

	t.Run("no integration in context disables voting", func(t *testing.T) {
		ctx := context.Background()
		assert.Equal(t, "", featureflags.MemoryVotingFlagFromContext(ctx))
	})
}

func TestMemoryDisabledFlagForIntegration(t *testing.T) {
	tests := []struct {
		name          string
		integrationID string
		wantFlag      string
	}{
		// VS Code clients → disabled flag
		{name: "vscode-chat", integrationID: "vscode-chat", wantFlag: featureflags.CopilotSWEAgentMemoryDisabledVSCode},
		{name: "vscode-chat-dev", integrationID: "vscode-chat-dev", wantFlag: featureflags.CopilotSWEAgentMemoryDisabledVSCode},
		// Other clients → no disable flag (memory stays enabled)
		{name: "copilot-developer", integrationID: "copilot-developer", wantFlag: ""},
		{name: "copilot-developer-dev", integrationID: "copilot-developer-dev", wantFlag: ""},
		{name: "copilot-developer-cli", integrationID: "copilot-developer-cli", wantFlag: ""},
		{name: "claude-code", integrationID: "claude-code", wantFlag: ""},
		{name: "claude-code-cloud", integrationID: "claude-code-cloud", wantFlag: ""},
		{name: "codex-cloud", integrationID: "codex-cloud", wantFlag: ""},
		{name: "copilot-pr-reviews", integrationID: "copilot-pr-reviews", wantFlag: ""},
		{name: "unknown integration", integrationID: "some-unknown-client", wantFlag: ""},
		{name: "empty integration", integrationID: "", wantFlag: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := featureflags.MemoryDisabledFlagForIntegration(tt.integrationID)
			assert.Equal(t, tt.wantFlag, got)
		})
	}
}

func TestMemoryDisabledFlagFromContext(t *testing.T) {
	t.Run("vscode integration in context returns disable flag", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "vscode-chat")
		assert.Equal(t, featureflags.CopilotSWEAgentMemoryDisabledVSCode, featureflags.MemoryDisabledFlagFromContext(ctx))
	})

	t.Run("non-vscode integration in context returns empty", func(t *testing.T) {
		ctx := featureflags.ContextWithIntegrationID(context.Background(), "copilot-developer")
		assert.Equal(t, "", featureflags.MemoryDisabledFlagFromContext(ctx))
	})

	t.Run("no integration in context returns empty", func(t *testing.T) {
		ctx := context.Background()
		assert.Equal(t, "", featureflags.MemoryDisabledFlagFromContext(ctx))
	})
}
