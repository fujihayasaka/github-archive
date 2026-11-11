package agenticapp

import (
	"context"
	"crypto/rsa"
	"math"
	"slices"
	"testing"
	"time"

	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/sweagentd"
)

// mockActorWithLogin is a test helper that implements sweagentd.ActorWithLogin
type mockActorWithLogin struct {
	actorID int64
	login   string
}

func (m mockActorWithLogin) GetActorID() int64 {
	return m.actorID
}

func (m mockActorWithLogin) GetLogin() string {
	return m.login
}

// mockAgenticApp is a test helper that implements sweagentd.AgenticApp
// and has hasLogin and isMentioned methods
type mockAgenticApp struct {
	appID       int64
	botID       int64
	validLogins []string
	mentionText string
}

func (m *mockAgenticApp) AppID() int64 {
	return m.appID
}

func (m *mockAgenticApp) AppName() string {
	return "Mock App"
}

func (m *mockAgenticApp) BranchPrefix() string {
	return "mock"
}

func (m *mockAgenticApp) BotID() int64 {
	return m.botID
}

func (m *mockAgenticApp) PrivateKey() *rsa.PrivateKey {
	return nil
}

func (m *mockAgenticApp) ClientID() string {
	return "mock-client-id"
}

func (m *mockAgenticApp) ClientSecret() string {
	return "mock-client-secret"
}

func (m *mockAgenticApp) BotLogin() string {
	return "mock-bot"
}

func (m *mockAgenticApp) CommitLogin() string {
	return "mock-commit"
}

func (m *mockAgenticApp) CommitEmail() string {
	return "mock@email.com"
}

func (m *mockAgenticApp) MentionableSlug() string {
	return "mock-app"
}

func (m *mockAgenticApp) ComputeSlug() string {
	return "mock-app"
}

func (m *mockAgenticApp) MintToken(ctx context.Context, client *gg.Client, tokenReq sweagentd.AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error) {
	return "", time.Unix(math.MaxInt64, 0), nil, nil
}

func (m *mockAgenticApp) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return nil
}

func (m *mockAgenticApp) SetupCompute(compute sweagentd.ComputeEnv) {
}

func (m *mockAgenticApp) hasLogin(login string) bool {
	return slices.Contains(m.validLogins, login)
}

func (m *mockAgenticApp) isMentioned(body string) bool {
	return body == m.mentionText
}

