package prompt

import (
	"context"

	"github.com/github/codeml-autofix/go/v3/pkg/autofix/alerts"
)

// MessageLinksTemplateArgs provides template data for the message_links prompt.
type MessageLinksTemplateArgs struct {
	Links []alerts.AlertMessageLink
}

// BuildMessageLinksPrompt renders the message links prompt for an alert.
func BuildMessageLinksPrompt(ctx context.Context, links []alerts.AlertMessageLink, omitCodeBlocks bool) (string, error) {
	// If omitCodeBlocks is set, drop all code-block context from the links (without modification):
	if omitCodeBlocks {
		newLinks := make([]alerts.AlertMessageLink, len(links))
		for i := range links {
			newLinks[i] = alerts.AlertMessageLink{
				Target:   links[i].Target,
				TargetID: links[i].TargetID,
				Text:     links[i].Text,
				Context:  nil,
			}
		}
		links = newLinks
	}

	args := MessageLinksTemplateArgs{Links: links}
	return ExecuteTemplate(ctx, "message_links.md", args)
}
