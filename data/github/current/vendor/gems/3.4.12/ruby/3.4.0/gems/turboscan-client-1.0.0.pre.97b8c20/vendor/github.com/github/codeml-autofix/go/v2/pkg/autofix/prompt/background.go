// Package prompt contains helpers for building prompt parts from templates.
package prompt

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
)

// BackgroundTemplateArgs supplies template parameters for the background prompt section.
type BackgroundTemplateArgs struct {
	Alert alerts.Alert
}

// BuildBackgroundPrompt renders the background section of the prompt for an alert.
func BuildBackgroundPrompt(ctx context.Context, alert alerts.Alert) (string, error) {
	args := BackgroundTemplateArgs{Alert: alert}
	return ExecuteTemplate(ctx, "background.md", args)
}
