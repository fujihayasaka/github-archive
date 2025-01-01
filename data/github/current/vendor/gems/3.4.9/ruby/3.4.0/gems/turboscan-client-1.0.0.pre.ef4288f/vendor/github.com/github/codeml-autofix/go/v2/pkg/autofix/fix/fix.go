// Package fix contains the logic to generate fix suggestions.
package fix

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/errors"

	shared_enhancedctx "github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/codebase"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/dependencies"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/editcommands"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixstate"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/prompt"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/replacement"
	toolsuites "github.com/github/codeml-autofix/go/v2/pkg/autofix/tools_suites"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

// FixSuggestion represents a proposed fix for an alert.
type FixSuggestion struct {
	// The alert we want to fix.
	Alert alerts.Alert
	// The state for the interaction with the model that produced this fix.
	State fixstate.BaseFixState
	// A natural-language description of the fix.
	FixDescription string
	// The edits comprising the fix.
	Edits []editcommands.FileEdit
	// An assessment of whether the fix is syntactically valid.
	Assessment fixdata.Assessment
	// A transcript of the conversation with the model that produced this fix.
	Transcript string
	// Metadata about new dependencies that are added as part of this fix, if any.
	DependencyMetadata []fixdata.DependencyMetadata
}

func (fs FixSuggestion) Write() error {
	cb := fs.Alert.Location.File.Codebase
	for _, edit := range fs.Edits {
		contents, err := cb.ReadContents(edit.FilePath)
		if err != nil {
			return err
		}
		contents = edit.EditCommands.Apply(contents)
		err = cb.WriteContents(edit.FilePath, contents)
		if err != nil {
			return err
		}
	}
	return nil
}

// NewFalsePositiveError returns an error indicating that autofix determined that the problem
// is a false positive, and a fix should not be generated. This type of error
// should not be retried.
func NewFalsePositiveError() autofix.AutofixError {
	return autofix.NewNotAutofixableError("false positive")
}

// FixError represents an error encountered while attempting to produce a fix suggestion.
type FixError struct {
	Alert      alerts.Alert
	Err        autofix.AutofixError
	Transcript string
	// Transient and Severity properties are deprecated: use the error types in errors.go instead.
}

var _ error = FixError{} //nolint:exhaustruct

func (e FixError) Error() string {
	return e.Err.Error()
}

// ValidationErrors represents a single validation failure emitted by a specific validator.
// It captures the validator’s name (e.g., CodeQL, ESLint, LLM) and a human-readable
// description of what went wrong, suitable for JSON serialization in logs or API responses.
type ValidationErrors struct {
	ValidatorName   string `json:"validatorName"`   // e.g. CodeQL, ESLint, LLM. Which validation failed.
	ValidationError string `json:"validationError"` // a human (or LLM) readable message about what went wrong.
}

// PreviousAttempt records the results of a previous code validation attempt.
// It contains the diffs that were generated and the corresponding validation errors.
// This struct is useful for tracking changes and understanding why validation failed.
type PreviousAttempt struct {
	Diffs            []string           `json:"diffs"`
	ValidationErrors []ValidationErrors `json:"validationErrors"`
}

// FixAlertDeps contains dependencies for the FixAlert function.
//
// This struct is used to pass dependencies to the function. This
// way, we can easily supply mock dependencies for testing purposes.
type FixAlertDeps struct {
	AddDependenciesDeps dependencies.AddDependenciesDeps
}

// MkFixAlertDeps constructs the default FixAlertDeps using production dependencies.
func MkFixAlertDeps() FixAlertDeps {
	return FixAlertDeps{
		AddDependenciesDeps: dependencies.MkAddDependenciesDeps(),
	}
}

