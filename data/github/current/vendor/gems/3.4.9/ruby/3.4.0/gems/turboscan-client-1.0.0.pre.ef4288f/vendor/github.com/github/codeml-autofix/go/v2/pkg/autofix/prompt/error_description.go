package prompt

import (
	"context"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixstate"
)

// ErrorDescriptionTemplateArgs provides data to the error_description.md
// prompt template.
type ErrorDescriptionTemplateArgs struct {
	Alert alerts.Alert
	// MessageLinks is the rendered message links prompt, i.e. an instantiation
	// of the message_links prompt template.
	MessageLinks          string
	SingleFileFlowContext *alerts.CollapsedFlowStep
}

// BuildErrorDescriptionPrompt renders the error description section of the
// user prompt using the provided fix state.
func BuildErrorDescriptionPrompt(ctx context.Context, fixState fixstate.BaseFixState) (string, error) {
	messageLinks, err := BuildMessageLinksPrompt(ctx, fixState.Alert)
	if err != nil {
		return "", st.EnsureStackTrace(err, "failed to build message links prompt")
	}
	args := ErrorDescriptionTemplateArgs{
		Alert:                 fixState.Alert,
		MessageLinks:          messageLinks,
		SingleFileFlowContext: fixState.SingleFileFlowContext,
	}
	return ExecuteTemplate(ctx, "error_description.md", args)
}
