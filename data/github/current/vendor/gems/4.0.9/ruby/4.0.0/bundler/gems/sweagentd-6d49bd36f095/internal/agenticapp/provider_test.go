package agenticapp

import (
	"context"
	"crypto/rsa"
	"slices"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/goerrors"
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
	name        string
}

func (m *mockAgenticApp) AppID() int64 {
	return m.appID
}

func (m *mockAgenticApp) AppName() string {
	if m.name != "" {
		return m.name
	}
	return "Mock App"
}

func (m *mockAgenticApp) WorkflowRunName(_ int) string {
	return ""
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

func (m *mockAgenticApp) EngineSlug() string {
	return m.ComputeSlug()
}

func (m *mockAgenticApp) RevokeToken(ctx context.Context, api sweagentd.GitHubAPI, token string) error {
	return nil
}

func (m *mockAgenticApp) ModelVendors() []string { return nil }

func (m *mockAgenticApp) SetupCompute(compute sweagentd.ComputeEnv) {
}

func (m *mockAgenticApp) HasSource() bool {
	return false
}

func (m *mockAgenticApp) SourceURL() string {
	return ""
}

func (m *mockAgenticApp) IsQuotaExempt() bool   { return false }
func (m *mockAgenticApp) UsesExperiments() bool { return true }

func (m *mockAgenticApp) AgentSource() *sweagentd.AgentSource { return nil }
func (m *mockAgenticApp) IsGlobalApp() bool                   { return false }
func (m *mockAgenticApp) IsPartnerApp() bool                  { return false }
func (m *mockAgenticApp) IsThirdPartyApp() bool               { return true }

func (m *mockAgenticApp) Metadata() map[string]string {
	return nil
}

func (m *mockAgenticApp) hasLogin(login string) bool {
	return slices.Contains(m.validLogins, login)
}

func (m *mockAgenticApp) isMentioned(body string) bool {
	return body == m.mentionText
}

func TestNewProvider(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	provider := NewProvider(copilot, nil)
	require.NotNil(t, provider)
	require.Equal(t, copilot, provider.CopilotApp())
}

func TestProvider_IsAgenticActor(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
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

func TestProvider_IsAgenticMentionWithModel_ThirdPartyAgents(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	claude := NewClaude(100, "claude-app", 101, "claude-bot", "commit-login", "commit@email.com")
	codex := NewCodex(200, "codex-app", 201, "codex-bot", "commit-login", "commit@email.com")
	provider := NewProvider(copilot, claude, codex)

	tests := []struct {
		name          string
		body          string
		expectedMatch bool
		expectedModel string
		expectedAppID int64
	}{
		{
			name:          "claude mention with model",
			body:          "@claude[agent]+claude-opus.4.5 please help",
			expectedMatch: true,
			expectedModel: "claude-opus.4.5",
			expectedAppID: 100,
		},
		{
			name:          "codex mention with model",
			body:          "@codex[agent]+gpt-5.1-codex please help",
			expectedMatch: true,
			expectedModel: "gpt-5.1-codex",
			expectedAppID: 200,
		},
		{
			name:          "claude mention without model",
			body:          "@claude[agent] please help",
			expectedMatch: true,
			expectedModel: "",
			expectedAppID: 100,
		},
		{
			name:          "codex mention without model",
			body:          "@codex[agent] please help",
			expectedMatch: true,
			expectedModel: "",
			expectedAppID: 200,
		},
		{
			name:          "copilot mention with model still takes precedence",
			body:          "@copilot+claude-opus.4.5 please help",
			expectedMatch: true,
			expectedModel: "claude-opus.4.5",
			expectedAppID: 1,
		},
		{
			name:          "claude mention with model case insensitive",
			body:          "@CLAUDE[agent]+claude-sonnet-4 fix this",
			expectedMatch: true,
			expectedModel: "claude-sonnet-4",
			expectedAppID: 100,
		},
		{
			name:          "claude mention with model in code block ignored",
			body:          "Check `@claude[agent]+claude-opus.4.5` here",
			expectedMatch: false,
			expectedModel: "",
		},
		{
			name:          "no mention at all",
			body:          "no mention here",
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
	require.Nil(t, provider.CopilotApp())

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
		copilot1 := NewCopilot(1, "app1", 10, "bot1", "commit-login", "commit@email.com")
		provider1 := NewProvider(copilot1, nil)

		copilot2 := NewCopilot(2, "app2", 20, "bot2", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	ccrApp := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 456, "github-copilot-code-review-bot", "commit-login", "commit@email.com")
	provider := NewProvider(copilot, ccrApp)

	tests := []struct {
		name          string
		appID         int64
		expectErr     bool
		expectCopilot bool
		expectCCR     bool
	}{
		{
			name:          "matching copilot app ID",
			appID:         123,
			expectErr:     false,
			expectCopilot: true,
			expectCCR:     false,
		},
		{
			name:          "non-matching app ID",
			appID:         999,
			expectErr:     true,
			expectCopilot: false,
			expectCCR:     false,
		},
		{
			name:          "zero app ID defaults to copilot",
			appID:         0,
			expectErr:     false,
			expectCopilot: true,
			expectCCR:     false,
		},
		{
			name:          "CCR app ID is not treated as copilot",
			appID:         testCCRAppID,
			expectErr:     false,
			expectCopilot: false,
			expectCCR:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, err := provider.FindByID(context.Background(), tt.appID)
			if tt.expectErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				switch {
				case tt.expectCopilot:
					require.Equal(t, copilot, app)
				case tt.expectCCR:
					require.Equal(t, ccrApp, app)
				default:
					t.Errorf("unexpected app found for appID %d", tt.appID)
				}
			}

			require.Equal(t, tt.expectCopilot || tt.expectCCR, provider.IsCopilotApp(tt.appID))
		})
	}
}

func TestProvider_IsCopilotApp_CCRNotConfigured(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
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
			name:          "CCR app ID returns error when CCR is not configured",
			appID:         testCCRAppID,
			expectErr:     true,
			expectCopilot: false,
		},
		{
			name:          "non-matching app ID",
			appID:         999,
			expectErr:     true,
			expectCopilot: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			app, err := provider.FindByID(context.Background(), tt.appID)
			if tt.expectErr {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				switch {
				case tt.expectCopilot:
					require.Equal(t, copilot, app)
				default:
					t.Errorf("unexpected app found for appID %d", tt.appID)
				}
			}

			require.Equal(t, tt.expectCopilot, provider.IsCopilotApp(tt.appID))
		})
	}
}