// FixAlert attempts to fix an alert using the provided model and prompt template.
// It returns a FixSuggestion if successful, or a FixError if it fails.
func FixAlert(
	ctx context.Context,
	alert alerts.Alert,
	model models.Model,
	// promptTemplate is an extra message to add to the LLM chat history, containing previous fix suggestions and
	// reasoning for why they are incorrect.
	promptTemplate prompt.PromptTemplate,
	previousAttempts []PreviousAttempt,
	deps ...FixAlertDeps,
) (*FixSuggestion, *FixError) {
	// Include the model name with all messages.
	ctx = shared_enhancedctx.WithLoggerFields(ctx, kvp.String("gh.autofix.ai_model", model.GetModelName()))

	// Before we go any further, we need to check if the alert rule is fixable by the given client.
	fixable, querySuiteErr := alertRuleFixable(ctx, alert)

	// There are two failure modes here we need to check:

	// We failed while trying to check if the alert rule is fixable, for instance, we couldn't
	// find the query suite file in our embedded filesystem.
	if !fixable && querySuiteErr != nil && strings.Contains(querySuiteErr.Error(), "failed to check if alert rule is fixable") {
		return nil, &FixError{
			Alert:      alert,
			Err:        autofix.NewLogicError(querySuiteErr.Error()),
			Transcript: "",
		}
	}

	// Or we actually did find a query suite, but it doesn't include the alert rule in question.
	if !fixable && querySuiteErr != nil && strings.Contains(querySuiteErr.Error(), "is not present in query suite") {
		// If the error is about the query suite not being fixable by this client, we return a FixError with a not autofixable error.
		return nil, &FixError{
			Alert:      alert,
			Err:        autofix.NewNotAutofixableError(querySuiteErr.Error()),
			Transcript: "",
		}
	}

	// Otherwise, we assume that the alert rule is fixable by this client.

	if !fixable {
		// This is just a sanity check, we should never reach this point if the alert rule is not fixable.
		return nil, &FixError{
			Alert:      alert,
			Err:        autofix.NewLogicError("unexpected error while checking if alert rule is fixable"),
			Transcript: "",
		}
	}

	var faDeps FixAlertDeps
	if len(deps) == 0 {
		faDeps = MkFixAlertDeps()
	} else {
		faDeps = deps[0]
	}
	state, err := fixstate.NewBaseFixState(&alert)
	// Doing this here so that we can use the state in the error wrapper.
	var wrapError = func(err autofix.AutofixError) *FixError {
		return &FixError{Alert: alert, Err: err, Transcript: state.Transcript}
	}
	// Now we can check if there was an error creating the state.
	if err != nil {
		return nil, wrapError(err)
	}

	enhancedctx.Logger(ctx).Info(
		"Fixing alert with model",
		kvp.String("gh.autofix.rule_id", alert.Rule.ID),
		kvp.String("gh.autofix.language", string(alert.Language)),
		kvp.String("gh.autofix.tool", string(alert.Tool)),
	)
	err = fixAlertWithModel(ctx, model, promptTemplate, &state, previousAttempts)
	if err != nil {
		return nil, wrapError(err)
	}

	if state.IsFalsePositive {
		return nil, wrapError(NewFalsePositiveError())
	}

	if len(state.ParsedEdits) == 0 {
		return nil, wrapError(autofix.BadModelOutputError{Err: errors.New("Failed to extract edits")})
	}

	edits := state.ParsedEdits

	problems := []fixdata.Problem{}

	// check for problems with the suggested fix
	foundProblems, err := checkForProblems(
		ctx,
		alert.Location.File.Codebase,
		edits,
	)
	if err != nil {
		return nil, wrapError(err)
	}
	problems = append(problems, foundProblems...)

	// add dependencies if necessary
	addDependenciesProblems := addDependencies(ctx, &state, alert.Language, &edits, faDeps)
	problems = append(problems, addDependenciesProblems...)

	var assessment fixdata.Assessment
	if len(problems) == 0 {
		assessment = fixdata.Assessment{
			Outcome:  fixdata.AssessmentOutcome_VALID,
			Problems: []fixdata.Problem{},
		}
	} else {
		assessment = fixdata.Assessment{
			Outcome:  fixdata.AssessmentOutcome_INVALID,
			Problems: problems,
		}
	}

	return &FixSuggestion{
		Alert:              alert,
		State:              state,
		FixDescription:     state.FixDescription,
		Edits:              edits,
		Assessment:         assessment,
		Transcript:         state.Transcript,
		DependencyMetadata: state.DependencyMetadata,
	}, nil
}

