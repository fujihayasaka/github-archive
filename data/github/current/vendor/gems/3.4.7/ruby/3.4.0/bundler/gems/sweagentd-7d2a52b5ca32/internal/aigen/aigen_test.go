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

func TestSanitizeBranchName(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "basic case with spaces",
			input:    "fix user login bug",
			expected: "fix-user-login-bug",
		},
		{
			name:     "with special characters",
			input:    "fix: user@login.bug!",
			expected: "fix-userloginbug",
		},
		{
			name:     "with underscores",
			input:    "fix_user_login_bug",
			expected: "fix-user-login-bug",
		},
		{
			name:     "with multiple hyphens",
			input:    "fix---user---login",
			expected: "fix-user-login",
		},
		{
			name:     "with leading/trailing hyphens",
			input:    "-fix-user-login-",
			expected: "fix-user-login",
		},
		{
			name:     "too long name",
			input:    "this-is-a-very-long-branch-name-that-exceeds-the-maximum-allowed-length-for-branches",
			expected: "this-is-a-very-long-branch-name-that-exceeds-the-m",
		},
		{
			name:     "mixed case",
			input:    "Fix User Login Bug",
			expected: "fix-user-login-bug",
		},
		{
			name:     "empty string",
			input:    "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := sanitizeBranchName(tt.input)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestGenerateJobData(t *testing.T) {
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			jobDataResponse := `{
				"branch_name": "fix-authentication-issue",
				"session_name": "Fixing user authentication system",
				"pull_request_title": "Fix authentication bug in login flow"
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
			Content: "There is an authentication bug in the login flow that needs to be fixed.",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job)

	require.NoError(t, err)
	assert.Equal(t, "fix-authentication-issue", jobData.BranchName)
	assert.Equal(t, "Fixing user authentication system", jobData.SessionName)
	assert.Equal(t, "Fix authentication bug in login flow", jobData.PullRequestTitle)
}

func TestGenerateJobDataEmptyContent(t *testing.T) {
	mockClient := &capi.NoopClient{}
	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{})
	generator := NewNameGenerator(obsv, mockClient, ffs)

	job := &jobs.Job{
		ID:               "test-job-123",
		Action:           jobs.AgentActionFix,
		ActorID:          12345,
		ProblemStatement: jobs.ProblemStatement{Content: ""},
	}

	ctx := context.Background()
	_, err := generator.GenerateJobData(ctx, job)

	require.Error(t, err)
	assert.Contains(t, err.Error(), "no problem statement content available")
}

func TestGenerateJobDataWithReviewAction(t *testing.T) {
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			jobDataResponse := `{
				"branch_name": "fix-user-auth-issue",
				"session_name": "Fixing user authentication issue",
				"pull_request_title": "Fix user authentication issue"
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
		Action:     jobs.AgentActionFix,
		ActorID:    12345,
		ActorLogin: "testuser",
		ProblemStatement: jobs.ProblemStatement{
			Content: "There is an authentication bug in the login flow that needs to be fixed.",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job)

	require.NoError(t, err)
	assert.Equal(t, "fix-user-auth-issue", jobData.BranchName)
	assert.Equal(t, "Fixing user authentication issue", jobData.SessionName)
	assert.Equal(t, "Fix user authentication issue", jobData.PullRequestTitle)
}

func TestGenerateJobDataForReviewAction(t *testing.T) {
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			jobDataResponse := `{
				"branch_name": "review-auth-changes",
				"session_name": "Reviewing authentication code changes",
				"pull_request_title": "Review authentication changes in this PR"
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
			Content: "Please review the authentication changes in this PR.",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job)

	require.NoError(t, err)
	assert.Equal(t, "review-auth-changes", jobData.BranchName)
	assert.Equal(t, "Reviewing authentication code changes", jobData.SessionName)
	assert.Equal(t, "Review authentication changes in this PR", jobData.PullRequestTitle)
}

func TestGenerateJobDataBranchNameSanitization(t *testing.T) {
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			jobDataResponse := `{
				"branch_name": "Fix: User@Login.Bug!",
				"session_name": "Fixing user login bug",
				"pull_request_title": "Fix user login bug with special characters"
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
		Action:     jobs.AgentActionFix,
		ActorID:    12345,
		ActorLogin: "testuser",
		ProblemStatement: jobs.ProblemStatement{
			Content: "Some task content",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job)

	require.NoError(t, err)
	// Branch name should be sanitized
	assert.Equal(t, "fix-userloginbug", jobData.BranchName)
	assert.Equal(t, "Fixing user login bug", jobData.SessionName)
	assert.Equal(t, "Fix user login bug with special characters", jobData.PullRequestTitle)
}

func TestGenerateJobDataWithGPT5Nano(t *testing.T) {
	var usedModel string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			usedModel = body.Model
			jobDataResponse := `{
				"branch_name": "fix-authentication-issue",
				"session_name": "Fixing user authentication system",
				"pull_request_title": "Fix authentication bug in login flow"
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
	ffs := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentAINameGenerationUseGPT5Nano: true,
	})
	generator := NewNameGenerator(obsv, mockClient, ffs)

	job := &jobs.Job{
		ID:      "test-job-123",
		Action:  jobs.AgentActionFix,
		ActorID: 12345,
		ProblemStatement: jobs.ProblemStatement{
			Content: "There is an authentication bug in the login flow that needs to be fixed.",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job)

	require.NoError(t, err)
	assert.Equal(t, AIModelGPT5Nano, usedModel, "Expected gpt-5-nano model to be used when feature flag is enabled")
	assert.Equal(t, "fix-authentication-issue", jobData.BranchName)
	assert.Equal(t, "Fixing user authentication system", jobData.SessionName)
	assert.Equal(t, "Fix authentication bug in login flow", jobData.PullRequestTitle)
}

func TestGenerateJobDataWithDefaultModel(t *testing.T) {
	var usedModel string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			usedModel = body.Model
			jobDataResponse := `{
				"branch_name": "fix-authentication-issue",
				"session_name": "Fixing user authentication system",
				"pull_request_title": "Fix authentication bug in login flow"
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
	ffs := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentAINameGenerationUseGPT5Nano: false,
	})
	generator := NewNameGenerator(obsv, mockClient, ffs)

	job := &jobs.Job{
		ID:      "test-job-123",
		Action:  jobs.AgentActionFix,
		ActorID: 12345,
		ProblemStatement: jobs.ProblemStatement{
			Content: "There is an authentication bug in the login flow that needs to be fixed.",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job)

	require.NoError(t, err)
	assert.Equal(t, AIModelDefault, usedModel, "Expected gpt-4o-mini model to be used when feature flag is disabled")
	assert.Equal(t, "fix-authentication-issue", jobData.BranchName)
	assert.Equal(t, "Fixing user authentication system", jobData.SessionName)
	assert.Equal(t, "Fix authentication bug in login flow", jobData.PullRequestTitle)
}