func TestProvider_IsCopilotCodingAgentApp(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	ccrApp := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 456, "github-copilot-code-review-bot", "commit-login", "commit@email.com")
	codeScanning := NewCodeScanning(789, CodeScanningComputeSlug, 1011, CodeScanningComputeSlug+"[bot]", "cs-commit", "cs@email.com")
	provider := NewProvider(copilot, ccrApp, codeScanning)

	tests := []struct {
		name   string
		appID  int64
		expect bool
	}{
		{name: "matching copilot app ID", appID: 123, expect: true},
		{name: "zero defaults to copilot", appID: 0, expect: true},
		{name: "CCR is not CCA", appID: testCCRAppID, expect: false},
		{name: "code scanning is not CCA", appID: 789, expect: false},
		{name: "unknown app is not CCA", appID: 999, expect: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expect, provider.IsCopilotCodingAgentApp(tt.appID))
		})
	}
}

func TestProvider_IsCodeScanningApp(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codeScanning := NewCodeScanning(789, CodeScanningComputeSlug, 1011, CodeScanningComputeSlug+"[bot]", "cs-commit", "cs@email.com")

	tests := []struct {
		name                  string
		apps                  []sweagentd.AgenticApp
		appID                 int64
		expectCodeScanningApp bool
	}{
		{
			name:                  "code scanning app returns true",
			apps:                  []sweagentd.AgenticApp{codeScanning},
			appID:                 789,
			expectCodeScanningApp: true,
		},
		{
			name:                  "copilot app returns false",
			apps:                  []sweagentd.AgenticApp{codeScanning},
			appID:                 123,
			expectCodeScanningApp: false,
		},
		{
			name:                  "unknown app returns false",
			apps:                  []sweagentd.AgenticApp{codeScanning},
			appID:                 999,
			expectCodeScanningApp: false,
		},
		{
			name:                  "code scanning not configured returns false",
			apps:                  nil,
			appID:                 789,
			expectCodeScanningApp: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			provider := NewProvider(copilot, tt.apps...)
			result := provider.IsCodeScanningApp(tt.appID)
			require.Equal(t, tt.expectCodeScanningApp, result)
		})
	}
}

func TestProvider_IsThirdPartyAgent(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codeScanning := NewCodeScanning(555, CodeScanningComputeSlug, 556, CodeScanningComputeSlug+"[bot]", "cs-commit", "cs@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")

	codex := &mockAgenticApp{
		appID:       789,
		botID:       1011,
		validLogins: []string{"codex-app", "codex-bot"},
		mentionText: "@codex",
	}

	claude := &mockAgenticApp{
		appID:       1213,
		botID:       1415,
		validLogins: []string{"claude-app", "claude-bot"},
		mentionText: "@claude",
	}

	provider := NewProvider(copilot, codeScanning, ccr, codex, claude)

	tests := []struct {
		name             string
		app              sweagentd.AgenticApp
		expectThirdParty bool
	}{
		{
			name:             "copilot app is not third-party",
			app:              copilot,
			expectThirdParty: false,
		},
		{
			name:             "code scanning app is not third-party",
			app:              codeScanning,
			expectThirdParty: false,
		},
		{
			name:             "copilot code review app is not third-party",
			app:              ccr,
			expectThirdParty: false,
		},
		{
			name:             "codex app is third-party",
			app:              codex,
			expectThirdParty: true,
		},
		{
			name:             "claude app is third-party",
			app:              claude,
			expectThirdParty: true,
		},
		{
			name:             "nil app is not third-party",
			app:              nil,
			expectThirdParty: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := provider.IsThirdPartyAgent(tt.app)
			require.Equal(t, tt.expectThirdParty, result)
		})
	}
}

