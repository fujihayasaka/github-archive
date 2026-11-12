package prompt

import (
	"context"

	"github.com/github/code-scanning-ai-libraries/v4/st"
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/contextsset"
	"github.com/github/codeml-autofix/go/v4/pkg/autofix/fixstate"
)

type variantWithMessageLinksPrompt struct {
	Message            string
	MessageLinksPrompt string
}

// AlertBodyTemplateArgs provides data to the alert_body.md prompt template.
type AlertBodyTemplateArgs struct {
	Alert          alerts.Alert
	ContextSet     contextsset.IContextsSet
	FilePath       string
	Message        string
	OmitCodeBlocks bool
}

// ErrorDescriptionTemplateArgs provides data to the error_description.md
// prompt template.
type ErrorDescriptionTemplateArgs struct {
	Alert                    alerts.Alert
	VariantsWithLinksPrompts []variantWithMessageLinksPrompt
	SingleFileFlowContext    *alerts.CollapsedFlowStep
	OmitCodeBlocks           bool
	AlertNumber              int
	RenderAlert              func(contextSet contextsset.IContextsSet, filePath string) (string, error)
}

// BuildErrorDescriptionPrompt renders the error description section of the
// user prompt using the provided fix state.
func BuildErrorDescriptionPrompt(ctx context.Context, fixState *fixstate.BaseFixState, omitCodeBlocks bool, alertIndex int) (string, error) {
	variantsWithLinksPrompts := make([]variantWithMessageLinksPrompt, 0, len(fixState.Alert.Variants))
	for _, variant := range fixState.Alert.Variants {
		messageLinksPrompt, err := BuildMessageLinksPrompt(ctx, variant.Links, omitCodeBlocks)
		if err != nil {
			return "", st.EnsureStackTrace(err, "failed to build message links prompt for variant")
		}
		variantsWithLinksPrompts = append(variantsWithLinksPrompts, variantWithMessageLinksPrompt{
			Message:            variant.Message,
			MessageLinksPrompt: messageLinksPrompt,
		})
	}

	// Get the first variant message for renderAlert
	firstMessage := ""
	if len(variantsWithLinksPrompts) > 0 {
		firstMessage = variantsWithLinksPrompts[0].Message
	}

	// Define renderAlert function that calls out to alert_body.md template
	renderAlert := func(contextSet contextsset.IContextsSet, filePath string) (string, error) {
		alertBodyArgs := AlertBodyTemplateArgs{
			Alert:          fixState.Alert,
			ContextSet:     contextSet,
			FilePath:       filePath,
			Message:        firstMessage,
			OmitCodeBlocks: omitCodeBlocks,
		}
		return ExecuteTemplate(ctx, "alert_body.md", alertBodyArgs)
	}

	args := ErrorDescriptionTemplateArgs{
		Alert:                    fixState.Alert,
		VariantsWithLinksPrompts: variantsWithLinksPrompts,
		SingleFileFlowContext:    fixState.SingleFileFlowContext,
		OmitCodeBlocks:           omitCodeBlocks,
		AlertNumber:              alertIndex + 1,
		RenderAlert:              renderAlert,
	}
	return ExecuteTemplate(ctx, "error_description.md", args)
}