func TestNewProvider(t *testing.T) {
	copilot := NewCopilot(1, nil, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")

	provider := NewProvider(copilot, nil)
	require.NotNil(t, provider)
	require.Equal(t, copilot, provider.copilotApp)
}

func TestProvider_IsAgenticActor(t *testing.T) {
	copilot := NewCopilot(1, nil, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot, nil)

	tests := []struct {
		name     string
		actor    mockActorWithLogin
		expected bool
	}{
		{
			name: "copilot app login",
			actor: mockActorWithLogin{
				actorID: 1,
				login:   "github-copilot",
			},
			expected: true,
		},
		{
			name: "copilot bot login",
			actor: mockActorWithLogin{
				actorID: 2,
				login:   "github-copilot[bot]",
			},
			expected: true,
		},
		{
			name: "copilot-bot login",
			actor: mockActorWithLogin{
				actorID: 3,
				login:   "github-copilot-bot",
			},
			expected: true,
		},
		{
			name: "Copilot login",
			actor: mockActorWithLogin{
				actorID: 4,
				login:   "Copilot",
			},
			expected: true,
		},
		{
			name: "non-agentic actor",
			actor: mockActorWithLogin{
				actorID: 5,
				login:   "some-user",
			},
			expected: false,
		},
		{
			name: "empty login",
			actor: mockActorWithLogin{
				actorID: 6,
				login:   "",
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, result := provider.IsAgenticActor(tt.actor)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestProvider_HasAnyAgenticActor(t *testing.T) {
	copilot := NewCopilot(1, nil, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot, nil)

	tests := []struct {
		name     string
		actors   []mockActorWithLogin
		expected bool
	}{
		{
			name: "single agentic actor",
			actors: []mockActorWithLogin{
				{actorID: 1, login: "github-copilot"},
			},
			expected: true,
		},
		{
			name: "multiple actors with one agentic",
			actors: []mockActorWithLogin{
				{actorID: 1, login: "user1"},
				{actorID: 2, login: "github-copilot"},
				{actorID: 3, login: "user2"},
			},
			expected: true,
		},
		{
			name: "multiple agentic actors",
			actors: []mockActorWithLogin{
				{actorID: 1, login: "github-copilot"},
				{actorID: 2, login: "Copilot"},
			},
			expected: true,
		},
		{
			name: "no agentic actors",
			actors: []mockActorWithLogin{
				{actorID: 1, login: "user1"},
				{actorID: 2, login: "user2"},
			},
			expected: false,
		},
		{
			name:     "empty list",
			actors:   []mockActorWithLogin{},
			expected: false,
		},
		{
			name: "agentic actor at end",
			actors: []mockActorWithLogin{
				{actorID: 1, login: "user1"},
				{actorID: 2, login: "user2"},
				{actorID: 3, login: "github-copilot-bot"},
			},
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Convert to slice of interface
			actors := make([]mockActorWithLogin, len(tt.actors))
			copy(actors, tt.actors)

			// Create a slice that implements the interface properly
			var actorInterfaces []mockActorWithLogin
			actorInterfaces = append(actorInterfaces, actors...)

			// We need to call a different approach since Go's type system
			// Let's test this directly with the provider
			var hasAgentic bool
			for _, actor := range actorInterfaces {
				if _, isAgentic := provider.IsAgenticActor(actor); isAgentic {
					hasAgentic = true
					break
				}
			}
			require.Equal(t, tt.expected, hasAgentic)
		})
	}
}

func TestProvider_IsAgenticMention(t *testing.T) {
	copilot := NewCopilot(1, nil, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot, nil)

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			name:     "mention at start",
			body:     "@copilot please help",
			expected: true,
		},
		{
			name:     "mention in middle",
			body:     "Can you @copilot fix this?",
			expected: true,
		},
		{
			name:     "mention at end",
			body:     "Please help @copilot",
			expected: true,
		},
		{
			name:     "case insensitive",
			body:     "@Copilot help",
			expected: true,
		},
		{
			name:     "no mention",
			body:     "This is a comment without mention",
			expected: false,
		},
		{
			name:     "empty body",
			body:     "",
			expected: false,
		},
		{
			name:     "mention with newlines",
			body:     "First line\n@copilot second line",
			expected: true,
		},
		{
			name:     "mention in inline code",
			body:     "Example `@copilot` mention",
			expected: false,
		},
		{
			name:     "mention with bang should not match",
			body:     "@!copilot please help",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, result := provider.IsAgenticMention(tt.body)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestProvider_IsAgenticMentionWithModel(t *testing.T) {
	copilot := NewCopilot(1, nil, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot, nil)

	tests := []struct {
		name          string
		body          string
		expectedMatch bool
		expectedModel string
	}{
		{
			name:          "mention with model",
			body:          "@copilot+claude-opus.4.5 please help",
			expectedMatch: true,
			expectedModel: "claude-opus.4.5",
		},
		{
			name:          "mention without model",
			body:          "@copilot please help",
			expectedMatch: true,
			expectedModel: "",
		},
		{
			name:          "no mention",
			body:          "This is a comment without mention",
			expectedMatch: false,
			expectedModel: "",
		},
		{
			name:          "mention with model case insensitive",
			body:          "@COPILOT+claude-sonnet-4 help",
			expectedMatch: true,
			expectedModel: "claude-sonnet-4",
		},
		{
			name:          "mention with model in code block",
			body:          "Check `@copilot+claude-opus.4.5` here",
			expectedMatch: false,
			expectedModel: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, ok := provider.IsAgenticMentionWithModel(tt.body)
			require.Equal(t, tt.expectedMatch, ok)
			if ok {
				require.NotNil(t, result)
				require.Equal(t, tt.expectedModel, result.Model)
				require.NotNil(t, result.App)
			} else {
				require.Nil(t, result)
			}
		})
	}
}

func TestProvider_IsAgenticMentionWithModel_OtherApps(t *testing.T) {
	copilot := NewCopilot(1, nil, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	mockApp := &mockAgenticApp{
		appID:       100,
		botID:       101,
		validLogins: []string{"mock-app"},
		mentionText: "@mock-app please help",
	}
	provider := NewProvider(copilot, mockApp)

	tests := []struct {
		name          string
		body          string
		expectedMatch bool
		expectedModel string
		expectedAppID int64
	}{
		{
			name:          "copilot mention takes precedence",
			body:          "@copilot please help",
			expectedMatch: true,
			expectedModel: "",
			expectedAppID: 1,
		},
		{
			name:          "copilot mention with model takes precedence",
			body:          "@copilot+claude-opus.4.5 please help",
			expectedMatch: true,
			expectedModel: "claude-opus.4.5",
			expectedAppID: 1,
		},
		{
			name:          "other app mention returns app with no model",
			body:          "@mock-app please help",
			expectedMatch: true,
			expectedModel: "",
			expectedAppID: 100,
		},
		{
			name:          "no mention returns false",
			body:          "no mention here",
			expectedMatch: false,
			expectedModel: "",
			expectedAppID: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, ok := provider.IsAgenticMentionWithModel(tt.body)
			require.Equal(t, tt.expectedMatch, ok)
			if ok {
				require.NotNil(t, result)
				require.Equal(t, tt.expectedModel, result.Model)
				require.NotNil(t, result.App)
				require.Equal(t, tt.expectedAppID, result.App.AppID())
			} else {
				require.Nil(t, result)
			}
		})
	}
}

func TestProvider_WithNilCopilot(t *testing.T) {
	// Test that provider handles nil copilot gracefully (though this shouldn't happen in practice)
	provider := NewProvider(nil, nil)
	require.NotNil(t, provider)
	require.Nil(t, provider.copilotApp)

	// These should panic since copilotApp is nil - we're testing defensive behavior
	// In real usage, NewProvider should always be called with a valid Copilot
	t.Run("IsAgenticActor panics with nil copilot", func(t *testing.T) {
		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic with nil copilotApp")
			}
		}()
		actor := mockActorWithLogin{actorID: 1, login: "test"}
		provider.IsAgenticActor(actor)
	})

	t.Run("IsAgenticMention panics with nil copilot", func(t *testing.T) {
		defer func() {
			if r := recover(); r == nil {
				t.Error("Expected panic with nil copilotApp")
			}
		}()
		_, _ = provider.IsAgenticMention("@copilot")
	})
}

func TestProvider_MultipleAppsScenario(t *testing.T) {
	// Test scenario with different app configurations
	t.Run("different app logins", func(t *testing.T) {
		copilot1 := NewCopilot(1, nil, "app1", 10, "bot1", "commit-login", "commit@email.com", "client-id", "client-secret")
		provider1 := NewProvider(copilot1, nil)

		copilot2 := NewCopilot(2, nil, "app2", 20, "bot2", "commit-login", "commit@email.com", "client-id", "client-secret")
		provider2 := NewProvider(copilot2, nil)

		actor1 := mockActorWithLogin{actorID: 1, login: "app1"}
		actor2 := mockActorWithLogin{actorID: 2, login: "app2"}

		// Each provider should only recognize its own app
		_, isAgentic := provider1.IsAgenticActor(actor1)
		require.True(t, isAgentic)
		_, isAgentic = provider1.IsAgenticActor(actor2)
		require.False(t, isAgentic)

		_, isAgentic = provider2.IsAgenticActor(actor1)
		require.False(t, isAgentic)
		_, isAgentic = provider2.IsAgenticActor(actor2)
		require.True(t, isAgentic)

		// Both should recognize "Copilot"
		copilotActor := mockActorWithLogin{actorID: 3, login: "Copilot"}
		_, isAgentic = provider1.IsAgenticActor(copilotActor)
		require.True(t, isAgentic)
		_, isAgentic = provider2.IsAgenticActor(copilotActor)
		require.True(t, isAgentic)
	})
}

func TestProvider_IsCopilotApp(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot)

	tests := []struct {
		name          string
		appID         int64
		expectErr     bool
		expectCopilot bool
	}{
		{
			name:          "matching copilot app ID",
			appID:         123,
			expectErr:     false,
			expectCopilot: true,
		},
		{
			name:          "non-matching app ID",
			appID:         999,
			expectErr:     true,
			expectCopilot: false,
		},
		{
			name:          "zero app ID defaults to copilot",
			appID:         0,
			expectErr:     false,
			expectCopilot: true,
		},
		{
			name:          "CCR app ID treated as copilot",
			appID:         946600,
			expectErr:     false,
			expectCopilot: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, err := provider.FindByID(tt.appID)
			if tt.expectErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, copilot, app)
			}

			require.Equal(t, tt.expectCopilot, provider.IsCopilotApp(tt.appID))
		})
	}
}