func checkForProblems(
	ctx context.Context,
	cb codebase.VirtualCodebase,
	edits []editcommands.FileEdit,
) ([]fixdata.Problem, autofix.AutofixError) {
	codeUnchanged := true
	problems := []fixdata.Problem{}

	for _, edit := range edits {
		beforeContents, err := cb.ReadContents(edit.FilePath)
		if err != nil {
			return nil, autofix.NewRetryableError(
				fmt.Sprintf("Failed to read contents of file %s", edit.FilePath))
		}
		afterContents := edit.EditCommands.Apply(beforeContents)

		codeUnchanged = codeUnchanged && (beforeContents == afterContents)

		checkChange, autofixErr := GetChecker(ctx, edit.FilePath)
		if autofixErr != nil {
			return nil, autofixErr
		}
		newProblems, err := checkChange(beforeContents, afterContents)
		if err != nil {
			return nil, autofix.NewLogicError(
				fmt.Sprintf("Failed to check changes in file %s", edit.FilePath))
		}
		problems = append(problems, newProblems...)
	}
	if codeUnchanged {
		problems = append(problems, fixdata.Problem{
			Kind:        fixdata.ProblemKind_NO_CODE_CHANGES,
			Description: "no code changes",
		})
	}

	return problems, nil
}

// TODO: Integrate fix parsing
func fixAlertWithModel(ctx context.Context, model models.Model, promptTemplate prompt.PromptTemplate, state *fixstate.BaseFixState, previousAttempts []PreviousAttempt) autofix.AutofixError {
	systemMessage, err := prompt.BuildSystemPrompt(
		ctx,
		promptTemplate,
		state.Alert,
		state.SeenFiles(),
	)

	if err != nil {
		return autofix.NewLogicError(
			"Failed to build system prompt: " + err.Error())
	}

	systemMessageRole := models.ChatMessageRoleSystem

	// System message is not yet supported in o1 models (https://platform.openai.com/docs/guides/reasoning#beta-limitations)
	// TODO: remove this once o1 models support chat.
	if strings.HasPrefix(model.GetModelName(), "o1") {
		systemMessageRole = models.ChatMessageRoleUser
	}

	chatHistory := []models.ChatMessage{
		{
			Content: systemMessage,
			Role:    systemMessageRole,
		},
	}

	transcriptPrefix := systemMessage + "\n\n-----\n\n"
	state.Transcript = transcriptPrefix

	// TODO: user prompt does not yet support different templates.
	userPrompt, err := prompt.BuildUserPrompt(ctx, *state)
	if err != nil {
		return autofix.NewLogicError(
			"Failed to build user prompt: " + err.Error())
	}

	state.Transcript += userPrompt + "\n\n-----\n\n"
	chatHistory = append(chatHistory, models.ChatMessage{
		Content: userPrompt,
		Role:    models.ChatMessageRoleUser,
	})

	// Append previous incorrect fix suggestion(s) and the explanation of why each is incorrect
	for attemptIdx, attempt := range previousAttempts {
		// Header
		fixNumber := ""
		if len(previousAttempts) > 1 {
			fixNumber = fmt.Sprintf(" (%d)", attemptIdx+1)
		}
		extraMsg := fmt.Sprintf("# Incorrect previous fix attempt%s", fixNumber)
		// If there is a single feedback, the fix number is empty, so trim the extra space if that is the case.
		extraMsg = strings.TrimSuffix(extraMsg, " ")
		extraMsg += "\n\n"

		// Suggested fix
		extraMsg += "## Suggested fix\n\n"
		for _, diff := range attempt.Diffs {
			extraMsg += fmt.Sprintf("```diff\n%s\n```\n", diff)
		}
		extraMsg += "\n"

		// Validation errors
		for _, failure := range attempt.ValidationErrors {
			extraMsg += fmt.Sprintf("## Error detected by %s\n\n", failure.ValidatorName)
			extraMsg += failure.ValidationError + "\n\n"
		}

		// Add the extra message to the chat history
		extraMsg = strings.TrimSpace(extraMsg)
		chatHistory = append(chatHistory, models.ChatMessage{
			Content: extraMsg,
			Role:    models.ChatMessageRoleUser,
		})
		// Add this attempt and its critiques to the transcript
		state.Transcript += extraMsg + "\n\n-----\n\n"
	}

	enhancedctx.Logger(ctx).Info("Making model call",
		kvp.Any("gh.autofix.model_name", model.GetModelName()))

	modelCallStartTime := time.Now()
	response, _, _, llmError := model.Complete(ctx, chatHistory, nil, models.MkDefaultCompletionOptions())

	enhancedctx.Statter(ctx).DistributionMs(
		"model.completion",
		stats.Tags{
			"success":     strconv.FormatBool(llmError == nil),
			"model":       model.GetModelName(),
			"client_name": enhancedctx.ClientNameFromContext(ctx),
		},
		time.Since(modelCallStartTime),
	)
	if llmError != nil {
		fields := modelCallFields(state, model, time.Since(modelCallStartTime))
		enhancedctx.Logger(ctx).WithError(llmError).Info("Model call completed with error", fields...)

		err := autofix.NewLLMError(llmError)
		autofix.ReportErrorToTelemetry(ctx, err)
		return err
	}

	// Add two new lines at the end of the response to match the behavior of the
	// previous implementation.
	state.Transcript += response + "\n\n-----\n\n"

	parseErr := state.ParseModelResponse(ctx, response, replacement.ProcessReplacementBlocksSection)

	if parseErr != nil {
		fields := modelCallFields(state, model, time.Since(modelCallStartTime))

		enhancedctx.Logger(ctx).WithError(parseErr).Info("Failed to parse model response", fields...)
		return autofix.NewBadModelOutputError("failed to parse model response", parseErr)
	}

	return nil
}

