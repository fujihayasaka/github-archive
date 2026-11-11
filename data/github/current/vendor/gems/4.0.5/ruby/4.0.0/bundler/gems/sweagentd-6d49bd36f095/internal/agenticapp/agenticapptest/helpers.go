// Package agenticapptest provides test helpers for creating agenticapp instances.
package agenticapptest

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/sweagentd"
)

// NewTestCopilot creates a test Copilot instance with sensible defaults.
// Uses app ID = 0 to match NoopClientFactory default.
func NewTestCopilot(t *testing.T) *agenticapp.Copilot {
	t.Helper()
	return agenticapp.NewCopilot(
		0,
		"github-copilot",
		0,
		"github-copilot-bot",
		"commit-login",
		"commit@email.com",
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
		"github-copilot",
		appID+1,
		"github-copilot-bot",
		"commit-login",
		"commit@email.com",
	)
}

// NewTestCopilotWithLogins creates a test Copilot instance with specific logins.
// Uses app ID = 0 to match NoopClientFactory default.
func NewTestCopilotWithLogins(t *testing.T, appLogin, botLogin string) *agenticapp.Copilot {
	t.Helper()
	return agenticapp.NewCopilot(
		0,
		appLogin,
		0,
		botLogin,
		"commit-login",
		"commit@email.com",
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

// NewTestProviderWithIDAndLogins creates a test Provider with a Copilot instance with a specific app ID and logins.
func NewTestProviderWithIDAndLogins(t *testing.T, appID int64, appLogin, botLogin string) *agenticapp.Provider {
	t.Helper()
	copilot := agenticapp.NewCopilot(appID, appLogin, 123, botLogin, "commit-login", "commit@email.com")
	return agenticapp.NewProvider(copilot)
}

// TestApp is a lightweight implementation of sweagentd.AgenticApp used in tests.
type TestApp struct {
	id               int64
	botID            int64
	name             string
	branchPrefix     string
	slug             string
	modelVendors     []string
	quotaExempt      bool
	jobLimitExempt   bool
	enablementExempt bool
	globalApp        bool
	metadata         map[string]string
	agentSource      *sweagentd.AgentSource
	workflowRunName  string
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

// NewTestAppWithDetails creates a new test agentic app with custom app ID, bot ID, name, and slug.
func NewTestAppWithDetails(appID, botID int64, name, slug string) *TestApp {
	return &TestApp{
		id:           appID,
		botID:        botID,
		name:         name,
		branchPrefix: slug,
		slug:         slug,
	}
}

// AppID returns the app ID.
func (a *TestApp) AppID() int64 { return a.id }

// AppName returns the app name.
func (a *TestApp) AppName() string { return a.name }

// WorkflowRunName returns the configured workflow run name (empty by default).
func (a *TestApp) WorkflowRunName(_ int) string { return a.workflowRunName }

// WithWorkflowRunName sets the workflow run name for the test app and returns it for chaining.
func (a *TestApp) WithWorkflowRunName(name string) *TestApp {
	a.workflowRunName = name
	return a
}

// BranchPrefix returns the branch prefix.
func (a *TestApp) BranchPrefix() string { return a.branchPrefix }

// BotID returns the bot ID.
func (a *TestApp) BotID() int64 { return a.botID }

// BotLogin returns the bot login.
func (a *TestApp) BotLogin() string { return a.slug + "-bot" }

// CommitLogin returns the commit login.
func (a *TestApp) CommitLogin() string { return a.slug + "-commit" }

// CommitEmail returns the commit email.
func (a *TestApp) CommitEmail() string { return a.slug + "@github.com" }

// MentionableSlug returns the mentionable slug.
func (a *TestApp) MentionableSlug() string { return a.slug + "[agent]" }

// ComputeSlug returns the compute slug.
func (a *TestApp) ComputeSlug() string { return "test-agent" }

// EngineSlug returns the engine slug (same as ComputeSlug for tests).
func (a *TestApp) EngineSlug() string { return a.ComputeSlug() }

// RevokeToken is a no-op for tests.
func (a *TestApp) RevokeToken(context.Context, sweagentd.GitHubAPI, string) error {
	return nil
}

// ModelVendors returns the configured model vendors for tests.
func (a *TestApp) ModelVendors() []string { return a.modelVendors }

// WithModelVendors sets the model vendors for the test app and returns it for chaining.
func (a *TestApp) WithModelVendors(vendors []string) *TestApp {
	a.modelVendors = vendors
	return a
}

// SetupCompute is a no-op for tests.
func (a *TestApp) SetupCompute(sweagentd.ComputeEnv) {}

// Metadata returns the configured metadata for tests (nil by default).
func (a *TestApp) Metadata() map[string]string {
	return a.metadata
}

// WithMetadata sets the metadata for the test app and returns it for chaining.
func (a *TestApp) WithMetadata(m map[string]string) *TestApp {
	a.metadata = m
	return a
}

// HasSource indicates that this agent has source code available in a repository.
func (a *TestApp) HasSource() bool {
	return a.agentSource != nil && a.agentSource.URL != ""
}

// SourceURL returns an empty string for tests.
func (a *TestApp) SourceURL() string {
	return ""
}

// IsQuotaExempt returns the configured quota exemption status.
func (a *TestApp) IsQuotaExempt() bool {
	return a.quotaExempt
}

// UsesExperiments returns true — test apps participate in experiments by default.
func (a *TestApp) UsesExperiments() bool {
	return true
}

// IsJobLimitExempt returns the configured job limit exemption status.
func (a *TestApp) IsJobLimitExempt() bool {
	return a.jobLimitExempt
}

// WithJobLimitExempt enables job limit exemption on the test app and returns it for chaining.
func (a *TestApp) WithJobLimitExempt() *TestApp {
	a.jobLimitExempt = true
	return a
}

// WithQuotaExempt enables quota exemption on the test app and returns it for chaining.
func (a *TestApp) WithQuotaExempt() *TestApp {
	a.quotaExempt = true
	return a
}

// SkipEnablementCheck implements sweagentd.AgenticAppEnablementExempt.
func (a *TestApp) SkipEnablementCheck() bool {
	return a.enablementExempt
}

// WithEnablementExempt returns the TestApp with enablement exemption enabled.
func (a *TestApp) WithEnablementExempt() *TestApp {
	a.enablementExempt = true
	return a
}

// AgentSource returns the configured agent source for tests.
func (a *TestApp) AgentSource() *sweagentd.AgentSource { return a.agentSource }

// WithAgentSource sets the agent source for the test app and returns it for chaining.
func (a *TestApp) WithAgentSource(src *sweagentd.AgentSource) *TestApp {
	a.agentSource = src
	return a
}

// IsGlobalApp returns the configured global app status (false by default).
func (a *TestApp) IsGlobalApp() bool { return a.globalApp }

// IsPartnerApp returns false for tests.
func (a *TestApp) IsPartnerApp() bool { return false }

// IsThirdPartyApp returns true unless the app is configured as global.
func (a *TestApp) IsThirdPartyApp() bool { return !a.globalApp }

// WithGlobalApp marks the test app as a global (first-party) app.
func (a *TestApp) WithGlobalApp() *TestApp {
	a.globalApp = true
	return a
}

// NewTestProviderWithThirdPartyApps creates a test Provider with Copilot and third-party apps.
func NewTestProviderWithThirdPartyApps(t *testing.T, copilotAppID int64, thirdPartyApps ...sweagentd.AgenticApp) *agenticapp.Provider {
	t.Helper()
	copilot := NewTestCopilotWithID(t, copilotAppID)
	return agenticapp.NewProvider(copilot, thirdPartyApps...)
}
