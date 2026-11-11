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

// defaultNameGeneratorDefaultPromptUniqueSnippet is a snippet that is present
// only in the default name-generation system prompt template. Using this in
// assertions ensures we truly verify that the default prompt was selected.
const defaultNameGeneratorDefaultPromptUniqueSnippet = "Refactoring legacy payment code"

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
	jobData, err := generator.GenerateJobData(ctx, job, "")

	require.NoError(t, err)
	assert.Equal(t, "fix-authentication-issue", jobData.BranchName)
	assert.Equal(t, "Fixing user authentication system", jobData.SessionName)
	assert.Equal(t, "Fix authentication bug in login flow", jobData.PullRequestTitle)
}

func TestGenerateJobDataUsesEventContentWhenFlagEnabled(t *testing.T) {
	var capturedUserMessage string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			for _, msg := range body.Messages {
				if msg.OfUser != nil {
					capturedUserMessage = msg.OfUser.Content.OfString.Value
				}
			}
			jobDataResponse := `{
				"branch_name": "user-prompt-branch",
				"session_name": "User prompt session",
				"pull_request_title": "User prompt PR"
			}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{Message: openai.ChatCompletionMessage{Content: jobDataResponse}},
				},
			}, nil
		},
	}

	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentAINameGenerationUseEventContent: true,
	})
	generator := NewNameGenerator(obsv, mockClient, ffs)

	job := &jobs.Job{
		ID:           "test-job-123",
		Action:       jobs.AgentActionFix,
		ActorID:      12345,
		EventContent: "Fix the typo in README",
		ProblemStatement: jobs.ProblemStatement{
			Content: "Full problem statement with lots of derived context like issue body, repo info, etc.",
		},
	}

	_, err := generator.GenerateJobData(context.Background(), job, "")
	require.NoError(t, err)
	assert.Equal(t, "Fix the typo in README", capturedUserMessage)
}

func TestGenerateJobDataFallsBackToProblemStatementWhenEventContentEmpty(t *testing.T) {
	var capturedUserMessage string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			for _, msg := range body.Messages {
				if msg.OfUser != nil {
					capturedUserMessage = msg.OfUser.Content.OfString.Value
				}
			}
			jobDataResponse := `{
				"branch_name": "fallback-branch",
				"session_name": "Fallback session",
				"pull_request_title": "Fallback PR"
			}`
			return &openai.ChatCompletion{
				Choices: []openai.ChatCompletionChoice{
					{Message: openai.ChatCompletionMessage{Content: jobDataResponse}},
				},
			}, nil
		},
	}

	obsv := observability.NewNoopExporters()
	ffs := featureflags.NewNoopClient(map[string]bool{
		featureflags.CopilotSWEAgentAINameGenerationUseEventContent: true,
	})
	generator := NewNameGenerator(obsv, mockClient, ffs)

	job := &jobs.Job{
		ID:           "test-job-123",
		Action:       jobs.AgentActionFix,
		ActorID:      12345,
		EventContent: "",
		ProblemStatement: jobs.ProblemStatement{
			Content: "Full problem statement",
		},
	}

	_, err := generator.GenerateJobData(context.Background(), job, "")
	require.NoError(t, err)
	assert.Equal(t, "Full problem statement", capturedUserMessage)
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
	_, err := generator.GenerateJobData(ctx, job, "")

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
	jobData, err := generator.GenerateJobData(ctx, job, "")

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
	jobData, err := generator.GenerateJobData(ctx, job, "")

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
	jobData, err := generator.GenerateJobData(ctx, job, "")

	require.NoError(t, err)
	// Branch name should be sanitized
	assert.Equal(t, "fix-userloginbug", jobData.BranchName)
	assert.Equal(t, "Fixing user login bug", jobData.SessionName)
	assert.Equal(t, "Fix user login bug with special characters", jobData.PullRequestTitle)
}

func TestGenerateJobDataWithImprovedPrompt(t *testing.T) {
	var usedPrompt string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			// Extract the system prompt from the messages
			for _, msg := range body.Messages {
				if msg.OfSystem != nil {
					usedPrompt = msg.OfSystem.Content.OfString.Value
				}
			}
			jobDataResponse := `{
				"branch_name": "investigate-sdk-versions",
				"session_name": "Investigating SDK version compatibility",
				"pull_request_title": "Investigate SDK version compatibility for agents"
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
		featureflags.CopilotSWEAgentAINameGenerationImprovedPrompt: true,
	})
	generator := NewNameGenerator(obsv, mockClient, ffs)

	job := &jobs.Job{
		ID:      "test-job-123",
		Action:  jobs.AgentActionFix,
		ActorID: 12345,
		ProblemStatement: jobs.ProblemStatement{
			Content: "What version of the Codex and Claude Code SDKs is used?",
		},
	}

	ctx := context.Background()
	jobData, err := generator.GenerateJobData(ctx, job, "")

	require.NoError(t, err)
	assert.Contains(t, usedPrompt, "whether it is coding, research, investigation", "Expected improved prompt to be used when feature flag is enabled")
	assert.Equal(t, "investigate-sdk-versions", jobData.BranchName)
	assert.Equal(t, "Investigating SDK version compatibility", jobData.SessionName)
	assert.Equal(t, "Investigate SDK version compatibility for agents", jobData.PullRequestTitle)
}

