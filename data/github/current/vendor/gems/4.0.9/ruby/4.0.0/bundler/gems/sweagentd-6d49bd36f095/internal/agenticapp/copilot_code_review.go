package agenticapp

import (
	"regexp"
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	// CopilotCodeReviewBranchPrefix is the branch prefix for the Copilot Code Review agentic app.
	CopilotCodeReviewBranchPrefix = "copilot-pull-request-reviewer"

	// CopilotCodeReviewComputeSlug is the slug used in compute environments for the Copilot Code Review app.
	CopilotCodeReviewComputeSlug = "copilot-pull-request-reviewer"

	// CopilotCodeReviewAppName is the name of the Copilot Code Review app
	CopilotCodeReviewAppName = "Copilot"

	// CopilotCodeReviewCAPIIntegrationID is the CAPI integration ID for the
	// Copilot Code Review app. This is intended to be passed to the runtime so it can
	// authenticate against the Copilot API using the correct integration.
	CopilotCodeReviewCAPIIntegrationID = "copilot-pr-reviews"
)

// CopilotCodeReview represents the "copilot-pull-request-reviewer" GitHub App with its configuration and credentials.
// In production (dotcom) the App ID is 946600. In development it is 836.
type CopilotCodeReview struct {
	id                       int64
	name                     string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionableSlug          string
	mentionRegexp            *regexp.Regexp
}

// NewCopilotCodeReview creates a new CopilotCodeReview instance.
func NewCopilotCodeReview(id int64, appLogin string, botID int64, botLogin, commitLogin, commitEmail string) *CopilotCodeReview {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	// You are not allowed to mention CCR at all
	mentionPattern := `\z.` // Pattern that never matches (end of string followed by any character)
	mentionRegexp := regexp.MustCompile(mentionPattern)

	mentionableSlug := CopilotCodeReviewComputeSlug

	return &CopilotCodeReview{
		id:              id,
		name:            CopilotCodeReviewAppName,
		botID:           botID,
		botLogin:        botLogin,
		commitLogin:     commitLogin,
		commitEmail:     commitEmail,
		logins:          logins,
		mentionableSlug: mentionableSlug,
		mentionRegexp:   mentionRegexp,
	}
}

// MentionableSlug returns the mentionable slug for the CopilotCodeReview app.
func (c *CopilotCodeReview) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *CopilotCodeReview) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *CopilotCodeReview) AppName() string {
	return c.name
}

// WorkflowRunName returns the workflow run name for CopilotCodeReview.
func (c *CopilotCodeReview) WorkflowRunName(_ int) string {
	return "Running Copilot Code Review"
}

// BranchPrefix returns the branch prefix for the agent.
func (c *CopilotCodeReview) BranchPrefix() string {
	return CopilotCodeReviewBranchPrefix
}

// BotID returns the bot ID for the CopilotCodeReview instance.
func (c *CopilotCodeReview) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the CopilotCodeReview instance.
func (c *CopilotCodeReview) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the CopilotCodeReview instance.
func (c *CopilotCodeReview) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the CopilotCodeReview instance.
func (c *CopilotCodeReview) CommitEmail() string {
	return c.commitEmail
}

// SetupCompute configures the compute environment with the CopilotCodeReview agent setup and runtime entry point.
func (c *CopilotCodeReview) SetupCompute(compute sweagentd.ComputeEnv) {
	SetupComputeForAutofind(compute)
}

// SetupComputeForAutofind configures the compute environment with the setup and runtime entry point for autofind.js.
//
// Used by both CopilotCodeReview and CodeScanning agents. Be mindful of both when making changes to this function.
func SetupComputeForAutofind(compute sweagentd.ComputeEnv) {
	// Note: since we update the TS version independently of this sweagentd code, we
	// have put the actual logic of setting up the agent (with npm install of copilot
	// cli) into the bundled TS code itself. This means that IF we need to change any of
	// the setup steps for a version upgrade in the TS code, we can BY DEFINITION rely
	// on the code being updated in sync.
	//
	// If we had put the `npm install` command directly in the SetupAgent argument, and
	// we had to change any of that, we would have to be very careful about landing both
	// changes at once (which we can now avoid).
	compute.SetupAgent("node copilot-developer-action-main/dist-autofind-ts/ts/autofind.js cca-setup")

	compute.EntryPoint("dist-autofind-ts/ts/autofind.js")
}

// IsEntryPointForAutofind checks if the given command is the expected entry point for
// autofind.js, this is used in actions launcher to decide whether to use custom runner
// image. Exported so it can be reused there, without relying on the exact string in
// multiple places, so should handle _any_ possible future variations of the entry point
// command (currently, that's just "dist-autofind-ts/ts/autofind.js").
func IsEntryPointForAutofind(cmd string) bool {
	return cmd == "dist-autofind-ts/ts/autofind.js"
}

