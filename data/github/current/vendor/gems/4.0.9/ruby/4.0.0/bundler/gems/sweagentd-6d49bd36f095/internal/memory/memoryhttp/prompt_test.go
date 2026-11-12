package memoryhttp

import (
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func requirePromptResponse(t *testing.T, builder promptBuilder) MemoryPromptResponse {
	t.Helper()
	response, err := builder.buildResponse()
	require.NoError(t, err)
	return response
}

func assertMemoryDeletionManualGuidance(t *testing.T, prompt string) {
	t.Helper()
	assert.Contains(t, prompt, "delete, remove, or forget a memory")
	assert.Contains(t, prompt, "Settings > Copilot > Memory")
	assert.Contains(t, prompt, copilotSettingsURL)
	assert.Contains(t, prompt, copilotMemoryDocsURL)
}

func assertMemoryDeletionVotingGuidance(t *testing.T, prompt string) {
	t.Helper()
	assert.Contains(t, prompt, "delete, remove, or forget a memory")
	assert.Contains(t, prompt, `direction "downvote"`)
	assert.Contains(t, prompt, "deprioritize")
	assert.Contains(t, prompt, "Settings > Copilot > Memory")
	assert.Contains(t, prompt, copilotSettingsURL)
	assert.Contains(t, prompt, copilotMemoryDocsURL)
}

func TestBuildContextPromptContainsPreamble(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	result := requirePromptResponse(t, newPromptBuilder(memories)).MemoriesContext.Prompt
	assert.Contains(t, result, "recent memories from previous agent interactions")
	assert.Contains(t, result, "store_memory")
	assert.Contains(t, result, "**logging**")
	assert.Contains(t, result, "Use structured logging")
	assert.Contains(t, result, "logger.go:10")
	assertMemoryDeletionManualGuidance(t, result)
	// Should not contain the template field
	assert.NotContains(t, result, "{{template \"memories-list\" .RepoMemories}}")
}

func TestBuildContextPromptRendersMemoriesInOrderWithBlankLineSeparation(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "testing practices", Fact: "Use vitest for unit tests", Citations: []string{"vitest.config.ts:5", "vitest.setup.ts:1"}},
		{Subject: "code style", Fact: "Use single quotes for strings", Citations: []string{"eslintrc.json:10"}},
	}

	result := requirePromptResponse(t, newPromptBuilder(memories)).MemoriesContext.Prompt

	assert.Contains(t, result, `**testing practices**
- Fact: Use vitest for unit tests
- Citations: vitest.config.ts:5, vitest.setup.ts:1

**code style**
- Fact: Use single quotes for strings
- Citations: eslintrc.json:10`)
}

func TestBuildContextPromptRendersNilCitationsAsNone(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "build commands", Fact: "Run npm run build to build the project", Citations: nil},
	}

	result := requirePromptResponse(t, newPromptBuilder(memories)).MemoriesContext.Prompt

	assert.Contains(t, result, `**build commands**
- Fact: Run npm run build to build the project
- Citations: <none>`)
}

func TestBuildContextPromptRendersEmptyCitationsAsNone(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "build commands", Fact: "Run npm run build to build the project", Citations: []string{}},
	}

	result := requirePromptResponse(t, newPromptBuilder(memories)).MemoriesContext.Prompt

	assert.Contains(t, result, `**build commands**
- Fact: Run npm run build to build the project
- Citations: <none>`)
}

func TestBuildContextPromptEmpty(t *testing.T) {
	result := requirePromptResponse(t, newPromptBuilder([]*core.Memory{})).MemoriesContext.Prompt
	assert.Empty(t, result)
}

func TestMemoriesContextTemplateContainsPlaceholder(t *testing.T) {
	assert.Contains(t, memoriesContextTemplateSource, "{{template \"memories-list\" .RepoMemories}}")
}

func TestStoreMemoryToolInstructionsContent(t *testing.T) {
	instructions, err := resolveStoreInstructions(false, false, false, "")
	require.NoError(t, err)
	assert.Contains(t, instructions, "store_memory")
	assert.Contains(t, instructions, "Examples:")
	assert.Contains(t, instructions, "Only store facts that meet the following criteria:")
	assert.Contains(t, instructions, "npm run build")
	assert.Contains(t, instructions, "npm run test")
}

func TestStoreInstructionsWithUserLogin(t *testing.T) {
	instructions, err := resolveStoreInstructions(false, false, true, "octocat")
	require.NoError(t, err)
	assert.Contains(t, instructions, "The current user is @octocat.")
	assert.Contains(t, instructions, `User input: "<exact quotation>"`)
}

func TestStoreInstructionsWithUserScopedButNoLogin(t *testing.T) {
	instructions, err := resolveStoreInstructions(false, false, true, "")
	require.NoError(t, err)
	assert.NotContains(t, instructions, "The current user is @")
	assert.NotContains(t, instructions, "from @")
	assert.Contains(t, instructions, "Only store user preferences for the current user")
}

