package agenticapp

import (
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

const testClaudeAppID = int64(11111)

func TestNewClaude(t *testing.T) {
	appLogin := "claude-app"
	botLogin := "claude-bot"

	claude := NewClaude(testClaudeAppID, appLogin, 456, botLogin, "commit-login", "commit@email.com")
	require.NotNil(t, claude)
	require.NotNil(t, claude.logins)
	require.NotNil(t, claude.mentionRegexp)
	require.Equal(t, testClaudeAppID, claude.AppID())
	require.Equal(t, ClaudeCodeAppName, claude.AppName())

	expectedLogins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}
	require.Equal(t, expectedLogins, claude.logins)
	require.Equal(t, "claude[agent]", claude.MentionableSlug())
}

func TestClaude_Getters(t *testing.T) {
	appID := int64(22222)
	botID := int64(33333)
	botLogin := "claude-bot"
	commitLogin := "commit-user"
	commitEmail := "commit@example.com"

	claude := NewClaude(appID, "claude-app", botID, botLogin, commitLogin, commitEmail)

	require.Equal(t, appID, claude.AppID())
	require.Equal(t, botID, claude.BotID())
	require.Equal(t, botLogin, claude.BotLogin())
	require.Equal(t, commitLogin, claude.CommitLogin())
	require.Equal(t, commitEmail, claude.CommitEmail())
	require.Equal(t, ClaudeCodeAppName, claude.AppName())
	require.Equal(t, "claude[agent]", claude.MentionableSlug())
	require.Equal(t, map[string]string{sweagentd.MetadataCAPIIntegrationID: ClaudeCAPIIntegrationID}, claude.Metadata())
}

func TestClaude_hasLogin(t *testing.T) {
	claude := NewClaude(1, "claude-app", 2, "claude-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "exact app login match",
			login:    "claude-app",
			expected: true,
		},
		{
			name:     "app login with [bot] suffix",
			login:    "claude-app[bot]",
			expected: true,
		},
		{
			name:     "bot login match",
			login:    "claude-bot",
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
			login:    "CLAUDE-APP",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := claude.hasLogin(tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestClaude_isMentioned(t *testing.T) {
	claude := NewClaude(1, "claude-app", 2, "claude-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			name:     "mention at beginning",
			body:     "@claude[agent] please help",
			expected: true,
		},
		{
			name:     "mention in middle",
			body:     "Hey @claude[agent] can you fix this?",
			expected: true,
		},
		{
			name:     "mention at end",
			body:     "Can you help @claude[agent]",
			expected: true,
		},
		{
			name:     "case insensitive match",
			body:     "@Claude[agent] please help",
			expected: true,
		},
		{
			name:     "uppercase mention",
			body:     "@CLAUDE[agent] fix this",
			expected: true,
		},
		{
			name:     "mention with punctuation before",
			body:     "Hey,@claude[agent] help",
			expected: true,
		},
		{
			name:     "mention with punctuation after",
			body:     "@claude[agent], please help",
			expected: true,
		},
		{
			name:     "no mention",
			body:     "This is a normal comment",
			expected: false,
		},
		{
			name:     "mention without @",
			body:     "claude[agent] please help",
			expected: false,
		},
		{
			name:     "empty body",
			body:     "",
			expected: false,
		},
		{
			name:     "mention with newline",
			body:     "First line\n@claude[agent] second line",
			expected: true,
		},
		{
			name:     "multiple mentions",
			body:     "@claude[agent] fix this and @claude[agent] also that",
			expected: true,
		},
		{
			name:     "mention in inline code should be ignored",
			body:     "Check out `@claude[agent]` in the code",
			expected: false,
		},
		{
			name:     "mention in code block should be ignored",
			body:     "```\n@claude[agent]\n```",
			expected: false,
		},
		{
			name:     "mention outside code block should match",
			body:     "@claude[agent] check this ```code block```",
			expected: true,
		},
		{
			name:     "mention without [agent] suffix should not match",
			body:     "@claude please help",
			expected: false,
		},
		{
			name:     "mention with bang should not match",
			body:     "@!claude please help",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := claude.isMentioned(tt.body)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestClaude_isMentionedWithModel(t *testing.T) {
	claude := NewClaude(1, "claude-app", 2, "claude-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name          string
		body          string
		expectedModel string
		expectedMatch bool
	}{
		{
			name:          "mention with model at beginning",
			body:          "@claude[agent]+claude-opus.4.5 please help",
			expectedModel: "claude-opus.4.5",
			expectedMatch: true,
		},
		{
			name:          "mention with model in middle",
			body:          "Hey @claude[agent]+claude-sonnet-4 can you fix this?",
			expectedModel: "claude-sonnet-4",
			expectedMatch: true,
		},
		{
			name:          "mention with model at end",
			body:          "Can you help @claude[agent]+claude-opus.4.5",
			expectedModel: "claude-opus.4.5",
			expectedMatch: true,
		},
		{
			name:          "case insensitive",
			body:          "@CLAUDE[agent]+claude-opus.4.5 please help",
			expectedModel: "claude-opus.4.5",
			expectedMatch: true,
		},
		{
			name:          "mention with model and punctuation after",
			body:          "@claude[agent]+claude-sonnet-4, please help",
			expectedModel: "claude-sonnet-4",
			expectedMatch: true,
		},
		{
			name:          "mention without model",
			body:          "@claude[agent] please help",
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
			body:          "Look at `@claude[agent]+claude-opus.4.5` here",
			expectedModel: "",
			expectedMatch: false,
		},
		{
			name:          "mention with model containing dots",
			body:          "@claude[agent]+claude-3.7-sonnet please help",
			expectedModel: "claude-3.7-sonnet",
			expectedMatch: true,
		},
		{
			name:          "mention with newline before",
			body:          "First line\n@claude[agent]+claude-opus.4.5 second line",
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
			model, ok := claude.isMentionedWithModel(tt.body)
			require.Equal(t, tt.expectedMatch, ok)
			require.Equal(t, tt.expectedModel, model)
		})
	}
}

func TestClaude_EdgeCases(t *testing.T) {
	t.Run("empty app login", func(t *testing.T) {
		claude := NewClaude(1, "", 0, "bot-login", "commit-login", "commit@email.com")
		require.NotNil(t, claude)

		require.True(t, claude.hasLogin(""))
		require.True(t, claude.hasLogin("bot-login"))
	})

	t.Run("empty bot login", func(t *testing.T) {
		claude := NewClaude(1, "app-login", 0, "", "commit-login", "commit@email.com")
		require.NotNil(t, claude)

		require.True(t, claude.hasLogin("app-login"))
		require.True(t, claude.hasLogin(""))
	})

	t.Run("both logins empty", func(t *testing.T) {
		claude := NewClaude(1, "", 0, "", "commit-login", "commit@email.com")
		require.NotNil(t, claude)

		require.True(t, claude.hasLogin(""))
	})
}
