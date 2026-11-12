package api

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/codeml-autofix/go/v3/pkg/autofix"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v3/pkg/autofix/fixstate"
	"github.com/github/github-telemetry-go/kvp"
)

// GenerateUserPromptFromAlerts generates the user prompt from pre-extracted alerts.
//
// This method takes a context, a slice of alerts, a map of source file contents, and a repository ID.
// It generates the user prompt that would be sent to the LLM for fix generation, without actually
// generating fixes. This is useful for scenarios where the prompt needs to be generated independently
// or for debugging purposes.
//
// Parameters:
//   - ctx: The context for controlling cancellation and deadlines.
//   - alts: A slice of alerts.Alert objects representing code issues to fix.
//   - sourceFiles: A map of file paths to their contents, used for prompt generation.
//   - repositoryID: The repository identifier for identification in logging and telemetry.
//     This value is client-specific, but can be the numeric repository id or the nwo.
//
// Returns:
//   - string: The generated user prompt.
//   - autofix.AutofixError: An error object if the operation fails.
//
// Errors:
//   - Returns an error if prompt generation fails or if the response is empty.
func (a *Autofixer) GenerateUserPromptFromAlerts(
	ctx context.Context,
	alts []alerts.Alert,
	sourceFiles map[string][]byte,
	repositoryID string,
	omitCodeBlocks bool,
) (string, autofix.AutofixError) {
	ctx = a.initializeContext(ctx)

	enhancedctx.Logger(ctx).Info("Generating user prompt from alerts",
		kvp.Int("gh.autofix.alert_count", len(alts)))

	params := &fixParams{ //nolint:exhaustruct // No need to specify all fields
		alerts:         alts,
		sourceFiles:    sourceFiles,
		repositoryID:   repositoryID,
		omitCodeBlocks: omitCodeBlocks,
	}
	return generateUserPrompt(ctx, a, params)
}

// GenerateUserPromptFromSarifContent generates the user prompt from SARIF content.
//
// This method takes a context, SARIF content as a byte slice, a map of source file contents,
// and a repository ID. It validates the input, generates the user prompt that would be sent
// to the LLM for fix generation of the alerts found in the SARIF content, without actually
// generating fixes. This is useful for scenarios where the prompt needs to be generated
// independently or for debugging purposes.
//
// Parameters:
//   - ctx: The context for controlling cancellation and deadlines.
//   - content: The SARIF content as a byte slice, containing code analysis results.
//   - sourceFiles: A map of file paths to their contents, used for prompt generation.
//   - repositoryID: The repository identifier for identification in logging and telemetry.
//     This value is client-specific, but can be the numeric repository id or the nwo.
//
// Returns:
//   - string: The generated user prompt.
//   - autofix.AutofixError: An error object if the operation fails.
//
// Errors:
//   - Returns an error if the SARIF content is empty, source files map is nil, or prompt generation fails.
func (a *Autofixer) GenerateUserPromptFromSarifContent(
	ctx context.Context,
	content []byte,
	sourceFiles map[string][]byte,
	repositoryID string,
	omitCodeBlocks bool,
	onlyAlertNumbers []int,
) (string, autofix.AutofixError) {
	ctx = a.initializeContext(ctx)
	enhancedctx.Logger(ctx).Info("Generating user prompt from alerts")

	if len(content) == 0 {
		return "", autofix.NewInvalidRequestError("SARIF content cannot be empty")
	}

	if sourceFiles == nil {
		return "", autofix.NewInvalidRequestError("source files map cannot be nil")
	}

	params := &fixParams{ //nolint:exhaustruct // No need to specify all fields
		sarifContent:     content,
		sourceFiles:      sourceFiles,
		repositoryID:     repositoryID,
		omitCodeBlocks:   omitCodeBlocks,
		onlyAlertNumbers: onlyAlertNumbers,
	}
	return generateUserPrompt(ctx, a, params)
}

// GenerateUserPromptFromSarifFile generates the user prompt from a SARIF file.
//
// This method takes a context, the path to a SARIF file, the source root directory,
// a repository ID, and a map of file checksums. It generates the user prompt that would be sent
// to the LLM for fix generation of the alerts found in the SARIF file, without actually
// generating fixes. This is useful for scenarios where the prompt needs to be generated
// independently or for debugging purposes.
//
// Parameters:
//   - ctx: The context for controlling cancellation and deadlines.
//   - sarifFilePath: The file path to the SARIF file containing code analysis results.
//   - sourceRoot: The root directory of the source code, used for resolving file paths.
//   - repositoryID: The repository identifier for identification in logging and telemetry.
//     This value is client-specific, but can be the numeric repository id or the nwo.
//   - fileChecksums: A map of file paths to their checksums for validation purposes.
//
// Returns:
//   - string: The generated user prompt.
//   - autofix.AutofixError: An error object if the operation fails.
//
// Errors:
//   - Returns an error if the SARIF file cannot be read or prompt generation fails.
func (a *Autofixer) GenerateUserPromptFromSarifFile(
	ctx context.Context,
	sarifFilePath, sourceRoot, repositoryID string,
	fileChecksums map[string]string,
	omitCodeBlocks bool,
	onlyAlertNumbers []int,
) (string, autofix.AutofixError) {
	ctx = a.initializeContext(ctx)
	enhancedctx.Logger(ctx).Info("Generating user prompt from alerts",
		kvp.String("gh.autofix.sarif_path", sarifFilePath))

	params := &fixParams{ //nolint:exhaustruct // No need to specify all fields
		sarifFilePath:    sarifFilePath,
		sourceRoot:       sourceRoot,
		fileChecksums:    fileChecksums,
		repositoryID:     repositoryID,
		omitCodeBlocks:   omitCodeBlocks,
		onlyAlertNumbers: onlyAlertNumbers,
	}
	return generateUserPrompt(ctx, a, params)
}