func TestBuildContextPromptWithVoting(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	result := requirePromptResponse(t, newPromptBuilder(memories, withVoting(true))).MemoriesContext.Prompt
	assert.Contains(t, result, "vote_memory")
	assert.Contains(t, result, `direction "upvote"`)
	assert.Contains(t, result, "exact string match")
	assert.Contains(t, result, "reflecting the current reality")
	assert.Contains(t, result, "store_memory")
	assertMemoryDeletionVotingGuidance(t, result)
}

func TestBuildStoreInstructionsPromptWithVoting(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	result := requirePromptResponse(t, newPromptBuilder(memories, withVoting(true))).StoreInstructions.Prompt
	assert.Contains(t, result, "vote_memory")
	assert.Contains(t, result, "list of recent memories shown in the prompt")
	assert.Contains(t, result, "genuinely new facts")
	assert.Contains(t, result, "reflecting the current reality")
	assert.Contains(t, result, "npm run build")
	assert.Contains(t, result, "npm run test")
	// Voting-enabled duplicate-check guidance must use explicit
	// upvote/downvote semantics aligned with the vote_memory tool
	// description, not the prior "agreement or disagreement" framing.
	assert.Contains(t, result, `direction "upvote"`)
	assert.Contains(t, result, `direction "downvote"`)
	assert.Contains(t, result, "delete, remove, or forget")
	assert.NotContains(t, result, "agreement or disagreement")
	// When memories are present the standalone no-memories deletion block
	// should not also be rendered (memories context covers that case).
	assert.NotContains(t, result, "no memories visible in the current prompt")
}

func TestBuildStoreInstructionsPromptWithVotingButNoMemories(t *testing.T) {
	result := requirePromptResponse(t, newPromptBuilder(nil, withVoting(true))).StoreInstructions.Prompt
	assert.NotContains(t, result, "vote_memory")
	// When voting is enabled but no memories are visible, store instructions
	// must still tell the agent how to handle a deletion request: direct the
	// user to manual deletion, since vote_memory cannot be used.
	assertMemoryDeletionManualGuidance(t, result)
}

func TestBuildStoreInstructionsPromptWithoutVotingAndNoMemories(t *testing.T) {
	result := requirePromptResponse(t, newPromptBuilder(nil)).StoreInstructions.Prompt
	// Coverage for the user-asks-to-delete case must be present even when
	// neither voting nor any memories are available in the prompt.
	assertMemoryDeletionManualGuidance(t, result)
	// The deletion paragraph must not reference vote_memory or "vote" when
	// voting is disabled, since the agent has no voting tool to use.
	assert.NotContains(t, result, "vote_memory")
	assert.NotContains(t, result, "vote on")
}

func TestBuildStoreInstructionsPromptWithoutVotingButWithMemories(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	result := requirePromptResponse(t, newPromptBuilder(memories)).StoreInstructions.Prompt
	// When memories exist, the memories-context prompt carries the manual
	// deletion guidance; the no-memories store-instructions block must
	// not duplicate it.
	assert.NotContains(t, result, "no memories visible in the current prompt")
}

func TestResolvePromptOptionsDefaults(t *testing.T) {
	assert.False(t, resolvePromptOptions().votingEnabled)
}

func TestResolvePromptOptionsWithVoting(t *testing.T) {
	assert.True(t, resolvePromptOptions(withVoting(true)).votingEnabled)
}

func TestStoreInstructionsVersionWithVoting(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	assert.Equal(t, storeInstructionsPromptVersionWithVoting, requirePromptResponse(t, newPromptBuilder(memories, withVoting(true))).StoreInstructions.PromptVersion)
}

func TestStoreInstructionsVersionWithoutVoting(t *testing.T) {
	assert.Equal(t, storeInstructionsPromptVersion, requirePromptResponse(t, newPromptBuilder(nil)).StoreInstructions.PromptVersion)
}

func TestStoreInstructionsVersionWithoutMemories(t *testing.T) {
	assert.Equal(t, storeInstructionsPromptVersion, requirePromptResponse(t, newPromptBuilder(nil, withVoting(true))).StoreInstructions.PromptVersion)
}

func TestStoreInstructionsVersionWithScope(t *testing.T) {
	assert.Equal(t, storeInstructionsPromptVersionWithScope, requirePromptResponse(t, newPromptBuilder(nil, withUserScoped(true))).StoreInstructions.PromptVersion)
}

func TestStoreInstructionsVersionWithVotingAndScope(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	assert.Equal(t, storeInstructionsPromptVersionWithVotingAndScope, requirePromptResponse(t, newPromptBuilder(memories, withVoting(true), withUserScoped(true))).StoreInstructions.PromptVersion)
}

func TestStoreInstructionsVersionWithVotingAndScopeButNoMemories(t *testing.T) {
	assert.Equal(t, storeInstructionsPromptVersionWithScope, requirePromptResponse(t, newPromptBuilder(nil, withVoting(true), withUserScoped(true))).StoreInstructions.PromptVersion)
}