func TestGenerateJobDataWithImprovedPromptDisabled(t *testing.T) {
	var usedPrompt string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			for _, msg := range body.Messages {
				if msg.OfSystem != nil {
					usedPrompt = msg.OfSystem.Content.OfString.Value
				}
			}
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
		featureflags.CopilotSWEAgentAINameGenerationImprovedPrompt: false,
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
	_, err := generator.GenerateJobData(ctx, job, "")

	require.NoError(t, err)
	assert.Contains(t, usedPrompt, defaultNameGeneratorDefaultPromptUniqueSnippet, "Expected default prompt to be used when feature flag is disabled")
}

func TestGenerateJobDataAppendsBranchNamePatternWhenFlagEnabled(t *testing.T) {
	var usedPrompt string
	mockClient := &capi.NoopClient{
		MockChatCompletions: func(ctx context.Context, userID string, interactionID string, body *openai.ChatCompletionNewParams) (*openai.ChatCompletion, error) {
			for _, msg := range body.Messages {
				if msg.OfSystem != nil {
					usedPrompt = msg.OfSystem.Content.OfString.Value
				}
			}
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
		featureflags.CopilotSWEAgentAIBranchNameGenerationFollowsRules: true,
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
	_, err := generator.GenerateJobData(ctx, job, "must start with copilot/*")

	require.NoError(t, err)
	assert.Contains(t, usedPrompt, "\n\nOnly if provided by the user prompt use their exact branch name and DO NOT ADD ANY EXTRA DESCRIPTIONS TO THE BRANCH NAME.\n\n**branch name must start with copilot/***")
}

func TestGenerateJobDataWithGPT54Nano(t *testing.T) {
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
		featureflags.CopilotSWEAgentAINameGenerationUseGPT54Nano: true,
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
	jobData, err := generator.GenerateJobData(ctx, job, "")

	require.NoError(t, err)
	assert.Equal(t, AIModelGPT54Nano, usedModel, "Expected gpt-5.4-nano model to be used when feature flag is enabled")
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
		featureflags.CopilotSWEAgentAINameGenerationUseGPT54Nano: false,
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
	jobData, err := generator.GenerateJobData(ctx, job, "")

	require.NoError(t, err)
	assert.Equal(t, AIModelDefault, usedModel, "Expected gpt-4o-mini model to be used when feature flag is disabled")
	assert.Equal(t, "fix-authentication-issue", jobData.BranchName)
	assert.Equal(t, "Fixing user authentication system", jobData.SessionName)
	assert.Equal(t, "Fix authentication bug in login flow", jobData.PullRequestTitle)
}