func modelCallFields(state *fixstate.BaseFixState, model models.Model, duration time.Duration) []kvp.Field {
	if state == nil {
		return []kvp.Field{
			kvp.String("gh.autofix.model_name", model.GetModelName()),
			kvp.Duration("gh.autofix.model_call_duration", duration),
		}
	}

	fields := alertLogFields(state.Alert)
	return append(fields,
		kvp.String("gh.autofix.model_name", model.GetModelName()),
		kvp.Duration("gh.autofix.model_call_duration", duration),
	)
}

func alertLogFields(alert alerts.Alert) []kvp.Field {
	ruleID := "unknown"
	language := "unknown"
	toolName := "unknown"

	if alert.Rule.ID != "" {
		ruleID = alert.Rule.ID
	}

	if alert.Language != "" {
		language = string(alert.Language)
	}

	if alert.Tool != "" {
		toolName = string(alert.Tool)
	}

	return []kvp.Field{
		kvp.String("gh.autofix.rule_id", ruleID),
		kvp.String("gh.autofix.language", language),
		kvp.String("gh.autofix.tool", toolName),
	}
}

func addDependencies(
	ctx context.Context,
	state *fixstate.BaseFixState,
	language utils.Language,
	edits *[]editcommands.FileEdit,
	faDeps FixAlertDeps,
) []fixdata.Problem {
	if state == nil || len(state.PackagesToInstall) == 0 {
		return []fixdata.Problem{}
	}

	// This is a bit arbitrary, but most of the time only a single file is
	// edited.
	if len(state.ParsedEdits) == 0 {
		enhancedctx.Logger(ctx).Warn("No parsed edits found in state")
		return []fixdata.Problem{}
	}

	editedFile := codebase.File{
		Path:     state.ParsedEdits[0].FilePath,
		Codebase: state.Alert.Location.File.Codebase,
	}

	deps := dependencies.CreateAddDependenciesEditCommands(
		ctx,
		editedFile,
		language,
		state.PackagesToInstall,
		faDeps.AddDependenciesDeps,
	)
	problems := []fixdata.Problem{}
	for dep, outcome := range deps.Info {
		meta, err := outcome.GetAddDependencyMetadata()
		outcomeIsSuccess := err == nil
		if outcomeIsSuccess {
			state.DependencyMetadata = append(state.DependencyMetadata, meta)
			problematicAdvisories := utils.Filter(meta.Advisories, func(a fixdata.Advisory) bool {
				return a.Severity == "high" || a.Severity == "critical"
			})
			if len(problematicAdvisories) > 0 {
				description := strings.Join(utils.Map(problematicAdvisories, func(a fixdata.Advisory) string {
					return a.Severity + " advisory: " + a.Summary
				}), ", ")
				problems = append(problems, fixdata.Problem{
					Kind:        fixdata.ProblemKind_VULNERABLE_DEPENDENCY,
					Description: description,
				})
			}
		} else {
			problems = append(problems, fixdata.Problem{
				Kind:        fixdata.ProblemKind_MISSING_DEPENDENCY,
				Description: "failed to add dependency " + dep + ": " + err.Error(),
			})
		}
	}
	*edits = append(*edits, deps.Edits...)

	return problems
}

