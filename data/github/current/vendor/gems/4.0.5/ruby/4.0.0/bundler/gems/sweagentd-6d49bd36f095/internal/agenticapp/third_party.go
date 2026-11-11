package agenticapp

import (
	"regexp"
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

// ThirdPartyAgenticCAPIIntegrationID is the Copilot-Integration-Id value sent
// on CAPI inference requests made on behalf of dynamically-registered
// third-party agentic apps. A shared integration isolates 3P capacity from
// Copilot's own quota; see ADR 0018.
const ThirdPartyAgenticCAPIIntegrationID = "third-party-agentic"

// ThirdParty represents GitHub App backed by IntegrationAgentSource DB record
type ThirdParty struct {
	id                       int64
	name                     string
	botID                    int64
	botLogin                 string
	commitLogin, commitEmail string
	logins                   []string
	mentionableSlug          string
	mentionRegexp            *regexp.Regexp
	agentSource              *sweagentd.AgentSource
	modelVendors             []string
}

// NewThirdParty creates a new ThirdParty instance.
// appSlug is a URL-friendly identifier (no spaces) used for @mentions.
// When appSlug is empty, appLogin is used as a fallback.
func NewThirdParty(id int64, appLogin, appSlug string, botID int64, botLogin, commitLogin, commitEmail string, agentSource *sweagentd.AgentSource, modelVendors []string) *ThirdParty {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
	}

	slugForMention := appSlug
	if slugForMention == "" {
		slugForMention = appLogin
	}
	mentionableSlug := slugForMention + "[agent]"
	mentionRegexp := regexp.MustCompile(`(?i)(?:^|\s|\W)@` + regexp.QuoteMeta(mentionableSlug) + `(?:\s|\W|$)`)

	return &ThirdParty{
		id:              id,
		name:            appLogin,
		botID:           botID,
		botLogin:        botLogin,
		commitLogin:     commitLogin,
		commitEmail:     commitEmail,
		logins:          logins,
		mentionableSlug: mentionableSlug,
		mentionRegexp:   mentionRegexp,
		agentSource:     agentSource,
		modelVendors:    modelVendors,
	}
}

// MentionableSlug returns the mentionable slug for the ThirdParty app.
func (c *ThirdParty) MentionableSlug() string {
	return c.mentionableSlug
}

// AppID returns the App ID of the agent.
func (c *ThirdParty) AppID() int64 {
	return c.id
}

// AppName returns the GitHub App name of the agent.
func (c *ThirdParty) AppName() string {
	return c.name
}

// WorkflowRunName returns an empty string for ThirdParty.
func (c *ThirdParty) WorkflowRunName(_ int) string {
	return ""
}

// BranchPrefix returns the branch prefix for the agent.
func (c *ThirdParty) BranchPrefix() string {
	return c.name
}

// BotID returns the Bot ID of the agent.
func (c *ThirdParty) BotID() int64 {
	return c.botID
}

// BotLogin returns the bot login name for the ThirdParty instance.
func (c *ThirdParty) BotLogin() string {
	return c.botLogin
}

// CommitLogin returns the commit login name for the ThirdParty instance.
func (c *ThirdParty) CommitLogin() string {
	return c.commitLogin
}

// CommitEmail returns the commit email address for the ThirdParty instance.
func (c *ThirdParty) CommitEmail() string {
	return c.commitEmail
}

// SetupCompute configures the compute environment with the ThirdParty agent setup and runtime entry point.
func (c *ThirdParty) SetupCompute(compute sweagentd.ComputeEnv) {
	compute.EntryPoint("dist/index.js")
}

// ComputeSlug returns the slug used in compute environments.
func (c *ThirdParty) ComputeSlug() string {
	return c.name
}

// EngineSlug returns the slug used to resolve the runtime artifact.
func (c *ThirdParty) EngineSlug() string {
	return c.ComputeSlug()
}

// ModelVendors returns the vendor names for model filtering.
func (c *ThirdParty) ModelVendors() []string {
	return c.modelVendors
}

// Metadata returns app-specific key-value metadata for a third-party app.
// All dynamically-registered third-party agentic apps share a single CAPI
// integration so 3P traffic is rate-limited independently of Copilot's own
// quota (see ADR 0018).
func (c *ThirdParty) Metadata() map[string]string {
	return map[string]string{
		sweagentd.MetadataCAPIIntegrationID: ThirdPartyAgenticCAPIIntegrationID,
	}
}

// HasSource returns true if the ThirdParty app has source code information available.
func (c *ThirdParty) HasSource() bool {
	return c.agentSource != nil && c.agentSource.URL != ""
}

// SourceURL returns the source code URL for the ThirdParty app if available, otherwise returns an empty string.
func (c *ThirdParty) SourceURL() string {
	if c.agentSource == nil {
		return ""
	}
	return c.agentSource.URL
}

// AgentSource returns the source code information for the agent.
func (c *ThirdParty) AgentSource() *sweagentd.AgentSource {
	return c.agentSource
}

// IsGlobalApp returns false because ThirdParty is not a global app.
func (c *ThirdParty) IsGlobalApp() bool { return false }

// IsPartnerApp returns false because ThirdParty is not a partner app.
func (c *ThirdParty) IsPartnerApp() bool { return false }

// IsThirdPartyApp returns true because ThirdParty is a regular third-party app.
func (c *ThirdParty) IsThirdPartyApp() bool { return true }

// IsQuotaExempt returns false — third-party apps use standard quota checks.
func (c *ThirdParty) IsQuotaExempt() bool {
	return false
}

// UsesExperiments returns true — third-party apps participate in experiments.
func (c *ThirdParty) UsesExperiments() bool {
	return true
}

func (c *ThirdParty) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *ThirdParty) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := backtickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @<appLogin>[agent] mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}
