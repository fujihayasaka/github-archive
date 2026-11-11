package prompt

import (
	"context"

	"github.com/github/codeml-autofix/go/v4/pkg/autofix/fixstate"
)

// BuildUserPrompt composes the full user prompt (background + error description).
func BuildUserPrompt(ctx context.Context, fixState *fixstate.BaseFixState, omitCodeBlocks bool, alertIndex int) (string, error) {
	background, err := BuildBackgroundPrompt(ctx, &fixState.Alert)
	if err != nil {
		return "", err
	}

	errorDescription, err := BuildErrorDescriptionPrompt(ctx, fixState, omitCodeBlocks, alertIndex)
	if err != nil {
		return "", err
	}

	return background + "\n" + errorDescription, nil
}
