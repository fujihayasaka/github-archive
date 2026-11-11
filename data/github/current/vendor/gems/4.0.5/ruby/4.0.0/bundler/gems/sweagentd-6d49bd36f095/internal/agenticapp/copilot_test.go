package agenticapp

import (
	"testing"

	"github.com/stretchr/testify/require"
)

const testAgentID = int64(12345)

func TestNewCopilot(t *testing.T) {
	appLogin := "github-copilot"
	botLogin := "github-copilot-bot"

	copilot := NewCopilot(testAgentID, appLogin, 0, botLogin, "commit-login", "commit@email.com")
	require.NotNil(t, copilot)
	require.NotNil(t, copilot.logins)
	require.NotNil(t, copilot.mentionRegexp)
	require.Equal(t, testAgentID, copilot.AppID())

	// Verify all expected logins are present
	expectedLogins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
		"Copilot",
	}
	require.Equal(t, expectedLogins, copilot.logins)
}

func TestCopilot_hasLogin(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "exact app login match",
			login:    "github-copilot",
			expected: true,
		},
		{
			name:     "app login with [bot] suffix",
			login:    "github-copilot[bot]",
			expected: true,
		},
		{
			name:     "bot login match",
			login:    "github-copilot-bot",
			expected: true,
		},
		{
			name:     "Copilot match",
			login:    "Copilot",
			expected: true,
		},
		{
			name:     "non-matching login",
			login:    "some-other-user",
			expected: false,
		},
		{
			name:     "empty login",
			login:    "",
			expected: false,
		},
		{
			name:     "case sensitive mismatch",
			login:    "GITHUB-COPILOT",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := copilot.hasLogin(tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestCopilot_isMentioned(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			name:     "mention at beginning",
			body:     "@copilot please help",
			expected: true,
		},
		{
			name:     "mention in middle",
			body:     "Hey @copilot can you fix this?",
			expected: true,
		},
		{
			name:     "mention at end",
			body:     "Can you help @copilot",
			expected: true,
		},
		{
			name:     "case insensitive match",
			body:     "@Copilot please help",
			expected: true,
		},
		{
			name:     "uppercase mention",
			body:     "@COPILOT fix this",
			expected: true,
		},
		{
			name:     "mention with punctuation before",
			body:     "Hey,@copilot help",
			expected: true,
		},
		{
			name:     "mention with punctuation after",
			body:     "@copilot, please help",
			expected: true,
		},
		{
			name:     "no mention",
			body:     "This is a normal comment",
			expected: false,
		},
		{
			name:     "mention as part of word",
			body:     "notacopilot",
			expected: false,
		},
		{
			name:     "mention without @",
			body:     "copilot please help",
			expected: false,
		},
		{
			name:     "empty body",
			body:     "",
			expected: false,
		},
		{
			name:     "mention with newline",
			body:     "First line\n@copilot second line",
			expected: true,
		},
		{
			name:     "mention inside inline code block",
			body:     "Look at `@copilot` here",
			expected: false,
		},
		{
			name:     "multiple mentions",
			body:     "@copilot fix this and @copilot also that",
			expected: true,
		},
		{
			name:     "mention with bang should not match",
			body:     "@!copilot please help",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := copilot.isMentioned(tt.body)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestCopilot_EdgeCases(t *testing.T) {
	t.Run("empty app login", func(t *testing.T) {
		copilot := NewCopilot(1, "", 0, "bot-login", "commit-login", "commit@email.com")
		require.NotNil(t, copilot)

		// Should still include the empty string in logins
		require.True(t, copilot.hasLogin(""))
		require.True(t, copilot.hasLogin("Copilot"))
		require.True(t, copilot.hasLogin("bot-login"))
	})

	t.Run("empty bot login", func(t *testing.T) {
		copilot := NewCopilot(1, "app-login", 0, "", "commit-login", "commit@email.com")
		require.NotNil(t, copilot)

		require.True(t, copilot.hasLogin("app-login"))
		require.True(t, copilot.hasLogin("Copilot"))
		require.True(t, copilot.hasLogin(""))
	})

	t.Run("both logins empty", func(t *testing.T) {
		copilot := NewCopilot(1, "", 0, "", "commit-login", "commit@email.com")
		require.NotNil(t, copilot)

		// Should still have "Copilot" and empty strings
		require.True(t, copilot.hasLogin("Copilot"))
		require.True(t, copilot.hasLogin(""))
	})
}

func TestCopilot_AppID(t *testing.T) {
	expectedAppID := int64(54321)
	copilot := NewCopilot(expectedAppID, "github-copilot", 0, "github-copilot-bot", "commit-login", "commit@email.com")

	actualAppID := copilot.AppID()
	require.Equal(t, expectedAppID, actualAppID)
}

func TestCopilot_isMentionedWithModel(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name          string
		body          string
		expectedModel string
		expectedMatch bool
	}{
		{
			name:          "mention with model at beginning",
			body:          "@copilot+claude-opus.4.5 please help",
			expectedModel: "claude-opus.4.5",
			expectedMatch: true,
		},
		{
			name:          "mention with model in middle",
			body:          "Hey @copilot+claude-sonnet-4 can you fix this?",
			expectedModel: "claude-sonnet-4",
			expectedMatch: true,
		},
		{
			name:          "mention with model at end",
			body:          "Can you help @copilot+gpt-5.2-codex",
			expectedModel: "gpt-5.2-codex",
			expectedMatch: true,
		},
		{
			name:          "case insensitive copilot",
			body:          "@COPILOT+claude-opus.4.5 please help",
			expectedModel: "claude-opus.4.5",
			expectedMatch: true,
		},
		{
			name:          "mention with model and punctuation after",
			body:          "@copilot+claude-sonnet-4, please help",
			expectedModel: "claude-sonnet-4",
			expectedMatch: true,
		},
		{
			name:          "mention without model",
			body:          "@copilot please help",
			expectedModel: "",
			expectedMatch: false,
		},
		{
			name:          "no mention at all",
			body:          "This is a normal comment",
			expectedModel: "",
			expectedMatch: false,
		},
		{
			name:          "mention with model inside code block",
			body:          "Look at `@copilot+claude-opus.4.5` here",
			expectedModel: "",
			expectedMatch: false,
		},
		{
			name:          "mention with model containing underscore",
			body:          "@copilot+model_with_underscore fix this",
			expectedModel: "model_with_underscore",
			expectedMatch: true,
		},
		{
			name:          "mention with model containing dots",
			body:          "@copilot+claude-3.7-sonnet please help",
			expectedModel: "claude-3.7-sonnet",
			expectedMatch: true,
		},
		{
			name:          "mention with newline before",
			body:          "First line\n@copilot+claude-opus.4.5 second line",
			expectedModel: "claude-opus.4.5",
			expectedMatch: true,
		},
		{
			name:          "empty body",
			body:          "",
			expectedModel: "",
			expectedMatch: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			model, ok := copilot.isMentionedWithModel(tt.body)
			require.Equal(t, tt.expectedMatch, ok)
			require.Equal(t, tt.expectedModel, model)
		})
	}
}
