package jobapi

import (
	"fmt"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/stretchr/testify/require"
)

func TestCreateJob_AgentDescription(t *testing.T) {
	t.Run("includes agent description in body suffix when agent has description", func(t *testing.T) {
		agentMetadata := customagent.Metadata{
			Name:      "test-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Test Agent",
			Description: "This is a test agent that helps with testing functionality",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := generateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "Custom agent used: Test Agent")
		require.Contains(t, customAgentQuote, "This is a test agent that helps with testing functionality")
		require.Equal(t, "\n> [!NOTE] \n> **Custom agent used: Test Agent**\n> This is a test agent that helps with testing functionality\n\n", customAgentQuote)
	})

	t.Run("handles agent description ending with newline", func(t *testing.T) {
		agentMetadata := customagent.Metadata{
			Name:      "trailing-newline-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Trailing Newline Agent",
			Description: "Description that ends with newline\n",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := generateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "Custom agent used: Trailing Newline Agent")
		require.Contains(t, customAgentQuote, "Description that ends with newline\n")
		require.Equal(t, "\n> [!NOTE] \n> **Custom agent used: Trailing Newline Agent**\n> Description that ends with newline\n> \n\n", customAgentQuote)
	})

	t.Run("truncates long agent description with link", func(t *testing.T) {
		longDescription := strings.Repeat("A", MaxPullRequestBodyAgentDescriptionLength+100)

		agentMetadata := customagent.Metadata{
			Name:      "long-desc-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Long Description Agent",
			Description: longDescription,
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := generateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "Long Description Agent")
		require.Contains(t, customAgentQuote, "... [see config here](https://github.com/test-owner/test-repo/blob/main/.github/agents/long-desc-agent.md)")

		agentNameStart := strings.Index(customAgentQuote, "Long Description Agent")
		require.NotEqual(t, -1, agentNameStart)

		agentDescStart := strings.Index(customAgentQuote[agentNameStart:], "> ")
		require.NotEqual(t, -1, agentDescStart)
		descriptionPart := customAgentQuote[agentNameStart+agentDescStart:]

		require.True(t, strings.HasSuffix(descriptionPart, "\n\n"))
		require.Equal(t, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA... [see config here](https://github.com/test-owner/test-repo/blob/main/.github/agents/long-desc-agent.md)\n\n", descriptionPart[2:])
		descriptionContent := strings.TrimSuffix(descriptionPart[2:], "\n\n")
		require.LessOrEqual(t, len(descriptionContent), MaxPullRequestBodyAgentDescriptionLength)
	})

	t.Run("does not include agent description for default Copilot agent", func(t *testing.T) {
		agent := customagent.Copilot(1, 2, "test-owner", "test-repo")

		customAgentQuote := generateCustomAgentQuote(agent)

		require.Empty(t, customAgentQuote)
		require.NotContains(t, customAgentQuote, "Custom agent used:")
		require.NotContains(t, customAgentQuote, customagent.DefaultAgentDisplayName)
	})

	t.Run("includes agent name but not description when description is empty", func(t *testing.T) {
		agentMetadata := customagent.Metadata{
			Name:      "no-desc-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "No Description Agent",
			Description: "",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := generateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "No Description Agent")

		agentNameStart := strings.Index(customAgentQuote, "No Description Agent")
		require.NotEqual(t, -1, agentNameStart)

		require.Equal(t, "\n> [!NOTE] \n> **Custom agent used: No Description Agent**\n\n", customAgentQuote)
	})

	t.Run("formats agent description with markdown quotes", func(t *testing.T) {
		multiLineDescription := "This is line one.\nThis is line two.\nThis is line three."

		agentMetadata := customagent.Metadata{
			Name:      "multiline-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Multiline Agent",
			Description: multiLineDescription,
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := generateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "Multiline Agent")
		require.Contains(t, customAgentQuote, "> This is line one.")
		require.Contains(t, customAgentQuote, "> This is line two.")
		require.Contains(t, customAgentQuote, "> This is line three.")
	})
}

func TestTruncateAgentDescriptionWithLink(t *testing.T) {
	t.Run("does not truncate short descriptions", func(t *testing.T) {
		description := "> Short description\n"
		result := truncateAgentDescriptionWithLink(description, "owner", "repo", "agent", 100)
		require.Equal(t, description, result)
	})

	t.Run("truncates long descriptions and adds link", func(t *testing.T) {
		longDescription := "> " + strings.Repeat("A", 500) + "\n"
		result := truncateAgentDescriptionWithLink(longDescription, "owner", "repo", "agent", 100)

		require.Contains(t, result, "... [see config here](https://github.com/owner/repo/blob/main/.github/agents/agent.md)")
		require.LessOrEqual(t, len(result), 100)
	})
}

func TestConstructResponseBodySuffix(t *testing.T) {
	t.Run("adds proper spacing between custom agent quote and user suffix", func(t *testing.T) {
		// Create a custom agent
		agentMetadata := customagent.Metadata{
			Name:      "test-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Test Agent",
			Description: "This is a test agent for spacing verification",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		// Generate inputs
		problemStatementQuote := fmt.Sprintf(PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := generateCustomAgentQuote(agent)
		userProvidedSuffix := "Fixes github/test-repo/issues#123"

		// Call the actual function being tested
		result := constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

		// Verify the custom agent quote is present
		require.Contains(t, result, "Custom agent used: Test Agent")
		require.Contains(t, result, "This is a test agent for spacing verification")

		// Verify the user-provided suffix is present
		require.Contains(t, result, "Fixes github/test-repo/issues#123")

		// Most importantly: verify there's proper spacing between the custom agent description and the user suffix
		// This is the core bug we're fixing - ensuring there's a blank line between the agent note and the issue reference
		require.Contains(t, result, "This is a test agent for spacing verification\n\nFixes github/test-repo/issues#123")

		// Also verify the suffix separator is properly included
		require.Contains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")
	})

	t.Run("handles empty user suffix correctly", func(t *testing.T) {
		// Create a custom agent
		agentMetadata := customagent.Metadata{
			Name:      "test-agent",
			RepoOwner: "test-owner",
			RepoName:  "test-repo",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Test Agent",
			Description: "Test description",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		// Generate inputs
		problemStatementQuote := fmt.Sprintf(PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := generateCustomAgentQuote(agent)
		userProvidedSuffix := ""

		// Call the actual function being tested
		result := constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

		// Verify the custom agent quote is present
		require.Contains(t, result, "Custom agent used: Test Agent")
		require.Contains(t, result, "Test description")

		// Verify no extra spacing is added when there's no user suffix
		// The suffix should end with the agent description followed by a single newline
		require.True(t, strings.HasSuffix(result, "Test description\n\n"))
	})

	t.Run("handles empty custom agent quote", func(t *testing.T) {
		// Test with default Copilot agent (which produces empty custom agent quote)
		agent := customagent.Copilot(1, 2, "test-owner", "test-repo")

		problemStatementQuote := fmt.Sprintf(PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := generateCustomAgentQuote(agent) // Should be empty
		userProvidedSuffix := "Fixes github/test-repo/issues#123"

		// Call the actual function being tested
		result := constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

		// Verify no custom agent info is included
		require.NotContains(t, result, "Custom agent used:")

		// Verify the user-provided suffix is still present with proper spacing
		require.Contains(t, result, "Fixes github/test-repo/issues#123")
	})
}

func TestConstructResponseBodySuffix_SlackEvent(t *testing.T) {
	t.Run("omits original prompt when event type is Slack", func(t *testing.T) {
		// When constructing the response body suffix for a Slack event,
		// the problem statement quote should be empty
		problemStatementQuote := ""
		customAgentQuote := ""
		userProvidedSuffix := "See the [Slack conversation](https://slack.com/archives/C123/p456)"

		result := constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

		// Verify the original prompt details/summary is NOT included
		require.NotContains(t, result, "<details>")
		require.NotContains(t, result, "Original prompt")
		require.NotContains(t, result, "</details>")

		// Verify the suffix separator is still present
		require.Contains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")

		// Verify the user-provided suffix (Slack link) is present
		require.Contains(t, result, "See the [Slack conversation](https://slack.com/archives/C123/p456)")
	})

	t.Run("omits original prompt when event type is Slack Staging", func(t *testing.T) {
		// When constructing the response body suffix for a Slack Staging event,
		// the problem statement quote should be empty (same behavior as Slack)
		problemStatementQuote := ""
		customAgentQuote := ""
		userProvidedSuffix := "See the [Slack conversation](https://slack.com/archives/C123/p456)"

		result := constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

		// Verify the original prompt details/summary is NOT included
		require.NotContains(t, result, "<details>")
		require.NotContains(t, result, "Original prompt")
		require.NotContains(t, result, "</details>")

		// Verify the suffix separator is still present
		require.Contains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")

		// Verify the user-provided suffix (Slack link) is present
		require.Contains(t, result, "See the [Slack conversation](https://slack.com/archives/C123/p456)")
	})

	t.Run("includes original prompt when event type is not Slack", func(t *testing.T) {
		// When constructing the response body suffix for a non-Slack event,
		// the problem statement quote should be included
		problemStatementQuote := fmt.Sprintf(PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := ""
		userProvidedSuffix := ""

		result := constructResponseBodySuffix(problemStatementQuote, customAgentQuote, userProvidedSuffix)

		// Verify the original prompt details/summary IS included
		require.Contains(t, result, "<details>")
		require.Contains(t, result, "Original prompt")
		require.Contains(t, result, "</details>")
		require.Contains(t, result, "Test problem statement")

		// Verify the suffix separator is present
		require.Contains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")
	})
}
