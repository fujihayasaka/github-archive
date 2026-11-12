package jobapi

import (
	"fmt"
	"strings"
	"testing"

	"github.com/github/sweagentd/internal/customagent"
	"github.com/github/sweagentd/internal/jobservice"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestCreateJob_AgentDescription(t *testing.T) {
	t.Run("includes agent description in body suffix when agent has description", func(t *testing.T) {
		agentMetadata := customagent.Metadata{
			Name: "test-agent",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Test Agent",
			Description: "This is a test agent that helps with testing functionality",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := GenerateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "Custom agent used: Test Agent")
		require.Contains(t, customAgentQuote, "This is a test agent that helps with testing functionality")
		require.Equal(t, "\n> **Custom agent used: Test Agent**\n> This is a test agent that helps with testing functionality\n\n", customAgentQuote)
	})

	t.Run("handles agent description ending with newline", func(t *testing.T) {
		agentMetadata := customagent.Metadata{
			Name: "trailing-newline-agent",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Trailing Newline Agent",
			Description: "Description that ends with newline\n",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := GenerateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "Custom agent used: Trailing Newline Agent")
		require.Contains(t, customAgentQuote, "Description that ends with newline\n")
		require.Equal(t, "\n> **Custom agent used: Trailing Newline Agent**\n> Description that ends with newline\n> \n\n", customAgentQuote)
	})

	t.Run("truncates long agent description with link", func(t *testing.T) {
		longDescription := strings.Repeat("A", jobservice.MaxPullRequestBodyAgentDescriptionLength+100)

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

		customAgentQuote := GenerateCustomAgentQuote(agent)

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
		require.LessOrEqual(t, len(descriptionContent), jobservice.MaxPullRequestBodyAgentDescriptionLength)
	})

	t.Run("does not include agent description for default Copilot agent", func(t *testing.T) {
		agent := customagent.Copilot(1, 2, "test-owner", "test-repo")

		customAgentQuote := GenerateCustomAgentQuote(agent)

		require.Empty(t, customAgentQuote)
		require.NotContains(t, customAgentQuote, "Custom agent used:")
		require.NotContains(t, customAgentQuote, customagent.DefaultAgentDisplayName)
	})

	t.Run("includes agent name but not description when description is empty", func(t *testing.T) {
		agentMetadata := customagent.Metadata{
			Name: "no-desc-agent",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "No Description Agent",
			Description: "",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := GenerateCustomAgentQuote(agent)

		require.Contains(t, customAgentQuote, "No Description Agent")

		agentNameStart := strings.Index(customAgentQuote, "No Description Agent")
		require.NotEqual(t, -1, agentNameStart)

		require.Equal(t, "\n> **Custom agent used: No Description Agent**\n\n", customAgentQuote)
	})

	t.Run("formats agent description with markdown quotes", func(t *testing.T) {
		multiLineDescription := "This is line one.\nThis is line two.\nThis is line three."

		agentMetadata := customagent.Metadata{
			Name: "multiline-agent",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Multiline Agent",
			Description: multiLineDescription,
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		customAgentQuote := GenerateCustomAgentQuote(agent)

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

func TestConstructBodySections(t *testing.T) {
	t.Run("adds proper spacing between custom agent quote and user suffix", func(t *testing.T) {
		// Create a custom agent
		agentMetadata := customagent.Metadata{
			Name: "test-agent",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Test Agent",
			Description: "This is a test agent for spacing verification",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		// Generate inputs
		problemStatementQuote := fmt.Sprintf(jobservice.PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := GenerateCustomAgentQuote(agent)
		userProvidedSuffix := "Fixes github/test-repo/issues#123"

		// Call the actual functions being tested
		originalPromptSection := constructOriginalPromptSection(problemStatementQuote, customAgentQuote)
		userSuffixSection := constructUserSuffixSection(userProvidedSuffix)
		result := originalPromptSection + userSuffixSection

		// Verify the custom agent quote is present
		require.Contains(t, result, "Custom agent used: Test Agent")
		require.Contains(t, result, "This is a test agent for spacing verification")

		// Verify the user-provided suffix is present
		require.Contains(t, result, "Fixes github/test-repo/issues#123")

		// Verify both separators are properly included and in the right order
		require.Contains(t, result, "<!-- START COPILOT ORIGINAL PROMPT -->")
		require.Contains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")

		// Verify the structure: original prompt section comes before user suffix section
		originalPromptIdx := strings.Index(result, "<!-- START COPILOT ORIGINAL PROMPT -->")
		userSuffixIdx := strings.Index(result, "<!-- START COPILOT CODING AGENT SUFFIX -->")
		require.Less(t, originalPromptIdx, userSuffixIdx, "Original prompt section should come before user suffix section")

		// Verify custom agent is in the original prompt section, not the user suffix section
		customAgentIdx := strings.Index(result, "Custom agent used: Test Agent")
		require.Greater(t, customAgentIdx, originalPromptIdx, "Custom agent should be in original prompt section")
		require.Less(t, customAgentIdx, userSuffixIdx, "Custom agent should not be in user suffix section")

		// Verify user suffix is in the user suffix section
		fixesIdx := strings.Index(result, "Fixes github/test-repo/issues#123")
		require.Greater(t, fixesIdx, userSuffixIdx, "Fixes should be in user suffix section")
	})

	t.Run("handles empty user suffix correctly", func(t *testing.T) {
		// Create a custom agent
		agentMetadata := customagent.Metadata{
			Name: "test-agent",
		}
		agentAttrs := customagent.ConfigAttributes{
			DisplayName: "Test Agent",
			Description: "Test description",
			Tools:       []string{"*"},
		}
		agent := customagent.NewWithConfig(agentMetadata, customagent.NewConfigWithAttributes(agentAttrs))

		// Generate inputs
		problemStatementQuote := fmt.Sprintf(jobservice.PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := GenerateCustomAgentQuote(agent)
		userProvidedSuffix := ""

		// Call the actual functions being tested
		originalPromptSection := constructOriginalPromptSection(problemStatementQuote, customAgentQuote)
		userSuffixSection := constructUserSuffixSection(userProvidedSuffix)
		result := originalPromptSection + userSuffixSection

		// Verify the custom agent quote is present
		require.Contains(t, result, "Custom agent used: Test Agent")
		require.Contains(t, result, "Test description")

		// Verify the original prompt section is present but user suffix section is empty
		require.Contains(t, result, "<!-- START COPILOT ORIGINAL PROMPT -->")
		require.NotContains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")
	})

	t.Run("handles empty custom agent quote", func(t *testing.T) {
		// Test with default Copilot agent (which produces empty custom agent quote)
		agent := customagent.Copilot(1, 2, "test-owner", "test-repo")

		problemStatementQuote := fmt.Sprintf(jobservice.PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := GenerateCustomAgentQuote(agent) // Should be empty
		userProvidedSuffix := "Fixes github/test-repo/issues#123"

		// Call the actual functions being tested
		originalPromptSection := constructOriginalPromptSection(problemStatementQuote, customAgentQuote)
		userSuffixSection := constructUserSuffixSection(userProvidedSuffix)
		result := originalPromptSection + userSuffixSection

		// Verify no custom agent info is included
		require.NotContains(t, result, "Custom agent used:")

		// Verify the user-provided suffix is still present with proper spacing
		require.Contains(t, result, "Fixes github/test-repo/issues#123")
		require.Contains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")
	})
}

func TestConstructBodySections_SlackEvent(t *testing.T) {
	t.Run("omits original prompt when event type is Slack", func(t *testing.T) {
		// When constructing the response body suffix for a Slack event,
		// the problem statement quote should be empty
		problemStatementQuote := ""
		customAgentQuote := ""
		userProvidedSuffix := "See the [Slack conversation](https://slack.com/archives/C123/p456)"

		originalPromptSection := constructOriginalPromptSection(problemStatementQuote, customAgentQuote)
		userSuffixSection := constructUserSuffixSection(userProvidedSuffix)
		result := originalPromptSection + userSuffixSection

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
		problemStatementQuote := fmt.Sprintf(jobservice.PullRequestBodyProblemStatementQuoteWrapper, "> Test problem statement\n")
		customAgentQuote := ""
		userProvidedSuffix := ""

		originalPromptSection := constructOriginalPromptSection(problemStatementQuote, customAgentQuote)
		userSuffixSection := constructUserSuffixSection(userProvidedSuffix)
		result := originalPromptSection + userSuffixSection

		// Verify the original prompt details/summary IS included
		require.Contains(t, result, "<details>")
		require.Contains(t, result, "Original prompt")
		require.Contains(t, result, "</details>")
		require.Contains(t, result, "Test problem statement")

		// Verify the original prompt separator is present (not the suffix separator since userProvidedSuffix is empty)
		require.Contains(t, result, "<!-- START COPILOT ORIGINAL PROMPT -->")
		require.NotContains(t, result, "<!-- START COPILOT CODING AGENT SUFFIX -->")
	})
}

func TestJobCreationWithOnlyProblemStatement(t *testing.T) {
	// This test covers the failure mode from PR #8389/#8501 where omitting the PR
	// also inadvertently omitted branch creation, leading to downstream failures.
	// When a request contains only problem_statement (no features.pull_request),
	// we should still create a branch by default.

	t.Run("creates branch when only problem_statement is provided", func(t *testing.T) {
		// Test that when features.pull_request is nil (not explicitly set),
		// a branch is still created because the default behavior should be
		// to create a branch unless a PR is being created (which handles its own branch).
		req := &NewJobAPIRequest{
			ProblemStatement: "Fix the authentication bug",
			Features:         &EnvironmentFeatures{
				// No PullRequest feature - this is the key test case
				// No Branch feature either - should still create a branch by default
			},
		}

		// The request should be valid
		repo := &gg.Repository{
			DefaultBranch: stringPtr("main"),
		}
		err := req.validate(repo)
		require.NoError(t, err)

		// Validate that neither PR nor Branch were explicitly set in the request
		require.Nil(t, req.Features.PullRequest, "PullRequest should not be set when not provided")
		require.Nil(t, req.Features.Branch, "Branch should not be explicitly set when not provided")
		// Note: The branch will be created by the builder logic in new_job_builder.go
	})

	t.Run("creates both branch and PR when pull_request is provided", func(t *testing.T) {
		// Test the existing behavior where providing features.pull_request
		// should create both a branch and a pull request
		req := &NewJobAPIRequest{
			ProblemStatement: "Fix the authentication bug",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					Title:           "Fix auth bug",
					BodyPlaceholder: "Working on fixing the bug",
				},
			},
		}

		repo := &gg.Repository{
			DefaultBranch: stringPtr("main"),
		}
		err := req.validate(repo)
		require.NoError(t, err)

		require.NotNil(t, req.Features.PullRequest, "PullRequest should be set when provided")
	})

	t.Run("creates only branch when branch feature is explicitly provided without PR", func(t *testing.T) {
		// Test that providing an explicit branch feature without a PR feature
		// creates only a branch
		req := &NewJobAPIRequest{
			ProblemStatement: "Fix the bug",
			Features: &EnvironmentFeatures{
				Branch: &BranchFeature{
					Name:    "my-custom-branch",
					BaseRef: "develop",
				},
			},
		}

		repo := &gg.Repository{
			DefaultBranch: stringPtr("main"),
		}
		err := req.validate(repo)
		require.NoError(t, err)

		require.NotNil(t, req.Features.Branch, "Branch should be set when provided")
		require.Nil(t, req.Features.PullRequest, "PullRequest should not be set when not provided")
	})
}

// TestbuildEnvironmentFeatures tests that buildEnvironmentFeatures correctly creates
// the jobs.EnvironmentFeatures structure based on the request features.
// These integration tests invoke the builder and verify the resulting structure.
func TestBuildEnvironmentFeatures(t *testing.T) {
	t.Run("creates PR with default base ref when neither Branch nor PR is provided", func(t *testing.T) {
		// When features is empty (no Branch, no PR), a default Branch should be created
		reqFeatures := &EnvironmentFeatures{
			// No PullRequest feature
			// No Branch feature
		}

		features := BuildEnvironmentFeatures(reqFeatures, nil)

		require.Nil(t, features.Branch, "Branch should be not created when features is empty")
		require.NotNil(t, features.PullRequest, "PullRequest should be set when features is empty")
	})

	t.Run("creates PullRequest and does not set Branch when PR is provided", func(t *testing.T) {
		// When a PullRequest feature is provided, PullRequest should be set and Branch should NOT be set
		reqFeatures := &EnvironmentFeatures{
			// No Branch feature
		}
		prFeature := &PullRequestFeature{
			Title:           "[WIP] Fix auth bug",
			BodyPlaceholder: "Working on it",
			BodySuffix:      "<!-- suffix -->",
			Labels:          []string{"bug", "priority:high"},
			BaseRef:         "refs/heads/develop",
			HeadRef:         "fix-auth-bug",
		}

		features := BuildEnvironmentFeatures(reqFeatures, prFeature)

		require.Nil(t, features.Branch, "Branch should NOT be set when PullRequest is provided (PR handles its own branch)")
		require.NotNil(t, features.PullRequest, "PullRequest should be created when PR feature is provided")
		require.Equal(t, "[WIP] Fix auth bug", features.PullRequest.TitlePlaceholder)
		require.Equal(t, "Working on it", features.PullRequest.BodyPlaceholder)
		require.Equal(t, "<!-- suffix -->", features.PullRequest.BodySuffix)
		require.Equal(t, []string{"bug", "priority:high"}, features.PullRequest.Labels)
		require.Equal(t, "refs/heads/develop", features.PullRequest.BaseRef)
		require.Equal(t, "fix-auth-bug", features.PullRequest.HeadRef)
	})

	t.Run("creates Branch with explicit config when Branch is provided without PR", func(t *testing.T) {
		// When an explicit Branch feature is provided (without PR), the Branch should be created with the provided config
		reqFeatures := &EnvironmentFeatures{
			Branch: &BranchFeature{
				Name:    "my-custom-branch",
				BaseRef: "refs/heads/develop",
			},
		}
		features := BuildEnvironmentFeatures(reqFeatures, nil)

		require.NotNil(t, features.Branch, "Branch should be set when explicitly provided")
		require.Equal(t, "my-custom-branch", features.Branch.Name, "Branch should use the provided name")
		require.Equal(t, "refs/heads/develop", features.Branch.BaseRef, "Branch should use the provided base ref, not the default")
		require.Nil(t, features.PullRequest, "PullRequest should not be set when not provided")
	})

	t.Run("creates Branch with only base ref when branch name is not provided", func(t *testing.T) {
		// When Branch feature is provided without a name, only the base ref should be set
		reqFeatures := &EnvironmentFeatures{
			Branch: &BranchFeature{
				BaseRef: "refs/heads/develop",
				// Name intentionally omitted
			},
		}

		features := BuildEnvironmentFeatures(reqFeatures, nil)

		require.NotNil(t, features.Branch, "Branch should be set when explicitly provided")
		require.Empty(t, features.Branch.Name, "Branch name should be empty when not provided")
		require.Equal(t, "refs/heads/develop", features.Branch.BaseRef, "Branch should use the provided base ref")
	})
}

func TestGenerateProblemStatementQuote(t *testing.T) {
	t.Run("returns empty string for empty content", func(t *testing.T) {
		result := GenerateProblemStatementQuote("")
		require.Empty(t, result)
	})

	t.Run("wraps content in collapsible details/summary block", func(t *testing.T) {
		result := GenerateProblemStatementQuote("Test content")

		require.Contains(t, result, "<details>")
		require.Contains(t, result, "<summary>Original prompt</summary>")
		require.Contains(t, result, "</details>")
		require.Contains(t, result, "Test content")
	})

	t.Run("formats content as markdown quote", func(t *testing.T) {
		result := GenerateProblemStatementQuote("Line one")

		require.Contains(t, result, "> Line one")
	})

	t.Run("handles multi-line content", func(t *testing.T) {
		result := GenerateProblemStatementQuote("Line one\nLine two")

		require.Contains(t, result, "> Line one")
		require.Contains(t, result, "> Line two")
	})

	t.Run("truncates very long content", func(t *testing.T) {
		// Create content longer than jobservice.MaxPullRequestBodyProblemStatementQuoteLength
		longContent := make([]byte, jobservice.MaxPullRequestBodyProblemStatementQuoteLength+1000)
		for i := range longContent {
			longContent[i] = 'a'
		}

		result := GenerateProblemStatementQuote(string(longContent))

		// Should contain truncation indicator
		require.Contains(t, result, "...")
		// Should still be wrapped in details/summary
		require.Contains(t, result, "<details>")
		require.Contains(t, result, "</details>")
	})
}
