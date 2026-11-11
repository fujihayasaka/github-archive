package aigen

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/openai/openai-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAIGenerationWithRealContent(t *testing.T) {
	t.Run("AI generates job data based on problem content", func(t *testing.T) {
		mockClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				// Simulate AI generating relevant job data based on the prompt
				jobDataResponse := `{
					"branch_name": "fix-user-authentication-login-bug",
					"session_name": "Fixing authentication login bug",
					"pull_request_title": "Fix user authentication login bug"
				}`
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: jobDataResponse,
							},
						},
					},
				}, nil
			},
		}

		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{})
		generator := NewNameGenerator(obsv, mockClient, ffs)

		job := &jobs.Job{
			ID:      "test-job-123",
			Action:  jobs.AgentActionFix,
			ActorID: 12345,
			ProblemStatement: jobs.ProblemStatement{
				Content: `There's a critical bug in the user authentication system where users can't log in after password reset. The issue seems to be in the password validation logic in auth/login.go around line 45. Users are getting "Invalid credentials" even with correct passwords.`,
			},
		}

		ctx := context.Background()
		jobData, err := generator.GenerateJobData(ctx, job)

		require.NoError(t, err)
		assert.Equal(t, "fix-user-authentication-login-bug", jobData.BranchName)
		assert.Equal(t, "Fixing authentication login bug", jobData.SessionName)
		assert.Equal(t, "Fix user authentication login bug", jobData.PullRequestTitle)
	})

	t.Run("AI generates appropriate data for different content types", func(t *testing.T) {
		mockClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				// Simulate AI generating relevant job data based on the prompt
				jobDataResponse := `{
					"branch_name": "fix-auth-login-bug",
					"session_name": "Fixing authentication login bug",
					"pull_request_title": "Fix authentication login bug in password validation"
				}`
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: jobDataResponse,
							},
						},
					},
				}, nil
			},
		}

		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{})
		generator := NewNameGenerator(obsv, mockClient, ffs)

		job := &jobs.Job{
			ID:      "test-job-123",
			Action:  jobs.AgentActionFix,
			ActorID: 12345,
			ProblemStatement: jobs.ProblemStatement{
				Content: `There's a critical bug in the user authentication system where users can't log in after password reset. The issue seems to be in the password validation logic in auth/login.go around line 45.`,
			},
		}

		ctx := context.Background()
		jobData, err := generator.GenerateJobData(ctx, job)

		require.NoError(t, err)
		assert.Equal(t, "fix-auth-login-bug", jobData.BranchName)
		assert.Equal(t, "Fixing authentication login bug", jobData.SessionName)
		assert.Equal(t, "Fix authentication login bug in password validation", jobData.PullRequestTitle)
	})

	t.Run("AI handles review action appropriately", func(t *testing.T) {
		mockClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				jobDataResponse := `{
					"branch_name": "review-api-error-handling",
					"session_name": "Reviewing API error handling changes",
					"pull_request_title": "Review API error handling improvements"
				}`
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: jobDataResponse,
							},
						},
					},
				}, nil
			},
		}

		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{})
		generator := NewNameGenerator(obsv, mockClient, ffs)

		job := &jobs.Job{
			ID:         "test-job-123",
			Action:     "review", // Not AgentActionFix
			ActorID:    12345,
			ActorLogin: "reviewer",
			ProblemStatement: jobs.ProblemStatement{
				Content: `Please review the error handling improvements in the API endpoints. The changes include better error messages and proper status codes.`,
			},
		}

		ctx := context.Background()
		jobData, err := generator.GenerateJobData(ctx, job)

		require.NoError(t, err)
		assert.Equal(t, "review-api-error-handling", jobData.BranchName)
		assert.Equal(t, "Reviewing API error handling changes", jobData.SessionName)
		assert.Equal(t, "Review API error handling improvements", jobData.PullRequestTitle)
	})

	t.Run("Long content is handled appropriately", func(t *testing.T) {
		mockClient := &capi.NoopClient{
			MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
				jobDataResponse := `{
					"branch_name": "fix-performance-optimization",
					"session_name": "Optimizing system performance",
					"pull_request_title": "Fix performance optimization issues"
				}`
				return &openai.ChatCompletion{
					Choices: []openai.ChatCompletionChoice{
						{
							Message: openai.ChatCompletionMessage{
								Content: jobDataResponse,
							},
						},
					},
				}, nil
			},
		}

		obsv := observability.NewNoopExporters()
		ffs := featureflags.NewNoopClient(map[string]bool{})
		generator := NewNameGenerator(obsv, mockClient, ffs)

		// Create a very long problem statement
		longContent := ""
		for i := 0; i < 100; i++ {
			longContent += "This is a very detailed description of a complex performance issue that affects multiple components in the system and requires careful analysis and optimization. "
		}

		job := &jobs.Job{
			ID:      "test-job-123",
			Action:  jobs.AgentActionFix,
			ActorID: 12345,
			ProblemStatement: jobs.ProblemStatement{
				Content: longContent,
			},
		}

		ctx := context.Background()
		jobData, err := generator.GenerateJobData(ctx, job)

		require.NoError(t, err)
		assert.Equal(t, "fix-performance-optimization", jobData.BranchName)
		assert.Equal(t, "Optimizing system performance", jobData.SessionName)
		assert.Equal(t, "Fix performance optimization issues", jobData.PullRequestTitle)
	})
}
