package agenticapp

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"testing"

	"github.com/stretchr/testify/require"
)

const testCodexAppID = int64(67890)

func generateTestRSAKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	return key
}

func rsaKeyToPEM(key *rsa.PrivateKey) string {
	privateKeyBytes := x509.MarshalPKCS1PrivateKey(key)
	privateKeyPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: privateKeyBytes,
	})
	return string(privateKeyPEM)
}

func TestNewCodex(t *testing.T) {
	appLogin := "codex-app"
	botLogin := "codex-bot"
	privateKey := generateTestRSAKey(t)

	codex := NewCodex(testCodexAppID, privateKey, appLogin, 123, botLogin, "commit-login", "commit@email.com", "client-id", "client-secret", nil)
	require.NotNil(t, codex)
	require.NotNil(t, codex.logins)
	require.NotNil(t, codex.mentionRegexp)
	require.Equal(t, testCodexAppID, codex.AppID())
	require.Equal(t, privateKey, codex.PrivateKey())
	require.Equal(t, CodexAppName, codex.AppName())

	expectedLogins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}
	require.Equal(t, expectedLogins, codex.logins)
	require.Equal(t, "codex[agent]", codex.MentionableSlug())
}

func TestNewCodexWithPEM(t *testing.T) {
	privateKey := generateTestRSAKey(t)
	privateKeyPEM := rsaKeyToPEM(privateKey)

	codex, err := NewCodexWithPEM(testCodexAppID, privateKeyPEM, "codex-app", 123, "codex-bot", "commit-login", "commit@email.com", "client-id", "client-secret", nil)
	require.NoError(t, err)
	require.NotNil(t, codex)
	require.Equal(t, testCodexAppID, codex.AppID())
	require.NotNil(t, codex.PrivateKey())
	require.Equal(t, CodexAppName, codex.AppName())
}

func TestNewCodexWithPEM_InvalidKey(t *testing.T) {
	invalidPEM := "not a valid PEM"

	codex, err := NewCodexWithPEM(testCodexAppID, invalidPEM, "codex-app", 123, "codex-bot", "commit-login", "commit@email.com", "client-id", "client-secret", nil)
	require.Error(t, err)
	require.Nil(t, codex)
}

func TestCodex_Getters(t *testing.T) {
	privateKey := generateTestRSAKey(t)
	appID := int64(54321)
	botID := int64(98765)
	botLogin := "codex-bot"
	commitLogin := "commit-user"
	commitEmail := "commit@example.com"
	clientID := "test-client-id"
	clientSecret := "test-client-secret"

	codex := NewCodex(appID, privateKey, "codex-app", botID, botLogin, commitLogin, commitEmail, clientID, clientSecret, nil)

	require.Equal(t, appID, codex.AppID())
	require.Equal(t, privateKey, codex.PrivateKey())
	require.Equal(t, botID, codex.BotID())
	require.Equal(t, botLogin, codex.BotLogin())
	require.Equal(t, commitLogin, codex.CommitLogin())
	require.Equal(t, commitEmail, codex.CommitEmail())
	require.Equal(t, clientID, codex.ClientID())
	require.Equal(t, clientSecret, codex.ClientSecret())
	require.Equal(t, CodexAppName, codex.AppName())
	require.Equal(t, "codex[agent]", codex.MentionableSlug())
}

func TestCodex_hasLogin(t *testing.T) {
	codex := NewCodex(1, nil, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com", "client-id", "client-secret", nil)

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
	codex := NewCodex(1, nil, "codex-app", 2, "codex-bot", "commit-login", "commit@email.com", "client-id", "client-secret", nil)

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

func TestCodex_EdgeCases(t *testing.T) {
	t.Run("empty app login", func(t *testing.T) {
		codex := NewCodex(1, nil, "", 0, "bot-login", "commit-login", "commit@email.com", "client-id", "client-secret", nil)
		require.NotNil(t, codex)

		require.True(t, codex.hasLogin(""))
		require.True(t, codex.hasLogin("bot-login"))
	})

	t.Run("empty bot login", func(t *testing.T) {
		codex := NewCodex(1, nil, "app-login", 0, "", "commit-login", "commit@email.com", "client-id", "client-secret", nil)
		require.NotNil(t, codex)

		require.True(t, codex.hasLogin("app-login"))
		require.True(t, codex.hasLogin(""))
	})

	t.Run("both logins empty", func(t *testing.T) {
		codex := NewCodex(1, nil, "", 0, "", "commit-login", "commit@email.com", "client-id", "client-secret", nil)
		require.NotNil(t, codex)

		require.True(t, codex.hasLogin(""))
	})

	t.Run("nil private key is allowed", func(t *testing.T) {
		codex := NewCodex(1, nil, "app-login", 0, "bot-login", "commit-login", "commit@email.com", "client-id", "client-secret", nil)
		require.NotNil(t, codex)
		require.Nil(t, codex.PrivateKey())
	})
}