func TestMemoriesContextVersionWithVoting(t *testing.T) {
	memories := []*core.Memory{
		{Subject: "logging", Fact: "Use structured logging", Citations: []string{"logger.go:10"}},
	}
	assert.Equal(t, memoriesContextPromptVersionWithVoting, requirePromptResponse(t, newPromptBuilder(memories, withVoting(true))).MemoriesContext.PromptVersion)
}

func TestMemoriesContextVersionWithoutVoting(t *testing.T) {
	assert.Equal(t, memoriesContextPromptVersion, requirePromptResponse(t, newPromptBuilder(nil)).MemoriesContext.PromptVersion)
}

func TestMemoriesContextVersionWithoutMemories(t *testing.T) {
	assert.Equal(t, memoriesContextPromptVersion, requirePromptResponse(t, newPromptBuilder(nil, withVoting(true))).MemoriesContext.PromptVersion)
}

func TestStoreToolDefinition(t *testing.T) {
	result, err := storeToolDefinition(false)
	require.NoError(t, err)

	expectedDescription, err := resolveStoreToolDescription(false)
	require.NoError(t, err)
	assert.Equal(t, storeMemoryToolName, result.Name)
	assert.Equal(t, expectedDescription, result.Description)
	assert.Equal(t, storeToolDefinitionVersion, result.DefinitionVersion)
}

func TestStoreToolDefinitionWithScope(t *testing.T) {
	result, err := storeToolDefinition(true)
	require.NoError(t, err)

	expectedDescription, err := resolveStoreToolDescription(true)
	require.NoError(t, err)
	assert.Equal(t, storeMemoryToolName, result.Name)
	assert.Equal(t, expectedDescription, result.Description)
	assert.Equal(t, storeToolDefinitionVersionWithScope, result.DefinitionVersion)
}

func TestVoteToolDefinitionWithoutVoting(t *testing.T) {
	result := voteToolDefinition(false)

	assert.Nil(t, result)
}

func TestVoteToolDefinitionWithVoting(t *testing.T) {
	result := voteToolDefinition(true)

	require.NotNil(t, result)
	assert.Equal(t, voteMemoryToolName, result.Name)
	assert.Equal(t, voteMemoryToolDescription, result.Description)
	assert.Equal(t, voteToolDefinitionVersion, result.DefinitionVersion)
}

func TestVoteMemoryToolDescription(t *testing.T) {
	// The vote_memory tool description must give the agent unambiguous,
	// imperative guidance covering the key points: the exact-text requirement,
	// the upvote case, and the downvote cases (including user-requested deletion).
	// It must also avoid the prior "agree/disagree" framing, which conflicts
	// with the user-requested-deletion case.
	assert.Contains(t, voteMemoryToolDescription, "exact string match")
	assert.Contains(t, voteMemoryToolDescription, `direction "upvote"`)
	assert.Contains(t, voteMemoryToolDescription, `direction "downvote"`)
	assert.Contains(t, voteMemoryToolDescription, "incorrect or outdated")
	assert.Contains(t, voteMemoryToolDescription, "delete, remove, or forget")
	assert.NotContains(t, voteMemoryToolDescription, "agree or disagree")
	assert.NotContains(t, voteMemoryToolDescription, "agreement or disagreement")
}

func TestStoreInstructionsContainsGDPRArticle9Restriction(t *testing.T) {
	tests := []struct {
		name              string
		votingEnabled     bool
		hasMemories       bool
		userScopedEnabled bool
	}{
		{"default", false, false, false},
		{"with voting and memories", true, true, false},
		{"with user scoped", false, false, true},
		{"with voting and user scoped", true, true, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			instructions, err := resolveStoreInstructions(tt.votingEnabled, tt.hasMemories, tt.userScopedEnabled, "")
			require.NoError(t, err)
			assert.Contains(t, instructions, "Personal data covered by GDPR Article 9")
			assert.Contains(t, instructions, "health")
			assert.Contains(t, instructions, "religion")
			assert.Contains(t, instructions, "ethnicity")
			assert.Contains(t, instructions, "sexual orientation")
			assert.Contains(t, instructions, "political views")
			assert.Contains(t, instructions, "biometrics")
			assert.Contains(t, instructions, "union membership")
		})
	}
}

func TestStoreInstructionsGDPRRestrictionInDoNotStoreSection(t *testing.T) {
	instructions, err := resolveStoreInstructions(false, false, false, "")
	require.NoError(t, err)

	// The GDPR restriction should appear in the "Do not store" section alongside other sensitive data prohibitions.
	assert.Contains(t, instructions, "Secrets, credentials, tokens, API keys")
	assert.Contains(t, instructions, "Personal data covered by GDPR Article 9, including health, religion, ethnicity, sexual orientation, political views, biometrics, and union membership")
}

func TestStoreInstructionsBuilderIncludesGDPRRestriction(t *testing.T) {
	// Verify the GDPR restriction appears in the full prompt response built by promptBuilder.
	memories := []*core.Memory{
		{Subject: "testing", Fact: "Use go test", Citations: []string{"Makefile:1"}},
	}
	result := requirePromptResponse(t, newPromptBuilder(memories)).StoreInstructions.Prompt
	assert.Contains(t, result, "Personal data covered by GDPR Article 9")
}
