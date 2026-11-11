// Package agenticapptest provides test helpers for creating agenticapp instances.
package agenticapptest

import (
	"context"
	"crypto/rsa"
	"math"
	"testing"
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

// NewTestCopilot creates a test Copilot instance with sensible defaults.
// Uses app ID = 0 to match NoopClientFactory default.
func NewTestCopilot(t *testing.T) *agenticapp.Copilot {
	t.Helper()
	return agenticapp.NewCopilot(
		0,
		nil,
		"github-copilot",
		0,
		"github-copilot-bot",
		"commit-login",
		"commit@email.com",
		"client-id",
		"client-secret",
	)
}

// NewTestProvider creates a test Provider with a default Copilot instance.
func NewTestProvider(t *testing.T) *agenticapp.Provider {
	t.Helper()
	copilot := NewTestCopilot(t)
	return agenticapp.NewProvider(copilot)
}

// NewTestCopilotWithID creates a test Copilot instance with a specific app ID.
func NewTestCopilotWithID(t *testing.T, appID int64) *agenticapp.Copilot {
	t.Helper()
	return agenticapp.NewCopilot(
		appID,
		nil,
		"github-copilot",
		appID+1,
		"github-copilot-bot",
		"commit-login",
		"commit@email.com",
		"client-id",
		"client-secret",
	)
}

// NewTestCopilotWithLogins creates a test Copilot instance with specific logins.
// Uses app ID = 0 to match NoopClientFactory default.
func NewTestCopilotWithLogins(t *testing.T, appLogin, botLogin string) *agenticapp.Copilot {
	t.Helper()
	return agenticapp.NewCopilot(
		0,
		nil,
		appLogin,
		0,
		botLogin,
		"commit-login",
		"commit@email.com",
		"client-id",
		"client-secret",
	)
}

// NewTestProviderWithID creates a test Provider with a Copilot instance with a specific app ID.
func NewTestProviderWithID(t *testing.T, appID int64) *agenticapp.Provider {
	t.Helper()
	copilot := NewTestCopilotWithID(t, appID)
	return agenticapp.NewProvider(copilot)
}

// NewTestProviderWithLogins creates a test Provider with a Copilot instance with specific logins.
func NewTestProviderWithLogins(t *testing.T, appLogin, botLogin string) *agenticapp.Provider {
	t.Helper()
	copilot := NewTestCopilotWithLogins(t, appLogin, botLogin)
	return agenticapp.NewProvider(copilot)
}

// NewTestProviderWithPrivateKey creates a test Provider with a Copilot instance that has a private key.
func NewTestProviderWithPrivateKey(t *testing.T, appID int64, privateKey *rsa.PrivateKey, appLogin, botLogin string) *agenticapp.Provider {
	t.Helper()
	copilot := agenticapp.NewCopilot(appID, privateKey, appLogin, 123, botLogin, "commit-login", "commit@email.com", "client-id", "client-secret")
	return agenticapp.NewProvider(copilot)
}

// TestApp is a lightweight implementation of sweagentd.AgenticApp used in tests.
type TestApp struct {
	id           int64
	name         string
	branchPrefix string
	slug         string
}

// NewTestApp creates a new test agentic app with the provided ID.
func NewTestApp(id int64) *TestApp {
	return &TestApp{
		id:           id,
		name:         "Test Agentic App",
		branchPrefix: "test",
		slug:         "test-agent",
	}
}

// AppID returns the app ID.
func (a *TestApp) AppID() int64 { return a.id }

// AppName returns the app name.
func (a *TestApp) AppName() string { return a.name }

// BranchPrefix returns the branch prefix.
func (a *TestApp) BranchPrefix() string { return a.branchPrefix }

// PrivateKey returns nil for tests.
func (a *TestApp) PrivateKey() *rsa.PrivateKey { return nil }

// ClientID returns the client ID.
func (a *TestApp) ClientID() string { return "" }

// ClientSecret returns the client secret.
func (a *TestApp) ClientSecret() string { return "" }

// BotID returns the bot ID.
func (a *TestApp) BotID() int64 { return 0 }

// BotLogin returns the bot login.
func (a *TestApp) BotLogin() string { return "" }

// CommitLogin returns the commit login.
func (a *TestApp) CommitLogin() string { return "" }

// CommitEmail returns the commit email.
func (a *TestApp) CommitEmail() string { return "" }

// MentionableSlug returns the mentionable slug.
func (a *TestApp) MentionableSlug() string { return a.slug + "[agent]" }

// ComputeSlug returns the compute slug.
func (a *TestApp) ComputeSlug() string { return "test-agent" }

// MintToken returns an empty token for tests.
func (a *TestApp) MintToken(context.Context, *gg.Client, sweagentd.AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error) {
	return "", time.Unix(math.MaxInt64, 0), nil, nil
}

// RevokeToken is a no-op for tests.
func (a *TestApp) RevokeToken(context.Context, sweagentd.GitHubAPI, string) error {
	return nil
}

// SetupCompute is a no-op for tests.
func (a *TestApp) SetupCompute(sweagentd.ComputeEnv) {}