func TestProvider_CopilotApp(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot, nil)

	result := provider.CopilotApp()
	require.Equal(t, copilot, result)
}

func TestActorLoginFromString(t *testing.T) {
	tests := []struct {
		name     string
		login    string
		expected string
	}{
		{
			name:     "regular login",
			login:    "user123",
			expected: "user123",
		},
		{
			name:     "empty login",
			login:    "",
			expected: "",
		},
		{
			name:     "login with special chars",
			login:    "user-123[bot]",
			expected: "user-123[bot]",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actor := ActorLoginFromString(tt.login)
			require.Equal(t, tt.expected, actor.GetLogin())
		})
	}
}

func TestActorLoginsFromStrings(t *testing.T) {
	tests := []struct {
		name     string
		logins   []string
		expected []string
	}{
		{
			name:     "multiple logins",
			logins:   []string{"user1", "user2", "user3"},
			expected: []string{"user1", "user2", "user3"},
		},
		{
			name:     "single login",
			logins:   []string{"user1"},
			expected: []string{"user1"},
		},
		{
			name:     "empty list",
			logins:   []string{},
			expected: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actors := ActorLoginsFromStrings(tt.logins)
			require.Len(t, actors, len(tt.expected))
			for i, actor := range actors {
				require.Equal(t, tt.expected[i], actor.GetLogin())
			}
		})
	}
}

