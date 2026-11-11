package prompt

import (
	"context"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixstate"
)

// BuildUserPrompt composes the full user prompt (background + error description).
func BuildUserPrompt(ctx context.Context, fixState fixstate.BaseFixState) (string, error) {
	background, err := BuildBackgroundPrompt(ctx, fixState.Alert)
	if err != nil {
		return "", err
	}

	errorDescription, err := BuildErrorDescriptionPrompt(ctx, fixState)
	if err != nil {
		return "", err
	}

	return background + "\n" + errorDescription, nil
}