func TestProvider_CopilotApp(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codex := NewCodex(789, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")
	provider := NewProvider(copilot, codex, ccr)

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
			name:      "CCR app ID is not treated as copilot",
			appID:     testCCRAppID,
			expectApp: false,
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
			app, err := provider.FindByID(context.Background(), tt.appID)
			if tt.expectErr != nil {
				require.Error(t, err)
				require.ErrorIs(t, err, tt.expectErr)
				require.Nil(t, app)
			} else {
				require.NoError(t, err)
				require.NotNil(t, app)
				switch tt.appID {
				case 0, 123:
					require.Equal(t, copilot, app)
				case 789:
					require.Equal(t, codex, app)
				case testCCRAppID:
					require.Equal(t, ccr, app)
				default:
					t.Errorf("unexpected appID: %d", tt.appID)
				}
			}
		})
	}
}

func TestProvider_FindByBotID(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codex := NewCodex(789, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")
	provider := NewProvider(copilot, codex, ccr)

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
			app, err := provider.FindByBotID(context.Background(), tt.botID)
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
				case 501:
					require.Equal(t, ccr, app)
				default:
					t.Errorf("unexpected botID: %d", tt.botID)
				}
			}
		})
	}
}

func TestProvider_IsAgenticActorWithMultipleApps(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codex := NewCodex(789, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")
	provider := NewProvider(copilot, codex, ccr)

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
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codex := NewCodex(789, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")
	provider := NewProvider(copilot, codex, ccr)

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
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
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
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
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
		app, err := provider.FindByID(context.Background(), 999)
		require.NoError(t, err)
		require.Equal(t, mockApp, app)
	})

	t.Run("FindByBotID returns mock app", func(t *testing.T) {
		app, err := provider.FindByBotID(context.Background(), 888)
		require.NoError(t, err)
		require.Equal(t, mockApp, app)
	})
}

func TestProvider_CodexAndClaudeIntegration(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codex := NewCodex(789, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com")
	claude := NewClaude(321, "claude-app", 654, "claude-bot", "claude-commit", "claude@email.com")
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
		app, err := provider.FindByID(context.Background(), 789)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("FindByID returns claude", func(t *testing.T) {
		app, err := provider.FindByID(context.Background(), 321)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})

	t.Run("FindByBotID returns codex", func(t *testing.T) {
		app, err := provider.FindByBotID(context.Background(), 101112)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(789), app.AppID())
	})

	t.Run("FindByBotID returns claude", func(t *testing.T) {
		app, err := provider.FindByBotID(context.Background(), 654)
		require.NoError(t, err)
		require.NotNil(t, app)
		require.Equal(t, int64(321), app.AppID())
	})
}

func TestProvider_OnlyCodex(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	codex := NewCodex(789, "codex-app", 101112, "codex-bot", "codex-commit", "codex@email.com")
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
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	claude := NewClaude(321, "claude-app", 654, "claude-bot", "claude-commit", "claude@email.com")
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

func TestProvider_CopilotCodeReviewIntegration(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")
	provider := NewProvider(copilot, ccr)

	t.Run("FindByID returns CCR app", func(t *testing.T) {
		app, err := provider.FindByID(context.Background(), testCCRAppID)
		require.NoError(t, err)
		require.Equal(t, testCCRAppID, app.AppID())
	})

	t.Run("FindByBotID returns CCR app", func(t *testing.T) {
		app, err := provider.FindByBotID(context.Background(), 501)
		require.NoError(t, err)
		require.Equal(t, testCCRAppID, app.AppID())
	})

	t.Run("IsAgenticActor recognizes CCR app login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 1, login: CopilotCodeReviewComputeSlug}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, testCCRAppID, app.AppID())
	})

	t.Run("IsAgenticActor recognizes CCR bot login", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 2, login: "ccr-bot"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, testCCRAppID, app.AppID())
	})

	t.Run("IsAgenticActor recognizes CCR app login with [bot] suffix", func(t *testing.T) {
		actor := mockActorWithLogin{actorID: 3, login: CopilotCodeReviewComputeSlug + "[bot]"}
		app, result := provider.IsAgenticActor(actor)
		require.True(t, result)
		require.Equal(t, testCCRAppID, app.AppID())
	})

	t.Run("IsAgenticMention never matches CCR", func(t *testing.T) {
		bodies := []string{
			"@copilot-pull-request-reviewer please review",
			"@ccr-app help",
			"@ccr-bot do something",
			"@copilot please review",
		}
		for _, body := range bodies {
			app, result := provider.IsAgenticMention(body)
			if result {
				// If a match is found, it must be copilot, not CCR
				require.Equal(t, copilot, app, "CCR should never match mentions, but copilot may: %q", body)
			}
		}
	})

	t.Run("IsAgenticMentionWithModel never matches CCR", func(t *testing.T) {
		// Use a body that only mentions CCR's slug, not @copilot
		result, ok := provider.IsAgenticMentionWithModel("@ccr-app please review")
		require.False(t, ok)
		require.Nil(t, result)
	})

	t.Run("Apps includes CCR", func(t *testing.T) {
		apps := provider.Apps()
		require.Len(t, apps, 2)

		var foundCCR bool
		for _, app := range apps {
			if app.AppID() == testCCRAppID {
				foundCCR = true
			}
		}
		require.True(t, foundCCR, "CCR should be in Apps() list")
	})
}

