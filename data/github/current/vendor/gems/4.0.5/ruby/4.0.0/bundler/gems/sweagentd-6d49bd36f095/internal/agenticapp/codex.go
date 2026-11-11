package agenticapp

import (
	"regexp"
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	// CodexBranchPrefix is the branch prefix for the Codex agentic app.
	CodexBranchPrefix = "codex"
	// CodexAppName is the name of the Codex agentic app - will ultimately be the actual App name.
	CodexAppName = "OpenAI Codex"

	// CodexCAPIIntegrationID is the Copilot-Integration-Id value sent on
	// CAPI /models requests to identify the Codex Cloud integration.
	CodexCAPIIntegrationID = "codex-cloud"

	// CodexSetupCommand installs the Codex CLI used by Codex-backed runtimes.
	CodexSetupCommand = "npm install -g @openai/codex@0.115.0"
)

// Codex represents the Codex GitHub App with its configuration and credentials.
type Codex struct {
	id                       int64
	name                     string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionableSlug          string
	mentionRegexp            *regexp.Regexp
	mentionWithModelRegexp   *regexp.Regexp
}

// NewCodex creates a new Codex instance with app and bot configuration.
func NewCodex(id int64, appLogin string, botID int64, botLogin, commitLogin, commitEmail string) *Codex {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	mentionableSlug := "codex[agent]"
	mentionRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + regexp.QuoteMeta(mentionableSlug) + `(?:\s|\W|$)`)
	mentionWithModelRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + regexp.QuoteMeta(mentionableSlug) + `\+([a-zA-Z0-9._-]+)(?:\s|$|[^\w+-])`)

	return &Codex{
		id:                     id,
		name:                   CodexAppName,
		botID:                  botID,
		botLogin:               botLogin,
		commitLogin:            commitLogin,
		commitEmail:            commitEmail,
		logins:                 logins,
		mentionableSlug:        mentionableSlug,
		mentionRegexp:          mentionRegexp,
		mentionWithModelRegexp: mentionWithModelRegexp,
	}
}

// MentionableSlug returns the mentionable slug for the Codex app.
func (c *Codex) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *Codex) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *Codex) AppName() string {
	return c.name
}

// WorkflowRunName returns an empty string for Codex.
func (c *Codex) WorkflowRunName(_ int) string {
	return ""
}

// BranchPrefix returns the branch prefix for the agent.
func (c *Codex) BranchPrefix() string {
	return CodexBranchPrefix
}

// BotID returns the Bot ID of the agent.
func (c *Codex) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the Codex instance.
func (c *Codex) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the Codex instance.
func (c *Codex) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the Codex instance.
func (c *Codex) CommitEmail() string {
	return c.commitEmail
}

// SetupCompute configures the compute environment with the Codex agent setup and runtime entry point.
func (c *Codex) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.SetupAgent(CodexSetupCommand)
	compute.EntryPoint("dist-codex/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *Codex) ComputeSlug() string {
	return "codex"
}

// EngineSlug returns the slug used to resolve the runtime artifact.
func (c *Codex) EngineSlug() string {
	return c.ComputeSlug()
}

// ModelVendors returns the OpenAI vendor string for Codex model filtering.
func (c *Codex) ModelVendors() []string {
	return []string{sweagentd.ModelVendorOpenAI}
}

// Metadata returns app-specific key-value metadata for the Codex app.
func (c *Codex) Metadata() map[string]string {
	return map[string]string{
		sweagentd.MetadataCAPIIntegrationID: CodexCAPIIntegrationID,
	}
}

// HasSource returns false for Codex.
func (c *Codex) HasSource() bool {
	return false
}

// SourceURL returns empty string for Codex.
func (c *Codex) SourceURL() string {
	return ""
}

// IsQuotaExempt returns false — the Codex app uses standard quota checks.
func (c *Codex) IsQuotaExempt() bool {
	return false
}

// UsesExperiments returns true — the Codex app participates in experiments.
func (c *Codex) UsesExperiments() bool {
	return true
}

// AgentSource returns nil since the Codex agent does not have external source code.
func (c *Codex) AgentSource() *sweagentd.AgentSource { return nil }

// IsGlobalApp returns false because Codex is not a global app.
func (c *Codex) IsGlobalApp() bool { return false }

// IsPartnerApp returns true because Codex is a partner app.
func (c *Codex) IsPartnerApp() bool { return true }

// IsThirdPartyApp returns false because Codex is not a third-party app.
func (c *Codex) IsThirdPartyApp() bool { return false }

func (c *Codex) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Codex) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @codex[agent] mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}

// isMentionedWithModel checks if the body contains a @codex[agent]+model mention
// and returns the model ID if found.
func (c *Codex) isMentionedWithModel(body string) (string, bool) {
	return matchMentionWithModel(body, c.mentionWithModelRegexp)
}
