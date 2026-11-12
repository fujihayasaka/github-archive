package prompt

import (
	"context"

	"github.com/github/code-scanning-ai-libraries/v4/guidelines"
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/alerts"
)

// Template is an enumeration of the system prompt variants we can render.
type Template string

const (
	// TemplatePlain renders the "plain" system prompt.
	TemplatePlain Template = "plain"
	// TemplateReasoning renders the "reasoning"system prompt.
	TemplateReasoning Template = "reasoning"
)

// SystemTemplateArgs provides template data for the system prompt.
type SystemTemplateArgs struct {
	Alert            alerts.Alert
	SeenFiles        []string
	CodingGuidelines []guidelines.CodingGuideline
}

// BuildSystemPrompt renders the system prompt for the given alert & seen files.
func BuildSystemPrompt(ctx context.Context, template Template, alert *alerts.Alert, seenFiles []alerts.RelativePath, codingGuidelines []guidelines.CodingGuideline) (string, error) {
	stringSeenFiles := make([]string, len(seenFiles))
	for i, file := range seenFiles {
		stringSeenFiles[i] = string(file)
	}
	args := SystemTemplateArgs{Alert: *alert, SeenFiles: stringSeenFiles, CodingGuidelines: codingGuidelines}
	return ExecuteTemplate(ctx, string(template)+"-system.md", args)
}