// ToOutputFormat converts a FixSuggestion to the standardized API output format
func (fs *FixSuggestion) ToOutputFormat(version, model string) fixdata.Output {
	// Generate diffs for each edit
	diffs := make([]fixdata.Diff, 0, len(fs.Edits))
	for _, edit := range fs.Edits {
		// Get the original content
		originalContent, err := fs.Alert.Location.File.Codebase.ReadContents(edit.FilePath)
		if err != nil {
			// Skip this edit if we can't read the original content
			continue
		}

		// Apply edits to get new content
		newContent := edit.EditCommands.Apply(originalContent)

		// Generate a unified diff
		diffText, err := replacement.FormatDiff(originalContent, newContent, string(edit.FilePath), "git")
		if err != nil {
			// Skip this edit if we can't generate a diff
			continue
		}

		diffs = append(diffs, fixdata.Diff{
			Path: string(edit.FilePath),
			Diff: diffText,
		})
	}

	// Create the outcome
	outcome := fixdata.Outcome{
		Kind:       fixdata.OutcomeKind_FIX,
		Assessment: fs.Assessment,
		Details: fixdata.Details{
			FixDescription:     fs.FixDescription,
			DependencyMetadata: fs.DependencyMetadata,
		},
		Diffs:        diffs,
		AutofixError: nil,            // no error
		Error:        "",             // no error
		Transient:    false,          // no error is not transient
		Severity:     autofix.Ignore, // There is no error
		Transcript:   &fs.Transcript,
	}

	return fixdata.NewAutofixOutput(version, model, fs.Alert, outcome)
}