func TestProvider_Reload(t *testing.T) {
	copilot1 := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	provider := NewProvider(copilot1)

	// Initial state
	require.Equal(t, int64(1), provider.CopilotApp().AppID())
	require.Len(t, provider.Apps(), 1)

	app, err := provider.FindByID(context.Background(), 1)
	require.NoError(t, err)
	require.Equal(t, int64(1), app.AppID())

	_, err = provider.FindByID(context.Background(), 99)
	require.Error(t, err)

	// Reload with new copilot and an additional app
	copilot2 := NewCopilot(10, "github-copilot-v2", 20, "github-copilot-bot-v2", "commit-login-v2", "commit-v2@email.com")
	mockApp := &mockAgenticApp{appID: 99, botID: 199}
	provider.Reload(copilot2, mockApp)

	// Verify new state
	require.Equal(t, int64(10), provider.CopilotApp().AppID())
	require.Len(t, provider.Apps(), 2)

	app, err = provider.FindByID(context.Background(), 10)
	require.NoError(t, err)
	require.Equal(t, int64(10), app.AppID())

	app, err = provider.FindByID(context.Background(), 99)
	require.NoError(t, err)
	require.Equal(t, int64(99), app.AppID())

	// Old app ID is no longer found
	_, err = provider.FindByID(context.Background(), 1)
	require.Error(t, err)
}

func TestProvider_HasAppID(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	mockApp := &mockAgenticApp{appID: 42, botID: 100}
	provider := NewProvider(copilot, mockApp)

	require.True(t, provider.HasAppID(1))
	require.True(t, provider.HasAppID(42))
	require.False(t, provider.HasAppID(999))
}

func TestProvider_Reload_ConcurrentAccess(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	provider := NewProvider(copilot)

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := range 1000 {
			newCopilot := NewCopilot(int64(i+10), "github-copilot", int64(i+20), "bot", "commit", "e@e.com")
			provider.Reload(newCopilot)
		}
	}()

	// Concurrent reads should not panic
	for range 1000 {
		_ = provider.CopilotApp()
		_ = provider.Apps()
		_, _ = provider.FindByID(context.Background(), 1)
		_, _ = provider.FindByBotID(context.Background(), 2)
		_ = provider.HasAppID(1)
	}

	<-done
}

func TestProvider_IsAgentJobLimitExempt(t *testing.T) {
	copilot := NewCopilot(123, "github-copilot", 456, "github-copilot-bot", "commit-login", "commit@email.com")
	ccr := NewCopilotCodeReview(testCCRAppID, CopilotCodeReviewComputeSlug, 501, "ccr-bot", "ccr-commit", "ccr@email.com")
	provider := NewProvider(copilot, ccr)
	ctx := context.Background()

	t.Run("CCR is exempt", func(t *testing.T) {
		require.True(t, provider.IsAgentJobLimitExempt(ctx, testCCRAppID))
	})

	t.Run("Copilot (CCA) is never exempt", func(t *testing.T) {
		require.False(t, provider.IsAgentJobLimitExempt(ctx, int64(123)))
	})

	t.Run("agentID 0 is never exempt", func(t *testing.T) {
		require.False(t, provider.IsAgentJobLimitExempt(ctx, 0))
	})

	t.Run("unknown agent is not exempt", func(t *testing.T) {
		require.False(t, provider.IsAgentJobLimitExempt(ctx, 99999))
	})
}

func TestProvider_JobLimitExemptAgentIDs(t *testing.T) {
	ccrAppID := int64(42)
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot[bot]", "commit-login", "commit@email.com")
	ccr := NewCopilotCodeReview(ccrAppID, "copilot-code-review", 43, "copilot-code-review[bot]", "commit-login", "commit@email.com")
	provider := NewProvider(copilot, ccr)

	ids := provider.JobLimitExemptAgentIDs()
	require.Equal(t, []int64{ccrAppID}, ids)
}