// ComputeSlug returns the slug used in compute environments.
func (c *CopilotCodeReview) ComputeSlug() string {
	return CopilotCodeReviewComputeSlug
}

// EngineSlug returns the slug used to resolve the runtime artifact.
func (c *CopilotCodeReview) EngineSlug() string {
	return c.ComputeSlug()
}

// ModelVendors returns the vendor names for model filtering.
// CopilotCodeReview is a first-party Copilot app, so it returns an empty slice to allow all models.
func (c *CopilotCodeReview) ModelVendors() []string {
	return nil
}

// SkipModelValidation implements sweagentd.AgenticAppModelPassthrough.
// CopilotCodeReview manages its own model selection externally (via CCRA),
// so sweagentd should pass the requested model through without validation.
func (c *CopilotCodeReview) SkipModelValidation() bool {
	return true
}

// AssignActorAsReviewer implements sweagentd.AgenticAppReviewerAssignment.
// Returns false because if an actor triggers a Copilot review of someone else's
// PR they should not be assigned as a human reviewer.
func (c *CopilotCodeReview) AssignActorAsReviewer() bool {
	return false
}

// SkipBranchAndPRCreation implements sweagentd.AgenticAppBranchlessMode.
// Returns true because Copilot Code Review operates on an existing PR — it
// never needs sweagentd to create a new branch or pull request.
func (c *CopilotCodeReview) SkipBranchAndPRCreation() bool {
	return true
}

// SkipPRCloseCancel implements sweagentd.AgenticAppSkipPRCloseCancel.
// Returns true so that an in-flight review is not cancelled when the source
// PR is closed or merged. Otherwise the merge would race the review and
// surface a "Copilot encountered an error" review on the just-closed PR;
// letting the review complete instead posts the real result.
func (c *CopilotCodeReview) SkipPRCloseCancel() bool {
	return true
}

// SkipEnablementCheck implements sweagentd.AgenticAppEnablementExempt.
// Returns true because CCRA performs its own enablement and disallow-flag
// checks before dispatching work to sweagentd.
func (c *CopilotCodeReview) SkipEnablementCheck() bool {
	return true
}

// NotifyOnSetupStepFailure implements sweagentd.AgenticAppSetupStepFailureNotifier.
// See github/copilot-code-review#2166.
func (c *CopilotCodeReview) NotifyOnSetupStepFailure() bool {
	return true
}

// SkipAgentFirewall implements sweagentd.AgenticAppFirewallExempt.
// Returns true to keep parity with CCR's legacy workflow, which never enforced
// an agent firewall. The repo-level CCA firewall settings target CCA and
// aren't applicable to CCR, and CCR's only new tooling over legacy is MCP,
// which already runs outside the firewall. Revisit when CCR exposes a bash
// tool.
func (c *CopilotCodeReview) SkipAgentFirewall() bool {
	return true
}

// Metadata returns app-specific key-value metadata for the Copilot Code Review app.
func (c *CopilotCodeReview) Metadata() map[string]string {
	return map[string]string{
		sweagentd.MetadataCAPIIntegrationID: CopilotCodeReviewCAPIIntegrationID,
	}
}

// HasSource returns false for Copilot Code Review.
func (c *CopilotCodeReview) HasSource() bool {
	return false
}

// SourceURL returns empty string for Copilot Code Review.
func (c *CopilotCodeReview) SourceURL() string {
	return ""
}

// IsQuotaExempt returns false — the CopilotCodeReview app uses standard quota checks.
func (c *CopilotCodeReview) IsQuotaExempt() bool {
	return false
}

// UsesExperiments returns false — CCR gets its experiments from an external service.
func (c *CopilotCodeReview) UsesExperiments() bool {
	return false
}

// IsJobLimitExempt implements sweagentd.AgenticAppJobLimitExempt.
// Returns true because CopilotCodeReview manages its own concurrency via pull
// request creation limits, so sweagentd should not enforce per-actor caps.
func (c *CopilotCodeReview) IsJobLimitExempt() bool {
	return true
}

// AgentSource returns nil since the Copilot Code Review agent does not have external source code.
func (c *CopilotCodeReview) AgentSource() *sweagentd.AgentSource { return nil }

// IsGlobalApp returns true because CopilotCodeReview is a global app.
func (c *CopilotCodeReview) IsGlobalApp() bool { return true }

// IsPartnerApp returns false because CopilotCodeReview is not a partner app.
func (c *CopilotCodeReview) IsPartnerApp() bool { return false }

// IsThirdPartyApp returns false because CopilotCodeReview is not a third-party app.
func (c *CopilotCodeReview) IsThirdPartyApp() bool { return false }

func (c *CopilotCodeReview) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *CopilotCodeReview) isMentioned(body string) bool {
	return false
}
