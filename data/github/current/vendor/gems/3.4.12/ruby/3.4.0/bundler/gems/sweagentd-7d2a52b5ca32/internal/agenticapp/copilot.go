package agenticapp

import (
	"regexp"
	"slices"
)

// Copilot represents a GitHub Copilot Agentic App.
type Copilot struct {
	logins        []string
	mentionRegexp *regexp.Regexp
}

var (
	// CopilotAtMentionRegexp matches mentions of Copilot (includes `@copilot`).
	// It's public temporarily so other packages can reference this
	// And tie us to this specific regexp.
	CopilotAtMentionRegexp = regexp.MustCompile(`(?i)(?:^|\s|\W)@copilot\b`)

	// BacktickContentPattern matches content within backticks (both single and triple backticks).
	BacktickContentPattern = regexp.MustCompile("```[\\s\\S]*?```|`[^`]*`")
)

// NewCopilot creates a new Copilot instance.
func NewCopilot(appLogin, botLogin string) (*Copilot, error) {
	logins := []string{
		appLogin,
		appLogin + "[bot]",
		botLogin,
		"Copilot",
	}

	return &Copilot{
		logins: logins,

		// TODO(josebalius): update hardcode to come from app config
		mentionRegexp: CopilotAtMentionRegexp,
	}, nil
}

func (c *Copilot) hasLogin(login string) bool {
	return slices.Contains(c.logins, login)
}

func (c *Copilot) isMentioned(body string) bool {
	// Step 1: Remove all backtick-enclosed content (both inline code and code blocks)
	bodyWithoutBackticks := BacktickContentPattern.ReplaceAllString(body, "")

	// Step 2: Check if @copilot mention exists in the remaining text
	return c.mentionRegexp.MatchString(bodyWithoutBackticks)
}
