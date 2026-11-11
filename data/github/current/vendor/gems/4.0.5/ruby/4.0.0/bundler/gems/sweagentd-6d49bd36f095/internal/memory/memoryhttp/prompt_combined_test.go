package memoryhttp

import (
	"testing"

	"github.com/github/sweagentd/internal/memory/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func requireCombinedPromptResponse(t *testing.T, builder combinedPromptBuilder) MemoryPromptResponse {
	t.Helper()
	response, err := builder.buildResponse()
	require.NoError(t, err)
	return response
}

func sampleRepoMemories() []*core.Memory {
	return []*core.Memory{
		{Subject: "testing practices", Fact: "Use vitest for unit tests", Citations: []string{"vitest.config.ts:5"}},
		{Subject: "code style", Fact: "Use single quotes for strings", Citations: []string{"eslintrc.json:10"}},
	}
}

func sampleUserMemories() []*core.Memory {
	return []*core.Memory{
		{Subject: "editor config", Fact: "Prefer dark theme", Citations: []string{}},
	}
}

var testRepoNWO = &core.RepoNWO{Owner: "octocat", Repo: "hello-world"}

func TestCombinedPromptBothScopes(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser"))

	assert.Equal(t, 3, response.MemoriesContext.MemoriesCount)
	require.NotNil(t, response.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 2, *response.MemoriesContext.RepoMemoriesCount)
	require.NotNil(t, response.MemoriesContext.UserMemoriesCount)
	assert.Equal(t, 1, *response.MemoriesContext.UserMemoriesCount)

	prompt := response.MemoriesContext.Prompt
	assert.Contains(t, prompt, "## Repository memories for `octocat/hello-world`")
	assert.Contains(t, prompt, "Use vitest for unit tests")
	assert.Contains(t, prompt, "Use single quotes for strings")
	assert.Contains(t, prompt, "## User memories for @testuser")
	assert.Contains(t, prompt, "Prefer dark theme")
	assert.Contains(t, prompt, "recent memories from previous agent interactions")
	assert.Contains(t, prompt, "verify their current applicability")
	// Store instructions should be scope-neutral
	assert.NotContains(t, response.StoreInstructions.Prompt, "about the codebase that could help")
	assert.Contains(t, response.StoreInstructions.Prompt, "that could help in future code generation or review")
}

func TestCombinedPromptRepoOnly(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), nil, testRepoNWO, "testuser"))

	assert.Equal(t, 2, response.MemoriesContext.MemoriesCount)
	assert.Equal(t, 2, *response.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 0, *response.MemoriesContext.UserMemoriesCount)

	prompt := response.MemoriesContext.Prompt
	assert.Contains(t, prompt, "## Repository memories for `octocat/hello-world`")
	assert.NotContains(t, prompt, "## User memories for @testuser")
}

func TestCombinedPromptUserOnly(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(nil, sampleUserMemories(), nil, "testuser"))

	assert.Equal(t, 1, response.MemoriesContext.MemoriesCount)
	assert.Equal(t, 0, *response.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 1, *response.MemoriesContext.UserMemoriesCount)

	prompt := response.MemoriesContext.Prompt
	assert.NotContains(t, prompt, "## Repository memories")
	assert.Contains(t, prompt, "## User memories for @testuser")
	assert.Contains(t, prompt, "Prefer dark theme")
}

func TestCombinedPromptNoMemories(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(nil, nil, testRepoNWO, "testuser"))

	assert.Equal(t, 0, response.MemoriesContext.MemoriesCount)
	assert.Empty(t, response.MemoriesContext.Prompt)
	require.NotNil(t, response.MemoriesContext.RepoMemoriesCount)
	assert.Equal(t, 0, *response.MemoriesContext.RepoMemoriesCount)
	require.NotNil(t, response.MemoriesContext.UserMemoriesCount)
	assert.Equal(t, 0, *response.MemoriesContext.UserMemoriesCount)
}

func TestCombinedPromptVersioning(t *testing.T) {
	t.Run("no voting", func(t *testing.T) {
		response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser"))
		assert.Equal(t, combinedMemoriesContextPromptVersion, response.MemoriesContext.PromptVersion)
		assert.Equal(t, combinedStoreInstructionsPromptVersion, response.StoreInstructions.PromptVersion)
	})

	t.Run("voting enabled with memories", func(t *testing.T) {
		response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withVoting(true)))
		assert.Equal(t, combinedMemoriesContextPromptVersionWithVoting, response.MemoriesContext.PromptVersion)
		assert.Equal(t, combinedStoreInstructionsPromptVersionWithVoting, response.StoreInstructions.PromptVersion)
	})

	t.Run("voting enabled no memories", func(t *testing.T) {
		response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(nil, nil, testRepoNWO, "testuser", withVoting(true)))
		assert.Equal(t, combinedMemoriesContextPromptVersion, response.MemoriesContext.PromptVersion)
		assert.Equal(t, combinedStoreInstructionsPromptVersion, response.StoreInstructions.PromptVersion)
	})

	t.Run("user scoped enabled", func(t *testing.T) {
		response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withUserScoped(true)))
		assert.Equal(t, combinedMemoriesContextPromptVersion, response.MemoriesContext.PromptVersion)
		assert.Equal(t, combinedStoreInstructionsPromptVersionWithScope, response.StoreInstructions.PromptVersion)
	})

	t.Run("voting and user scoped enabled with memories", func(t *testing.T) {
		response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withVoting(true), withUserScoped(true)))
		assert.Equal(t, combinedMemoriesContextPromptVersionWithVoting, response.MemoriesContext.PromptVersion)
		assert.Equal(t, combinedStoreInstructionsPromptVersionWithVotingAndScope, response.StoreInstructions.PromptVersion)
	})

	t.Run("voting and user scoped enabled no memories", func(t *testing.T) {
		response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(nil, nil, testRepoNWO, "testuser", withVoting(true), withUserScoped(true)))
		assert.Equal(t, combinedMemoriesContextPromptVersion, response.MemoriesContext.PromptVersion)
		assert.Equal(t, combinedStoreInstructionsPromptVersionWithScope, response.StoreInstructions.PromptVersion)
	})
}

