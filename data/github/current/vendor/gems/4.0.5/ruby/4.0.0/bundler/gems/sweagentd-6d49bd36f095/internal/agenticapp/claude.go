package agenticapp

import (
	"regexp"
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

const (
	// ClaudeBranchPrefix is the branch prefix for the Claude agentic app.
	ClaudeBranchPrefix = "claude"
	// ClaudeCodeAppName is the name of the Claude app - will ultimately be the actual App name.
	ClaudeCodeAppName = "Claude"
	// ClaudeCAPIIntegrationID is the Copilot-Integration-Id value sent on
	// CAPI /models requests to identify the Claude Code Cloud integration.
	ClaudeCAPIIntegrationID = "claude-code-cloud"
)

// Claude represents the Claude GitHub App with its configuration and credentials.
type Claude struct {
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

// NewClaude creates a new Claude instance with app and bot configuration.
func NewClaude(id int64, appLogin string, botID int64, botLogin, commitLogin, commitEmail string) *Claude {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	mentionableSlug := "claude[agent]"
	quotedSlug := regexp.QuoteMeta(mentionableSlug)
	mentionPattern := `(?i)(?:^|\s|\W)@` + quotedSlug + `(?:\s|\W|$)`
	mentionRegexp := regexp.MustCompile(mentionPattern)
	mentionWithModelRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + quotedSlug + `\+([a-zA-Z0-9._-]+)(?:\s|$|[^\w+-])`)

	return &Claude{
		id:                     id,
		name:                   ClaudeCodeAppName,
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

// MentionableSlug returns the mentionable slug for the Claude app.
func (c *Claude) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *Claude) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *Claude) AppName() string {
	return c.name
}

// WorkflowRunName returns an empty string for Claude.
func (c *Claude) WorkflowRunName(_ int) string {
	return ""
}

// BranchPrefix returns the branch prefix for the agent.
func (c *Claude) BranchPrefix() string {
	return ClaudeBranchPrefix
}

// BotID returns the bot ID for the Claude instance.
func (c *Claude) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the Claude instance.
func (c *Claude) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the Claude instance.
func (c *Claude) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the Claude instance.
func (c *Claude) CommitEmail() string {
	return c.commitEmail
}

// SetupCompute configures the compute environment with the Claude agent setup and runtime entry point.
func (c *Claude) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.EntryPoint("dist-claude/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *Claude) ComputeSlug() string {
	return "claude"
}

// EngineSlug returns the slug used to resolve the runtime artifact.
func (c *Claude) EngineSlug() string {
	return c.ComputeSlug()
}

// ModelVendors returns the Anthropic vendor string for Claude model filtering.
func (c *Claude) ModelVendors() []string {
	return []string{sweagentd.ModelVendorAnthropic}
}

// Metadata returns app-specific key-value metadata for the Claude app.
func (c *Claude) Metadata() map[string]string {
	return map[string]string{
		sweagentd.MetadataCAPIIntegrationID: ClaudeCAPIIntegrationID,
	}
}

// HasSource returns false for Claude
func (c *Claude) HasSource() bool {
	return false
}

// SourceURL returns empty string for Claude
func (c *Claude) SourceURL() string {
	return ""
}

// IsQuotaExempt returns false — the Claude app uses standard quota checks.
func (c *Claude) IsQuotaExempt() bool {
	return false
}

// UsesExperiments returns true — the Claude app participates in experiments.
func (c *Claude) UsesExperiments() bool {
	return true
}

// AgentSource returns nil since the Claude agent does not have external source code.
func (c *Claude) AgentSource() *sweagentd.AgentSource { return nil }

// IsGlobalApp returns false because Claude is not a global app.
func (c *Claude) IsGlobalApp() bool { return false }

// IsPartnerApp returns true because Claude is a partner app.
func (c *Claude) IsPartnerApp() bool { return true }

// IsThirdPartyApp returns false because Claude is not a third-party app.
func (c *Claude) IsThirdPartyApp() bool { return false }

func (c *Claude) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Claude) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @claude[agent] mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}

// isMentionedWithModel checks if the body contains a @claude[agent]+model mention
// and returns the model ID if found.
func (c *Claude) isMentionedWithModel(body string) (string, bool) {
	return matchMentionWithModel(body, c.mentionWithModelRegexp)
}