const seePreviousDocumentationNote = `This alert is of the same general kind as the previous one. Its background information also applies to this alert.`

// generateUserPrompt runs the generateFix method in dry-run mode and then extracts
// the user prompts from the response transcript, combining them if more than one is present.
func generateUserPrompt(ctx context.Context, a *Autofixer, params *fixParams) (string, autofix.AutofixError) {
	// to generate the user prompt we only need to run in dry-run mode
	params.createPromptOnly = true
	params.preprocessAlerts = func(oldAlerts []alerts.Alert) []alerts.Alert {
		// When an alert concerns the same Rule as the previous alert,
		// replace .Rule.Documentation with seePreviousDocumentationNote

		newAlerts := make([]alerts.Alert, len(oldAlerts))
		copy(newAlerts, oldAlerts)

		var previousRuleID string
		for i := range newAlerts {
			if i > 0 && newAlerts[i].Rule.ID == previousRuleID {
				newAlerts[i] = newAlerts[i].ShallowClone()
				newAlerts[i].Rule = newAlerts[i].Rule.Clone()
				newAlerts[i].Rule.Documentation = seePreviousDocumentationNote
			}
			previousRuleID = newAlerts[i].Rule.ID
		}
		return newAlerts
	}

	afResponse, _, err := a.generateFix(ctx, params)
	if err != nil {
		return "", err
	}

	userPrompts := make([]string, 0, len(afResponse))
	totalUserPromptLength := 0
	for i := range afResponse {
		userPrompt, err := outputToUserPrompt(&afResponse[i])
		if err != nil {
			return "", err
		}
		promptLen := len(userPrompt)
		totalUserPromptLength += promptLen
		enhancedctx.Logger(ctx).Info("Extracted user prompt from alert",
			kvp.Int("gh.autofix.alert_index", i),
			kvp.Int("gh.autofix.user_prompt_length", promptLen))
		userPrompts = append(userPrompts, userPrompt)
	}

	enhancedctx.Logger(ctx).Info("User prompts summary",
		kvp.Int("gh.autofix.total_alerts", len(userPrompts)),
		kvp.Int("gh.autofix.total_user_prompts_length", totalUserPromptLength))

	var finalPrompt string
	isMultiAlert := false
	switch len(userPrompts) {
	case 0:
		return "", autofix.NewLogicError("no user prompts generated")
	case 1:
		finalPrompt = userPrompts[0]
	default:
		finalPrompt = combinePrompts(userPrompts)
		isMultiAlert = true
	}

	enhancedctx.Logger(ctx).Info("Final prompt generated",
		kvp.Int("gh.autofix.final_prompt_length", len(finalPrompt)),
		kvp.Int("gh.autofix.alert_count", len(userPrompts)),
		kvp.Bool("gh.autofix.is_multi_alert", isMultiAlert),
		kvp.Bool("gh.autofix.exceeds_30k_limit", len(finalPrompt) > 30000))

	enhancedctx.Statter(ctx).Distribution("prompt.final_length", nil, float64(len(finalPrompt)))
	enhancedctx.Statter(ctx).Distribution("prompt.alert_count", nil, float64(len(userPrompts)))

	return finalPrompt, nil
}

// outputToUserPrompt extracts the user prompt from a given autofix output.
func outputToUserPrompt(output *fixdata.Output) (string, autofix.AutofixError) {
	if output.Outcome.Transcript == nil {
		return "", autofix.NewLogicError("no transcript available")
	}

	parts := strings.Split(*output.Outcome.Transcript, fixstate.TranscriptSeparator)

	if len(parts) < 2 {
		return "", autofix.NewLogicError("transcript is missing the user prompt")
	}

	return parts[1], nil
}

const multiAlertPrefix = `In the following, we will provide details of %d alerts that should be fixed. If they can be fixed using a single or few solutions, this is preferable, but solving each individually is also valuable.

Make sure you address ALL the alerts. Do not stop and ask for confirmation after fixing some of them.`

// combinePrompts combines multiple user prompts into a single prompt.
func combinePrompts(prompts []string) string {
	var builder strings.Builder

	prefixText := fmt.Sprintf(multiAlertPrefix, len(prompts))
	_, _ = builder.WriteString(prefixText)
	_, _ = builder.WriteString("\n\n")

	for i, prompt := range prompts {
		alertHeader := fmt.Sprintf("# Alert #%d\n\n", i+1)
		_, _ = builder.WriteString(alertHeader)
		_, _ = builder.WriteString(prompt)
		if i < len(prompts)-1 {
			_, _ = builder.WriteString("\n\n")
		}
	}

	return builder.String()
}