func TestFindByID_ReloadOnMiss(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}

	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return copilot, []sweagentd.AgenticApp{newApp}, nil
	}, nil, nil)

	app, err := provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), app.AppID())
	require.Equal(t, 1, reloadCount)
}

func TestFindByBotID_ReloadOnMiss(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}

	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return copilot, []sweagentd.AgenticApp{newApp}, nil
	}, nil, nil)

	app, err := provider.FindByBotID(context.Background(), 142)
	require.NoError(t, err)
	require.Equal(t, int64(142), app.BotID())
	require.Equal(t, 1, reloadCount)
}

func TestFindByID_ReloadOnMiss_StillNotFound(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return copilot, nil, nil
	}, nil, nil)

	_, err := provider.FindByID(context.Background(), 999)
	require.ErrorIs(t, err, ErrAgentNotFound)
	require.Equal(t, 1, reloadCount)
}

func TestFindByID_ReloadOnMiss_ReloadError(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		return nil, nil, goerrors.New("twirp unavailable")
	}, nil, nil)

	_, err := provider.FindByID(context.Background(), 999)
	require.ErrorIs(t, err, ErrAgentNotFound)
}

func TestFindByID_ReloadOnMiss_ReloadErrorAppliesCooldown(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	reloadCount := 0
	now := time.Now()
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return nil, nil, goerrors.New("twirp unavailable")
	}, nil, nil)
	provider.nowFunc = func() time.Time { return now }

	// First miss triggers reload (which fails).
	_, _ = provider.FindByID(context.Background(), 999)
	require.Equal(t, 1, reloadCount)

	// Second miss within cooldown should NOT trigger another reload, even though
	// the first one failed. This prevents thundering herd on a failing endpoint.
	now = now.Add(5 * time.Second)
	provider.nowFunc = func() time.Time { return now }
	_, _ = provider.FindByID(context.Background(), 888)
	require.Equal(t, 1, reloadCount)
}

func TestFindByID_ReloadOnMiss_Cooldown(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	reloadCount := 0
	now := time.Now()
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return copilot, nil, nil
	}, nil, nil)
	provider.nowFunc = func() time.Time { return now }

	// First miss triggers a reload.
	_, _ = provider.FindByID(context.Background(), 999)
	require.Equal(t, 1, reloadCount)

	// Second miss within cooldown should NOT trigger another reload.
	now = now.Add(5 * time.Second)
	provider.nowFunc = func() time.Time { return now }
	_, _ = provider.FindByID(context.Background(), 888)
	require.Equal(t, 1, reloadCount)

	// After cooldown expires, a miss triggers a reload again.
	now = now.Add(defaultReloadCooldown)
	provider.nowFunc = func() time.Time { return now }
	_, _ = provider.FindByID(context.Background(), 888)
	require.Equal(t, 2, reloadCount)
}

func TestFindByID_ReloadOnMiss_EventDrivenReloadResetsCooldown(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	reloadCount := 0
	now := time.Now()
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return copilot, nil, nil
	}, nil, nil)
	provider.nowFunc = func() time.Time { return now }

	// Miss triggers reload.
	_, _ = provider.FindByID(context.Background(), 999)
	require.Equal(t, 1, reloadCount)

	// Advance time past cooldown.
	now = now.Add(defaultReloadCooldown + time.Second)
	provider.nowFunc = func() time.Time { return now }

	// Simulate an event-driven Reload() -- updates lastReloadAt.
	provider.Reload(copilot)

	// A miss right after event-driven reload should NOT trigger another reload
	// because Reload() updated the cooldown timestamp.
	now = now.Add(1 * time.Second)
	provider.nowFunc = func() time.Time { return now }
	_, _ = provider.FindByID(context.Background(), 999)
	require.Equal(t, 1, reloadCount)
}

func TestFindByID_ReloadOnMiss_NoReloadFuncConfigured(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	provider := NewProvider(copilot)

	_, err := provider.FindByID(context.Background(), 999)
	require.ErrorIs(t, err, ErrAgentNotFound)
}

func TestFindByID_ReloadOnMiss_ConcurrentMissesCoalesce(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}

	var mu sync.Mutex
	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		time.Sleep(10 * time.Millisecond)
		mu.Lock()
		reloadCount++
		mu.Unlock()
		return copilot, []sweagentd.AgenticApp{newApp}, nil
	}, nil, nil)

	var wg sync.WaitGroup
	for range 20 {
		wg.Go(func() {
			_, _ = provider.FindByID(context.Background(), 42)
		})
	}
	wg.Wait()

	mu.Lock()
	defer mu.Unlock()
	require.Equal(t, 1, reloadCount)
}

