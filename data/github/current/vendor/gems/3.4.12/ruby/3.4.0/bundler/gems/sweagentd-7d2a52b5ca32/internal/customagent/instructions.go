package customagent

import (
	"regexp"
	"strings"

	"github.com/github/sweagentd/internal/sweagentd"
)

const agentInstructionsTag = "agent_instructions"

var agentInstructionsRemover = regexp.MustCompile(`(?s)<` + agentInstructionsTag + `>.*?</` + agentInstructionsTag + `>`)

// Instructions represents the prompt instructions for a custom agent.
type Instructions struct {
	Prompt string
}

// Instructions returns the prompt instructions for the custom agent.
func (a *Agent) Instructions() sweagentd.CustomAgentInstructions {
	return &Instructions{
		Prompt: a.cfg.prompt(),
	}
}

// WritePrompt writes the agent instructions as an XML tag to the provided strings.Builder.
// If the prompt is empty, it does nothing.
func (i *Instructions) WritePrompt(sb *strings.Builder) {
	if i.Prompt == "" {
		return
	}

	writeXMLTag(sb, agentInstructionsTag, i.Prompt)
}

// RemovePrompt removes the agent instructions tag from the problem statement.
// It returns the cleaned problem statement without the agent instructions.
// If the problem statement does not contain the agent instructions tag, it returns the original statement.
// It also trims any leading or trailing whitespace from the resulting string.
func (i *Instructions) RemovePrompt(problemStatement string) string {
	// Remove the agent instructions tag from the problem statement
	problemStatement = agentInstructionsRemover.ReplaceAllString(problemStatement, "")
	return strings.TrimSpace(problemStatement)
}

func writeXMLTag(sb *strings.Builder, tag, content string) {
	_, _ = sb.WriteString("<")
	_, _ = sb.WriteString(tag)
	_, _ = sb.WriteString(">")
	_, _ = sb.WriteString(content)
	_, _ = sb.WriteString("</")
	_, _ = sb.WriteString(tag)
	_, _ = sb.WriteString(">\n")
}