// FormatAsText returns a text representation of the fix suggestion that matches TypeScript output
func (fs *FixSuggestion) FormatAsText(diffStyle string) (string, error) {
	var builder strings.Builder

	if fs == nil {
		return "", errors.New("fix suggestion is nil")
	}

	// Format changes section first
	builder.WriteString("Changes:\n\n")

	// Handle case with no edits
	if len(fs.Edits) == 0 {
		builder.WriteString("No changes proposed.\n\n")

		// Add description
		builder.WriteString("Description:\n\n")
		builder.WriteString(fs.FixDescription + "\n\n")

		// Add assessment
		if fs.Assessment.Outcome == "valid" {
			builder.WriteString("Fix is valid.\n")
		} else {
			builder.WriteString("Fix has the following issues:\n")
			for _, problem := range fs.Assessment.Problems {
				builder.WriteString(fmt.Sprintf("- %s: %s\n", problem.Kind, problem.Description))
			}
		}

		return builder.String(), nil
	}

	// Process each edit
	for _, edit := range fs.Edits {
		// Get original content
		originalContent, err := fs.Alert.Location.File.Codebase.ReadContents(edit.FilePath)
		if err != nil {
			builder.WriteString(fmt.Sprintf("Error reading file %s: %v\n", edit.FilePath, err))
			continue
		}

		// Apply edits to get new content
		newContent := edit.EditCommands.Apply(originalContent)

		// Skip if no changes
		if originalContent == newContent {
			continue
		}

		// Show file info
		builder.WriteString(fmt.Sprintf("Will patch: %s\n", edit.FilePath))

		// Manually format a simplified, colored diff using the exact TS style
		originalLines := strings.Split(originalContent, "\n")
		newLines := strings.Split(newContent, "\n")

		// Add ellipses at the top (just 1 like the TS output)
		builder.WriteString("...\n")

		// Find the line numbers of the changes
		lineChange := -1
		for i := 0; i < min(len(originalLines), len(newLines)); i++ {
			if originalLines[i] != newLines[i] {
				lineChange = i
				break
			}
		}

		if lineChange < 0 {
			lineChange = 0
		}

		// Add context before change (with double space like TS output)
		start := max(0, lineChange-2)
		end := min(lineChange+1, len(originalLines)-1)

		// Print context lines before change (with two spaces at beginning like TS)
		for i := start; i < lineChange; i++ {
			builder.WriteString("  " + originalLines[i] + "\n")
		}

		// Print the changed line(s) with proper spacing and colors
		// The TS format has a space after the +/- symbol
		builder.WriteString("\033[31m- " + originalLines[lineChange] + "\033[0m\n")
		builder.WriteString("\033[32m+ " + newLines[lineChange] + "\033[0m\n")

		// Print context lines after change (with two spaces like TS)
		for i := lineChange + 1; i <= end; i++ {
			if i < len(originalLines) {
				builder.WriteString("  " + originalLines[i] + "\n")
			}
		}

		// No final ellipsis in TS output for this example
		// builder.WriteString("...\n\n")
		builder.WriteString("\n")
	}

	// Add description
	builder.WriteString("Description:\n\n")
	builder.WriteString(fs.FixDescription + "\n\n")

	// Add assessment
	if fs.Assessment.Outcome == "valid" {
		builder.WriteString("Fix is valid.\n")
	} else {
		builder.WriteString("Fix has the following issues:\n")
		for _, problem := range fs.Assessment.Problems {
			builder.WriteString(fmt.Sprintf("- %s: %s\n", problem.Kind, problem.Description))
		}
	}

	return builder.String(), nil
}

// Check if the query suite allows for the alert rule to be fixable.
func alertRuleFixable(ctx context.Context, alert alerts.Alert) (bool, error) {
	querySuite := ctx.Value(toolsuites.QuerySuiteKey)
	if querySuite == nil || querySuite == "" {
		enhancedctx.Logger(ctx).Warn("No query suite found in context, defaulting to accepting all rules as fixable")
		return true, nil // No query suite means we assume all rules are fixable
	}

	querySuiteStr := toolsuites.QuerySuite(querySuite.(string))
	fixable, err := querySuiteStr.IsIncluded(
		toolsuites.QueryID(alert.Rule.ID),
		alert.Language,
		alert.Tool,
	)

	if err != nil {
		return false, st.EnsureStackTrace(err, "failed to check if alert rule is fixable")
	}
	if !fixable {
		return false, errors.Errorf("alert rule %s is not present in query suite: %s", alert.Rule.ID, querySuiteStr)
	}

	return true, nil
}