func TestFindByID_ReloadOnMiss_HitSkipsReload(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")

	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		return copilot, nil, nil
	}, nil, nil)

	app, err := provider.FindByID(context.Background(), 1)
	require.NoError(t, err)
	require.Equal(t, int64(1), app.AppID())
	require.Equal(t, 0, reloadCount)

	app, err = provider.FindByID(context.Background(), 0)
	require.NoError(t, err)
	require.Equal(t, int64(1), app.AppID())
	require.Equal(t, 0, reloadCount)
}

// --- Race condition fix tests ---

func TestReload_AcquiresMutex_NoConcurrentOverwrite(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}
	newerApp := &mockAgenticApp{appID: 99, botID: 199}

	// Start a slow reload-on-miss
	reloadStarted := make(chan struct{})
	reloadContinue := make(chan struct{})
	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		close(reloadStarted)
		<-reloadContinue
		// Returns old data — simulates a slow monolith fetch
		return copilot, []sweagentd.AgenticApp{newApp}, nil
	}, nil, nil)

	done := make(chan struct{})
	go func() {
		defer close(done)
		// This will trigger reloadOnMiss which holds the mutex
		_, _ = provider.FindByID(context.Background(), 42)
	}()

	// Wait for reloadOnMiss to start and hold the mutex
	<-reloadStarted

	// Now simulate an event-driven Reload with newer data.
	// This should block on the mutex until reloadOnMiss finishes.
	reloadDone := make(chan struct{})
	go func() {
		defer close(reloadDone)
		provider.Reload(copilot, newerApp)
	}()

	// Let the slow reload finish
	close(reloadContinue)
	<-done
	<-reloadDone

	// The event-driven Reload ran after reloadOnMiss released the mutex,
	// so it should have the final say. App 99 should be present.
	_, err := provider.FindByID(context.Background(), 99)
	require.NoError(t, err)
}

// TestFindByID_CooldownTrippedByConcurrentReload verifies the race condition fix:
// when reloadOnMiss() returns (false, nil) because a concurrent event-driven
// Reload() set the cooldown while we were waiting on the mutex, the caller must
// re-check state and return the app rather than ErrAgentNotFound.
//
// Ordering guaranteed by the test:
//  1. Test goroutine holds reloadMu.
//  2. FindByID misses at step 2, then blocks in reloadOnMiss on reloadMu.Lock().
//  3. Background goroutine stores newApp in state (simulating Reload), then unlocks.
//  4. reloadOnMiss acquires lock, sees active cooldown → returns (false, nil).
//  5. With the fix: state is re-checked → newApp found → returned. ✓
func TestFindByID_CooldownTrippedByConcurrentReload(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}
	now := time.Now()

	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		// Should not be called: cooldown is active (set below).
		t.Error("reloadFn should not be called when cooldown is active")
		return nil, nil, nil
	}, nil, nil)
	provider.nowFunc = func() time.Time { return now }
	// Set cooldown active: simulates a prior Reload() having run.
	provider.lastReloadAt.Store(&now)

	// Hold reloadMu so FindByID's reloadOnMiss blocks waiting for it.
	// FindByID is called synchronously below, so this goroutine is guaranteed
	// to store state before FindByID's re-check can run.
	provider.reloadMu.Lock()
	go func() {
		// Store newApp (simulating what Reload() would have stored), then unlock.
		// Because this unlock happens before reloadOnMiss can proceed,
		// newApp is guaranteed to be in state at the time of the re-check.
		provider.state.Store(newProviderState(copilot, newApp))
		provider.reloadMu.Unlock()
	}()

	// FindByID: step 2 misses (state = {copilot only}), then blocks in reloadOnMiss
	// on reloadMu.Lock(). Goroutine above stores newApp and unlocks. reloadOnMiss
	// acquires lock, sees cooldown → returns (false, nil).
	// With fix: re-checks state → finds newApp → returns it. ✓
	app, err := provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), app.AppID())
}

// TestFindByBotID_CooldownTrippedByConcurrentReload mirrors the above for FindByBotID.
func TestFindByBotID_CooldownTrippedByConcurrentReload(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}
	now := time.Now()

	provider := NewProvider(copilot).WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		t.Error("reloadFn should not be called when cooldown is active")
		return nil, nil, nil
	}, nil, nil)
	provider.nowFunc = func() time.Time { return now }
	provider.lastReloadAt.Store(&now)

	provider.reloadMu.Lock()
	go func() {
		provider.state.Store(newProviderState(copilot, newApp))
		provider.reloadMu.Unlock()
	}()

	app, err := provider.FindByBotID(context.Background(), 142)
	require.NoError(t, err)
	require.Equal(t, int64(142), app.BotID())
}

// --- Context cancellation fix tests ---

