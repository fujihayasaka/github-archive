package prompt

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
)

// MessageLinksTemplateArgs provides template data for the message_links prompt.
type MessageLinksTemplateArgs struct {
	Alert alerts.Alert
}

// BuildMessageLinksPrompt renders the message links prompt for an alert.
func BuildMessageLinksPrompt(ctx context.Context, alert alerts.Alert) (string, error) {
	args := MessageLinksTemplateArgs{Alert: alert}
	return ExecuteTemplate(ctx, "message_links.md", args)
}
