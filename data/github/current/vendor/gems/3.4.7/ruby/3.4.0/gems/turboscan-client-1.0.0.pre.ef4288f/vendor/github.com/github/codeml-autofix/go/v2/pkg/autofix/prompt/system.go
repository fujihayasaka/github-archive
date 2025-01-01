package prompt

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
)

// PromptTemplate is an enumeration of the system prompt variants we can render.
type PromptTemplate string

const (
	PromptTemplatePlain     PromptTemplate = "plain"
	PromptTemplateReasoning PromptTemplate = "reasoning"
)

// SystemTemplateArgs provides template data for the system prompt.
type SystemTemplateArgs struct {
	Alert     alerts.Alert
	SeenFiles []string
}

// BuildSystemPrompt renders the system prompt for the given alert & seen files.
func BuildSystemPrompt(ctx context.Context, promptTemplate PromptTemplate, alert alerts.Alert, seenFiles []alerts.RelativePath) (string, error) {
	stringSeenFiles := make([]string, len(seenFiles))
	for i, file := range seenFiles {
		stringSeenFiles[i] = string(file)
	}
	args := SystemTemplateArgs{Alert: alert, SeenFiles: stringSeenFiles}
	return ExecuteTemplate(ctx, string(promptTemplate)+"-system.md", args)
}