func TestProvider_FindByID(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	codex := NewCodex(789, nil, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com", "codex-client-id", "codex-client-secret", nil)
	provider := NewProvider(copilot, codex)

	tests := []struct {
		name      string
		appID     int64
		expectApp bool
		expectErr error
	}{
		{
			name:      "zero defaults to copilot",
			appID:     0,
			expectApp: true,
			expectErr: nil,
		},
		{
			name:      "CCR app ID defaults to copilot",
			appID:     946600,
			expectApp: true,
			expectErr: nil,
		},
		{
			name:      "copilot app ID",
			appID:     123,
			expectApp: true,
			expectErr: nil,
		},
		{
			name:      "codex app ID",
			appID:     789,
			expectApp: true,
			expectErr: nil,
		},
		{
			name:      "unknown app ID",
			appID:     999,
			expectApp: false,
			expectErr: ErrAgentNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, err := provider.FindByID(tt.appID)
			if tt.expectErr != nil {
				require.Error(t, err)
				require.ErrorIs(t, err, tt.expectErr)
				require.Nil(t, app)
			} else {
				require.NoError(t, err)
				require.NotNil(t, app)
				switch tt.appID {
				case 0, 946600, 123:
					require.Equal(t, copilot, app)
				case 789:
					require.Equal(t, codex, app)
				default:
					t.Errorf("unexpected appID: %d", tt.appID)
				}
			}
		})
	}
}

func TestProvider_FindByBotID(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	codex := NewCodex(789, nil, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com", "codex-client-id", "codex-client-secret", nil)
	provider := NewProvider(copilot, codex)

	tests := []struct {
		name      string
		botID     int64
		expectApp bool
		expectErr error
	}{
		{
			name:      "copilot bot ID",
			botID:     456,
			expectApp: true,
			expectErr: nil,
		},
		{
			name:      "codex bot ID",
			botID:     101112,
			expectApp: true,
			expectErr: nil,
		},
		{
			name:      "unknown bot ID",
			botID:     999,
			expectApp: false,
			expectErr: ErrAgentNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, err := provider.FindByBotID(tt.botID)
			if tt.expectErr != nil {
				require.Error(t, err)
				require.ErrorIs(t, err, tt.expectErr)
				require.Nil(t, app)
			} else {
				require.NoError(t, err)
				require.NotNil(t, app)
				switch tt.botID {
				case 456:
					require.Equal(t, copilot, app)
				case 101112:
					require.Equal(t, codex, app)
				default:
					t.Errorf("unexpected botID: %d", tt.botID)
				}
			}
		})
	}
}