func TestCombinedPromptScopeVisibilityFraming(t *testing.T) {
	const visibilityIntro = "They may include repository facts (visible to all repository collaborators) and user preferences (visible only to the current user)."

	t.Run("included when user scoped enabled", func(t *testing.T) {
		prompt := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withUserScoped(true))).MemoriesContext.Prompt
		assert.Contains(t, prompt, visibilityIntro)
	})

	t.Run("omitted when user scoped disabled", func(t *testing.T) {
		prompt := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser")).MemoriesContext.Prompt
		assert.NotContains(t, prompt, visibilityIntro)
	})
}

func TestCombinedPromptVotingGuidance(t *testing.T) {
	t.Run("without voting", func(t *testing.T) {
		prompt := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser")).MemoriesContext.Prompt
		assert.Contains(t, prompt, "store_memory tool to store the same fact again")
		assert.NotContains(t, prompt, "vote_memory")
		assertMemoryDeletionManualGuidance(t, prompt)
	})

	t.Run("with voting", func(t *testing.T) {
		prompt := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withVoting(true))).MemoriesContext.Prompt
		assert.Contains(t, prompt, "vote_memory")
		assert.Contains(t, prompt, "upvote")
		assert.Contains(t, prompt, "downvote")
		assertMemoryDeletionVotingGuidance(t, prompt)
	})
}

func TestCombinedPromptStoreInstructions(t *testing.T) {
	t.Run("without voting", func(t *testing.T) {
		instructions := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser")).StoreInstructions.Prompt
		assert.Contains(t, instructions, "store_memory")
		assert.NotContains(t, instructions, "vote_memory")
	})

	t.Run("with voting and memories", func(t *testing.T) {
		instructions := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withVoting(true))).StoreInstructions.Prompt
		assert.Contains(t, instructions, "vote_memory")
	})
}

func TestCombinedPromptBuildResponseToolDefinitions(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser"))

	assert.NotEmpty(t, response.StoreInstructions.Prompt)
	assert.Equal(t, combinedStoreInstructionsPromptVersion, response.StoreInstructions.PromptVersion)
	assert.Equal(t, combinedMemoriesContextPromptVersion, response.MemoriesContext.PromptVersion)

	// Combined endpoint uses scope-neutral tool description
	expectedDescription, err := resolveStoreToolDescription(false)
	require.NoError(t, err)
	assert.Equal(t, storeMemoryToolName, response.ToolDefinition.Name)
	assert.Equal(t, expectedDescription, response.ToolDefinition.Description)
	assert.Equal(t, storeToolDefinitionVersion, response.ToolDefinition.DefinitionVersion)
	assert.Equal(t, response.ToolDefinition, response.StoreToolDefinition)
	assert.Nil(t, response.VoteToolDefinition)
}

func TestCombinedPromptBuildResponseToolDefinitionsWithScope(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withUserScoped(true)))

	expectedDescription, err := resolveStoreToolDescription(true)
	require.NoError(t, err)
	assert.Equal(t, storeMemoryToolName, response.StoreToolDefinition.Name)
	assert.Equal(t, expectedDescription, response.StoreToolDefinition.Description)
	assert.Equal(t, storeToolDefinitionVersionWithScope, response.StoreToolDefinition.DefinitionVersion)
}

func TestCombinedPromptBuildResponseWithVoting(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), sampleUserMemories(), testRepoNWO, "testuser", withVoting(true)))

	assert.Equal(t, combinedStoreInstructionsPromptVersionWithVoting, response.StoreInstructions.PromptVersion)
	assert.Equal(t, combinedMemoriesContextPromptVersionWithVoting, response.MemoriesContext.PromptVersion)
	assertVoteToolDefinition(t, response.VoteToolDefinition)
}

func TestCombinedPromptEmptyUserLogin(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(nil, sampleUserMemories(), nil, ""))

	prompt := response.MemoriesContext.Prompt
	assert.Contains(t, prompt, "## User memories")
	assert.NotContains(t, prompt, "## User memories for @")
	assert.Contains(t, prompt, "Prefer dark theme")
}

func TestCombinedPromptRepoMemoriesWithNilNWO(t *testing.T) {
	response := requireCombinedPromptResponse(t, newCombinedPromptBuilder(sampleRepoMemories(), nil, nil, "testuser"))

	prompt := response.MemoriesContext.Prompt
	// Repo memories should be silently dropped when repoNWO is nil
	assert.NotContains(t, prompt, "## Repository memories")
	assert.NotContains(t, prompt, "Use vitest for unit tests")
	// Counts reflect the effective set (zero, since repo memories were dropped)
	assert.Equal(t, 0, response.MemoriesContext.MemoriesCount)
	assert.Equal(t, 0, *response.MemoriesContext.RepoMemoriesCount)
}
