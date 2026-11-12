package joberrors

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestCopilotErrorCommentRegex(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected bool
	}{
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: issue-no-commits -->",
			input:    "<!-- copilot-coding-agent-error: issue-no-commits -->",
			expected: true,
		},
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: issue-generic-error -->",
			input:    "<!-- copilot-coding-agent-error: issue-generic-error -->",
			expected: true,
		},
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: issue-rules-error -->",
			input:    "<!-- copilot-coding-agent-error: issue-rules-error -->",
			expected: true,
		},
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: issue-generic-error -->",
			input:    "<!-- copilot-coding-agent-error: issue-generic-error -->",
			expected: true,
		},
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: generic-error -->",
			input:    "<!-- copilot-coding-agent-error: generic-error -->",
			expected: true,
		},
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: comment-setup-steps-invalid -->",
			input:    "<!-- copilot-coding-agent-error: comment-setup-steps-invalid -->",
			expected: true,
		},
		{
			name:     "Known comment directly <!-- copilot-coding-agent-error: issue-setup-steps-invalid -->",
			input:    "<!-- copilot-coding-agent-error: issue-setup-steps-invalid -->",
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := IsCopilotErrorComment(tt.input)
			require.Equal(t, tt.expected, result, "Expected result for input '%s' to be %v", tt.input, tt.expected)
		})
	}
}

func TestCreateErrorCommentAddsTelemetry(t *testing.T) {
	ctx := context.Background()
	obsv := observability.NewNoopExporters()
	gh := &github.NoopClient{}

	t.Run("telemetry tag is added to the comment body", func(t *testing.T) {
		err := CreateErrorComment(ctx, obsv, gh, 0, 1, "some error comment body")
		require.NoError(t, err)
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				require.Equal(t, int64(0), call.Args[0])
				require.Equal(t, 1, call.Args[1])
				require.Contains(t, call.Args[2], "some error comment body")
				require.True(t, IsCopilotErrorComment(call.Args[2].(string)))
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})

	t.Run("telemetry tag is not added to the comment body when it already exists", func(t *testing.T) {
		err := CreateErrorComment(ctx, obsv, gh, 0, 1, "some error comment body\n<!-- copilot-coding-agent-error: generic-error -->")
		require.NoError(t, err)
		pass := false
		for _, call := range gh.MethodCalls {
			if call.Method == "CreateComment" {
				require.Equal(t, int64(0), call.Args[0])
				require.Equal(t, 1, call.Args[1])
				body := call.Args[2].(string)
				require.Contains(t, body, "some error comment body")
				require.True(t, IsCopilotErrorComment(body))
				// the body should only contain a single occurrence of the copilot error comment
				matches := copilotErrorPattern.FindAllStringSubmatch(body, -1)
				require.Len(t, matches, 1, "Expected only one copilot error comment in the body")
				pass = true
			} else {
				t.Errorf("unexpected call: %s", call.Method)
			}
		}
		require.True(t, pass)
	})
}

func TestTruncate(t *testing.T) {
	t.Run("string shorter than limit", func(t *testing.T) {
		result := Truncate("hello", 10)
		require.Equal(t, "hello", result)
	})

	t.Run("string exactly at limit", func(t *testing.T) {
		result := Truncate("hello", 5)
		require.Equal(t, "hello", result)
	})

	t.Run("string longer than limit", func(t *testing.T) {
		result := Truncate("hello world", 5)
		require.Equal(t, "hello...", result)
	})

	t.Run("empty string", func(t *testing.T) {
		result := Truncate("", 5)
		require.Equal(t, "", result)
	})

	t.Run("zero limit", func(t *testing.T) {
		result := Truncate("hello", 0)
		require.Equal(t, "hello", result)
	})

	t.Run("negative limit", func(t *testing.T) {
		result := Truncate("hello", -1)
		require.Equal(t, "hello", result)
	})

	t.Run("unicode characters", func(t *testing.T) {
		result := Truncate("héllo wörld", 5)
		require.Equal(t, "héllo...", result)
	})

	t.Run("unicode characters at boundary", func(t *testing.T) {
		result := Truncate("héllo", 5)
		require.Equal(t, "héllo", result)
	})
}

func TestJobError(t *testing.T) {
	t.Run("ErrActionsSelfHostedRunnerLost has correct service and code", func(t *testing.T) {
		require.Equal(t, "actions", ErrActionsSelfHostedRunnerLost.Service)
		require.Equal(t, "self_hosted_runner_lost", ErrActionsSelfHostedRunnerLost.Code)
	})

	t.Run("ErrActionsSelfHostedRunnerLost String() returns correct format", func(t *testing.T) {
		require.Equal(t, "actions:self_hosted_runner_lost", ErrActionsSelfHostedRunnerLost.String())
	})

	t.Run("ErrActionsSelfHostedRunnerLost Error() returns correct format", func(t *testing.T) {
		require.Equal(t, "actions:self_hosted_runner_lost", ErrActionsSelfHostedRunnerLost.Error())
	})
}