func TestProvider_IsAgenticActorWithMultipleApps(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	codex := NewCodex(789, nil, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com", "codex-client-id", "codex-client-secret", nil)
	provider := NewProvider(copilot, codex)

	tests := []struct {
		name     string
		actor    mockActorWithLogin
		expected bool
	}{
		{
			name:     "copilot actor",
			actor:    mockActorWithLogin{actorID: 1, login: "github-copilot"},
			expected: true,
		},
		{
			name:     "codex actor",
			actor:    mockActorWithLogin{actorID: 2, login: "codex-app"},
			expected: true,
		},
		{
			name:     "non-agentic actor",
			actor:    mockActorWithLogin{actorID: 4, login: "random-user"},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, result := provider.IsAgenticActor(tt.actor)
			require.Equal(t, tt.expected, result)
			if result {
				require.NotNil(t, app)
			} else {
				require.Nil(t, app)
			}
		})
	}
}

func TestProvider_IsAgenticMentionWithMultipleApps(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	codex := NewCodex(789, nil, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com", "codex-client-id", "codex-client-secret", nil)
	provider := NewProvider(copilot, codex)

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{
			name:     "copilot mention",
			body:     "@copilot please help",
			expected: true,
		},
		{
			name:     "codex mention",
			body:     "@codex[agent] please help",
			expected: true,
		},
		{
			name:     "no mention",
			body:     "This is a comment",
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, result := provider.IsAgenticMention(tt.body)
			require.Equal(t, tt.expected, result)
			if result {
				require.NotNil(t, app)
			} else {
				require.Nil(t, app)
			}
		})
	}
}

func TestProvider_HasAnyAgenticActorWithActualMethod(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	provider := NewProvider(copilot, nil)

	tests := []struct {
		name     string
		logins   []string
		expected bool
	}{
		{
			name:     "single agentic actor",
			logins:   []string{"github-copilot"},
			expected: true,
		},
		{
			name:     "multiple actors with one agentic",
			logins:   []string{"user1", "github-copilot"},
			expected: true,
		},
		{
			name:     "no agentic actors",
			logins:   []string{"user1", "user2"},
			expected: false,
		},
		{
			name:     "empty list",
			logins:   []string{},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actorLogins := ActorLoginsFromStrings(tt.logins)
			app, result := provider.HasAnyAgenticActor(actorLogins)
			require.Equal(t, tt.expected, result)
			if result {
				require.NotNil(t, app)
			} else {
				require.Nil(t, app)
			}
		})
	}
}

func TestProvider_WithMockAgenticApp(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	mockApp := &mockAgenticApp{
		appID:       999,
		botID:       888,
		validLogins: []string{"mock-app", "mock-bot"},
		mentionText: "@mock-app please help",
	}
	provider := NewProvider(copilot, mockApp)

	t.Run("IsAgenticActor recognizes mock app login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: "mock-app"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, mockApp, app)
	})

	t.Run("IsAgenticActor recognizes mock bot login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 2, login: "mock-bot"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, mockApp, app)
	})

	t.Run("IsAgenticActor doesn't recognize invalid login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 3, login: "invalid-login"}
		app, result := provider.IsAgenticActor(actor)
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("IsAgenticMention recognizes mock app mention", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@mock-app please help")
		require.True(t, result)
		require.Equal(t, mockApp, app)
	})

	t.Run("IsAgenticMention doesn't recognize invalid mention", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@invalid please help")
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("FindByID returns mock app", func(t *testing.T) {
		app, err := provider.FindByID(999)
		require.NoError(t, err)
		require.Equal(t, mockApp, app)
	})

	t.Run("FindByBotID returns mock app", func(t *testing.T) {
		app, err := provider.FindByBotID(888)
		require.NoError(t, err)
		require.Equal(t, mockApp, app)
	})
}

