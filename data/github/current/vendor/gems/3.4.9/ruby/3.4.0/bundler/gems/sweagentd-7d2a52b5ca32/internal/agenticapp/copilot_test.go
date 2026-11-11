package agenticapp

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewCopilot(t *testing.T) {
	appLogin := "github-copilot"
	botLogin := "github-copilot-bot"

	copilot, err := NewCopilot(appLogin, botLogin)
	require.NoError(t, err)
	require.NotNil(t, copilot)
	require.NotNil(t, copilot.logins)
	require.NotNil(t, copilot.mentionRegexp)

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
	copilot, err := NewCopilot("github-copilot", "github-copilot-bot")
	require.NoError(t, err)

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
	copilot, err := NewCopilot("github-copilot", "github-copilot-bot")
	require.NoError(t, err)

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
			name:     "multiple mentions",
			body:     "@copilot fix this and @copilot also that",
			expected: true,
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
		copilot, err := NewCopilot("", "bot-login")
		require.NoError(t, err)
		require.NotNil(t, copilot)

		// Should still include the empty string in logins
		require.True(t, copilot.hasLogin(""))
		require.True(t, copilot.hasLogin("Copilot"))
		require.True(t, copilot.hasLogin("bot-login"))
	})

	t.Run("empty bot login", func(t *testing.T) {
		copilot, err := NewCopilot("app-login", "")
		require.NoError(t, err)
		require.NotNil(t, copilot)

		require.True(t, copilot.hasLogin("app-login"))
		require.True(t, copilot.hasLogin("Copilot"))
		require.True(t, copilot.hasLogin(""))
	})

	t.Run("both logins empty", func(t *testing.T) {
		copilot, err := NewCopilot("", "")
		require.NoError(t, err)
		require.NotNil(t, copilot)

		// Should still have "Copilot" and empty strings
		require.True(t, copilot.hasLogin("Copilot"))
		require.True(t, copilot.hasLogin(""))
	})
}
