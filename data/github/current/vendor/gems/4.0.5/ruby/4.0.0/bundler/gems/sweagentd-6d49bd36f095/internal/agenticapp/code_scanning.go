package agenticapp

import (
	"fmt"
	"regexp"
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	// CodeScanningBranchPrefix is the branch prefix for the Code scanning agentic app.
	CodeScanningBranchPrefix = "github-advanced-security"

	// CodeScanningComputeSlug is the slug used in compute environments for the Code scanning app.
	CodeScanningComputeSlug = "github-advanced-security"

	// CodeScanningAppName is the name of the Code scanning app
	CodeScanningAppName = "GitHub Advanced Security"

	// CodeScanningCAPIIntegrationID is the CAPI integration ID for the Code scanning app.
	CodeScanningCAPIIntegrationID = "ghas-code-scanning-autofix"
)

// CodeScanning represents the "github-advanced-security" GitHub App with its configuration and credentials.
type CodeScanning struct {
	id                       int64
	name                     string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionableSlug          string
	mentionRegexp            *regexp.Regexp
}

// NewCodeScanning creates a new CodeScanning instance.
func NewCodeScanning(id int64, appLogin string, botID int64, botLogin, commitLogin, commitEmail string) *CodeScanning {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	// We need to provide it but we don't need it
	mentionPattern := `\z.` // Pattern that never matches (end of string followed by any character)
	mentionRegexp := regexp.MustCompile(mentionPattern)

	mentionableSlug := CodeScanningComputeSlug

	return &CodeScanning{
		id:              id,
		name:            CodeScanningAppName,
		botID:           botID,
		botLogin:        botLogin,
		commitLogin:     commitLogin,
		commitEmail:     commitEmail,
		logins:          logins,
		mentionableSlug: mentionableSlug,
		mentionRegexp:   mentionRegexp,
	}
}

// MentionableSlug returns the mentionable slug for the CodeScanning app.
func (c *CodeScanning) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *CodeScanning) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *CodeScanning) AppName() string {
	return c.name
}

// WorkflowRunName returns the workflow run name for CodeScanning.
// When a pull request number is available it is appended for traceability.
func (c *CodeScanning) WorkflowRunName(prNumber int) string {
	if prNumber != 0 {
		return fmt.Sprintf("Code scanning AI findings on PR #%d", prNumber)
	}
	return "Code scanning AI findings"
}

// BranchPrefix returns the branch prefix for the agent.
func (c *CodeScanning) BranchPrefix() string {
	return CodeScanningBranchPrefix
}

// BotID returns the bot ID for the CodeScanning instance.
func (c *CodeScanning) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the CodeScanning instance.
func (c *CodeScanning) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the CodeScanning instance.
func (c *CodeScanning) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the CodeScanning instance.
func (c *CodeScanning) CommitEmail() string {
	return c.commitEmail
}

// SetupCompute configures the compute environment with the CodeScanning agent setup and runtime entry point.
func (c *CodeScanning) SetupCompute(compute sweagentd.ComputeEnv) {
	SetupComputeForAutofind(compute)
}

// ComputeSlug returns the slug used in compute environments.
func (c *CodeScanning) ComputeSlug() string {
	return CodeScanningComputeSlug
}

// EngineSlug returns the slug used to resolve the runtime artifact.
// CodeScanning shares the autofind runtime with CopilotCodeReview, so it
// returns the CopilotCodeReview slug to reference the same published artifact.
func (c *CodeScanning) EngineSlug() string {
	return CopilotCodeReviewComputeSlug
}

// ModelVendors returns the vendor names for model filtering.
// CodeScanning is a first-party Copilot app, so it returns an empty slice to allow all models.
func (c *CodeScanning) ModelVendors() []string {
	return nil
}

// SkipModelValidation implements sweagentd.AgenticAppModelPassthrough.
// CodeScanning manages its own model selection externally (via CCRA),
// so sweagentd should pass the requested model through without validation.
func (c *CodeScanning) SkipModelValidation() bool {
	return true
}

// AssignActorAsReviewer implements sweagentd.AgenticAppReviewerAssignment. Returns
// false because in the unexpected case where an actor triggers a code scanning AI
// analysis of someone else's PR they should not be assigned as a human reviewer.
func (c *CodeScanning) AssignActorAsReviewer() bool {
	return false
}

// HasSource returns false for CodeScanning.
func (c *CodeScanning) HasSource() bool {
	return false
}

// SourceURL returns empty string for CodeScanning.
func (c *CodeScanning) SourceURL() string {
	return ""
}

// IsQuotaExempt returns true — the Code Scanning app has its own billing
// model and is exempt from Copilot license and premium quota checks.
func (c *CodeScanning) IsQuotaExempt() bool {
	return true
}

// UsesExperiments returns false — Code Scanning gets experiments from an external service.
func (c *CodeScanning) UsesExperiments() bool {
	return false
}

// SkipEnablementCheck implements sweagentd.AgenticAppEnablementExempt.
// Returns true because the Code Scanning app performs its own enablement
// and disallow-flag checks before dispatching work to sweagentd.
func (c *CodeScanning) SkipEnablementCheck() bool {
	return true
}

// SkipAgentFirewall implements sweagentd.AgenticAppFirewallExempt.
// Returns true because the Code Scanning app has a narrow, well-known egress
// profile and the repo-level CCA firewall settings are not applicable to it.
func (c *CodeScanning) SkipAgentFirewall() bool {
	return true
}

// AgentSource returns nil since the Code scanning agent does not have external source code.
func (c *CodeScanning) AgentSource() *sweagentd.AgentSource { return nil }

// IsGlobalApp returns true because CodeScanning is a global app.
func (c *CodeScanning) IsGlobalApp() bool { return true }

// IsPartnerApp returns false because CodeScanning is not a partner app.
func (c *CodeScanning) IsPartnerApp() bool { return false }

// IsThirdPartyApp returns false because CodeScanning is not a third-party app.
func (c *CodeScanning) IsThirdPartyApp() bool { return false }

// Metadata returns per-app metadata for the Code scanning app.
func (c *CodeScanning) Metadata() map[string]string {
	return map[string]string{
		sweagentd.MetadataCAPIIntegrationID: CodeScanningCAPIIntegrationID,
	}
}

func (c *CodeScanning) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *CodeScanning) isMentioned(body string) bool {
	return false
}