func TestFindByID_ReloadOnMiss_ContextCanceledSkipsCooldown(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}

	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(ctx context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		if reloadCount == 1 {
			return nil, nil, context.Canceled
		}
		return copilot, []sweagentd.AgenticApp{newApp}, nil
	}, nil, nil)

	// First attempt: context canceled — should NOT burn the cooldown.
	_, err := provider.FindByID(context.Background(), 42)
	require.ErrorIs(t, err, ErrAgentNotFound)
	require.Equal(t, 1, reloadCount)

	// Second attempt immediately after: should be allowed to retry (no cooldown).
	app, err := provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), app.AppID())
	require.Equal(t, 2, reloadCount)
}

func TestFindByID_ReloadOnMiss_DeadlineExceededSkipsCooldown(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}

	reloadCount := 0
	provider := NewProvider(copilot).WithReloadOnMiss(func(ctx context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
		reloadCount++
		if reloadCount == 1 {
			return nil, nil, context.DeadlineExceeded
		}
		return copilot, []sweagentd.AgenticApp{newApp}, nil
	}, nil, nil)

	// First attempt: deadline exceeded — should NOT burn the cooldown.
	_, err := provider.FindByID(context.Background(), 42)
	require.ErrorIs(t, err, ErrAgentNotFound)
	require.Equal(t, 1, reloadCount)

	// Second attempt immediately after: should succeed.
	app, err := provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), app.AppID())
	require.Equal(t, 2, reloadCount)
}

// --- Version sync tests ---

func TestVersionSync_BumpTriggersReloadOnOtherProvider(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}
	cacheStore := cache.NewMemoryCacheStore()
	now := time.Now()

	// Simulate pod A: will bump the version via Reload
	podA := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			return copilot, []sweagentd.AgenticApp{newApp}, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 0)

	// Pod A triggers event-driven reload → bumps Redis version
	podA.Reload(copilot, newApp)

	// Verify version was bumped
	val, ok := cacheStore.Get(versionKey)
	require.True(t, ok)
	ver, err := strconv.ParseInt(val, 10, 64)
	require.NoError(t, err)
	require.Greater(t, ver, int64(0))

	// Simulate pod B: does NOT have the new app, seeded with version 0
	reloadCount := 0
	podB := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			reloadCount++
			return copilot, []sweagentd.AgenticApp{newApp}, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 0)
	// Override localVersion to 0 to simulate a pod that started before the bump
	podB.localVersion.Store(0)
	// Ensure cooldown doesn't interfere
	podB.nowFunc = func() time.Time { return now }

	// Pod B's localVersion (0) < remote version (1). FindByID should detect
	// the mismatch and reload via version sync.
	app, err := podB.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), app.AppID())
	require.Equal(t, 1, reloadCount, "version sync should trigger exactly one reload")
}

func TestVersionSync_TimeGating(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	cacheStore := cache.NewMemoryCacheStore()
	now := time.Now()

	reloadCount := 0
	provider := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			reloadCount++
			return copilot, nil, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 30*time.Second)
	provider.nowFunc = func() time.Time { return now }

	// Bump version externally to simulate another pod
	cacheStore.Set(versionKey, "5", time.Hour)

	// First miss: will check Redis and trigger reload
	_, _ = provider.FindByID(context.Background(), 999)
	firstReloadCount := reloadCount

	// Second miss within time gate: should NOT check Redis again
	now = now.Add(5 * time.Second)
	provider.nowFunc = func() time.Time { return now }
	cacheStore.Set(versionKey, "10", time.Hour) // bump again
	_, _ = provider.FindByID(context.Background(), 999)
	// reloadCount may have increased from reload-on-miss, but not from version sync
	// The key point is that Redis was not checked again within the 30s window

	// After time gate expires: should check Redis again
	now = now.Add(30 * time.Second)
	provider.nowFunc = func() time.Time { return now }
	provider.state.Store(newProviderState(copilot)) // clear state to force miss
	_, _ = provider.FindByID(context.Background(), 999)
	require.Greater(t, reloadCount, firstReloadCount, "reload should happen after time gate expires")
}

func TestVersionSync_RedisUnavailableFallsBackToReloadOnMiss(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}

	// Use a cache store that returns no data (simulates Redis down)
	emptyCache := cache.NewMemoryCacheStore()

	reloadCount := 0
	provider := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			reloadCount++
			return copilot, []sweagentd.AgenticApp{newApp}, nil
		}, nil, nil).
		WithVersionSync(emptyCache, 0)

	// No version key exists in Redis. Version check does nothing.
	// Reload-on-miss should still work as fallback.
	app, err := provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, int64(42), app.AppID())
	require.Equal(t, 1, reloadCount)
}

