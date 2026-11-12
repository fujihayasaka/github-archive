package agenticapp

import (
	"regexp"
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	// CopilotBranchPrefix is the branch prefix for the Copilot agentic app.
	// If a branch with the same name as this prefix exists, Copilot coding agent can't create a new branch with the prefix.
	// There are security implications like only allowing Copilot to push to branches with this prefix.
	// If this constant needs to be changed, ensure the security guardrails are updated too.
	// See https://github.com/github/sweagentd/issues/124 for details.
	CopilotBranchPrefix = "copilot"

	// CopilotComputeSlug is the slug used in compute environments for the Copilot app.
	CopilotComputeSlug = "copilot"
)

var backtickContentPattern = regexp.MustCompile("```[\\s\\S]*?```|`[^`]*`")

// Copilot represents a GitHub Copilot Agentic App.
type Copilot struct {
	id                       int64
	name                     string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionRegexp            *regexp.Regexp
	mentionableSlug          string
}

// NewCopilot creates a new Copilot instance.
func NewCopilot(id int64, appLogin string, botID int64, botLogin, commitLogin, commitEmail string) *Copilot {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
		"Copilot",
	}

	name := "Copilot cloud agent"
	mentionableSlug := "copilot"
	mentionRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + mentionableSlug + `\b`)

	return &Copilot{
		id:              id,
		name:            name,
		botID:           botID,
		botLogin:        botLogin,
		commitLogin:     commitLogin,
		commitEmail:     commitEmail,
		logins:          logins,
		mentionableSlug: mentionableSlug,
		mentionRegexp:   mentionRegexp,
	}
}

// MentionableSlug returns the mentionable slug for the Copilot app.
func (c *Copilot) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *Copilot) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *Copilot) AppName() string {
	return c.name
}

// WorkflowRunName returns an empty string for Copilot.
func (c *Copilot) WorkflowRunName(_ int) string {
	return ""
}

// BranchPrefix returns the branch prefix for the agent.
func (c *Copilot) BranchPrefix() string {
	return CopilotBranchPrefix
}

// BotID returns the Bot ID of the agent.
func (c *Copilot) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the Copilot instance.
func (c *Copilot) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the Copilot instance.
func (c *Copilot) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the Copilot instance.
func (c *Copilot) CommitEmail() string {
	return c.commitEmail
}

// SetupCompute configures the compute environment with the Copilot runtime entry point.
func (c *Copilot) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.EntryPoint("dist/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *Copilot) ComputeSlug() string {
	return CopilotComputeSlug
}

// EngineSlug returns the slug used to resolve the runtime artifact.
func (c *Copilot) EngineSlug() string {
	return c.ComputeSlug()
}

// ModelVendors returns an empty slice for Copilot, meaning all model vendors are allowed.
func (c *Copilot) ModelVendors() []string {
	return nil
}

// Metadata returns app-specific key-value metadata for the Copilot app.
func (c *Copilot) Metadata() map[string]string {
	return nil
}

// HasSource returns false for Copilot.
func (c *Copilot) HasSource() bool {
	return false
}

// SourceURL returns empty string for Copilot.
func (c *Copilot) SourceURL() string {
	return ""
}

// IsQuotaExempt returns false — the Copilot app uses standard quota checks.
func (c *Copilot) IsQuotaExempt() bool {
	return false
}

// UsesExperiments returns true — the Copilot coding agent participates in experiments.
func (c *Copilot) UsesExperiments() bool {
	return true
}

// AgentSource returns nil since the Copilot agent does not have external source code.
func (c *Copilot) AgentSource() *sweagentd.AgentSource { return nil }

// IsGlobalApp returns true because Copilot is a global app.
func (c *Copilot) IsGlobalApp() bool { return true }

// IsPartnerApp returns false because Copilot is not a partner app.
func (c *Copilot) IsPartnerApp() bool { return false }

// IsThirdPartyApp returns false because Copilot is not a third-party app.
func (c *Copilot) IsThirdPartyApp() bool { return false }

func (c *Copilot) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Copilot) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @copilot mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}

// MentionWithModelPattern matches @copilot+model-id patterns.
// It captures the model ID after the + sign.
var mentionWithModelPattern = regexp.MustCompile(`(?i)(?:^|\s|\W)@copilot\+([a-zA-Z0-9._-]+)(?:\s|$|[^\w+-])`)

// isMentionedWithModel checks if the body contains a @copilot+model mention
// and returns the model ID if found.
func (c *Copilot) isMentionedWithModel(body string) (string, bool) {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @copilot+model mention exists in the remaining text
	matches := mentionWithModelPattern.FindStringSubmatch(bodyWithoutBackticks)
	if len(matches) >= 2 {
		return matches[1], true
	}

	return "", false
}