func TestProvider_CodexAndClaudeIntegration(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	codex := NewCodex(789, nil, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com", "codex-client-id", "codex-client-secret", nil)
	claude := NewClaude(321, nil, "claude-app", 654, "claude-bot", "claude-commit", "claude@email.com", "claude-client-id", "claude-client-secret", nil)
	provider := NewProvider(copilot, codex, claude)

	t.Run("IsAgenticActor recognizes codex app login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: "codex-app"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticActor recognizes codex app login with [bot] suffix", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: "codex-app[bot]"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticActor recognizes codex bot login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 2, login: "codex-bot"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticActor recognizes claude app login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 3, login: "claude-app"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticActor recognizes claude app login with [bot] suffix", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 3, login: "claude-app[bot]"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticActor recognizes claude bot login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 4, login: "claude-bot"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticActor prioritizes copilot over other apps", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: "github-copilot"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(123), app.AppID())
	})

	t.Run("IsAgenticMention recognizes codex mention", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@codex[agent] please help with this")
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticMention recognizes codex mention case insensitive", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@CODEX[agent] fix this bug")
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticMention recognizes claude mention", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@claude[agent] can you help?")
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticMention should not recognizes claude mention without agent suffix", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@claude can you help?")
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("IsAgenticMention recognizes claude mention case insensitive", func(t *testing.T) {
		app, result := provider.IsAgenticMention("Hey @Claude[agent], fix this")
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticMention prioritizes copilot over other apps", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@copilot please review")
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(123), app.AppID())
	})

	t.Run("IsAgenticMention ignores mentions in code blocks for codex", func(t *testing.T) {
		app, result := provider.IsAgenticMention("Check this code: `@codex[agent]`")
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("IsAgenticMention ignores mentions in code blocks for claude", func(t *testing.T) {
		app, result := provider.IsAgenticMention("```\n@claude[agent] help\n```")
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("HasAnyAgenticActor with codex actor", func(t *testing.T) {
		actors := ActorLoginsFromStrings([]string{"random-user", "codex-bot", "another-user"})
		app, result := provider.HasAnyAgenticActor(actors)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("HasAnyAgenticActor with claude actor", func(t *testing.T) {
		actors := ActorLoginsFromStrings([]string{"random-user", "claude-bot", "another-user"})
		app, result := provider.HasAnyAgenticActor(actors)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("HasAnyAgenticActor with multiple agentic actors returns first actor match", func(t *testing.T) {
		actors := ActorLoginsFromStrings([]string{"codex-bot", "claude-bot", "github-copilot"})
		app, result := provider.HasAnyAgenticActor(actors)
		require.True(t, result)
		require.NotNil(t, app)
		// Should return codex as "codex-bot" is the first actor in the list that matches
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("HasAnyAgenticActor prioritizes copilot when copilot is first", func(t *testing.T) {
		actors := ActorLoginsFromStrings([]string{"github-copilot", "codex-bot", "claude-bot"})
		app, result := provider.HasAnyAgenticActor(actors)
		require.True(t, result)
		require.NotNil(t, app)
		require.Equal(t, int64(123), app.AppID())
	})

	t.Run("FindByID returns codex", func(t *testing.T) {
		app, err := provider.FindByID(789)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("FindByID returns claude", func(t *testing.T) {
		app, err := provider.FindByID(321)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("FindByBotID returns codex", func(t *testing.T) {
		app, err := provider.FindByBotID(101112)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("FindByBotID returns claude", func(t *testing.T) {
		app, err := provider.FindByBotID(654)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})
}

func TestProvider_OnlyCodex(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	codex := NewCodex(789, nil, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com", "codex-client-id", "codex-client-secret", nil)
	provider := NewProvider(copilot, codex)

	t.Run("IsAgenticActor recognizes codex", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: "codex-app"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticMention recognizes codex", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@codex[agent] help")
		require.True(t, result)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("IsAgenticActor does not recognize claude", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 2, login: "claude-app"}
		app, result := provider.IsAgenticActor(actor)
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("IsAgenticMention does not recognize claude", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@claude[agent] help")
		require.False(t, result)
		require.Nil(t, app)
	})
}

func TestProvider_OnlyClaude(t *testing.T) {
	copilot := NewCopilot(123, nil, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com", "client-id", "client-secret")
	claude := NewClaude(321, nil, "claude-app", 654, "claude-bot", "claude-commit", "claude@email.com", "claude-client-id", "claude-client-secret", nil)
	provider := NewProvider(copilot, claude)

	t.Run("IsAgenticActor recognizes claude", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: "claude-app"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticMention recognizes claude", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@claude[agent] help")
		require.True(t, result)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("IsAgenticActor does not recognize codex", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 2, login: "codex-app"}
		app, result := provider.IsAgenticActor(actor)
		require.False(t, result)
		require.Nil(t, app)
	})

	t.Run("IsAgenticMention does not recognize codex", func(t *testing.T) {
		app, result := provider.IsAgenticMention("@codex[agent] help")
		require.False(t, result)
		require.Nil(t, app)
	})
}