func TestVersionSync_ReloadBumpsRedisVersion(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	cacheStore := cache.NewMemoryCacheStore()

	provider := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			return copilot, nil, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 30*time.Second)

	// No version key exists yet
	_, ok := cacheStore.Get(versionKey)
	require.False(t, ok)

	// Event-driven Reload should create and bump the version
	provider.Reload(copilot)
	val, ok := cacheStore.Get(versionKey)
	require.True(t, ok)
	require.Equal(t, "1", val)

	// Second Reload bumps again
	provider.Reload(copilot)
	val, ok = cacheStore.Get(versionKey)
	require.True(t, ok)
	require.Equal(t, "2", val)

	// localVersion should match
	require.Equal(t, int64(2), provider.localVersion.Load())
}

func TestVersionSync_SeedLocalVersionOnInit(t *testing.T) {
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	cacheStore := cache.NewMemoryCacheStore()

	// Pre-populate Redis with version 5
	cacheStore.Set(versionKey, "5", time.Hour)

	reloadCount := 0
	provider := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			reloadCount++
			return copilot, nil, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 0) // 0 = check every time

	// localVersion should be seeded from Redis
	require.Equal(t, int64(5), provider.localVersion.Load())

	// A FindByID miss should NOT trigger a version-sync reload because
	// localVersion matches remote version.
	_, _ = provider.FindByID(context.Background(), 999)
	// reloadCount should be 1 (from reload-on-miss), not 2 (no version sync reload)
	require.Equal(t, 1, reloadCount)
}

func TestVersionSync_UpdatedAppDetectedViaVersionCheck(t *testing.T) {
	// Scenario: An existing app's metadata changes (e.g., source URL update).
	// The app ID is already in the local state, so FindByID would hit.
	// The version check must still detect the change and reload fresh data.
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	oldApp := &mockAgenticApp{appID: 42, botID: 142, name: "old-name"}
	updatedApp := &mockAgenticApp{appID: 42, botID: 142, name: "updated-name"}
	cacheStore := cache.NewMemoryCacheStore()

	reloadCount := 0
	provider := NewProvider(copilot, oldApp).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			reloadCount++
			return copilot, []sweagentd.AgenticApp{updatedApp}, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 0) // 0 = check every time

	// App 42 exists in local state with old name.
	app, err := provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, "old-name", app.AppName())
	require.Equal(t, 0, reloadCount, "no reload needed, app was a hit")

	// Simulate another pod bumping the Redis version (e.g., Hydro event processed).
	cacheStore.Incr(versionKey, 1, time.Hour)

	// Now FindByID should detect the version bump, reload, and return updated data.
	app, err = provider.FindByID(context.Background(), 42)
	require.NoError(t, err)
	require.Equal(t, "updated-name", app.AppName())
	require.Equal(t, 1, reloadCount, "version mismatch should trigger reload")
}

func TestVersionSync_SkippedReloadDoesNotAdvanceLocalVersion(t *testing.T) {
	// Scenario: A reload-on-miss happens, setting the cooldown. Then a version
	// bump occurs. The version-triggered reload is blocked by cooldown.
	// localVersion must NOT advance, so the next check retries.
	copilot := NewCopilot(1, "github-copilot", 2, "github-copilot-bot", "commit-login", "commit@email.com")
	newApp := &mockAgenticApp{appID: 42, botID: 142}
	cacheStore := cache.NewMemoryCacheStore()
	now := time.Now()

	reloadCount := 0
	provider := NewProvider(copilot).
		WithReloadOnMiss(func(_ context.Context) (*Copilot, []sweagentd.AgenticApp, error) {
			reloadCount++
			return copilot, []sweagentd.AgenticApp{newApp}, nil
		}, nil, nil).
		WithVersionSync(cacheStore, 0) // 0 = check every time
	provider.nowFunc = func() time.Time { return now }

	// First miss triggers reload-on-miss. Cooldown starts.
	_, _ = provider.FindByID(context.Background(), 999)
	require.Equal(t, 1, reloadCount)

	// Another pod bumps the version.
	cacheStore.Incr(versionKey, 1, time.Hour)
	remoteVal, _ := cacheStore.Get(versionKey)
	remoteVer, _ := strconv.ParseInt(remoteVal, 10, 64)

	// Advance time slightly (within cooldown).
	now = now.Add(5 * time.Second)
	provider.nowFunc = func() time.Time { return now }

	// FindByID: version check detects mismatch, but reloadOnMiss is
	// blocked by cooldown. localVersion must NOT advance.
	_, _ = provider.FindByID(context.Background(), 999)
	require.Less(t, provider.localVersion.Load(), remoteVer,
		"localVersion must not advance when reload was skipped due to cooldown")

	// After cooldown expires, the version check should succeed.
	now = now.Add(defaultReloadCooldown)
	provider.nowFunc = func() time.Time { return now }
	_, _ = provider.FindByID(context.Background(), 999)
	require.Equal(t, remoteVer, provider.localVersion.Load(),
		"localVersion should advance after successful reload")
	require.Equal(t, 2, reloadCount, "expected: initial miss + post-cooldown version sync")
}
