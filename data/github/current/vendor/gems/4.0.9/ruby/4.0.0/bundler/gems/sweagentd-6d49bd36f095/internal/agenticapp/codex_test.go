package agenticapp

import (
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

const testCodexAppID = int64(67890)

func TestNewCodex(t *testing.T) {
	appLogin := "codex-app"
	botLogin := "codex-bot"

	codex := NewCodex(testCodexAppID, appLogin, 123, botLogin, "commit-login", "commit@email.com")
	require.NotNil(t, codex)
	require.NotNil(t, codex.logins)
	require.NotNil(t, codex.mentionRegexp)
	require.Equal(t, testCodexAppID, codex.AppID())
	require.Equal(t, CodexAppName, codex.AppName())

	expectedLogins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}
	require.Equal(t, expectedLogins, codex.logins)
	require.Equal(t, "codex[agent]", codex.MentionableSlug())
}

func TestCodex_Getters(t *testing.T) {
	appID := int64(54321)
	botID := int64(98765)
	botLogin := "codex-bot"
	commitLogin := "commit-user"
	commitEmail := "commit@example.com"

	codex := NewCodex(appID, "codex-app", botID, botLogin, commitLogin, commitEmail)

	require.Equal(t, appID, codex.AppID())
	require.Equal(t, botID, codex.BotID())
	require.Equal(t, botLogin, codex.BotLogin())
	require.Equal(t, commitLogin, codex.CommitLogin())
	require.Equal(t, commitEmail, codex.CommitEmail())
	require.Equal(t, CodexAppName, codex.AppName())
	require.Equal(t, "codex[agent]", codex.MentionableSlug())
	require.Equal(t, map[string]string{sweagentd.MetadataCAPIIntegrationID: CodexCAPIIntegrationID}, codex.Metadata())
}

func TestCodex_hasLogin(t *testing.T) {
	codex := NewCodex(1, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{
			name:     "exact app login match",
			login:    "codex-app",
			expected: true,
		},
		{
			name:     "app login with [bot] suffix",
			login:    "codex-app[bot]",
			expected: true,
		},
		{
			name:     "bot login match",
			login:    "codex-bot",
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
			login:    "CODEX-APP",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := codex.hasLogin(tt.login)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestCodex_isMentioned(t *testing.T) {
	codex := NewCodex(1, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			name:     "mention at beginning",
			body:     "@codex[agent] please help",
			expected: true,
		},
		{
			name:     "mention in middle",
			body:     "Hey @codex[agent] can you fix this?",
			expected: true,
		},
		{
			name:     "mention at end",
			body:     "Can you help @codex[agent]",
			expected: true,
		},
		{
			name:     "case insensitive match",
			body:     "@Codex[agent] please help",
			expected: true,
		},
		{
			name:     "uppercase mention",
			body:     "@CODEX[agent] fix this",
			expected: true,
		},
		{
			name:     "mention with punctuation before",
			body:     "Hey,@codex[agent] help",
			expected: true,
		},
		{
			name:     "mention with punctuation after",
			body:     "@codex[agent], please help",
			expected: true,
		},
		{
			name:     "no mention",
			body:     "This is a normal comment",
			expected: false,
		},
		{
			name:     "mention without @",
			body:     "codex[agent] please help",
			expected: false,
		},
		{
			name:     "empty body",
			body:     "",
			expected: false,
		},
		{
			name:     "mention with newline",
			body:     "First line\n@codex[agent] second line",
			expected: true,
		},
		{
			name:     "multiple mentions",
			body:     "@codex[agent] fix this and @codex[agent] also that",
			expected: true,
		},
		{
			name:     "mention in inline code should be ignored",
			body:     "Check out `@codex[agent]` in the code",
			expected: false,
		},
		{
			name:     "mention in code block should be ignored",
			body:     "```\n@codex[agent]\n```",
			expected: false,
		},
		{
			name:     "mention outside code block should match",
			body:     "@codex[agent] check this ```code block```",
			expected: true,
		},
		{
			name:     "mention without [agent] suffix should not match",
			body:     "@codex please help",
			expected: false,
		},
		{
			name:     "mention with bang should not match",
			body:     "@!codex please help",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := codex.isMentioned(tt.body)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestCodex_isMentionedWithModel(t *testing.T) {
	codex := NewCodex(1, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com")

	tests := []struct {
		name          string
		body          string
		expectedModel string
		expectedMatch bool
	}{
		{
			name:          "mention with model at beginning",
			body:          "@codex[agent]+gpt-5.1-codex please help",
			expectedModel: "gpt-5.1-codex",
			expectedMatch: true,
		},
		{
			name:          "mention with model in middle",
			body:          "Hey @codex[agent]+gpt-5.2-codex can you fix this?",
			expectedModel: "gpt-5.2-codex",
			expectedMatch: true,
		},
		{
			name:          "mention with model at end",
			body:          "Can you help @codex[agent]+gpt-5.2-codex",
			expectedModel: "gpt-5.2-codex",
			expectedMatch: true,
		},
		{
			name:          "case insensitive",
			body:          "@CODEX[agent]+gpt-5.1-codex please help",
			expectedModel: "gpt-5.1-codex",
			expectedMatch: true,
		},
		{
			name:          "mention with model and punctuation after",
			body:          "@codex[agent]+gpt-5.1-codex, please help",
			expectedModel: "gpt-5.1-codex",
			expectedMatch: true,
		},
		{
			name:          "mention without model",
			body:          "@codex[agent] please help",
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
			body:          "Look at `@codex[agent]+gpt-5.1-codex` here",
			expectedModel: "",
			expectedMatch: false,
		},
		{
			name:          "mention with model containing dots",
			body:          "@codex[agent]+gpt-5.1 please help",
			expectedModel: "gpt-5.1",
			expectedMatch: true,
		},
		{
			name:          "mention with newline before",
			body:          "First line\n@codex[agent]+gpt-5.1-codex second line",
			expectedModel: "gpt-5.1-codex",
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
			model, ok := codex.isMentionedWithModel(tt.body)
			require.Equal(t, tt.expectedMatch, ok)
			require.Equal(t, tt.expectedModel, model)
		})
	}
}

func TestCodex_EdgeCases(t *testing.T) {
	t.Run("empty app login", func(t *testing.T) {
		codex := NewCodex(1, "", 0, "bot-login", "commit-login", "commit@email.com")
		require.NotNil(t, codex)

		require.True(t, codex.hasLogin(""))
		require.True(t, codex.hasLogin("bot-login"))
	})

	t.Run("empty bot login", func(t *testing.T) {
		codex := NewCodex(1, "app-login", 0, "", "commit-login", "commit@email.com")
		require.NotNil(t, codex)

		require.True(t, codex.hasLogin("app-login"))
		require.True(t, codex.hasLogin(""))
	})

	t.Run("both logins empty", func(t *testing.T) {
		codex := NewCodex(1, "", 0, "", "commit-login", "commit@email.com")
		require.NotNil(t, codex)

		require.True(t, codex.hasLogin(""))
	})
}
